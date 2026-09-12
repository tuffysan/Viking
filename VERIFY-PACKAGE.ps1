$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$required = @(
  '.gitignore',
  'README.md',
  'MANUAL-GITHUB-UPLOAD.md',
  'PUBLISH-CONFIG.ps1',
  'PUBLISH-CONFIG.example.ps1',
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

$version = (Get-Content .\VERSION -Raw).Trim()
Write-Host "Paket OK. Version $version" -ForegroundColor Green

$gitignore = Get-Content .\.gitignore -Raw
if ($gitignore -notmatch '(?m)^PUBLISH-CONFIG\.ps1\s*$') {
    Write-Host 'FEL: PUBLISH-CONFIG.ps1 saknas i .gitignore.' -ForegroundColor Red
    exit 1
}

Write-Host 'Token-konfigurationen är skyddad av .gitignore.' -ForegroundColor Green
Write-Host 'Fyll i PUBLISH-CONFIG.ps1 och kör sedan .\PUBLISH-RELEASE.cmd.' -ForegroundColor Cyan
