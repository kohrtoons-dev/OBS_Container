@echo off
rem =====================================================================
rem  Prop Trader Edge OBS Overlay - start the Companion/HTTP bridge
rem  Uses Node.js if installed, otherwise falls back to PowerShell
rem  (which ships with Windows - nothing to install).
rem =====================================================================
cd /d "%~dp0"
where node >nul 2>nul
if %errorlevel%==0 (
  echo Starting bridge with Node.js ...
  node "%~dp0bridge.js" %1
) else (
  echo Node.js not found - starting the PowerShell bridge instead ...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge.ps1"
)
pause
