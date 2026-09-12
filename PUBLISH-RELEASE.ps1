$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ConfigFile = Join-Path $PSScriptRoot 'PUBLISH-CONFIG.ps1'
$ExampleConfigFile = Join-Path $PSScriptRoot 'PUBLISH-CONFIG.example.ps1'

if (-not (Test-Path $ConfigFile)) {
    if (Test-Path $ExampleConfigFile) {
        Copy-Item $ExampleConfigFile $ConfigFile -Force
        Write-Host 'PUBLISH-CONFIG.ps1 saknades och har skapats automatiskt.' -ForegroundColor Yellow
        Write-Host 'Fyll i GitHub-token i filen och kör sedan scriptet igen.' -ForegroundColor Yellow
        Start-Process notepad.exe $ConfigFile
        exit 2
    }

    throw 'PUBLISH-CONFIG.ps1 och PUBLISH-CONFIG.example.ps1 saknas.'
}

. $ConfigFile

if (-not $GitHubOwner) {
    throw 'GitHubOwner saknas i PUBLISH-CONFIG.ps1.'
}
if (-not $GitHubRepo) {
    throw 'GitHubRepo saknas i PUBLISH-CONFIG.ps1.'
}
if (-not $GitHubToken -or $GitHubToken -eq 'PASTE_YOUR_GITHUB_TOKEN_HERE') {
    Write-Host ''
    Write-Host 'GitHub-token saknas i PUBLISH-CONFIG.ps1.' -ForegroundColor Yellow
    Write-Host 'Filen öppnas nu i Anteckningar.' -ForegroundColor Cyan
    Write-Host 'Klistra in token på raden $GitHubToken = "...", spara och kör PUBLISH-RELEASE.cmd igen.' -ForegroundColor Cyan
    Start-Process notepad.exe $ConfigFile
    exit 2
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

function Invoke-Gh {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $previousGhToken = $env:GH_TOKEN
    $previousGithubToken = $env:GITHUB_TOKEN

    try {
        $env:GH_TOKEN = $GitHubToken
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & gh @Arguments
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldEap
        }

        if (-not $IgnoreExitCode -and $exitCode -ne 0) {
            throw "GitHub CLI-kommandot misslyckades. Felkod: $exitCode"
        }

        return $exitCode
    }
    finally {
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
    }
}

function Invoke-NormalGitPush {
    param([Parameter(Mandatory=$true)][scriptblock]$Command)

    $previousGhToken = $env:GH_TOKEN
    $previousGithubToken = $env:GITHUB_TOKEN

    try {
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        & $Command
        return $LASTEXITCODE
    }
    finally {
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
    }
}

Write-Host "=== Viking IPTV Release Publisher $Tag ===" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host ''

Require-Command git 'Installera Git for Windows.'
Require-Command gh 'Installera GitHub CLI: winget install --id GitHub.cli -e'

Write-Host '[1/8] Verifierar GitHub-token för release...'
Invoke-Gh -Arguments @('auth','status','--hostname','github.com') | Out-Null

Write-Host '[2/8] Verifierar projektet...'
if (-not (Test-Path '.\app\VikingIptv.csproj')) { throw 'app\VikingIptv.csproj saknas.' }
if (-not (Test-Path '.\install-lxc.sh')) { throw 'install-lxc.sh saknas.' }

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    & dotnet build '.\app\VikingIptv.csproj' -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build misslyckades.' }
} else {
    Write-Host 'INFO: .NET SDK saknas lokalt. Appen byggs i LXC vid installation.' -ForegroundColor Yellow
}

Write-Host '[3/8] Förbereder Git repository...'
if (-not (Test-Path '.git')) {
    & git init
    if ($LASTEXITCODE -ne 0) { throw 'git init misslyckades.' }
}

& git checkout -B $Branch
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte aktivera main.' }

$remoteUrl = "https://github.com/$Repo.git"
$remotes = @(& git remote)
if ($remotes -contains 'origin') {
    & git remote set-url origin $remoteUrl
} else {
    & git remote add origin $remoteUrl
}

# Safety: token file must never be tracked
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & git rm --cached --ignore-unmatch PUBLISH-CONFIG.ps1 *> $null
    $trackedConfig = & git ls-files --error-unmatch PUBLISH-CONFIG.ps1 2>$null
    $trackedExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $oldEap
}

if ($trackedExit -eq 0 -and $trackedConfig) {
    throw 'SÄKERHETSSTOPP: PUBLISH-CONFIG.ps1 är spårad av Git.'
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

Write-Host '[4/8] Pushar main med befintlig Git-inloggning...'
$pushExit = Invoke-NormalGitPush { git push -u origin $Branch }
if ($pushExit -ne 0) {
    throw 'Push av main misslyckades. Kontrollera Git Credential Manager / vanlig Git-inloggning.'
}

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

Write-Host '[6/8] Skapar och pushar tagg...'
& git tag -f $Tag
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte skapa tagg.' }

$tagPushExit = Invoke-NormalGitPush { git push origin $Tag --force }
if ($tagPushExit -ne 0) {
    throw 'Push av tagg misslyckades. Kontrollera Git Credential Manager / vanlig Git-inloggning.'
}

Write-Host '[7/8] Skapar GitHub Release...'
$releaseViewExit = Invoke-Gh -Arguments @('release','view',$Tag,'--repo',$Repo) -IgnoreExitCode
$releaseExists = ($releaseViewExit -eq 0)

if ($releaseExists) {
    Write-Host "Release $Tag finns redan. Uppdaterar asset..." -ForegroundColor Yellow
    Invoke-Gh -Arguments @('release','upload',$Tag,$AssetPath,'--repo',$Repo,'--clobber') | Out-Null
} else {
    Invoke-Gh -Arguments @(
        'release','create',$Tag,$AssetPath,
        '--repo',$Repo,
        '--title',"Viking IPTV $Tag",
        '--generate-notes',
        '--latest'
    ) | Out-Null
}

Write-Host '[8/8] KLART.' -ForegroundColor Green
Write-Host "Release: https://github.com/$Repo/releases/tag/$Tag"
Write-Host ''
Write-Host 'Installera senaste release i Proxmox:' -ForegroundColor Cyan
Write-Host "bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
Write-Host ''
Write-Host 'Installera exakt denna version:' -ForegroundColor Cyan
Write-Host "VERSION=$Version bash -c `"`$(curl -fsSL https://raw.githubusercontent.com/$Repo/main/install-lxc.sh)`""
