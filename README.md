# Viking IPTV LXC

Version: **1.6.2**

Komplett Proxmox LXC-projekt med GitHub Release-publicering.

## GitHub-konfiguration

Filen `PUBLISH-CONFIG.ps1` används lokalt för repository och token:

```powershell
$GitHubOwner = "tuffysan"
$GitHubRepo  = "viking-iptv-lxc"
$GitHubToken = "github_pat_..."
```

`PUBLISH-CONFIG.ps1` ligger i `.gitignore` och ska aldrig publiceras till GitHub.

En säker mall finns som `PUBLISH-CONFIG.example.ps1`.

## Rekommenderad token

Använd en Fine-grained Personal Access Token begränsad till just repositoryt.

Repository permission:

```text
Contents: Read and write
```

## Verifiera projektet

```powershell
.\VERIFY-PACKAGE.ps1
```

## Skapa en GitHub Release

1. Öppna `PUBLISH-CONFIG.ps1`.
2. Ange owner, repository och token.
3. Kör:

```powershell
.\PUBLISH-RELEASE.cmd
```

Scriptet:

1. använder token endast i den aktuella processen
2. verifierar token
3. konfigurerar Git-autentisering via GitHub CLI
4. pushar `main`
5. skapar versionstaggen
6. skapar release-ZIP
7. skapar GitHub Release
8. laddar upp releaseasseten

Token skrivs inte till releasepaketet.

## Installera senaste releasen i Proxmox

När `install-lxc.sh` ligger på `main`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Installera exakt v1.6.2:

```bash
VERSION=1.6.2 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

## Standardvärden

- Hostname: `viking-iptv`
- Debian 12
- .NET 10
- 2 CPU
- 1024 MB RAM
- 8 GB disk
- Bridge: `vmbr0`
- DHCP
- Port: `8080`

## Data

```text
/var/lib/viking-iptv/data.json
/var/lib/viking-iptv/keys
```

## Systemd

```bash
systemctl status viking-iptv
journalctl -u viking-iptv -f
```

## Säkerhet

Lägg aldrig din riktiga GitHub-token i README, ett commit-meddelande eller någon fil som spåras av Git. Om en token råkar publiceras ska den återkallas direkt på GitHub och ersättas med en ny.


## Fix i v1.6.2

- `PUBLISH-RELEASE.cmd` använder nu Windows CRLF-radslut.
- CMD-filen är ren ASCII för maximal kompatibilitet med `cmd.exe`.
- PowerShell-scripten sparas med UTF-8 BOM så svenska tecken visas korrekt i Windows PowerShell 5.1.


## Fix i v1.6.2

- `PUBLISH-CONFIG.ps1` kan nu vara korrekt ignorerad utan att release-scriptet avbryts.
- `git ls-files --error-unmatch` exit code 1 behandlas som normalt för en ospårad tokenfil.
- Kontroll av befintlig GitHub Release hanterar nu också en saknad release utan att PowerShell stoppar.
