# Balatro High Stakes - tests for the installer's dependency pins (Windows PowerShell 5.1+).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_installer_pins.ps1
# Unit tests for installer\pins.ps1, then install.ps1 runs against throw-away folders in %TEMP%
# (fake game folder, fake Mods folder, fake payload). Never touches the real game or AppData.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $Repo 'installer\pins.ps1')
$script:fails = 0; $script:passes = 0
function Ok($cond, $msg) {
    if ($cond) { $script:passes++; Write-Host "ok: $msg" }
    else { $script:fails++; Write-Host "FAIL: $msg" -ForegroundColor Red }
}

# ---------- unit: versions ----------
Ok ((Compare-ModVersion '1.0.0~BETA-1620a' '1.0.0~BETA-1620a-STEAMODDED') -eq 0) 'same version with -STEAMODDED suffix'
Ok ((Compare-ModVersion '1.0.0~BETA-1801a' '1.0.0~BETA-1620a') -eq 1) 'newer Steamodded beta'
Ok ((Compare-ModVersion '1.0.0~BETA-0614a' '1.0.0~BETA-1620a') -eq -1) 'older Steamodded beta'
Ok ((Compare-ModVersion '1.0.0~BETA-1620b' '1.0.0~BETA-1620a') -eq 1) 'letter suffix counts'
Ok ((Compare-ModVersion '1.0.0' '1.0.0~BETA-1620a') -eq 1) 'a release is newer than its beta'
Ok ((Compare-ModVersion '0.10.0' '0.9.1') -eq 1 -and (Compare-ModVersion 'v0.10.0' '0.10.0') -eq 0) 'Lovely 0.10 > 0.9, leading v ignored'
Ok ((Compare-ModVersion '1.0.1o' '1.0.1') -eq 1) 'Balatro letters sort after numbers'

# ---------- unit: decisions ----------
$t = '1.0.0~BETA-1620a'
Ok ((Resolve-DepAction $null $false $t 'keep').action -eq 'install') 'not installed -> install'
Ok ((Resolve-DepAction '1.0.0~BETA-1620a' $true $t 'ask').action -eq 'same') 'same version -> same (no prompt)'
Ok ((Resolve-DepAction '1.0.0~BETA-0614a' $true $t 'keep').action -eq 'install') 'older -> install the tested one'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'ask').action -eq 'ask') 'newer + ask -> prompt'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'ask' 'enter').action -eq 'install') 'prompt Enter -> tested (recommended)'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'ask' '1').action -eq 'install') 'prompt 1 -> tested'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'ask' '2').action -eq 'keep') 'prompt 2 -> keep yours'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'keep').action -eq 'keep') 'newer + no prompt -> kept (never a silent downgrade)'
Ok ((Resolve-DepAction '1.0.0~BETA-1801a' $true $t 'tested').action -eq 'install') 'newer + policy tested -> install'
Ok ((Resolve-DepAction $null $true $t 'keep').action -eq 'keep') 'unknown version + no prompt -> kept'

# ---------- sandbox ----------
$root = Join-Path ([IO.Path]::GetTempPath()) ("mp3p-pintest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$inst = Join-Path $root 'inst'; $payload = Join-Path $inst 'payload'
$game = Join-Path $root 'game'; $mods = Join-Path $root 'data\Mods'
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function Reset-Sandbox([string]$smodsVer, [string]$lovelyVer) {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    foreach ($f in 'install.ps1', 'pins.ps1', 'settings.ps1') { W (Join-Path $inst $f) ([IO.File]::ReadAllText((Join-Path $Repo "installer\$f"))) }
    W (Join-Path $payload 'BalatroMultiplayer3P\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.8~3P" }'
    W (Join-Path $payload 'BalatroMultiplayer3P\compat.cfg') ([IO.File]::ReadAllText((Join-Path $Repo 'mod\compat.cfg')))
    W (Join-Path $payload 'smods\version.lua') 'return "1.0.0~BETA-1620a-STEAMODDED"'
    W (Join-Path $payload 'winmm.dll') "fake dll lovely-injectorversion0.10.0mod_dir"
    W (Join-Path $game 'Balatro.exe') 'fake'
    New-Item -ItemType Directory -Path $mods -Force | Out-Null
    if ($smodsVer) { W (Join-Path $mods 'smods-mine\version.lua') "return `"$smodsVer-STEAMODDED`"" }
    if ($lovelyVer) { W (Join-Path $game 'winmm.dll') "my dll lovely-injectorversion$($lovelyVer)repo" }
}
function Run-Installer([string[]]$extra) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $inst 'install.ps1'),
        '-GameDir', $game, '-ModsRoot', $mods, '-Mode', 'steam', '-NoPrompt', '-NoPause', '-SkipProcessCheck', '-SkipConnectionTest') + $extra
    $out = & powershell @args2 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out }
}
function Snapshot { return ((Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.FullName + '|' + $_.Length }) -join "`n") }

try {
    # newer Steamodded + newer Lovely, dry runs
    Reset-Sandbox '1.0.0~BETA-1801a' '0.11.0'
    $before = Snapshot
    $r = Run-Installer @('-DryRun')
    Ok ($r.code -eq 0 -and $r.out -match 'PIN steamodded installed=1\.0\.0~BETA-1801a tested=1\.0\.0~BETA-1620a action=keep') 'dry run, no prompt: newer Steamodded kept'
    Ok ($r.out -match 'PIN lovely installed=0\.11\.0 tested=0\.10\.0 action=keep') 'dry run: Lovely version read from the dll, newer kept'
    Ok ($r.out -match 'Keeping your Steamodded' -and $r.out -match 'DRY RUN') 'dry run says it clearly'
    Ok ((Snapshot) -eq $before) 'dry run changes nothing'
    $r = Run-Installer @('-DryRun', '-DepsPolicy', 'tested')
    Ok ($r.out -match 'PIN steamodded .* action=install' -and $r.out -match 'PIN lovely .* action=install') 'dry run, policy tested: both get the tested version'
    $r = Run-Installer @('-DryRun', '-DepsPolicy', 'ask')
    Ok ($r.out -match 'PIN steamodded .* action=ask \(dry run: would prompt\)') 'dry run, policy ask: would prompt'
    Ok ((Snapshot) -eq $before) 'still nothing changed'

    # older / missing
    Reset-Sandbox '1.0.0~BETA-0614a' $null
    $r = Run-Installer @('-DryRun')
    Ok ($r.out -match 'PIN steamodded installed=1\.0\.0~BETA-0614a .* action=install \(older' -and $r.out -match 'PIN lovely installed=none .* action=install') 'older Steamodded and missing Lovely -> tested versions'

    # real run in the sandbox, no prompt: newer ones are kept
    Reset-Sandbox '1.0.0~BETA-1801a' '0.11.0'
    $r = Run-Installer @()
    Ok ($r.code -eq 0) 'sandbox install (keep) exits 0'
    Ok ((Get-SmodsVersion (Join-Path $mods 'smods-mine')) -eq '1.0.0~BETA-1801a' -and -not (Test-Path (Join-Path $mods 'smods'))) 'kept Steamodded untouched, bundled one not added'
    Ok (([IO.File]::ReadAllText((Join-Path $game 'winmm.dll'))) -match '0\.11\.0') 'kept Lovely untouched'
    Ok (Test-Path (Join-Path $mods 'BalatroMultiplayer3P\compat.cfg')) 'mod installed with compat.cfg'
    $man = Get-Content -LiteralPath (Join-Path $root 'data\MP3P-install.json') -Raw | ConvertFrom-Json
    Ok ($man.deps.steamodded.action -eq 'keep' -and $man.deps.lovely.action -eq 'keep' -and -not (@($man.installedPaths) -contains (Join-Path $game 'winmm.dll'))) 'manifest records keep; kept files are not ours to uninstall'

    # real run, policy tested: replaced, with backups
    Reset-Sandbox '1.0.0~BETA-1801a' '0.11.0'
    $r = Run-Installer @('-DepsPolicy', 'tested')
    Ok ($r.code -eq 0 -and (Get-SmodsVersion (Join-Path $mods 'smods')) -eq '1.0.0~BETA-1620a' -and -not (Test-Path (Join-Path $mods 'smods-mine'))) 'policy tested: tested Steamodded installed'
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $root 'data') -Directory -Filter 'MP3P-backup-*')
    Ok ($bk.Count -eq 1 -and (Test-Path (Join-Path $bk[0].FullName 'mods__smods-mine')) -and (Test-Path (Join-Path $bk[0].FullName 'game__winmm.dll'))) 'your newer versions are backed up'
    Ok ((Get-LovelyVersion (Join-Path $game 'winmm.dll') $null) -eq '0.10.0') 'tested Lovely installed'

    # updater passes the policy only to installers that know it
    $upd = [IO.File]::ReadAllText((Join-Path $Repo 'mod\updater\update.ps1'))
    Ok ($upd -match "-DepsPolicy" -and $upd -match "'keep'" -and $upd -match "'ask'") 'updater passes -DepsPolicy (ask, or keep with -NoPrompt)'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host ""
if ($script:fails -gt 0) { Write-Host "$($script:fails) FAILED, $($script:passes) passed" -ForegroundColor Red; exit 1 }
Write-Host "PASS: installer pins ($($script:passes) checks)" -ForegroundColor Green
exit 0
