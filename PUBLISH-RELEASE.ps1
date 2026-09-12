$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ConfigFile = Join-Path $PSScriptRoot 'PUBLISH-CONFIG.ps1'
if (-not (Test-Path $ConfigFile)) {
    throw 'PUBLISH-CONFIG.ps1 saknas. Skapa den från PUBLISH-CONFIG.example.ps1.'
}

. $ConfigFile

if (-not $GitHubOwner -or -not $GitHubRepo) {
    throw 'GitHubOwner och GitHubRepo måste anges i PUBLISH-CONFIG.ps1.'
}

if (-not $GitHubToken -or $GitHubToken -eq 'PASTE_YOUR_GITHUB_TOKEN_HERE') {
    throw 'Ange din GitHub-token i PUBLISH-CONFIG.ps1 innan publicering.'
}

$Repo = "$GitHubOwner/$GitHubRepo"
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
Write-Host "Repository: $Repo"

Require-Command git 'Installera Git for Windows.'
Require-Command gh 'Installera GitHub CLI: winget install --id GitHub.cli -e'

# Använd token endast i denna process/session.
$previousGhToken = $env:GH_TOKEN
$previousGithubToken = $env:GITHUB_TOKEN

try {
    $env:GH_TOKEN = $GitHubToken
    Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

    Write-Host '[1/8] Verifierar GitHub-token...'
    & gh auth status --hostname github.com
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub-token är ogiltig eller saknar behörighet.'
    }

    # Configure git to use gh as credential helper for HTTPS pushes.
    & gh auth setup-git
    if ($LASTEXITCODE -ne 0) {
        throw 'Kunde inte konfigurera Git-autentisering via GitHub CLI.'
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
    $remoteUrl = "https://github.com/$Repo.git"
    if ($remotes -contains 'origin') {
        & git remote set-url origin $remoteUrl
    } else {
        & git remote add origin $remoteUrl
    }

    # Extra safety: local token config must never be tracked.
    & git rm --cached --ignore-unmatch PUBLISH-CONFIG.ps1 *> $null

    & git add -A
    if ($LASTEXITCODE -ne 0) { throw 'git add misslyckades.' }

    # Kontrollera säkert om den lokala tokenfilen råkat bli Git-spårad.
    # git ls-files --error-unmatch returnerar exit code 1 när filen INTE är spårad,
    # vilket är det normala och önskade fallet.
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $trackedConfig = & git ls-files --error-unmatch PUBLISH-CONFIG.ps1 2>$null
        $trackedConfigExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($trackedConfigExitCode -eq 0 -and $trackedConfig) {
        throw 'SÄKERHETSSTOPP: PUBLISH-CONFIG.ps1 är spårad av Git. Token får inte publiceras.'
    }
    elseif ($trackedConfigExitCode -ne 1 -and $trackedConfigExitCode -ne 0) {
        throw "Kunde inte kontrollera Git-status för PUBLISH-CONFIG.ps1. Git-felkod: $trackedConfigExitCode"
    }

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
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & gh release view $Tag --repo $Repo *> $null
        $releaseExists = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($releaseExists) {
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
    Write-Host "bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
    Write-Host ''
    Write-Host 'Installera exakt denna version med:' -ForegroundColor Cyan
    Write-Host "VERSION=$Version bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
}
finally {
    # Restore caller environment and clear the local variable copy.
    if ($null -eq $previousGhToken) {
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
    } else {
        $env:GH_TOKEN = $previousGhToken
    }

    if ($null -eq $previousGithubToken) {
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
    } else {
        $env:GITHUB_TOKEN = $previousGithubToken
    }

    $GitHubToken = $null
}
