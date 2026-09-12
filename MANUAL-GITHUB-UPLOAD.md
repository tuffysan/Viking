# Manuell GitHub-start och release-publicering

Repository:

`https://github.com/tuffysan/viking-iptv-lxc`

## Första uppladdningen

Du kan skapa repositoryt på GitHub och lägga upp projektet manuellt eller med Git.

Viktigt: `PUBLISH-CONFIG.ps1` innehåller din lokala token och är medvetet ignorerad av Git.

Kontrollera:

```powershell
git status
```

`PUBLISH-CONFIG.ps1` ska inte finnas bland filer som kommer att committas.

## Publicera nya versioner

Redigera:

```text
PUBLISH-CONFIG.ps1
```

Exempel:

```powershell
$GitHubOwner = "tuffysan"
$GitHubRepo  = "viking-iptv-lxc"
$GitHubToken = "github_pat_..."
```

Kör sedan:

```powershell
.\VERIFY-PACKAGE.ps1
.\PUBLISH-RELEASE.cmd
```

Release-scriptet använder token för Git-push och GitHub Release och återställer processens tidigare tokenmiljö när körningen är klar.

## Proxmox

Senaste release:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Specifik version:

```bash
VERSION=1.6.2 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```
