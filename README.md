# Viking IPTV LXC

Version **1.7.6**

Detta är den korrigerade releaseversionen. Ingen lokal GitHub-token ska ligga i projektet.

## Publicera

Förutsättning:

```powershell
gh auth status
```

Du ska vara inloggad som `tuffysan`.

Kör sedan:

```powershell
.\VERIFY-PACKAGE.ps1
.\PUBLISH-RELEASE.cmd
```

`PUBLISH-RELEASE.ps1` gör automatiskt följande:

1. tar bort gamla `GITHUB_TOKEN` och `GH_TOKEN` från den aktuella processen
2. använder din befintliga GitHub CLI keyring-inloggning
3. tar bort en gammal `PUBLISH-CONFIG.ps1` om den ligger kvar lokalt
4. stoppar publiceringen om en GitHub-token hittas i projektet
5. reparerar den tidigare lokala blockerade v1.7.0-committen om den innehåller `PUBLISH-CONFIG.ps1`
6. bygger .NET-projektet
7. committar och pushar `main`
8. skapar `v1.7.6`
9. skapar GitHub Release och laddar upp release-ZIP

## Repository

```text
https://github.com/tuffysan/Viking
```

## Proxmox

Senaste release:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

Exakt v1.7.6:

```bash
VERSION=1.7.6 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

## LXC

- Debian 12
- hostname `viking-iptv`
- 2 CPU
- 1024 MB RAM
- 8 GB disk
- DHCP
- `vmbr0`
- .NET 10
- port 8080


## Proxmox-installation i v1.7.6

Normal installation:

```bash
VERSION=1.7.6 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

Installeraren:
- använder `CT_HOSTNAME=viking-iptv` och påverkas inte av Proxmox-hostens `HOSTNAME`
- väljer automatiskt ett ledigt CTID
- använder `local-lvm` bara när thin-poolen ligger under säkerhetsgränsen
- faller annars tillbaka till `local`
- aktiverar automatiskt `rootdir` på `local` och bevarar övriga content-typer
- kontrollerar ledigt utrymme
- försöker automatiskt med `local` om `local-lvm` ändå vägrar skapa volym

Manuell override är fortfarande möjlig:

```bash
CTID=200 CT_HOSTNAME=viking-test STORAGE=local VERSION=1.7.6 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```
