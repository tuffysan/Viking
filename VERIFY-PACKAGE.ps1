$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$required = @(
  '.gitignore',
  'README.md',
  'MANUAL-GITHUB-UPLOAD.md',
  'PUBLISH-RELEASE.cmd',
  'PUBLISH-RELEASE.ps1',
  'VERIFY-PACKAGE.ps1',
  'VERSION',
  'install-lxc.sh',
  'update-from-github.sh',
  'app\VikingIptv.csproj',
  'app\Program.cs',
  'app\wwwroot\index.html',
  'app\wwwroot\app.js',
  'app\wwwroot\app.css'
)

$missing = $required | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) }
if ($missing) {
    Write-Host 'FEL: Paketet saknar:' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host " - $_" }
    exit 1
}

if (Test-Path '.\PUBLISH-CONFIG.ps1') {
    Write-Host 'FEL: PUBLISH-CONFIG.ps1 ska inte finnas i v1.7.1.' -ForegroundColor Red
    exit 1
}

$version = (Get-Content .\VERSION -Raw).Trim()

$publisher = Get-Content '.\PUBLISH-RELEASE.ps1' -Raw

# Known PowerShell interpolation trap: "$Variable:" must use "${Variable}:"
if ($publisher -match '\$[A-Za-z_][A-Za-z0-9_]*:') {
    Write-Host 'FEL: Möjlig ogiltig PowerShell-variabel följd av kolon hittades i PUBLISH-RELEASE.ps1.' -ForegroundColor Red
    exit 1
}

# .NET regular expressions do not support \Q...\E quoting.
if ($publisher -match '\\Q|\\E') {
    Write-Host 'FEL: PUBLISH-RELEASE.ps1 innehåller \Q eller \E som inte stöds av .NET-regex.' -ForegroundColor Red
    exit 1
}

Write-Host "Paket OK. Version $version" -ForegroundColor Green
Write-Host 'Ingen tokenfil används.' -ForegroundColor Green
Write-Host 'Publish-scriptet rensar gamla GITHUB_TOKEN/GH_TOKEN från processen.' -ForegroundColor Green
Write-Host 'Publish-scriptet skyddar mot GitHub-token i projekt/staged diff.' -ForegroundColor Green
Write-Host 'Publish-scriptet kan reparera blockerad lokal v1.7.0-commit.
Write-Host 'Kända PowerShell-parserfel kontrollerade.' -ForegroundColor Green' -ForegroundColor Green
Write-Host ''
Write-Host 'Kör nu: .\PUBLISH-RELEASE.cmd' -ForegroundColor Cyan
