@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul 2>&1
set "PI_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PI_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PI_PS%" (
  echo Windows PowerShell 5.1 is required.
  pause
  exit /b 1
)
"%PI_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater\scripts\Entry.ps1" -Action Update %*
set "PI_EXIT=%ERRORLEVEL%"
pause
exit /b %PI_EXIT%
