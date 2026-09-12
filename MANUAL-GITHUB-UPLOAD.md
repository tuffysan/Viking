# Publicera projektet manuellt till GitHub

Repository:

https://github.com/tuffysan/viking-iptv-lxc

## Alternativ A - GitHub webbsida

1. Logga in på GitHub.
2. Skapa repositoryt `viking-iptv-lxc` under kontot `tuffysan` om det inte redan finns.
3. Öppna repositoryt.
4. Välj **Add file** -> **Upload files**.
5. Dra in alla filer och mappar från den här projektmappen.
6. Skriv exempelvis commit-meddelandet:

   `Viking IPTV v1.5.0`

7. Välj **Commit changes**.

Viktigt: GitHub-webbuppladdning kan vara mindre smidig för många filer och mappar. Om webbläsaren inte tar emot hela strukturen, använd Git-klient enligt Alternativ B.

## Alternativ B - vanlig Git från PowerShell

Öppna PowerShell i projektmappen:

```powershell
cd "C:\Users\andreas.nilsson\Documents\GitHub\viking-iptv-lxc"
```

Initiera Git om `.git` saknas:

```powershell
git init
git branch -M main
```

Lägg till GitHub-repositoryt:

```powershell
git remote add origin https://github.com/tuffysan/viking-iptv-lxc.git
```

Om `origin` redan finns:

```powershell
git remote set-url origin https://github.com/tuffysan/viking-iptv-lxc.git
```

Lägg till och committa:

```powershell
git add .
git commit -m "Viking IPTV v1.5.0"
```

Pusha:

```powershell
git push -u origin main
```

Om Git frågar efter autentisering används normalt Git Credential Manager eller webbinloggning.

## Installera i Proxmox efter publicering

Kör som `root` på Proxmox:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```

Exempel med eget CTID:

```bash
CTID=165 bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"
```


## Skapa release efter första uppladdningen

När repositoryt finns på GitHub och GitHub CLI är inloggad:

```powershell
gh auth status
.\PUBLISH-RELEASE.cmd
```

Detta skapar en riktig GitHub Release med ett ZIP-asset som Proxmox-installern kan hämta.
