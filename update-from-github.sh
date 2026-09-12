#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-tuffysan/Viking}"
VERSION="${VERSION:-latest}"
CTID="${CTID:-}"

die() { printf 'FEL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Kör som root på Proxmox-hosten."
command -v pct >/dev/null 2>&1 || die "pct saknas."

if [[ -z "$CTID" ]]; then
  CTID="$(grep -l '^hostname: viking-iptv$' /etc/pve/lxc/*.conf 2>/dev/null \
    | sed -n 's#.*/\([0-9]\+\)\.conf#\1#p' | head -n1 || true)"
fi
[[ -n "$CTID" ]] || die "Kunde inte hitta Viking IPTV-container. Ange CTID=<id>."

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
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

echo "Uppdaterar CT $CTID till Viking IPTV $TAG..."
pct exec "$CTID" -- bash -lc "curl -fL '$URL' -o /opt/viking-iptv/app.zip"
pct exec "$CTID" -- bash -lc '
set -Eeuo pipefail
rm -rf /opt/viking-iptv/src
mkdir -p /opt/viking-iptv/src
unzip -q /opt/viking-iptv/app.zip -d /opt/viking-iptv/src
rm -rf /opt/viking-iptv/publish
dotnet publish /opt/viking-iptv/src/app/VikingIptv.csproj -c Release -o /opt/viking-iptv/publish
systemctl restart viking-iptv.service
sleep 2
systemctl --no-pager --full status viking-iptv.service
'
echo "Klart. Viking IPTV är nu $TAG."
