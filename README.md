# Viking IPTV LXC

Version **1.7.2**

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
8. skapar `v1.7.2`
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

Exakt v1.7.2:

```bash
VERSION=1.7.2 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
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
