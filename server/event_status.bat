@echo off
rem Double-click to see the running World Boss event: HP, end time and the top 10
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0boss_admin.ps1" status
pause
