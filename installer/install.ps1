# Balatro High Stakes (formerly Balatro Multiplayer 3P) - friend installer (Windows PowerShell 5.1+ compatible)
param(
    [string]$GameDir = "",
    [string]$ModsRoot = "",
    [string]$HostAddress = "",
    [string]$Mode = "",          # "steam" (peer-to-peer, no server) or "tcp" (server address)
    [int]$Port = 0,
    [switch]$NoPrompt,          # for automated tests: never ask anything
    [switch]$SkipProcessCheck,
    [switch]$SkipConnectionTest,
    [switch]$NoPause,
    [string]$SteamRoots = "",   # test hook: ';'-separated Steam install dirs
    [ValidateSet('', 'ask', 'tested', 'keep')]
    [string]$DepsPolicy = "",   # newer Steamodded/Lovely already installed: ask (default) | tested | keep (default with -NoPrompt)
    [switch]$DryRun             # only print what would happen (pins) and change nothing
)
$ErrorActionPreference = 'Stop'
function J([string]$base, [string]$rel) { $p = $base; foreach ($s in $rel.Split('\')) { if ($s) { $p = Join-Path $p $s } }; return $p }
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here 'payload'
$OurModName = 'BalatroMultiplayer3P'
. (Join-Path $Here 'pins.ps1')

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }
function Finish($code) {
    if (-not $NoPause) { Write-Host ""; Read-Host "Press Enter to close" | Out-Null }
    exit $code
}
function Ask($q, $default) {
    if ($NoPrompt) { return $default }
    $a = Read-Host $q
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim()
}

# ---------- Locate Balatro ----------
function Get-SteamRoots {
    if ($SteamRoots) { return $SteamRoots.Split(';') | Where-Object { $_ } }
    $roots = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            if ($p.SteamPath) { $roots += ($p.SteamPath -replace '/', '\') }
            if ($p.InstallPath) { $roots += $p.InstallPath }
        } catch {}
    }
    $roots += "${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam"
    return $roots | Where-Object { $_ } | Select-Object -Unique
}

function Get-SteamLibraries {
    $libs = @()
    foreach ($root in Get-SteamRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $libs += $root
        $vdf = J $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = Get-Content -LiteralPath $vdf -Raw
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    return $libs | Select-Object -Unique
}

function Test-GameDir($d) {
    return ($d -and (Test-Path -LiteralPath (Join-Path $d 'Balatro.exe')))
}

function Find-Balatro {
    foreach ($lib in Get-SteamLibraries) {
        $c = J $lib 'steamapps\common\Balatro'
        if (Test-GameDir $c) { return $c }
    }
    return $null
}

function Pick-Folder {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select your Balatro game folder (the one containing Balatro.exe)'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    } catch {}
    return $null
}

# ---------- Mod helpers ----------
function Get-ModId($folder) {
    $ver = Join-Path $folder 'version.lua'
    if ((Test-Path -LiteralPath $ver) -and ((Get-Content -LiteralPath $ver -Raw) -match 'STEAMODDED')) { return @{ id = 'Steamodded'; version = ((Get-Content -LiteralPath $ver -Raw) -replace '^\s*return\s*"|"\s*$', '') } }
    foreach ($j in Get-ChildItem -LiteralPath $folder -Filter *.json -File -ErrorAction SilentlyContinue) {
        try {
            $o = Get-Content -LiteralPath $j.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($o.id) { return @{ id = [string]$o.id; version = [string]$o.version } }
            if ($o.name -eq 'Steamodded') { return @{ id = 'Steamodded'; version = [string]$o.version_number } }
        } catch {}
    }
    foreach ($l in Get-ChildItem -LiteralPath $folder -Filter *.lua -File -ErrorAction SilentlyContinue) {
        $head = Get-Content -LiteralPath $l.FullName -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $head) {
            if ($line -match '^---\s*MOD_ID:\s*(\S+)') { return @{ id = $Matches[1]; version = '' } }
        }
    }
    return $null
}

# =================== MAIN ===================
Say "=== Balatro High Stakes installer (formerly Balatro Multiplayer 3P) ===" Cyan
Say "This installs: Lovely (mod loader), Steamodded, and the Balatro High Stakes mod (2-8 player Multiplayer)."
Say ""

if (-not (Test-Path -LiteralPath (J $Payload "$OurModName\Multiplayer.json"))) {
    Say "ERROR: the 'payload' folder is missing. Unzip the whole installer zip first, then run Install.bat from the unzipped folder." Red
    Finish 1
}

# 1. Balatro running?
if (-not $SkipProcessCheck) {
    while (Get-Process -Name 'Balatro' -ErrorAction SilentlyContinue) {
        Say "Balatro is running. Please close the game first." Yellow
        if ($NoPrompt) { Finish 1 }
        Read-Host "Press Enter when Balatro is closed" | Out-Null
    }
}

# 2. Find game folder
if (-not (Test-GameDir $GameDir)) { $GameDir = Find-Balatro }
while (-not (Test-GameDir $GameDir)) {
    if ($NoPrompt) { Say "ERROR: Balatro not found." Red; Finish 1 }
    Say "Could not find Balatro automatically." Yellow
    $GameDir = Pick-Folder
    if (-not $GameDir) { $GameDir = Ask "Paste the path to your Balatro folder (contains Balatro.exe)" "" }
    $GameDir = $GameDir.Trim('"')
    if (-not (Test-GameDir $GameDir)) { Say "Balatro.exe not found in '$GameDir'." Red }
}
Say "Balatro found: $GameDir" Green

if (-not $ModsRoot) { $ModsRoot = J $env:APPDATA 'Balatro\Mods' }
$BalatroData = Split-Path -Parent $ModsRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $BalatroData "MP3P-backup-$Stamp"
$ManifestPath = Join-Path $BalatroData 'MP3P-install.json'
if (-not $DryRun) { New-Item -ItemType Directory -Path $ModsRoot -Force | Out-Null }

$manifest = [ordered]@{ installed = (Get-Date).ToString('s'); gameDir = $GameDir; modsRoot = $ModsRoot; backupDir = $BackupDir; backups = @(); installedPaths = @() }
# Re-install: keep earlier backups, and don't back up files we installed ourselves
$prevInstalled = @()
if (Test-Path -LiteralPath $ManifestPath) {
    try {
        $prev = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $prevInstalled = @($prev.installedPaths)
        foreach ($b in @($prev.backups)) { if ($b) { $manifest.backups += [ordered]@{ original = $b.original; backup = $b.backup } } }
        Say "Previous MP3P install found - updating it." DarkGray
    } catch {}
}
function Backup-Item($path, $kind) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    if ($script:prevInstalled -contains $path) { Remove-Item -LiteralPath $path -Recurse -Force; return }
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $name = Split-Path -Leaf $path
    $dest = Join-Path $BackupDir ("{0}__{1}" -f $kind, $name)
    Move-Item -LiteralPath $path -Destination $dest -Force
    $script:manifest.backups += [ordered]@{ original = $path; backup = $dest }
    Say "  Backed up $path" DarkGray
}

# Keep the settings (.env) of an existing 3P install when updating
$prevEnvPath = Join-Path (Join-Path $ModsRoot $OurModName) '.env'
$prevEnv = $null
if (Test-Path -LiteralPath $prevEnvPath) { $prevEnv = [System.IO.File]::ReadAllText($prevEnvPath) }

# 3. Pinned dependencies (compat.json): decide for Steamodded and Lovely first
$Compat = Read-Compat (J $Payload "$OurModName\compat.json")
$TestedSmods = if ($Compat) { [string]$Compat.steamodded.pin.version } else { '1.0.0~BETA-1620a' }
$TestedLovely = if ($Compat) { [string]$Compat.lovely.pin.version } else { '0.10.0' }
$LovelyPin = if ($Compat) { $Compat.lovely.pin } else { $null }
if (-not $DepsPolicy) { $DepsPolicy = if ($NoPrompt) { 'keep' } else { 'ask' } }

Say "Checking existing mods..."
$smodsFolders = @()
$smodsBest = $null
foreach ($f in Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue) {
    $info = Get-ModId $f.FullName
    if ($info -and $info.id -eq 'Steamodded') {
        $v = Get-SmodsVersion $f.FullName
        if (-not $v) { $v = ConvertTo-CleanVersion $info.version }
        $smodsFolders += $f.FullName
        if (-not $smodsBest -or ($v -and (Compare-ModVersion $v $smodsBest) -gt 0)) { $smodsBest = $v }
    }
}
$smodsDec = Resolve-DepAction $smodsBest ($smodsFolders.Count -gt 0) $TestedSmods $DepsPolicy
if ($smodsDec.action -eq 'ask') {
    if ($DryRun) { $smodsDec.action = 'ask (dry run: would prompt)' }
    else { $smodsDec = Resolve-DepAction $smodsBest $true $TestedSmods 'ask' (Read-DepChoice 'Steamodded' $smodsBest $TestedSmods) }
}
$existingDll = Join-Path $GameDir 'winmm.dll'
$lovelyHere = Test-Path -LiteralPath $existingDll
$lovelyVer = Get-LovelyVersion $existingDll $LovelyPin
$lovelyDec = Resolve-DepAction $lovelyVer $lovelyHere $TestedLovely $DepsPolicy
if ($lovelyDec.action -eq 'same' -and $LovelyPin -and $LovelyPin.winmm_sha256 -and ((Get-FileSha256 $existingDll) -ne $LovelyPin.winmm_sha256)) {
    $lovelyDec = @{ action = 'install'; why = 'same version, different file: refreshing it' }
}
if ($lovelyDec.action -eq 'ask') {
    if ($DryRun) { $lovelyDec.action = 'ask (dry run: would prompt)' }
    else { $lovelyDec = Resolve-DepAction $lovelyVer $true $TestedLovely 'ask' (Read-DepChoice 'Lovely' $lovelyVer $TestedLovely) }
}
$shownSmods = if ($smodsBest) { $smodsBest } elseif ($smodsFolders.Count) { 'unknown' } else { 'none' }
$shownLovely = if ($lovelyVer) { $lovelyVer } elseif ($lovelyHere) { 'unknown' } else { 'none' }
Say "PIN steamodded installed=$shownSmods tested=$TestedSmods action=$($smodsDec.action) ($($smodsDec.why))" DarkGray
Say "PIN lovely installed=$shownLovely tested=$TestedLovely action=$($lovelyDec.action) ($($lovelyDec.why))" DarkGray
if ($smodsDec.action -eq 'keep') { Say "  Keeping your Steamodded $smodsBest (tested: $TestedSmods). The game will warn you if it is untested." Yellow }
if ($lovelyDec.action -eq 'keep') { Say "  Keeping your Lovely $shownLovely (tested: $TestedLovely). The game will warn you if it is untested." Yellow }
if ($DryRun) {
    Say "DRY RUN: nothing was changed." Cyan
    Finish 0
}
$manifest.deps = [ordered]@{
    steamodded = [ordered]@{ found = $shownSmods; tested = $TestedSmods; action = $smodsDec.action }
    lovely = [ordered]@{ found = $shownLovely; tested = $TestedLovely; action = $lovelyDec.action }
}

# Remove old Multiplayer / Steamodded copies (backed up)
foreach ($f in Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue) {
    $info = Get-ModId $f.FullName
    if (-not $info) { continue }
    if ($info.id -eq 'Steamodded' -and $smodsDec.action -eq 'keep') { continue }
    if ($f.Name -eq $OurModName -or $f.Name -eq 'smods') {
        if ($prevInstalled -contains $f.FullName) { Remove-Item -LiteralPath $f.FullName -Recurse -Force; continue }
    }
    if ($info.id -eq 'Multiplayer') {
        Say "  Found a Multiplayer mod in '$($f.Name)' (version $($info.version)) - replacing it." Yellow
        Backup-Item $f.FullName 'mods'
    } elseif ($info.id -eq 'Steamodded') {
        Say "  Found Steamodded in '$($f.Name)' (version $($info.version)) - replacing it with the tested $TestedSmods." Yellow
        Backup-Item $f.FullName 'mods'
    }
}
$copyLovely = ($lovelyDec.action -eq 'install')
if ($copyLovely -and $lovelyHere) { Backup-Item $existingDll 'game' }
# Old Lovely (<0.10) used version.dll; Lovely 0.10 refuses to start while it exists
$oldLovely = Join-Path $GameDir 'version.dll'
if ($copyLovely -and (Test-Path -LiteralPath $oldLovely)) { Say "  Removing old Lovely (version.dll)" Yellow; Backup-Item $oldLovely 'game' }

# 4. Install
Say "Installing..."
if ($copyLovely) {
    try {
        Copy-Item -LiteralPath (Join-Path $Payload 'winmm.dll') -Destination $GameDir -Force
    } catch {
        Say "ERROR: could not copy winmm.dll into $GameDir ($($_.Exception.Message))." Red
        Say "Try right-clicking Install.bat -> Run as administrator." Yellow
        Finish 1
    }
    $manifest.installedPaths += $existingDll
    Say "  Lovely $TestedLovely -> $existingDll" Green
} else {
    if ($prevInstalled -contains $existingDll) { $manifest.installedPaths += $existingDll }
    Say "  Lovely      -> kept ($shownLovely)" Green
}
if ($smodsDec.action -ne 'keep') {
    Copy-Item -LiteralPath (Join-Path $Payload 'smods') -Destination $ModsRoot -Recurse -Force
    $manifest.installedPaths += (Join-Path $ModsRoot 'smods')
    Say "  Steamodded $TestedSmods -> $(Join-Path $ModsRoot 'smods')" Green
} else {
    Say "  Steamodded  -> kept ($smodsBest)" Green
}
Copy-Item -LiteralPath (Join-Path $Payload $OurModName) -Destination $ModsRoot -Recurse -Force
$ModDir = Join-Path $ModsRoot $OurModName
$manifest.installedPaths += $ModDir
Say "  High Stakes -> $ModDir" Green

# 5. Connection mode
Say ""
if (-not $Mode -and -not $HostAddress -and $prevEnv) {
    $prevMode = if ($prevEnv -match '(?m)^\s*mode\s*=\s*steam') { 'Steam' } else { 'server address' }
    if ((Ask "Keep your current settings ($prevMode)? (Y/n)" "y") -notmatch '^[nN]') {
        [System.IO.File]::WriteAllText((Join-Path $ModDir '.env'), $prevEnv, (New-Object System.Text.UTF8Encoding($false)))
        Say "  Kept your existing settings ($prevMode)" Green
        $Mode = 'keep'
        if ($prevMode -eq 'Steam') { $SkipConnectionTest = $true } else {
            if ($prevEnv -match '(?m)^\s*server_url\s*=\s*(\S+)') { $HostAddress = $Matches[1] }
            if ($prevEnv -match '(?m)^\s*server_port\s*=\s*(\d+)') { $Port = [int]$Matches[1] }
        }
    }
}
if (-not $Mode) {
    if ($HostAddress) { $Mode = 'tcp' }
    else {
        Say "How do you want to play?" Cyan
        Say "  1 = via Steam (recommended: no server, no Tailscale - the host's Balatro is the server)"
        Say "  2 = via a server address (Tailscale / playit.gg / public IP)"
        $Mode = if ((Ask "Choice [1]" "1") -match '^2') { 'tcp' } else { 'steam' }
    }
}
$Mode = $Mode.ToLower()
if ($Mode -eq 'keep') {
    # settings restored above
} elseif ($Mode -eq 'steam') {
    $envText = "# Written by the MP3P installer`r`nmode=steam`r`n# TCP fallback: remove the mode line and set server_url / server_port`r`nserver_url=127.0.0.1`r`nserver_port=8788`r`n"
    [System.IO.File]::WriteAllText((Join-Path $ModDir '.env'), $envText, (New-Object System.Text.UTF8Encoding($false)))
    Say "  Saved: Steam peer-to-peer mode" Green
    $SkipConnectionTest = $true
} else {
    Say ""
    Say "Now enter the address of the friend who hosts the server" Cyan
    Say "(their Tailscale IP like 100.x.y.z, a public IP, or a playit.gg address)."
    while ([string]::IsNullOrWhiteSpace($HostAddress)) {
        if ($NoPrompt) { Say "ERROR: no host address given." Red; Finish 1 }
        $HostAddress = Ask "Host address" ""
    }
    $HostAddress = ($HostAddress.Trim() -replace '^\w+://', '').TrimEnd('/')
    if ($HostAddress -match '^([^:]+):(\d+)$') { $HostAddress = $Matches[1]; if (-not $Port) { $Port = [int]$Matches[2] } }
    if (-not $Port) { $Port = [int](Ask "Port [8788]" "8788") }
    $envText = "# Written by the MP3P installer`r`nserver_url=$HostAddress`r`nserver_port=$Port`r`n"
    [System.IO.File]::WriteAllText((Join-Path $ModDir '.env'), $envText, (New-Object System.Text.UTF8Encoding($false)))
    Say "  Saved server address: ${HostAddress}:$Port" Green
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

# 6. Connection test
$connOk = $null
$doTest = -not $SkipConnectionTest
if ($doTest -and -not $NoPrompt) { $doTest = ((Ask "Test the connection to the server now? (Y/n)" "y") -notmatch '^[nN]') }
if ($doTest) {
    Say "Testing ${HostAddress}:$Port ..."
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostAddress, $Port, $null, $null)
        $connOk = $iar.AsyncWaitHandle.WaitOne(5000) -and $client.Connected
        $client.Close()
    } catch { $connOk = $false }
    if ($connOk) { Say "  Connection OK - the server is reachable!" Green }
    else {
        Say "  Could not reach the server." Yellow
        Say "  That's fine if the host hasn't started it yet. Otherwise check: is the server running," Yellow
        Say "  are you both on Tailscale / is port $Port forwarded, and does the host's firewall allow it?" Yellow
    }
}

# 7. Summary
Say ""
Say "=== Done! ===" Cyan
Say "Start Balatro normally from Steam. You should see a 'Mods' button in the menu."
Say "Play -> Join Lobby -> enter the code from your host -> Ready."
if ($manifest.backups.Count -gt 0) { Say "Your old files were backed up to: $((@($manifest.backups | ForEach-Object { Split-Path -Parent $_.backup }) | Select-Object -Unique) -join ', ')" }
Say "To remove everything again, run Uninstall.bat."
Finish 0
