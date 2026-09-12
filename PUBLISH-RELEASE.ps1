$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Repo = 'tuffysan/viking-iptv-lxc'
$Branch = 'main'
$Version = (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
$Tag = "v$Version"
$ReleaseDir = Join-Path $PSScriptRoot 'release'
$AssetName = "viking-iptv-$Tag.zip"
$AssetPath = Join-Path $ReleaseDir $AssetName

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name saknas. $Hint"
    }
}

Write-Host "=== Viking IPTV Release Publisher $Tag ===" -ForegroundColor Cyan

Require-Command git 'Installera Git for Windows.'
Require-Command gh 'Installera GitHub CLI: winget install --id GitHub.cli -e'

Write-Host '[1/8] Kontrollerar GitHub-inloggning...'
& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI är inte inloggad. Kör först: gh auth login'
}

Write-Host '[2/8] Verifierar projektet...'
if (-not (Test-Path '.\app\VikingIptv.csproj')) {
    throw 'app\VikingIptv.csproj saknas.'
}
if (-not (Test-Path '.\install-lxc.sh')) {
    throw 'install-lxc.sh saknas.'
}

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet build '.\app\VikingIptv.csproj' -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build misslyckades.' }
} else {
    Write-Host 'INFO: .NET SDK saknas lokalt. Releasepaketet innehåller källkod och byggs i LXC.' -ForegroundColor Yellow
}

Write-Host '[3/8] Förbereder Git repository...'
if (-not (Test-Path '.git')) {
    & git init
    if ($LASTEXITCODE -ne 0) { throw 'git init misslyckades.' }
}

& git checkout -B $Branch
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte aktivera main.' }

$remotes = @(& git remote)
if ($remotes -contains 'origin') {
    & git remote set-url origin "https://github.com/$Repo.git"
} else {
    & git remote add origin "https://github.com/$Repo.git"
}

& git add -A
if ($LASTEXITCODE -ne 0) { throw 'git add misslyckades.' }

$changes = & git diff --cached --name-only
if ($changes) {
    & git commit -m "Viking IPTV $Tag"
    if ($LASTEXITCODE -ne 0) { throw 'git commit misslyckades.' }
} else {
    Write-Host 'Inga nya ändringar att committa.'
}

Write-Host '[4/8] Pushar main...'
& git push -u origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'Push av main misslyckades.' }

Write-Host '[5/8] Skapar releasepaket...'
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir | Out-Null

$staging = Join-Path $ReleaseDir 'staging'
New-Item -ItemType Directory -Path $staging | Out-Null

$include = @(
    'VERSION',
    'README.md',
    'install-lxc.sh',
    'update-from-github.sh',
    'app',
    'scripts'
)

foreach ($item in $include) {
    $source = Join-Path $PSScriptRoot $item
    if (Test-Path $source) {
        Copy-Item $source $staging -Recurse -Force
    }
}

Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $AssetPath -Force
Remove-Item $staging -Recurse -Force

Write-Host "Releaseasset: $AssetPath"

Write-Host '[6/8] Skapar/pushar tag...'
& git tag -f $Tag
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte skapa tag.' }

& git push origin $Tag --force
if ($LASTEXITCODE -ne 0) { throw 'Push av tag misslyckades.' }

Write-Host '[7/8] Skapar GitHub Release...'
& gh release view $Tag --repo $Repo *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Release $Tag finns redan. Uppdaterar asset..." -ForegroundColor Yellow
    & gh release upload $Tag $AssetPath --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw 'Upload av releaseasset misslyckades.' }
} else {
    & gh release create $Tag $AssetPath --repo $Repo --title "Viking IPTV $Tag" --generate-notes --latest
    if ($LASTEXITCODE -ne 0) { throw 'Kunde inte skapa GitHub Release.' }
}

Write-Host '[8/8] KLART.' -ForegroundColor Green
Write-Host "Release: https://github.com/$Repo/releases/tag/$Tag"
Write-Host ''
Write-Host 'Installera senaste releasen i Proxmox med:' -ForegroundColor Cyan
Write-Host 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)"'
Write-Host ''
Write-Host 'Installera exakt denna version med:' -ForegroundColor Cyan
Write-Host "VERSION=$Version bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/tuffysan/viking-iptv-lxc/main/install-lxc.sh)`""
