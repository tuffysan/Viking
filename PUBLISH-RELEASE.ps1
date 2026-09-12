$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$GitHubOwner = "tuffysan"
$GitHubRepo = "Viking"
$Repo = "$GitHubOwner/$GitHubRepo"
$Branch = "main"
$Version = (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
$Tag = "v$Version"
$ReleaseDir = Join-Path $PSScriptRoot "release"
$AssetName = "viking-iptv-$Tag.zip"
$AssetPath = Join-Path $ReleaseDir $AssetName

function Require-Command {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Hint
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is missing. $Hint"
    }
}

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$Args)

    & git @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Test-FileForGithubToken {
    param([Parameter(Mandatory=$true)][string]$Path)

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    }
    catch {
        return $false
    }

    $patterns = @(
        "github_pat_[A-Za-z0-9_]{20,}",
        "ghp_[A-Za-z0-9]{20,}",
        "gho_[A-Za-z0-9]{20,}",
        "ghu_[A-Za-z0-9]{20,}",
        "ghs_[A-Za-z0-9]{20,}",
        "ghr_[A-Za-z0-9]{20,}"
    )

    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            return $true
        }
    }

    return $false
}

function Assert-NoGithubTokens {
    $excludedDirectoryNames = @(".git", "release", "bin", "obj")

    $files = Get-ChildItem -Path $PSScriptRoot -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\','/')
        $parts = $relative -split '[\\/]'

        $skip = $false
        foreach ($part in $parts) {
            if ($excludedDirectoryNames -contains $part) {
                $skip = $true
                break
            }
        }

        if ($skip) {
            continue
        }

        if (Test-FileForGithubToken -Path $file.FullName) {
            throw "SECURITY STOP: possible GitHub token found in $($file.FullName)"
        }
    }
}

Write-Host "=== Viking IPTV Release Publisher $Tag ===" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host ""

Require-Command -Name "git" -Hint "Install Git for Windows."
Require-Command -Name "gh" -Hint "Install GitHub CLI."

# Environment tokens override the keyring login. Do not use them here.
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue

# Old versions used this file. It must never be committed again.
$LegacyConfig = Join-Path $PSScriptRoot "PUBLISH-CONFIG.ps1"
if (Test-Path $LegacyConfig) {
    Write-Host "Removing legacy PUBLISH-CONFIG.ps1..." -ForegroundColor Yellow
    Remove-Item $LegacyConfig -Force
}

Write-Host "[1/9] Checking GitHub CLI login..."
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not logged in. Run: gh auth login"
}

Write-Host "[2/9] Scanning project for GitHub tokens..."
Assert-NoGithubTokens

Write-Host "[3/9] Building project..."
if (-not (Test-Path ".\app\VikingIptv.csproj")) {
    throw "app\VikingIptv.csproj is missing."
}

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet build ".\app\VikingIptv.csproj" -c Release --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed."
    }
}
else {
    Write-Host "INFO: dotnet SDK is not installed locally. Build will happen in LXC." -ForegroundColor Yellow
}

Write-Host "[4/9] Preparing Git..."
if (-not (Test-Path ".git")) {
    Invoke-Git -Args @("init")
}

$originExists = $false
& git remote get-url origin *> $null
if ($LASTEXITCODE -eq 0) {
    $originExists = $true
}

if ($originExists) {
    Invoke-Git -Args @("remote","set-url","origin","https://github.com/$Repo.git")
}
else {
    Invoke-Git -Args @("remote","add","origin","https://github.com/$Repo.git")
}

# Fetch remote main if possible.
& git fetch origin $Branch
$fetchSucceeded = ($LASTEXITCODE -eq 0)

# Repair a previous local blocked commit if it contained the legacy config.
if ($fetchSucceeded) {
    $aheadText = (& git rev-list --count "origin/$Branch..HEAD" 2>$null)
    $ahead = 0
    if ($aheadText -match '^\d+$') {
        $ahead = [int]$aheadText
    }

    if ($ahead -gt 0) {
        $historyFiles = & git log --name-only --pretty=format: "origin/$Branch..HEAD" 2>$null
        if ($historyFiles -contains "PUBLISH-CONFIG.ps1") {
            Write-Host "Repairing previous local blocked commit..." -ForegroundColor Yellow
            Invoke-Git -Args @("reset","--soft","origin/$Branch")
        }
    }
}

Invoke-Git -Args @("checkout","-B",$Branch)

# Make sure the legacy file cannot remain tracked.
& git rm --cached --ignore-unmatch PUBLISH-CONFIG.ps1 *> $null

Invoke-Git -Args @("add","-A")

$trackedLegacy = & git ls-files PUBLISH-CONFIG.ps1
if ($trackedLegacy) {
    throw "SECURITY STOP: PUBLISH-CONFIG.ps1 is still tracked by Git."
}

# Scan staged patch for token patterns.
$stagedPatch = (& git diff --cached) -join "`n"
if ($stagedPatch -match "github_pat_[A-Za-z0-9_]{20,}" -or
    $stagedPatch -match "ghp_[A-Za-z0-9]{20,}" -or
    $stagedPatch -match "gho_[A-Za-z0-9]{20,}" -or
    $stagedPatch -match "ghu_[A-Za-z0-9]{20,}" -or
    $stagedPatch -match "ghs_[A-Za-z0-9]{20,}" -or
    $stagedPatch -match "ghr_[A-Za-z0-9]{20,}") {
    throw "SECURITY STOP: GitHub token found in staged changes."
}

$changes = & git diff --cached --name-only
if ($changes) {
    Invoke-Git -Args @("commit","-m","Viking IPTV $Tag")
}
else {
    Write-Host "No new changes to commit."
}

Write-Host "[5/9] Pushing main..."
Invoke-Git -Args @("push","-u","origin",$Branch)

Write-Host "[6/9] Creating release package..."
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}

New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
$StagingDir = Join-Path $ReleaseDir "staging"
New-Item -ItemType Directory -Path $StagingDir | Out-Null

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
        Copy-Item $source $StagingDir -Recurse -Force
    }
}

Compress-Archive -Path (Join-Path $StagingDir "*") -DestinationPath $AssetPath -Force
Remove-Item $StagingDir -Recurse -Force

Write-Host "Release asset: $AssetPath"

Write-Host "[7/9] Creating and pushing tag..."
& git rev-parse -q --verify "refs/tags/$Tag" *> $null
$localTagExists = ($LASTEXITCODE -eq 0)

if ($localTagExists) {
    Invoke-Git -Args @("tag","-d",$Tag)
}

& git ls-remote --exit-code --tags origin "refs/tags/$Tag" *> $null
$remoteTagExists = ($LASTEXITCODE -eq 0)

if ($remoteTagExists) {
    Invoke-Git -Args @("push","origin",":refs/tags/$Tag")
}

Invoke-Git -Args @("tag",$Tag)
Invoke-Git -Args @("push","origin",$Tag)

Write-Host "[8/9] Creating or updating GitHub Release..."

$releaseExists = $false
try {
    & gh release view $Tag --repo $Repo *> $null
    if ($LASTEXITCODE -eq 0) {
        $releaseExists = $true
    }
}
catch {
    # GitHub CLI writes "release not found" to stderr. In Windows PowerShell 5.1
    # that can be promoted to NativeCommandError even though this is an expected
    # condition for a new release. Treat it as "release does not exist".
    $releaseExists = $false
}

if ($releaseExists) {
    & gh release upload $Tag $AssetPath --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload release asset."
    }
}
else {
    & gh release create $Tag $AssetPath --repo $Repo --title "Viking IPTV $Tag" --generate-notes --latest
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub Release."
    }
}

Write-Host "[9/9] DONE." -ForegroundColor Green
Write-Host "Release: https://github.com/$Repo/releases/tag/$Tag"
Write-Host ""
Write-Host "Proxmox latest release:" -ForegroundColor Cyan
Write-Host ('bash -c "$(curl -fsSL https://raw.githubusercontent.com/{0}/main/install-lxc.sh)"' -f $Repo)
Write-Host ""
Write-Host ("Proxmox exact version {0}:" -f $Version) -ForegroundColor Cyan
Write-Host ('VERSION={0} bash -c "$(curl -fsSL https://raw.githubusercontent.com/{1}/main/install-lxc.sh)"' -f $Version,$Repo)
