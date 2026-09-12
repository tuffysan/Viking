#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-tuffysan/Viking}"
VERSION="${VERSION:-latest}"
CTID="${CTID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-viking-iptv}"
BRIDGE="${BRIDGE:-vmbr0}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-1024}"
SWAP="${SWAP:-512}"
DISK_GB="${DISK_GB:-8}"
STORAGE="${STORAGE:-auto}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
LVMTHIN_MAX_DATA_PERCENT="${LVMTHIN_MAX_DATA_PERCENT:-80}"
APP_PORT="${APP_PORT:-8080}"

log() { printf '%s\n' "$*"; }
die() { printf 'FEL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Kör installeraren som root på Proxmox-hosten."
command -v pct >/dev/null 2>&1 || die "pct saknas. Kör på Proxmox VE-hosten."
command -v pvesm >/dev/null 2>&1 || die "pvesm saknas."

if [[ -z "$CTID" ]]; then
  if command -v pvesh >/dev/null 2>&1; then
    CTID="$(pvesh get /cluster/nextid 2>/dev/null || true)"
  fi
  if [[ -z "$CTID" ]]; then
    CTID=100
    while pct status "$CTID" >/dev/null 2>&1 || [[ -e "/etc/pve/lxc/${CTID}.conf" ]]; do
      CTID=$((CTID+1))
    done
  fi
fi

if pct status "$CTID" >/dev/null 2>&1 || [[ -e "/etc/pve/lxc/${CTID}.conf" ]]; then
  die "CTID $CTID används redan."
fi

if [[ "$VERSION" == "latest" ]]; then
  TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$TAG" ]] || die "Kunde inte läsa senaste GitHub Release."
  VERSION="${TAG#v}"
else
  VERSION="${VERSION#v}"
  TAG="v${VERSION}"
fi

ASSET="viking-iptv-${TAG}.zip"

storage_exists() {
  pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$1"
}

storage_active() {
  pvesm status 2>/dev/null | awk -v s="$1" 'NR>1 && $1==s {print $3}' | grep -Fxq "active"
}

storage_has_content() {
  local storage="$1" content="$2"
  awk -v wanted="$storage" -v wanted_content="$content" '
    $1 ~ /:$/ { inblock=($2==wanted) }
    inblock && $1=="content" {
      n=split($2,a,",")
      for(i=1;i<=n;i++) if(a[i]==wanted_content) found=1
    }
    END { exit(found?0:1) }
  ' /etc/pve/storage.cfg
}

enable_local_rootdir() {
  storage_exists local || return 1
  storage_active local || return 1
  storage_has_content local rootdir && return 0

  local current
  current="$(awk '
    $1=="dir:" && $2=="local" {inblock=1; next}
    $1 ~ /:$/ {inblock=0}
    inblock && $1=="content" {print $2; exit}
  ' /etc/pve/storage.cfg)"
  [[ -n "$current" ]] || current="vztmpl,backup,iso,import"

  case ",$current," in
    *,rootdir,*) ;;
    *) current="${current},rootdir" ;;
  esac

  log "Aktiverar rootdir på storage 'local'..."
  pvesm set local --content "$current"
}

local_has_space() {
  local avail_kib required_kib
  avail_kib="$(pvesm status 2>/dev/null | awk '$1=="local" {print $6}')"
  [[ "$avail_kib" =~ ^[0-9]+$ ]] || return 1
  required_kib=$(( (DISK_GB + 2) * 1024 * 1024 ))
  (( avail_kib >= required_kib ))
}

local_lvm_safe() {
  storage_exists local-lvm || return 1
  storage_active local-lvm || return 1

  local used
  used="$(lvs --noheadings -o data_percent pve/data 2>/dev/null | tr -d ' ' | head -n1 || true)"
  [[ "$used" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v used="$used" -v max="$LVMTHIN_MAX_DATA_PERCENT" 'BEGIN { exit !(used < max) }'
}

choose_storage() {
  if [[ "$STORAGE" != "auto" ]]; then
    storage_exists "$STORAGE" || die "Storage '$STORAGE' finns inte."
    storage_active "$STORAGE" || die "Storage '$STORAGE' är inte aktiv."
    if [[ "$STORAGE" == "local" ]]; then
      enable_local_rootdir || die "Kunde inte aktivera rootdir på local."
      local_has_space || die "Storage local har inte tillräckligt med utrymme."
    fi
    printf '%s' "$STORAGE"
    return
  fi

  if local_lvm_safe; then
    printf '%s' "local-lvm"
    return
  fi

  if storage_exists local && storage_active local; then
    enable_local_rootdir || die "Kunde inte aktivera rootdir på local."
    local_has_space || die "Storage local har inte tillräckligt med utrymme."
    printf '%s' "local"
    return
  fi

  die "Ingen lämplig LXC-storage hittades."
}

SELECTED_STORAGE="$(choose_storage)"

get_template() {
  local existing template
  existing="$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null \
    | awk '/debian-12-standard_.*amd64\.tar\.(zst|gz)/ {print $1}' \
    | sort -V | tail -n1 || true)"
  if [[ -n "$existing" ]]; then
    printf '%s' "$existing"
    return
  fi

  pveam update >/dev/null
  template="$(pveam available --section system 2>/dev/null \
    | awk '/debian-12-standard_.*amd64\.tar\.(zst|gz)/ {print $2}' \
    | sort -V | tail -n1 || true)"
  [[ -n "$template" ]] || die "Kunde inte hitta Debian 12-template."
  log "Laddar ned $template till $TEMPLATE_STORAGE..."
  pveam download "$TEMPLATE_STORAGE" "$template"
  printf '%s:vztmpl/%s' "$TEMPLATE_STORAGE" "$template"
}

TEMPLATE="$(get_template)"

log "=== Viking IPTV LXC installer ==="
log "Repo:      $REPO"
log "Version:   $VERSION"
log "CTID:      $CTID"
log "Hostname:  $CT_HOSTNAME"
log "Storage:   $SELECTED_STORAGE"
log "Template:  $TEMPLATE"
log "Release:   $TAG"
log "Asset:     $ASSET"

create_ct() {
  local storage="$1"
  pct create "$CTID" "$TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap "$SWAP" \
    --rootfs "${storage}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --features nesting=1 \
    --unprivileged 1 \
    --onboot 1 \
    --start 0
}

set +e
create_output="$(create_ct "$SELECTED_STORAGE" 2>&1)"
create_rc=$?
set -e

if (( create_rc != 0 )); then
  printf '%s\n' "$create_output" >&2
  if [[ "$STORAGE" == "auto" && "$SELECTED_STORAGE" == "local-lvm" ]]; then
    log "local-lvm misslyckades. Försöker med storage 'local'..."
    if [[ -e "/etc/pve/lxc/${CTID}.conf" ]]; then
      pct destroy "$CTID" --purge 1 >/dev/null 2>&1 || true
    fi
    enable_local_rootdir || die "Kunde inte aktivera rootdir på local."
    local_has_space || die "Storage local har inte tillräckligt med utrymme."
    SELECTED_STORAGE="local"
    create_ct "$SELECTED_STORAGE"
  else
    die "Kunde inte skapa LXC-container."
  fi
fi

log "Startar CT $CTID..."
pct start "$CTID"

log "Installerar grundpaket..."
pct exec "$CTID" -- bash -lc '
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates unzip wget gnupg apt-transport-https
mkdir -p /opt/viking-iptv /var/lib/viking-iptv/keys
'

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
log "Hämtar $DOWNLOAD_URL"
pct exec "$CTID" -- bash -lc "curl -fL '$DOWNLOAD_URL' -o /opt/viking-iptv/app.zip"
pct exec "$CTID" -- bash -lc '
set -Eeuo pipefail
rm -rf /opt/viking-iptv/src
mkdir -p /opt/viking-iptv/src
unzip -q /opt/viking-iptv/app.zip -d /opt/viking-iptv/src
'

log "Installerar .NET 10..."
pct exec "$CTID" -- bash -lc '
set -Eeuo pipefail
if ! command -v dotnet >/dev/null 2>&1 || ! dotnet --list-sdks 2>/dev/null | grep -q "^10\."; then
  wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
  dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null
  rm -f /tmp/packages-microsoft-prod.deb
  apt-get update
  apt-get install -y dotnet-sdk-10.0 aspnetcore-runtime-10.0
fi
'

log "Bygger Viking IPTV..."
pct exec "$CTID" -- bash -lc '
set -Eeuo pipefail
rm -rf /opt/viking-iptv/publish
dotnet publish /opt/viking-iptv/src/app/VikingIptv.csproj -c Release -o /opt/viking-iptv/publish
'

log "Skapar systemd-tjänst..."
pct exec "$CTID" -- bash -lc "cat >/etc/systemd/system/viking-iptv.service <<'EOF'
[Unit]
Description=Viking IPTV
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/viking-iptv/publish
ExecStart=/usr/bin/dotnet /opt/viking-iptv/publish/VikingIptv.dll
Restart=always
RestartSec=3
Environment=ASPNETCORE_URLS=http://0.0.0.0:${APP_PORT}
Environment=VIKING_IPTV_DATA=/var/lib/viking-iptv
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now viking-iptv.service
"

sleep 3
pct exec "$CTID" -- systemctl --no-pager --full status viking-iptv.service || {
  pct exec "$CTID" -- journalctl -u viking-iptv.service -n 100 --no-pager || true
  die "Viking IPTV-tjänsten startade inte."
}

IP="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"

log ""
log "=== KLART ==="
log "CTID:      $CTID"
log "Hostname:  $CT_HOSTNAME"
log "Storage:   $SELECTED_STORAGE"
log "Version:   $VERSION"
if [[ -n "$IP" ]]; then
  log "Webb:      http://${IP}:${APP_PORT}"
else
  log "Webbport:  $APP_PORT"
fi
