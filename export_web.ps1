# Builds the web version into docs/, which GitHub Pages serves.
# Usage:  .\export_web.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64.exe"
# Needs the Godot 4.7.2 export templates (Editor > Manage Export Templates > Download and Install).
param(
    [Parameter(Mandatory = $true)]
    [string]$Godot
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Even out the music volume (writes Scripts/autoload/music_levels.gd; skipped if ffmpeg isn't installed)
& "$PSScriptRoot\level_music.ps1"

# Remove the previous build but keep the marker files
Get-ChildItem docs -File | Where-Object { $_.Name -notin @(".gdignore", ".nojekyll") } | Remove-Item

# The Godot exe is a GUI program, so PowerShell wouldn't wait for it with "&"; use Start-Process -Wait
$log = Join-Path $env:TEMP "godot_web_export.log"
$process = Start-Process $Godot -ArgumentList "--headless", "--path", ".", "--export-release", "Web", "docs/index.html", "--log-file", $log -Wait -NoNewWindow -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path docs\index.html)) {
    Get-Content $log -Encoding utf8 | Select-String "ERROR" -Context 0, 2
    throw "Export failed (full log: $log). Check that the 4.7.2 web export templates are installed."
}

Get-ChildItem docs -File | Select-Object Name, @{ n = "MB"; e = { [math]::Round($_.Length / 1MB, 1) } }
Write-Host "Done. Commit and push the docs folder to update the site."
