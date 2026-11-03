@echo off
rem Double-click to end the running World Boss event now. If the boss wasn't defeated, nobody gets rewards.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" status
echo.
echo Ending the event now means NO rewards unless the boss is already defeated.
set /p CONFIRM=Type YES to end it:
if /i not "%CONFIRM%"=="YES" (
    echo Cancelled.
    pause
    goto :eof
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" end
pause
