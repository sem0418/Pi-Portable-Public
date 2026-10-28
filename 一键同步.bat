@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater\scripts\Sync-Portable.ps1" %*
set "PORTABLE_EXIT=%ERRORLEVEL%"
echo.
if not "%PORTABLE_EXIT%"=="0" echo Sync stopped. Read the message above. No force/reset/clean was requested.
pause
exit /b %PORTABLE_EXIT%
