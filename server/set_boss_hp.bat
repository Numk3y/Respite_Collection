@echo off
rem Double-click to change the running World Boss's max HP. Damage players already dealt still counts:
rem 1,000,000 HP with 300,000 dealt, changed to 2000000, leaves 1,700,000 to go.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" status
echo.
set /p NEW_HP=New max HP (numbers only, e.g. 2000000):
if "%NEW_HP%"=="" goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" set-hp -MaxHp %NEW_HP%
pause
