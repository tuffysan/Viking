$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$required = @(
  ".gitignore",
  "README.md",
  "MANUAL-GITHUB-UPLOAD.md",
  "PUBLISH-RELEASE.cmd",
  "PUBLISH-RELEASE.ps1",
  "VERIFY-PACKAGE.ps1",
  "VERSION",
  "install-lxc.sh",
  "update-from-github.sh",
  "app\VikingIptv.csproj",
  "app\Program.cs",
  "app\wwwroot\index.html",
  "app\wwwroot\app.js",
  "app\wwwroot\app.css"
)

$missing = $required | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) }
if ($missing) {
    Write-Host "ERROR: package is missing required files:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host " - $_" }
    exit 1
}

if (Test-Path ".\PUBLISH-CONFIG.ps1") {
    Write-Host "ERROR: PUBLISH-CONFIG.ps1 must not exist." -ForegroundColor Red
    exit 1
}

$publisherBytes = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "PUBLISH-RELEASE.ps1"))
foreach ($b in $publisherBytes) {
    if ($b -gt 127) {
        Write-Host "ERROR: PUBLISH-RELEASE.ps1 is not ASCII-only." -ForegroundColor Red
        exit 1
    }
}

$publisher = Get-Content ".\PUBLISH-RELEASE.ps1" -Raw

if ($publisher -match '& git tag -d \$Tag \*> \$null') {
    Write-Host "ERROR: unsafe tag deletion remains in publisher." -ForegroundColor Red
    exit 1
}
if ($publisher -notmatch 'rev-parse -q --verify "refs/tags/\$Tag"') {
    Write-Host "ERROR: safe local tag existence check is missing." -ForegroundColor Red
    exit 1
}

if ($publisher -match '\$[A-Za-z_][A-Za-z0-9_]*:') {
    Write-Host "ERROR: unsafe PowerShell variable followed by colon found." -ForegroundColor Red
    exit 1
}

if ($publisher -match '\\Q|\\E') {
    Write-Host "ERROR: unsupported .NET regex quoting found." -ForegroundColor Red
    exit 1
}

$installer = Get-Content ".\install-lxc.sh" -Raw

if ($installer -match '\$\{HOSTNAME:-') {
    Write-Host "ERROR: installer still uses HOSTNAME variable." -ForegroundColor Red
    exit 1
}

if ($installer -notmatch 'CT_HOSTNAME="\$\{CT_HOSTNAME:-viking-iptv\}"') {
    Write-Host "ERROR: CT_HOSTNAME default is missing." -ForegroundColor Red
    exit 1
}

if ($installer -notmatch 'enable_local_rootdir') {
    Write-Host "ERROR: local rootdir fallback is missing." -ForegroundColor Red
    exit 1
}

if ($installer -notmatch 'local_lvm_safe') {
    Write-Host "ERROR: local-lvm safety check is missing." -ForegroundColor Red
    exit 1
}

$version = (Get-Content ".\VERSION" -Raw).Trim()
Write-Host "Package OK. Version $version" -ForegroundColor Green
Write-Host "Publisher is ASCII-only." -ForegroundColor Green
Write-Host "No token config file is included." -ForegroundColor Green
Write-Host "Proxmox hostname/storage safeguards are present." -ForegroundColor Green
Write-Host ""
Write-Host "Run: .\PUBLISH-RELEASE.cmd" -ForegroundColor Cyan
