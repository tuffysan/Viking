$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$GitHubOwner = "tuffysan"
$GitHubRepo  = "Viking"
$Repo        = "$GitHubOwner/$GitHubRepo"
$Branch      = "main"
$Version     = (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
$Tag         = "v$Version"
$ReleaseDir  = Join-Path $PSScriptRoot "release"
$AssetName   = "viking-iptv-$Tag.zip"
$AssetPath   = Join-Path $ReleaseDir $AssetName

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name saknas. $Hint"
    }
}

function Run-Git {
    param([Parameter(Mandatory=$true)][string[]]$Args)
    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') misslyckades. Felkod: $LASTEXITCODE"
    }
}

function Assert-NoSecrets {
    $patterns = @(
        'github_pat_[A-Za-z0-9_]{20,}',
        'ghp_[A-Za-z0-9]{20,}',
        'gho_[A-Za-z0-9]{20,}',
        'ghu_[A-Za-z0-9]{20,}',
        'ghs_[A-Za-z0-9]{20,}',
        'ghr_[A-Za-z0-9]{20,}'
    )

    $excluded = @('.git', 'release', 'bin', 'obj')
    $files = Get-ChildItem -Path $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $relative = $_.FullName.Substring($PSScriptRoot.Length).TrimStart('\','/')
            $segments = $relative -split '[\\/]'
            -not ($segments | Where-Object { $excluded -contains $_ })
        }

    foreach ($file in $files) {
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($pattern in $patterns) {
            if ($content -match $pattern) {
                throw "SÄKERHETSSTOPP: möjlig GitHub-token hittades i $($file.FullName). Ta bort den innan publicering."
            }
        }
    }
}

Write-Host "=== Viking IPTV Release Publisher $Tag ===" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host ""

Require-Command git "Installera Git for Windows."
Require-Command gh  "Installera GitHub CLI: winget install --id GitHub.cli -e"

# Old environment tokens have caused gh to ignore the valid keyring login.
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue

# Remove legacy credential file before Git sees it.
$legacyConfig = Join-Path $PSScriptRoot "PUBLISH-CONFIG.ps1"
if (Test-Path $legacyConfig) {
    Write-Host "Tar bort gammal PUBLISH-CONFIG.ps1..." -ForegroundColor Yellow
    Remove-Item $legacyConfig -Force
}

Write-Host "[1/9] Kontrollerar GitHub-inloggning..."
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI är inte inloggad. Kör 'gh auth login' och välj GitHub.com + HTTPS."
}

Write-Host "[2/9] Kontrollerar att inga GitHub-tokens finns i projektfiler..."
Assert-NoSecrets

Write-Host "[3/9] Bygger projektet..."
if (-not (Test-Path ".\app\VikingIptv.csproj")) {
    throw "app\VikingIptv.csproj saknas."
}
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet build ".\app\VikingIptv.csproj" -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "dotnet build misslyckades." }
} else {
    Write-Host "INFO: .NET SDK saknas lokalt. Appen byggs i LXC vid installation." -ForegroundColor Yellow
}

Write-Host "[4/9] Förbereder och reparerar Git-repot vid behov..."
if (-not (Test-Path ".git")) {
    Run-Git @("init")
}

$originExists = $false
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& git remote get-url origin *> $null
$originExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $oldEap

if ($originExists) {
    Run-Git @("remote","set-url","origin","https://github.com/$Repo.git")
} else {
    Run-Git @("remote","add","origin","https://github.com/$Repo.git")
}

# Fetch current remote main if it exists.
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& git fetch origin $Branch
$fetchExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap

# If the previously blocked local commit is still ahead and contains
# PUBLISH-CONFIG.ps1, flatten only the unpushed local commits back onto origin/main.
if ($fetchExit -eq 0) {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $ahead = (& git rev-list --count "origin/$Branch..HEAD" 2>$null)
    $ErrorActionPreference = $oldEap

    if ($ahead -and [int]$ahead -gt 0) {
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $badHistory = & git log --name-only --pretty=format: "origin/$Branch..HEAD" 2>$null |
            Where-Object { $_ -eq "PUBLISH-CONFIG.ps1" }
        $ErrorActionPreference = $oldEap

        if ($badHistory) {
            Write-Host "Reparerar tidigare blockerad lokal commit med PUBLISH-CONFIG.ps1..." -ForegroundColor Yellow
            Run-Git @("reset","--soft","origin/$Branch")
        }
    }
}

Run-Git @("checkout","-B",$Branch)

# Ensure old file cannot be tracked even if it existed in index.
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& git rm --cached --ignore-unmatch PUBLISH-CONFIG.ps1 *> $null
$ErrorActionPreference = $oldEap

Run-Git @("add","-A")

$trackedLegacy = & git ls-files PUBLISH-CONFIG.ps1
if ($trackedLegacy) {
    throw "SÄKERHETSSTOPP: PUBLISH-CONFIG.ps1 är fortfarande spårad av Git."
}

# Also scan staged diff for token-like strings.
$staged = & git diff --cached
if ($staged -match 'github_pat_[A-Za-z0-9_]{20,}' -or
    $staged -match 'gh[pousr]_[A-Za-z0-9]{20,}') {
    throw "SÄKERHETSSTOPP: en GitHub-token finns i staged Git-ändringar."
}

$changes = & git diff --cached --name-only
if ($changes) {
    Run-Git @("commit","-m","Viking IPTV $Tag")
} else {
    Write-Host "Inga nya ändringar att committa."
}

Write-Host "[5/9] Pushar main..."
Run-Git @("push","-u","origin",$Branch)

Write-Host "[6/9] Skapar releasepaket..."
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
$stagingDir = Join-Path $ReleaseDir "staging"
New-Item -ItemType Directory -Path $stagingDir | Out-Null

$include = @(
    "VERSION",
    "README.md",
    "MANUAL-GITHUB-UPLOAD.md",
    "install-lxc.sh",
    "update-from-github.sh",
    "app"
)

foreach ($item in $include) {
    $source = Join-Path $PSScriptRoot $item
    if (Test-Path $source) {
        Copy-Item $source $stagingDir -Recurse -Force
    }
}

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $AssetPath -Force
Remove-Item $stagingDir -Recurse -Force
Write-Host "Releaseasset: $AssetPath"

Write-Host "[7/9] Skapar och pushar tagg..."
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& git tag -d $Tag *> $null
$ErrorActionPreference = $oldEap
Run-Git @("tag",$Tag)
Run-Git @("push","origin",$Tag,"--force")

Write-Host "[8/9] Skapar eller uppdaterar GitHub Release..."
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& gh release view $Tag --repo $Repo *> $null
$releaseExists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $oldEap

if ($releaseExists) {
    & gh release upload $Tag $AssetPath --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw "Kunde inte uppdatera releaseasset." }
} else {
    & gh release create $Tag $AssetPath --repo $Repo --title "Viking IPTV $Tag" --generate-notes --latest
    if ($LASTEXITCODE -ne 0) { throw "Kunde inte skapa GitHub Release." }
}

Write-Host "[9/9] KLART." -ForegroundColor Green
Write-Host "Release: https://github.com/$Repo/releases/tag/$Tag"
Write-Host ""
Write-Host "Proxmox - senaste release:" -ForegroundColor Cyan
Write-Host "bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
Write-Host ""
Write-Host "Proxmox - exakt ${Version}:" -ForegroundColor Cyan
Write-Host "VERSION=$Version bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
