# Balatro High Stakes - installer test with the REAL official Balatro Multiplayer downloads (Windows PowerShell 5.1+).
#   powershell -File tools\test_installer_clash_real.ps1 -Work <empty temp dir> -InstallerZip <our Installer zip> -OfficialZip <zip of:
#     BalatroMultiplayerPvP-1.0.1-source.zip, BalatroMultiplayerAPI-1.0.1-source.zip (GitHub source zips),
#     ts-MultiplayerPvP-1.0.1.zip (Thunderstore), BalatroMultiplayer-0.5.5.zip (legacy release asset)>
# Runs Install.bat / Uninstall.bat on sandbox folders under -Work only (fake game + Mods dir). Never touches AppData.
param([string]$Work, [string]$InstallerZip, [string]$OfficialZip)
$ErrorActionPreference = 'Stop'
$script:res = @()
function Rec($n, $ok, $d = '') { $script:res += ('{0,-34} {1} {2}' -f $n, $(if ($ok) { 'PASS' } else { 'FAIL' }), $d) }
$off = Join-Path $Work 'official'; Expand-Archive $OfficialZip $off -Force
$inst = Join-Path $Work 'inst'; Expand-Archive $InstallerZip $inst -Force
$inst = (Get-ChildItem $inst -Directory | Select -First 1).FullName
function Tree($p) { if (-not (Test-Path -LiteralPath $p)) { return '' } ; (Get-ChildItem -LiteralPath $p -Recurse -File -Force | Sort-Object FullName | % { $_.FullName.Substring($p.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n" }
function Setup {
    $script:root = Join-Path $Work ('s' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $script:game = Join-Path $root 'game'; $script:mods = Join-Path $root 'Balatro\Mods'
    New-Item -ItemType Directory $game, $mods -Force | Out-Null; Set-Content (Join-Path $game 'Balatro.exe') 'fake'
    # like a player: Windows "Extract All" of the GitHub source zip (nested folder of the same name)
    Expand-Archive (Join-Path $off 'BalatroMultiplayerPvP-1.0.1-source.zip') (Join-Path $mods 'BalatroMultiplayerPvP-1.0.1')
    # GitHub source zip extracted "here" (one folder) and the Thunderstore zip (flat) into a named folder
    Expand-Archive (Join-Path $off 'BalatroMultiplayerAPI-1.0.1-source.zip') $mods
    Expand-Archive (Join-Path $off 'ts-MultiplayerPvP-1.0.1.zip') (Join-Path $mods 'BalatroMultiplayer-MultiplayerPvP')
    Expand-Archive (Join-Path $off 'BalatroMultiplayer-0.5.5.zip') (Join-Path $mods 'BalatroMultiplayer')
    New-Item -ItemType Directory (Join-Path $mods 'SomeJokers') | Out-Null; Set-Content (Join-Path $mods 'SomeJokers\SomeJokers.json') '{ "id": "SomeJokers", "version": "1.0" }'
    $script:orig = @{}; foreach ($f in 'BalatroMultiplayerPvP-1.0.1', 'BalatroMultiplayerAPI-1.0.1', 'BalatroMultiplayer-MultiplayerPvP', 'BalatroMultiplayer', 'SomeJokers') { $script:orig[$f] = Tree (Join-Path $mods $f) }
}
function Inst([string[]]$a, [string]$stdin = $null) {
    $args2 = @('-GameDir', $game, '-ModsRoot', $mods, '-NoPause', '-SkipProcessCheck', '-SteamRoots', (Join-Path $root 'nosteam')) + $a
    $bat = Join-Path $inst 'Install.bat'
    $line = '"' + $bat + '" ' + (($args2 | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    if ($null -ne $stdin) { $o = ($stdin | & cmd /c $line 2>&1 | Out-String) } else { $o = (& cmd /c $line 2>&1 | Out-String) }
    return @{ code = $LASTEXITCODE; out = $o }
}
function Has($f) { Test-Path -LiteralPath (Join-Path $mods $f) }
$names = 'BalatroMultiplayerPvP-1.0.1', 'BalatroMultiplayerAPI-1.0.1', 'BalatroMultiplayer-MultiplayerPvP', 'BalatroMultiplayer'
try {
    Setup
    $before = Tree $root
    $r = Inst @('-NoPrompt', '-DryRun')
    $cl = ([regex]::Matches($r.out, 'CLASH (\S+) folder=(\S+) action=move \(dry run\)') | % { "$($_.Groups[1].Value)@$($_.Groups[2].Value)" }) -join ','
    Rec 'dryrun_lists_4_real_folders' ($cl -eq 'MultiplayerPvP@BalatroMultiplayerPvP-1.0.1,MultiplayerAPI@BalatroMultiplayerAPI-1.0.1,MultiplayerPvP@BalatroMultiplayer-MultiplayerPvP,Multiplayer@BalatroMultiplayer' -or ($cl.Split(',').Count -eq 4)) $cl
    Rec 'dryrun_changes_nothing' ((Tree $root) -eq $before -and $r.code -eq 0)
    Rec 'dryrun_no_SomeJokers' ($r.out -notmatch 'folder=SomeJokers')
    $r = Inst @('-NoPrompt')
    Rec 'noprompt_moves_all_4' ($r.code -eq 0 -and -not ($names | ? { Has $_ })) "exit $($r.code)"
    Rec 'noprompt_keeps_unrelated' ((Tree (Join-Path $mods 'SomeJokers')) -eq $orig['SomeJokers'])
    $bk = Get-ChildItem (Split-Path $mods) -Directory -Filter 'MP3P-backup-*' | Select -First 1
    $okb = $true; foreach ($n in $names) { if ((Tree (Join-Path $bk.FullName "mods__$n")) -ne $orig[$n]) { $okb = $false } }
    Rec 'backup_byte_identical' $okb $bk.Name
    Rec 'high_stakes_installed' ((Has 'BalatroMultiplayer3P\Multiplayer.json') -and (Has 'smods'))
    $r2 = Inst @('-NoPrompt')
    Rec 'rerun_no_clash' ($r2.code -eq 0 -and $r2.out -notmatch 'CLASH ')
    $uline = '"' + (Join-Path $inst 'Uninstall.bat') + '" -ModsRoot "' + $mods + '" -NoPrompt -NoPause -SkipProcessCheck'
    $u = & cmd /c $uline 2>&1 | Out-String
    $okr = $true; foreach ($n in $names + 'SomeJokers') { if ((Tree (Join-Path $mods $n)) -ne $orig[$n]) { $okr = $false } }
    Rec 'uninstall_restores_exactly' ($okr -and -not (Has 'BalatroMultiplayer3P'))
    Remove-Item $root -Recurse -Force

    Setup
    $r = Inst @('-NoPrompt', '-KeepOtherMultiplayer')
    $kept = -not ($names | ? { -not (Has $_) }); $same = -not ($names | ? { (Tree (Join-Path $mods $_)) -ne $orig[$_] })
    Rec 'keep_switch_leaves_them' ($r.code -eq 0 -and $kept -and $same -and $r.out -match 'action=keep')
    Rec 'keep_switch_same_id_warning' ($r.out -match 'stops BOTH from loading')
    Remove-Item $root -Recurse -Force

    Setup
    $r = Inst @() "n`r`n"
    Rec 'prompt_answer_n_keeps' (-not ($names | ? { -not (Has $_) })) "exit $($r.code)"
    Remove-Item $root -Recurse -Force
    Setup
    $r = Inst @() "`r`n"
    Rec 'prompt_enter_default_moves' (-not ($names | ? { Has $_ })) "exit $($r.code)"
    if ($r.out -match 'FAIL|ERROR') { Rec 'prompt_run_output' $false (($r.out -split "`n" | ? { $_ -match 'ERROR' }) -join ' / ') }
} finally {
    $script:res | % { $_ }
    Get-ChildItem $Work -Directory | ? { $_.Name -like 's*' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
