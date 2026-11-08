# Opens, changes, ends or checks a World Boss event on the live server. Runs on your PC, not on GitHub.
# The .bat files next to this do the same with a double-click.
#
#   .\boss_admin.ps1 start -Event sample_event
#       Reads boss_hp, hours, attempts_per_day and the damage cap from Data/events/sample_event/event.tres
#       (through Godot, so edit the numbers there, not here) and opens the event.
#   .\boss_admin.ps1 set-hp -MaxHp 2000000      new max HP for the running event; damage already dealt still counts
#   .\boss_admin.ps1 set-hours -Hours 168        the event now lasts 168 hours from its start (reopens it if it ran out of time)
#   .\boss_admin.ps1 end                       ends the running event now (no rewards unless the boss already fell)
#   .\boss_admin.ps1 status                      shows the running event, top 10 and latest hits
#
# The admin key is asked for once and kept in server\.admin_key on this PC (never committed: see .gitignore).
# Pass -Key to use a different one. Add -Url http://localhost:8787 to use a local "npx wrangler dev" server.
param(
    [Parameter(Mandatory = $true)][ValidateSet("start", "set-hp", "set-hours", "end", "status")][string]$Action,
    [Alias("Event")][string]$EventId = "",
    [long]$MaxHp = 0,
    [double]$Hours = 0,
    [string]$Key = "",
    [string]$Url = "https://respite-boss.numk3y.workers.dev",
    [string]$Godot = "C:\Users\Numkey\Desktop\Godot_v4.7.2-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$keyFile = Join-Path $PSScriptRoot ".admin_key"

function Get-AdminKey {
    if ($Key) { return $Key }
    if (Test-Path $keyFile) { return (Get-Content $keyFile -Raw).Trim() }
    $entered = (Read-Host "Admin key (the ADMIN_KEY you set with 'wrangler secret put')").Trim()
    if (-not $entered) { throw "No admin key given." }
    Set-Content $keyFile $entered -NoNewline -Encoding ascii
    Write-Host "Saved to server\.admin_key, so you won't be asked again on this PC."
    return $entered
}

function Invoke-Admin($path, $body) {
    $headers = @{ "X-Admin-Key" = (Get-AdminKey); "X-Game-Version" = "999999" }
    try {
        return Invoke-RestMethod "$Url$path" -Method Post -Headers $headers -Body $body -ContentType "application/json"
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { throw "Can't reach the server ($Url): $($_.Exception.Message)" }
        $code = [int]$response.StatusCode
        $text = "$($_.ErrorDetails.Message)"  # the server's JSON answer, e.g. {"error":"no_active_event"}
        if ($code -eq 403) {
            if (Test-Path $keyFile) { Remove-Item $keyFile }
            throw "Wrong admin key. Run again to type it in."
        }
        throw "Server said ${code}: $text"
    }
}

function Show-Event($e) {
    Write-Host ("'{0}' is {1}: {2:N0} / {3:N0} HP, ends {4}" -f $e.boss_key, $e.status, $e.hp, $e.max_hp,
        [DateTimeOffset]::FromUnixTimeMilliseconds([long]$e.ends_at).LocalDateTime) -ForegroundColor Green
}

# Problems print as one red line instead of a PowerShell error dump
trap {
    Write-Host "$_" -ForegroundColor Red
    exit 1
}

switch ($Action) {
    "start" {
        if (-not $EventId) { throw "Say which event: -Event <folder name in Data/events>" }
        $project = Split-Path $PSScriptRoot -Parent
        $log = Join-Path $env:TEMP "respite_event_info.log"
        # Godot is a GUI program: Start-Process -Wait makes PowerShell wait for it, and its output is read from the log
        $p = Start-Process $Godot -ArgumentList "--headless", "--path", "`"$project`"", "res://Tools/event_info.tscn", "--log-file", "`"$log`"", "--", $EventId `
            -Wait -NoNewWindow -PassThru
        $lines = Get-Content $log -Encoding utf8
        $lines | Where-Object { $_ -like "WARNING*" } | ForEach-Object { Write-Warning $_ }
        $json = $lines | Where-Object { $_ -like "EVENT_JSON *" } | Select-Object -First 1
        if ($p.ExitCode -ne 0 -or -not $json) {
            $lines | Select-String "ERROR|No event" -Context 0, 2
            throw "Couldn't read event '$EventId' (full log: $log)"
        }
        $body = $json.Substring("EVENT_JSON ".Length)
        $info = $body | ConvertFrom-Json
        Write-Host ("Opening '{0}': {1:N0} HP for {2} hours, {3} attempts a day, max {4:N0} damage per fight" -f `
            $info.name, $info.max_hp, $info.hours, $info.attempts_per_day, $info.max_hit)
        Show-Event (Invoke-Admin "/admin/start" $body).event
    }
    "set-hp" {
        if ($MaxHp -le 0) { throw "Give the new max HP: -MaxHp 2000000" }
        try {
            $r = Invoke-Admin "/admin/set_hp" (@{ max_hp = $MaxHp } | ConvertTo-Json)
        } catch {
            if ("$_" -match "would_defeat") { throw "Players have already dealt more damage than $MaxHp. Pick a bigger number." }
            if ("$_" -match "no_active_event") { throw "No event is running." }
            throw
        }
        Write-Host ("Damage already dealt ({0:N0}) still counts." -f $r.damage_dealt)
        Show-Event $r.event
    }
    "set-hours" {
        if ($Hours -le 0) { throw "Give the event's new length in hours, counted from its start: -Hours 168" }
        try {
            $r = Invoke-Admin "/admin/set_hours" (@{ hours = $Hours } | ConvertTo-Json)
        } catch {
            if ("$_" -match "already_past") { throw "That end time has already passed. Pick more hours." }
            if ("$_" -match "already_defeated") { throw "The boss has already fallen; its event can't be reopened." }
            if ("$_" -match "no_event") { throw "No event has been opened yet." }
            if ("$_" -match "not_found") { throw "The live server doesn't know this command yet: run deploy.bat first." }
            throw
        }
        Show-Event $r.event
    }
    "end" {
        try {
            $r = Invoke-Admin "/admin/end" "{}"
        } catch {
            if ("$_" -match "no_active_event") { throw "No event is running." }
            throw
        }
        Write-Host "Event $($r.ended) ended." -ForegroundColor Yellow
    }
    "status" {
        $state = Invoke-RestMethod "$Url/boss" -Headers @{ "X-Game-Version" = "999999" }
        if (-not $state.event) { Write-Host "No event has been opened yet."; break }
        Show-Event $state.event
        Write-Host "Top damage:"
        $i = 1
        foreach ($t in $state.top) { Write-Host ("  {0,2}. {1,-16} {2,12:N0}" -f $i, $t.name, $t.damage); $i++ }
        if (-not $state.top) { Write-Host "  nobody yet" }
    }
}
