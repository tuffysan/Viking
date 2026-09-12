# Releaseguide – Viking IPTV v1.7.6

## Viktigt

Det finns **ingen** `PUBLISH-CONFIG.ps1` i detta paket och du ska inte skapa någon.

GitHub CLI använder den inloggning som redan finns i Windows Credential Manager / keyring.

## Kontrollera

```powershell
gh auth status
git remote -v
```

Förväntat repo:

```text
https://github.com/tuffysan/Viking.git
```

## Publicera

```powershell
.\VERIFY-PACKAGE.ps1
.\PUBLISH-RELEASE.cmd
```

Scriptet kan även reparera den tidigare lokala committen som GitHub blockerade på grund av en PAT i `PUBLISH-CONFIG.ps1`.
