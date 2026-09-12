# GitHub och release – Viking IPTV v1.6.4

## Första gången

1. Packa upp projektet.
2. Öppna `PUBLISH-CONFIG.ps1`.
3. Fyll i din token.
4. Kör:

```powershell
.\VERIFY-PACKAGE.ps1
.\PUBLISH-RELEASE.cmd
```

## Token

Rekommenderad Fine-grained Personal Access Token:

```text
Resource owner: tuffysan
Repository: Viking
Contents: Read and write
```

Token används endast av GitHub CLI för releasefunktionerna.

Vanlig `git push` använder din befintliga Git Credential Manager-inloggning.

## Om PUBLISH-CONFIG.ps1 saknas

`PUBLISH-RELEASE.ps1` skapar automatiskt filen från `PUBLISH-CONFIG.example.ps1`, öppnar den i Anteckningar och ber dig fylla i token.

## Proxmox

Senaste release:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```

Specifik release:

```bash
VERSION=1.6.4 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/Viking/main/install-lxc.sh)"
```
