@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo Viking IPTV - Release Publisher
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PUBLISH-RELEASE.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo Release-publiceringen misslyckades. Felkod: %RC%
  pause
  exit /b %RC%
)
echo Release-publiceringen ar klar.
pause
endlocal
