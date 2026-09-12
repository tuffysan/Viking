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

$version = (Get-Content .\VERSION -Raw).Trim()
Write-Host "Paket OK. Version $version" -ForegroundColor Green
Write-Host 'Kör .\PUBLISH-RELEASE.cmd för att skapa GitHub Release.' -ForegroundColor Cyan
