# Balatro High Stakes - installer tests for other (official) Balatro Multiplayer mods (Windows PowerShell 5.1+).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_installer_clash.ps1
# Runs install.ps1 / uninstall.ps1 against throw-away folders in %TEMP%. Never touches the real game or AppData.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:fails = 0; $script:passes = 0
function Ok($cond, $msg) {
    if ($cond) { $script:passes++; Write-Host "ok: $msg" }
    else { $script:fails++; Write-Host "FAIL: $msg" -ForegroundColor Red }
}

# ---------- sandbox ----------
$root = Join-Path ([IO.Path]::GetTempPath()) ("mp3p-clashtest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    W (Join-Path $payload 'BalatroMultiplayer3P\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.8~3P" }'
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

function Add-Official {
    W (Join-Path $mods 'BalatroMultiplayerPvP\MultiplayerPvP.json') '{ "id": "MultiplayerPvP", "prefix": "mp", "version": "1.0.0" }'
    W (Join-Path $mods 'BalatroMultiplayerPvP\keep.txt') 'user file'
    W (Join-Path $mods 'MPAPI\MPAPI\MultiplayerAPI.json') '{ "id": "MultiplayerAPI", "version": "1.0.0" }'
    W (Join-Path $mods 'Multiplayer-main\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.2.19" }'
    W (Join-Path $mods 'SomeJokers\SomeJokers.json') '{ "id": "SomeJokers", "version": "1.0" }'
}
function Run-Uninstaller {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $inst 'uninstall.ps1'), '-ModsRoot', $mods, '-NoPrompt', '-NoPause', '-SkipProcessCheck')
    $out = & powershell @a 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out }
}
function Has([string]$rel) { return (Test-Path -LiteralPath (Join-Path $mods $rel)) }

try {
    # dry run: lists the clashes, changes nothing
    Reset-Sandbox $null; W (Join-Path $inst 'uninstall.ps1') ([IO.File]::ReadAllText((Join-Path $Repo 'installer\uninstall.ps1'))); Add-Official
    $before = Snapshot
    $r = Run-Installer @('-DryRun')
    Ok ($r.code -eq 0 -and (Snapshot) -eq $before) 'dry run: nothing changed'
    Ok ($r.out -match 'CLASH MultiplayerPvP folder=BalatroMultiplayerPvP action=move \(dry run\)' -and $r.out -match 'CLASH MultiplayerAPI folder=MPAPI' -and $r.out -match 'CLASH Multiplayer folder=Multiplayer-main') 'dry run: PvP, nested API and legacy Multiplayer listed'
    Ok ($r.out -notmatch 'CLASH \S+ folder=SomeJokers' -and $r.out -match 'WARNING: other Balatro Multiplayer mods') 'dry run: warning shown, unrelated mod not listed'

    # -NoPrompt: moved to the backup (not deleted), unrelated mod untouched
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and -not (Has 'BalatroMultiplayerPvP') -and -not (Has 'MPAPI') -and -not (Has 'Multiplayer-main') -and (Has 'SomeJokers\SomeJokers.json')) 'NoPrompt: official mods moved out of Mods, other mods kept'
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $root 'data') -Recurse -Filter 'keep.txt' -ErrorAction SilentlyContinue)
    Ok ($bk.Count -eq 1 -and $bk[0].FullName -match 'MP3P-backup' -and (Has 'BalatroMultiplayer3P\Multiplayer.json')) 'NoPrompt: user files are in the backup folder, High Stakes installed'
    $r2 = Run-Installer @()
    Ok ($r2.code -eq 0 -and $r2.out -notmatch 'CLASH ') 'second run: no clash left, own folder not reported'

    # uninstall puts them back
    $u = Run-Uninstaller
    Ok ($u.code -eq 0 -and (Has 'BalatroMultiplayerPvP\keep.txt') -and (Has 'MPAPI\MPAPI\MultiplayerAPI.json') -and (Has 'Multiplayer-main\Multiplayer.json') -and -not (Has 'BalatroMultiplayer3P')) 'uninstall: official mods restored, High Stakes removed'

    # -KeepOtherMultiplayer: left alone, strong note for the same-id mod
    Reset-Sandbox $null; Add-Official
    $r = Run-Installer @('-KeepOtherMultiplayer')
    Ok ($r.code -eq 0 -and (Has 'BalatroMultiplayerPvP\keep.txt') -and (Has 'MPAPI') -and (Has 'Multiplayer-main') -and $r.out -match 'action=keep' -and $r.out -match "stops BOTH from loading") 'KeepOtherMultiplayer: kept, with a warning'

    # an older High Stakes copy in another folder is ours, not a clash (replaced as before)
    Reset-Sandbox $null
    W (Join-Path $mods 'Multiplayer3P-old\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.5~3P" }'
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and $r.out -notmatch 'CLASH ' -and -not (Has 'Multiplayer3P-old') -and $r.out -match 'replacing it') 'old High Stakes copy: no clash warning, replaced (backed up)'

    # no other mods: no warning at all
    Reset-Sandbox $null
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and $r.out -notmatch 'WARNING: other Balatro Multiplayer') 'clean Mods folder: no clash warning'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ""
if ($script:fails -gt 0) { Write-Host "FAIL: installer clash ($script:fails failed, $script:passes passed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS: installer clash ($script:passes checks)" -ForegroundColor Green
exit 0
