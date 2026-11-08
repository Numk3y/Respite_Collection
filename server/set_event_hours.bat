@echo off
rem Double-click to change how long the World Boss event lasts, counted from when it opened (168 = one week).
rem An event that already ran out of time opens again; damage and the leaderboard are kept.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" status
echo.
set /p NEW_HOURS=Event length in hours from its start (e.g. 168):
if "%NEW_HOURS%"=="" goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" set-hours -Hours %NEW_HOURS%
pause
