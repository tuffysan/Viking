# Viking IPTV LXC

Version: **1.6.4**

Detta paket innehåller allt som behövs för:

- lokal utveckling
- verifiering
- Git push
- GitHub Release
- release-ZIP
- Proxmox LXC-installation
- versionsspecifik installation

## Viktiga filer

```text
PUBLISH-CONFIG.ps1
PUBLISH-CONFIG.example.ps1
PUBLISH-RELEASE.cmd
PUBLISH-RELEASE.ps1
VERIFY-PACKAGE.ps1
install-lxc.sh
update-from-github.sh
VERSION
app/
```

## 1. Fyll i GitHub-token

Öppna:

```powershell
notepad .\PUBLISH-CONFIG.ps1
```

Standard:

```powershell
$GitHubOwner = "tuffysan"
$GitHubRepo  = "Viking"
$GitHubToken = "PASTE_YOUR_GITHUB_TOKEN_HERE"
```

Ersätt bara tokenvärdet.

`PUBLISH-CONFIG.ps1` är medvetet ignorerad av Git och ska inte pushas.

## 2. Verifiera

```powershell
.\VERIFY-PACKAGE.ps1
```

## 3. Publicera release

```powershell
.\PUBLISH-RELEASE.cmd
```

Flödet:

1. verifierar release-token
2. bygger .NET-projektet
3. committar ändringar
4. pushar `main` med din vanliga Git-inloggning
5. skapar release-ZIP
6. pushar versionstaggen med vanlig Git-inloggning
7. skapar/uppdaterar GitHub Release med token
8. visar färdigt Proxmox-installationskommando

## 4. Proxmox

Senaste release:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

Exakt v1.6.4:

```bash
VERSION=1.6.4 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

## Standard för LXC

- Debian 12
- hostname `viking-iptv`
- 2 CPU
- 1024 MB RAM
- 8 GB disk
- DHCP
- `vmbr0`
- .NET 10
- webbport 8080

## Data

Persistent data:

```text
/var/lib/viking-iptv
/var/lib/viking-iptv/keys
```

## Systemd

```bash
systemctl status viking-iptv
journalctl -u viking-iptv -f
```

## Säkerhet

Lägg aldrig en riktig GitHub-token i README, commit-historik eller någon annan fil som spåras av Git.
