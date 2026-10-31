# Balatro High Stakes - tests for the optional All-in-Jest step of the installer (PowerShell 5.1+ / pwsh).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_installer_aij.ps1
# Throw-away folders in TEMP only; uses a fake All-in-Jest zip (no network, never the real game).
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $Repo 'installer\pins.ps1')
$script:fails = 0; $script:passes = 0
function Ok($cond, $msg) { if ($cond) { $script:passes++; Write-Host "ok: $msg" } else { $script:fails++; Write-Host "FAIL: $msg" -ForegroundColor Red } }
$PS = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' }
if (-not $env:TEMP) { $env:TEMP = [IO.Path]::GetTempPath() }

# ---------- unit: decisions ----------
$e72 = @([pscustomobject]@{ path = 'x'; version = '0.7.2' }); $e74 = @([pscustomobject]@{ path = 'x'; version = '0.7.4' })
Ok ((Resolve-AijAction '' @() '0.7.2').action -eq 'skip') 'empty answer -> No (default)'
Ok ((Resolve-AijAction 'n' @() '0.7.2').action -eq 'skip' -and (Resolve-AijAction 'no' @() '0.7.2').action -eq 'skip') 'n/no -> skip'
Ok ((Resolve-AijAction 'y' @() '0.7.2').action -eq 'install' -and (Resolve-AijAction 'ja' @() '0.7.2').action -eq 'install') 'y/ja, none installed -> install'
Ok ((Resolve-AijAction 'yes' $e72 '0.7.2').action -eq 'same') 'same version installed -> nothing to do'
Ok ((Resolve-AijAction 'yes' $e74 '0.7.2').action -eq 'ask_overwrite') 'other version installed -> ask before replacing'
Ok ((Resolve-AijAction 'yes' $e74 '0.7.2' '').action -eq 'keep' -and (Resolve-AijAction 'yes' $e74 '0.7.2' 'n').action -eq 'keep') 'overwrite: Enter/n -> keep yours'
Ok ((Resolve-AijAction 'yes' $e74 '0.7.2' 'y').action -eq 'replace') 'overwrite: y -> replace (backed up)'
$cc = Get-Content -LiteralPath (Join-Path $Repo 'mod\compat.cfg') -Raw | ConvertFrom-Json
Ok ($cc.allinjest.pin.version -eq '0.7.2' -and $cc.allinjest.pin.url -match '^https://github\.com/survovoaneend/All-In-Jest/' -and $cc.allinjest.pin.sha256 -match '^[0-9a-f]{64}$') 'compat.json pins 0.7.2 from the official repo with a sha256'
Ok (-not (Test-Path (Join-Path $Repo 'installer\All-In-Jest'))) 'not bundled in the installer folder'
$cred = [IO.File]::ReadAllText((Join-Path $Repo 'installer\CREDITS.txt'))
Ok ($cred -match 'All-in-Jest' -and $cred -match 'permission') 'credits name All-in-Jest and the permission'
$readme = [IO.File]::ReadAllText((Join-Path $Repo 'installer\README.txt'))
Ok (-not ($readme -match 'permission')) 'permission note only in the credits, not the readme'

# ---------- sandbox ----------
$root = Join-Path ([IO.Path]::GetTempPath()) ("mp3p-aijtest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$inst = Join-Path $root 'inst'; $payload = Join-Path $inst 'payload'
$game = Join-Path $root 'game'; $mods = Join-Path $root 'data\Mods'
function W([string]$path, [string]$text) { New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null; [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false))) }
# fake All-in-Jest release zip (folder inside, like GitHub's tag archive)
$fz = Join-Path $root 'fake\All-In-Jest-0.7.2'
W (Join-Path $fz 'metadata.json') '{ "id": "allinjest", "name": "All in Jest", "version": "0.7.2" }'
W (Join-Path $fz 'main.lua') '-- fake'
$zip = Join-Path $root 'aij.zip'
Compress-Archive -Path $fz -DestinationPath $zip
$sha = Get-FileSha256 $zip
function Reset-Sandbox($existingVer, [string]$badSha) {
    foreach ($d in $inst, $game, (Join-Path $root 'data')) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
    foreach ($f in 'install.ps1', 'pins.ps1', 'settings.ps1') { W (Join-Path $inst $f) ([IO.File]::ReadAllText((Join-Path $Repo "installer\$f"))) }
    W (Join-Path $payload 'BalatroMultiplayer3P\Multiplayer.json') '{ "id": "Multiplayer", "version": "0.6.8" }'
    $c = Get-Content -LiteralPath (Join-Path $Repo 'mod\compat.cfg') -Raw | ConvertFrom-Json
    $c.allinjest.pin.sha256 = if ($badSha) { $badSha } else { $sha }
    W (Join-Path $payload 'BalatroMultiplayer3P\compat.cfg') ($c | ConvertTo-Json -Depth 8)
    W (Join-Path $payload 'smods\version.lua') 'return "1.0.0~BETA-1620a-STEAMODDED"'
    W (Join-Path $payload 'winmm.dll') "fake dll lovely-injectorversion0.10.0mod_dir"
    W (Join-Path $game 'Balatro.exe') 'fake'
    New-Item -ItemType Directory -Path $mods -Force | Out-Null
    if ($existingVer) { W (Join-Path $mods 'AllInJest-mine\metadata.json') "{ `"id`": `"allinjest`", `"version`": `"$existingVer`" }" }
}
function Run-Installer([string[]]$extra) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $inst 'install.ps1'), '-GameDir', $game, '-ModsRoot', $mods,
        '-Mode', 'steam', '-NoPrompt', '-NoPause', '-SkipProcessCheck', '-SkipConnectionTest', '-AijZip', $zip) + $extra
    $out = & $PS @a 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out }
}
try {
    Reset-Sandbox $null
    $r = Run-Installer @()
    Ok ($r.code -eq 0 -and $r.out -match 'PIN allinjest action=skip' -and -not (Test-Path (Join-Path $mods 'All-In-Jest'))) 'no answer (-NoPrompt) -> All-in-Jest not installed'
    Reset-Sandbox $null
    $r = Run-Installer @('-AllInJest', 'yes')
    Ok ($r.code -eq 0 -and (Test-Path (Join-Path $mods 'All-In-Jest\metadata.json'))) 'yes -> extracted to Mods\All-In-Jest (folder flattened)'
    $man = Get-Content -LiteralPath (Join-Path $root 'data\MP3P-install.json') -Raw | ConvertFrom-Json
    Ok (@($man.installedPaths) -contains (Join-Path $mods 'All-In-Jest') -and $man.deps.allinjest.action -eq 'install') 'manifest records it (uninstall removes only what we installed)'
    Reset-Sandbox '0.7.4'
    $r = Run-Installer @('-AllInJest', 'yes')
    Ok ($r.code -eq 0 -and $r.out -match 'action=keep' -and (Test-Path (Join-Path $mods 'AllInJest-mine')) -and -not (Test-Path (Join-Path $mods 'All-In-Jest'))) 'existing 0.7.4 + no answer -> kept, nothing overwritten'
    Reset-Sandbox '0.7.4'
    $r = Run-Installer @('-AllInJest', 'yes', '-AllInJestOverwrite', 'yes')
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $root 'data') -Directory -Filter 'MP3P-backup-*')
    Ok ($r.code -eq 0 -and (Test-Path (Join-Path $mods 'All-In-Jest\metadata.json')) -and -not (Test-Path (Join-Path $mods 'AllInJest-mine')) -and $bk.Count -eq 1 -and (Test-Path (Join-Path $bk[0].FullName 'allinjest__AllInJest-mine'))) 'overwrite yes -> replaced, yours backed up'
    Reset-Sandbox $null ('0' * 64)
    $r = Run-Installer @('-AllInJest', 'yes')
    Ok ($r.code -eq 0 -and $r.out -match 'does not match the pinned sha256' -and -not (Test-Path (Join-Path $mods 'All-In-Jest')) -and (Test-Path (Join-Path $mods 'BalatroMultiplayer3P'))) 'hash mismatch -> nothing installed, High Stakes still installed'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host "$($script:passes) passed, $($script:fails) failed"
if ($script:fails) { exit 1 }
