#!/usr/bin/env bash
set -euo pipefail
APP_DIR=/opt/viking-iptv-src
REPO_URL="${REPO_URL:-https://github.com/tuffysan/viking-iptv-lxc.git}"
BRANCH="${BRANCH:-main}"
if [[ ! -d "$APP_DIR/.git" ]]; then rm -rf "$APP_DIR"; git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"; else cd "$APP_DIR"; git fetch origin "$BRANCH"; git reset --hard "origin/$BRANCH"; fi
cd "$APP_DIR/app"
dotnet publish -c Release -o /opt/viking-iptv/app
systemctl restart viking-iptv
systemctl --no-pager --full status viking-iptv | head -20
