#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-tuffysan/viking-iptv-lxc}"
VERSION="${VERSION:-latest}"
CTID="${CTID:-$(pvesh get /cluster/nextid)}"
HOSTNAME="${HOSTNAME:-viking-iptv}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
MEMORY="${MEMORY:-1024}"
CORES="${CORES:-2}"
DISK="${DISK:-8}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"

if [[ $EUID -ne 0 ]]; then
  echo "Kör scriptet som root på Proxmox."
  exit 1
fi

echo "=== Viking IPTV LXC installer ==="
echo "Repo:      $REPO"
echo "Version:   $VERSION"
echo "CTID:      $CTID"
echo "Hostname:  $HOSTNAME"

if [[ "$VERSION" == "latest" ]]; then
  API_URL="https://api.github.com/repos/$REPO/releases/latest"
  RELEASE_JSON="$(curl -fsSL "$API_URL")"
  TAG="$(printf '%s' "$RELEASE_JSON" | grep -oE '"tag_name":[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)"
else
  TAG="v${VERSION#v}"
fi

if [[ -z "${TAG:-}" ]]; then
  echo "Kunde inte hitta release-version."
  exit 1
fi

ASSET="viking-iptv-$TAG.zip"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

echo "Release:   $TAG"
echo "Asset:     $ASSET"

# Ensure template exists
pveam update >/dev/null
TEMPLATE="$(pveam available --section system | awk '/debian-12-standard/ {print $2}' | tail -1)"
if [[ -z "$TEMPLATE" ]]; then
  echo "Kunde inte hitta Debian 12 template."
  exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$(basename "$TEMPLATE")"; then
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

TEMPLATE_REF="$TEMPLATE_STORAGE:vztmpl/$(basename "$TEMPLATE")"

pct create "$CTID" "$TEMPLATE_REF" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --rootfs "$STORAGE:$DISK" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1 \
  --start 1

echo "Väntar på nätverk..."
sleep 5

pct exec "$CTID" -- bash -lc "apt-get update && apt-get install -y curl unzip ca-certificates wget gnupg"

echo "Hämtar release $TAG..."
pct exec "$CTID" -- bash -lc "mkdir -p /opt/viking-iptv && cd /opt/viking-iptv && curl -fL '$ASSET_URL' -o app.zip && unzip -o app.zip && rm app.zip"

echo "Installerar .NET 10 SDK/runtime..."
pct exec "$CTID" -- bash -lc "
wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
apt-get update
apt-get install -y dotnet-sdk-10.0 aspnetcore-runtime-10.0
"

echo "Bygger applikationen..."
pct exec "$CTID" -- bash -lc "
cd /opt/viking-iptv
dotnet publish app/VikingIptv.csproj -c Release -o /opt/viking-iptv/publish
mkdir -p /var/lib/viking-iptv/keys
"

pct exec "$CTID" -- bash -lc "cat >/etc/systemd/system/viking-iptv.service <<'EOF'
[Unit]
Description=Viking IPTV
After=network.target

[Service]
WorkingDirectory=/opt/viking-iptv/publish
ExecStart=/usr/bin/dotnet /opt/viking-iptv/publish/VikingIptv.dll
Restart=always
RestartSec=5
User=root
Environment=ASPNETCORE_URLS=http://0.0.0.0:8080
Environment=DOTNET_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now viking-iptv
"

IP="$(pct exec "$CTID" -- hostname -I | awk '{print $1}')"

echo
echo "=== KLART ==="
echo "Version: $TAG"
echo "CTID:    $CTID"
echo "URL:     http://$IP:8080"
echo
echo "Status:"
pct exec "$CTID" -- systemctl --no-pager --full status viking-iptv || true
