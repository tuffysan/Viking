# Viking IPTV LXC

Version: **1.5.0**

Komplett Proxmox LXC-projekt för en webbapp som hanterar nya Viking IPTV-beställningar, förlängning av befintliga konton, orderhistorik, kontoöversikt och en separat administratörsdefinierad serviceavgift via Swish.

## Viktigt

Det här paketet är gjort för **manuell publicering till GitHub**. Det innehåller därför inga scripts som försöker logga in på GitHub eller skapa repository automatiskt.

Repository som används av installations- och uppdateringsscript:

`https://github.com/tuffysan/viking-iptv-lxc`

Se `MANUAL-GITHUB-UPLOAD.md` för steg-för-steg-publicering.

## Funktioner

- Dashboard
- Ny prenumeration
- Förlängning av befintligt konto
- Kontohantering
- Orderhistorik
- Admininställningar
- Obligatorisk serviceavgift
- Eget Swish-nummer för serviceavgiften
- Eget mottagarnamn
- Unik betalningsreferens per order
- Betalningsstatus för serviceavgift
- Separat visning av leverantörens betalning och serviceavgiften
- Viking/Safello-länkar
- Krypterad lagring av känsliga konto-/Xtream-uppgifter via ASP.NET Core Data Protection
- Provider health-check
- Proxmox LXC-installation
- GitHub-baserad uppdatering

## Projektstruktur

```text
.
├── .gitignore
├── README.md
├── MANUAL-GITHUB-UPLOAD.md
├── VERIFY-PACKAGE.ps1
├── VERSION
├── install-lxc.sh
├── update-from-github.sh
├── scripts/
└── app/
    ├── VikingIptv.csproj
    ├── Program.cs
    └── wwwroot/
        ├── index.html
        ├── app.js
        └── app.css
```

## Verifiera projektet i Windows

```powershell
cd "C:\Users\andreas.nilsson\Documents\GitHub\viking-iptv-lxc"
.\VERIFY-PACKAGE.ps1
```

## Publicera till GitHub

Följ instruktionerna i:

`MANUAL-GITHUB-UPLOAD.md`

## Installera på Proxmox

När projektet finns på GitHub kör du som `root` på Proxmox:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Exempel med eget CTID:

```bash
CTID=165 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

## Standardvärden för LXC

- Hostname: `viking-iptv`
- Display name: Viking IPTV
- Debian 12
- .NET 10
- 2 CPU
- 1024 MB RAM
- 8 GB disk
- DHCP
- Bridge: `vmbr0`
- Webbport: `8080`

## Data

Applikationsdata:

```text
/var/lib/viking-iptv/data.json
```

Data Protection-nycklar:

```text
/var/lib/viking-iptv/keys
```

## Systemd

Tjänst:

```text
viking-iptv
```

Status:

```bash
systemctl status viking-iptv
```

Logg:

```bash
journalctl -u viking-iptv -f
```

## Uppdatering

Efter att nya versioner publicerats till `main`:

```bash
bash update-from-github.sh
```

eller enligt instruktionerna i projektets uppdateringsscript.

## Betalningsmodell

Serviceavgiften i appen är separat från Viking IPTV:s egna priser och betalning. Den konfigureras av administratören och visas som en separat obligatorisk avgift. Appen automatiserar inte BankID- eller Swish-godkännande och lagrar inga Swish- eller BankID-autentiseringsuppgifter.


## Skapa GitHub Release

När repositoryt redan finns på GitHub och `gh auth status` fungerar:

```powershell
.\VERIFY-PACKAGE.ps1
.\PUBLISH-RELEASE.cmd
```

Scriptet:

1. verifierar GitHub-inloggningen
2. bygger projektet om .NET SDK finns lokalt
3. committar och pushar `main`
4. skapar ett release-ZIP
5. skapar/pushar taggen `v<VERSION>`
6. skapar en GitHub Release
7. laddar upp `viking-iptv-v<VERSION>.zip` som releaseasset

## Installera senaste GitHub Release i Proxmox

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Installera en specifik version:

```bash
VERSION=1.5.0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Installationsscriptet laddar releaseasset från GitHub Releases och bygger applikationen inne i LXC:n.
