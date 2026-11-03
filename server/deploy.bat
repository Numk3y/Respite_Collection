@echo off
rem Double-click to upload the server code to Cloudflare (see deploy.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
pause
