# Uploads the server code (src/index.js) to Cloudflare, then checks the live server answers.
# Cloudflare keeps the server running all the time; this is only needed after changing the server code.
# Opening or ending an event doesn't need it: use boss_admin.ps1 for that.
# Double-click deploy.bat, or run: .\deploy.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$url = "https://respite-boss.numk3y.workers.dev"

# Node may have been installed after this window opened; reload PATH so npx is found
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) { throw "Node.js isn't installed (npx not found)." }
if (-not (Test-Path node_modules)) { npm.cmd install --no-fund --no-audit }

npx.cmd wrangler deploy
if ($LASTEXITCODE -ne 0) { throw "Deploy failed. If it says you're not logged in, run: npx.cmd wrangler login" }

$state = Invoke-RestMethod "$url/boss" -Headers @{ "X-Game-Version" = "999999" }
if ($state.event) {
    Write-Host ("Live: event '{0}' is {1}, {2:N0} / {3:N0} HP" -f $state.event.boss_key, $state.event.status, $state.event.hp, $state.event.max_hp) -ForegroundColor Green
} else {
    Write-Host "Live: the server is up, no event running. Open one with boss_admin.ps1 start -Event <id> -Key <key>" -ForegroundColor Green
}
