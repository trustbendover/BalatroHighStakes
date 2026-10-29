<#
Balatro High Stakes - DEV ONLY local test match launcher (not part of any release).
Starts N Balatro instances on this PC that play each other over the dev file transport (mod/dev/).
Every instance gets its OWN test profile (APPDATA override) and its OWN Mods folder (--mod-dir and
LOVELY_MOD_DIR), so your real %APPDATA%\Balatro (save, settings, Mods) is never read or written.

  .\dev_local_match.ps1 -DevZip <BalatroHighStakes-DEV-LOCALTEST-*.zip> -Players 3 -Scenario full_match
  .\dev_local_match.ps1 -Stop                 # closes only the instances this script started
  .\dev_local_match.ps1 -Status

Scenarios: full_match, host_leave, guest_rejoin, elimination, presets, ready_gating (see mod/dev/scenarios.lua)
#>
param(
    [string]$DevZip,
    [ValidateRange(2, 8)][int]$Players = 2,
    [ValidateSet('full_match', 'host_leave', 'guest_rejoin', 'elimination', 'presets', 'ready_gating')][string]$Scenario = 'full_match',
    [ValidateSet('attrition', 'deathmatch', 'duel', 'showdown', 'survival', 'koth', 'teams')][string]$Mode = 'attrition',
    [string]$GameDir = 'G:\SteamLibrary\steamapps\common\Balatro',
    [string]$Root = (Join-Path $env:USERPROFILE 'GrokBot\Projects\BalatroMP3P\DevLocal'),
    [switch]$HostManual,          # you play the host yourself; guests are bots
    [int]$ShotEvery = 0,          # extra screenshot every N seconds per instance (0 = only scenario points + F9)
    [int]$RestartAfter = 20,      # guest_rejoin: seconds before dev2 is started again
    [int]$Speed = 4,
    [string]$Ffmpeg = (Join-Path $env:USERPROFILE 'GrokBot\Tools\ffmpeg\bin\ffmpeg.exe'),
    [int]$RecordSeconds = 0,      # >0: record the tiled game windows (primary display region only) to captures\<run>\match.mp4
    [switch]$Stop,
    [switch]$Status
)
$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $Root 'instances.json'

function Get-Ours {
    if (-not (Test-Path $pidFile)) { return @() }
    $list = Get-Content $pidFile -Raw | ConvertFrom-Json
    foreach ($e in @($list)) {
        $p = Get-Process -Id $e.pid -ErrorAction SilentlyContinue
        # only a process we started: same id AND same start time (ids get reused)
        if ($p -and $p.StartTime.ToString('o') -eq $e.start) { [pscustomobject]@{ name = $e.name; proc = $p } }
    }
}

if ($Stop) {
    $ours = @(Get-Ours)
    foreach ($o in $ours) { Write-Host "closing $($o.name) (pid $($o.proc.Id))"; $null = $o.proc.CloseMainWindow() }
    Start-Sleep 3
    foreach ($o in @(Get-Ours)) { Write-Host "stopping $($o.name)"; Stop-Process -Id $o.proc.Id }
    $rf = Join-Path $Root 'recording.json'
    if (Test-Path $rf) { $r = Get-Content $rf -Raw | ConvertFrom-Json; $rp = Get-Process -Id $r.pid -ErrorAction SilentlyContinue
        if ($rp -and $rp.StartTime.ToString('o') -eq $r.start) { Stop-Process -Id $r.pid; Write-Host "recording stopped (fragmented mp4 stays playable)" }
        Remove-Item $rf }
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    Write-Host "stopped $($ours.Count) instance(s)"; return
}
if ($Status) { Get-Ours | ForEach-Object { "$($_.name) pid $($_.proc.Id) running" }; return }

if (-not $DevZip -or -not (Test-Path $DevZip)) { throw "-DevZip <BalatroHighStakes-DEV-LOCALTEST-*.zip> is required" }
$exe = Join-Path $GameDir 'Balatro.exe'
if (-not (Test-Path $exe)) { throw "Balatro.exe not found in $GameDir" }
if (-not (Test-Path (Join-Path $GameDir 'winmm.dll'))) { throw "Lovely (winmm.dll) is not installed in $GameDir" }
if (@(Get-Ours).Count) { throw "test instances are still running: run with -Stop first" }
$real = Get-Process Balatro -ErrorAction SilentlyContinue
if ($real) { throw "Balatro is already running (pid $($real.Id -join ',')). Close it first - this script never kills it." }

# fresh build + transport + captures (test profiles are kept between runs so settings stick)
$build = Join-Path $Root 'build'; $net = Join-Path $Root 'net'
$cap = Join-Path $Root ('captures\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$Scenario")
foreach ($d in $build, $net) { if (Test-Path $d) { Remove-Item $d -Recurse -Force } }
New-Item -ItemType Directory -Force $build, $cap, "$net\peers", "$net\inbox", "$net\lobby", "$net\tmp" | Out-Null
Expand-Archive $DevZip $build
$mods = Get-ChildItem $build -Recurse -Directory -Filter Mods | Select-Object -First 1
if (-not (Test-Path (Join-Path $mods.FullName 'BalatroMultiplayer3P\dev\DEV_BUILD'))) { throw "$DevZip is not a DEV build" }

$names = 1..$Players | ForEach-Object { "dev$_" }
$started = @()
function Start-Instance([string]$name, [int]$i) {
    $appdata = Join-Path $Root "profiles\$name\AppData"
    $modDir = Join-Path $appdata 'Balatro\Mods'
    if (Test-Path $modDir) { Remove-Item $modDir -Recurse -Force }   # always the fresh dev build
    New-Item -ItemType Directory -Force $modDir | Out-Null
    Copy-Item (Join-Path $mods.FullName '*') $modDir -Recurse
    $vars = @{
        APPDATA = $appdata; LOVELY_MOD_DIR = $modDir
        HS_DEV_LOCAL = '1'; HS_DEV_DIR = $net; HS_DEV_NAME = $name; HS_DEV_PEERS = ($names -join ',')
        HS_DEV_ROLE = $(if ($i -eq 1) { 'host' } else { 'guest' }); HS_DEV_PLAYERS = "$Players"; HS_DEV_MODE = $Mode
        HS_DEV_AUTOPLAY = $(if ($i -eq 1 -and $HostManual) { '0' } else { '1' }); HS_DEV_SCENARIO = $Scenario
        HS_DEV_CAPTURE = $cap; HS_DEV_SHOT_EVERY = "$ShotEvery"; HS_DEV_SPEED = "$Speed"
    }
    $old = @{}
    foreach ($k in $vars.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
    try { $p = Start-Process -FilePath $exe -WorkingDirectory $GameDir -ArgumentList @('--mod-dir', "`"$modDir`"") -PassThru }
    finally { foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k], 'Process') } }
    Start-Sleep -Milliseconds 500
    return [pscustomobject]@{ name = $name; pid = $p.Id; start = $p.StartTime.ToString('o'); modDir = $modDir }
}
function Save-Pids { $started | Select-Object name, pid, start | ConvertTo-Json | Set-Content $pidFile -Encoding UTF8 }

for ($i = 1; $i -le $Players; $i++) {
    $started += Start-Instance $names[$i - 1] $i
    Save-Pids
    Start-Sleep -Seconds 2
}
Write-Host "started $Players instance(s); captures -> $cap"

if ($RecordSeconds -gt 0) {
    if (-not (Test-Path $Ffmpeg)) { Write-Warning "ffmpeg not found at $Ffmpeg - no video" } else {
        # same tiling as mod/dev/dev_local.lua D.layout: only the game windows, never the rest of the desktop
        if ($Players -le 2) { $vx = 0; $vy = 270; $vw = 1920; $vh = 540 } else { $vx = 0; $vy = 270; $vw = 1920; $vh = 540 }
        $fa = "-nostdin -hide_banner -loglevel warning -y -f gdigrab -framerate 15 -offset_x $vx -offset_y $vy -video_size ${vw}x$vh -i desktop -t $RecordSeconds " +
              "-c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -g 30 -movflags +frag_keyframe+empty_moov `"$cap\match.mp4`""
        $rp = Start-Process $Ffmpeg -ArgumentList $fa -WindowStyle Hidden -PassThru -RedirectStandardError "$cap\ffmpeg.log"
        @{ pid = $rp.Id; start = $rp.StartTime.ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'recording.json')
        Write-Host "recording ${vw}x$vh for max $RecordSeconds s -> $cap\match.mp4"
    }
}

# check that every instance really uses its own Mods folder (Lovely writes its log there)
Start-Sleep -Seconds 15
foreach ($s in $started) {
    $log = Get-ChildItem (Join-Path $s.modDir 'lovely\log') -Filter *.log -ErrorAction SilentlyContinue
    if (-not $log) { Write-Warning "$($s.name): no Lovely log in its test Mods folder yet - check that Lovely honours --mod-dir / LOVELY_MOD_DIR" }
    elseif (-not (Select-String $log[-1].FullName -Pattern 'DEV LOCAL TEST MODE' -Quiet)) { Write-Warning "$($s.name): dev mode not seen in the log (yet)" }
    else { Write-Host "$($s.name): dev mode active" }
}

if ($Scenario -eq 'guest_rejoin') {
    Write-Host "guest_rejoin: waiting for dev2 to close itself at ante 2..."
    $d2 = $started | Where-Object name -eq 'dev2'
    while (Get-Process -Id $d2.pid -ErrorAction SilentlyContinue) { Start-Sleep 2 }
    Write-Host "dev2 closed; starting it again in $RestartAfter s"
    Start-Sleep -Seconds $RestartAfter
    $started = @($started | Where-Object name -ne 'dev2') + (Start-Instance 'dev2' 2)
    Save-Pids
}
Write-Host "running. Stop with: .\dev_local_match.ps1 -Stop"
