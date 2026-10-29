# Balatro High Stakes - tests for "Steam only" (0.6.8) in the installer (Windows PowerShell 5.1+).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_installer_steam_only.ps1
# Unit tests for installer\settings.ps1, then install.ps1 runs against throw-away folders in %TEMP%
# (fake game folder, fake Mods folder, fake payload). Never touches the real game or AppData.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $Repo 'installer\settings.ps1')
$script:fails = 0; $script:passes = 0
function Ok($cond, $msg) {
    if ($cond) { $script:passes++; Write-Host "ok: $msg" }
    else { $script:fails++; Write-Host "FAIL: $msg" -ForegroundColor Red }
}

# ---------- unit: Convert-EnvToSteam ----------
$steam = "# Written by the MP3P installer`r`nmode=steam`r`n# TCP fallback: remove the mode line and set server_url / server_port`r`nserver_url=127.0.0.1`r`nserver_port=8788`r`nupdate_check=false`r`n"
$r = Convert-EnvToSteam $steam
Ok (-not $r.changed -and $r.text -eq $steam) 'mode=steam: unchanged, byte-identical'
$r = Convert-EnvToSteam "MODE = Steam`n"
Ok (-not $r.changed) 'mode=Steam (any case/spaces): unchanged'
$tcp = "# Written by the MP3P installer`r`nserver_url=example.playit.gg`r`nserver_port=1234`r`nupdate_check=false`r`n"
$r = Convert-EnvToSteam $tcp
Ok ($r.changed -and $r.old -eq 'server address: example.playit.gg:1234') "no mode line (old TCP default) -> changed, old: $($r.old)"
Ok ($r.text -match '(?m)^mode=steam\r$' -and $r.text -match '(?m)^update_check=false\r$') 'mode=steam added, other settings kept, CRLF kept'
Ok ($r.text -notmatch '(?m)^\s*server_url\s*=' -and $r.text -match '(?m)^# old setting .*server_url=example\.playit\.gg') 'server_url commented out (kept as a note)'
$r = Convert-EnvToSteam "mode=tcp`ncustom_line=1`n"
Ok ($r.changed -and $r.old -eq 'mode=tcp' -and $r.text -match "(?m)^custom_line=1`n" -and $r.text -match "(?m)^mode=steam`n$" -and $r.text -notmatch "`r") 'mode=tcp -> steam, LF kept, custom line kept'
$r = Convert-EnvToSteam "mode=steam`nmode=server`n"
Ok ($r.changed -and $r.text -notmatch '(?m)^mode=server') 'last mode line wins (like the mod): steam then server -> changed'
$r = Convert-EnvToSteam ''
Ok ($r.changed -and $r.text -match '(?m)^mode=steam') 'empty file -> fresh Steam settings'
# the mod's own .env parser (core.lua) must end up with mode=steam: emulate it
function Parse-ModEnv([string]$t) { $m = @{}; foreach ($l in ($t -split "`r?`n")) { $l = $l.Trim(); if ($l -and -not $l.StartsWith('#') -and $l -match '^([\w]+)\s*=\s*(.+)$') { $m[$Matches[1]] = $Matches[2] } }; return $m }
$p = Parse-ModEnv (Convert-EnvToSteam $tcp).text
Ok ($p['mode'] -eq 'steam' -and -not $p.ContainsKey('server_url') -and $p['update_check'] -eq 'false') 'mod parser sees mode=steam, no server_url, update_check kept'

# ---------- sandbox ----------
$root = Join-Path ([IO.Path]::GetTempPath()) ("mp3p-steamtest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$inst = Join-Path $root 'inst'; $payload = Join-Path $inst 'payload'
$game = Join-Path $root 'game'; $mods = Join-Path $root 'data\Mods'
$envPath = Join-Path $mods 'BalatroMultiplayer3P\.env'
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function Reset-Sandbox($oldEnv) {  # untyped: [string] would turn $null into ""
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    foreach ($f in 'install.ps1', 'pins.ps1', 'settings.ps1') { W (Join-Path $inst $f) ([IO.File]::ReadAllText((Join-Path $Repo "installer\$f"))) }
    W (Join-Path $payload 'BalatroMultiplayer3P\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.8", "author": ["Trust Ben Dover"] }'
    W (Join-Path $payload 'BalatroMultiplayer3P\compat.cfg') ([IO.File]::ReadAllText((Join-Path $Repo 'mod\compat.cfg')))
    W (Join-Path $payload 'smods\version.lua') 'return "1.0.0~BETA-1620a-STEAMODDED"'
    W (Join-Path $payload 'winmm.dll') "fake dll lovely-injectorversion0.10.0mod_dir"
    W (Join-Path $game 'Balatro.exe') 'fake'
    New-Item -ItemType Directory -Path $mods -Force | Out-Null
    if ($null -ne $oldEnv) {
        W (Join-Path $mods 'BalatroMultiplayer3P\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.7~3P" }'
        W $envPath $oldEnv
    }
}
function Run-Installer([string[]]$extra) {
    # the arguments the 0.6.7 updater passes (-SkipConnectionTest included), no -Mode
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $inst 'install.ps1'),
        '-GameDir', $game, '-ModsRoot', $mods, '-NoPrompt', '-NoPause', '-SkipProcessCheck', '-SkipConnectionTest', '-SteamRoots', (Join-Path $root 'nosteam')) + $extra
    $out = & powershell @args2 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out }
}
function Backups { return @(Get-ChildItem -LiteralPath (Join-Path $root 'data') -Recurse -Filter 'settings__.env' -ErrorAction SilentlyContinue) }
function Snapshot { return ((Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.FullName + '|' + $_.Length }) -join "`n") }

try {
    # fresh install: no prompt, mode=steam
    Reset-Sandbox $null
    $r = Run-Installer @()
    $e = [IO.File]::ReadAllText($envPath)
    Ok ($r.code -eq 0 -and $e -match '(?m)^mode=steam' -and $e -notmatch '(?m)^server_url') 'fresh install: .env has mode=steam and no server address'
    Ok ($r.out -notmatch 'How do you want to play' -and $r.out -notmatch 'Host address' -and $r.out -notmatch 'Testing ') 'fresh install: no mode question, no address, no connection test'
    Ok ($r.out -match 'SETTINGS \.env action=new \(mode=steam\)') 'fresh install: SETTINGS line'

    # update of a TCP/playit install -> switched to Steam once, backup, plain-text note
    $old = "# Written by the MP3P installer`r`nserver_url=example.playit.gg`r`nserver_port=1234`r`ne2e_custom=keepme`r`n"
    Reset-Sandbox $old
    $before = Snapshot
    $r = Run-Installer @('-DryRun')
    Ok ($r.code -eq 0 -and $r.out -match 'SETTINGS \.env action=switch to Steam \(was server address: example\.playit\.gg:1234\)' -and (Snapshot) -eq $before) 'dry run: says it would switch, changes nothing'
    $r = Run-Installer @()
    $e = [IO.File]::ReadAllText($envPath)
    $b = Backups
    Ok ($r.code -eq 0 -and $e -match '(?m)^mode=steam' -and $e -match '(?m)^e2e_custom=keepme') 'TCP install: switched to mode=steam, custom setting kept'
    Ok ($b.Count -eq 1 -and [IO.File]::ReadAllText($b[0].FullName) -eq $old) 'TCP install: old .env backed up byte-identical (settings__.env)'
    Ok ($r.out -match 'now plays over Steam only' -and $r.out -match 'example\.playit\.gg:1234' -and $r.out -match 'settings__\.env') 'TCP install: plain-text note with the old setting and the backup path'
    # second run: already Steam -> no second note, no second backup, file unchanged
    $e1 = [IO.File]::ReadAllText($envPath)
    Start-Sleep -Seconds 1
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and $r.out -notmatch 'now plays over Steam only' -and (Backups).Count -eq 1 -and [IO.File]::ReadAllText($envPath) -eq $e1) 'second update: told only once, .env unchanged'

    # mode=tcp with an old -Mode tcp / -HostAddress caller -> ignored, Steam
    Reset-Sandbox "mode=tcp`nserver_url=old.example.invalid`n"
    $r = Run-Installer @('-Mode', 'tcp', '-HostAddress', 'example.invalid', '-Port', '9999')
    $e = [IO.File]::ReadAllText($envPath)
    Ok ($r.code -eq 0 -and $r.out -match 'ignored' -and $e -match '(?m)^mode=steam' -and $e -notmatch '(?m)^server_url' -and $e -notmatch '9999') 'old -Mode/-HostAddress args: ignored, still Steam'

    # a Steam install stays byte-identical (no note, no backup)
    $st = "# Written by the MP3P installer`r`nmode=steam`r`n# TCP fallback: remove the mode line and set server_url / server_port`r`nserver_url=127.0.0.1`r`nserver_port=8788`r`n"
    Reset-Sandbox $st
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and [IO.File]::ReadAllText($envPath) -eq $st -and (Backups).Count -eq 0 -and $r.out -notmatch 'now plays over Steam only') 'Steam install: .env byte-identical, no backup, no note'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ""
if ($script:fails -gt 0) { Write-Host "FAIL: steam only ($script:fails failed, $script:passes passed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS: installer steam only ($script:passes checks)" -ForegroundColor Green
exit 0
