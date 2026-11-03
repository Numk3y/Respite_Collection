@echo off
rem Double-click to open a World Boss event on the live server. Its numbers come from Data\events\<id>\event.tres.
cd /d "%~dp0"
echo Events in Data\events:
for /d %%d in (..\Data\events\*) do echo   %%~nxd
echo.
set /p EVENT_ID=Event to open (folder name):
if "%EVENT_ID%"=="" goto :eof
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" start -EventId "%EVENT_ID%"
pause
