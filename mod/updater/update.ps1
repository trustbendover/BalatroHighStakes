# Balatro High Stakes (formerly Balatro Multiplayer 3P) - updater (Windows PowerShell 5.1+). GPL-3.0.
# Downloads the Installer zip of the latest GitHub release, verifies its SHA256 against the
# SHA256SUMS asset, waits until Balatro is closed and runs the installer in update mode
# (keeps your .env settings). Started by the "Update available" button in the game, or by Update.bat.
param(
    [string]$Repo = '',             # default: brand.json "repo" (trustbendover/BalatroHighStakes)
    [string]$FallbackRepo = '',     # default: brand.json "repo_old" (trustbendover/BalatroMultiplayer3P), tried when $Repo fails
    [string]$CurrentVersion = '',   # default: read from Multiplayer.json next to this script
    [switch]$CheckOnly,             # only print installed/latest and exit (0 = up to date, 10 = update available, 1 = error)
    [switch]$FromGame,              # started from Balatro: wait for the game to close
    [switch]$Force,                 # reinstall even when up to date
    [switch]$NoPrompt,
    [switch]$NoPause,
    [int]$WaitMinutes = 30,
    [string]$ApiBase = 'https://api.github.com',            # test hooks
    [string]$RawBase = 'https://raw.githubusercontent.com',
    [string]$InstallerArgs = ''                             # extra args for install.ps1 (tests), e.g. "-GameDir X -ModsRoot Y"
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Done($code) {
    if (-not $NoPause -and -not $CheckOnly) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
    exit $code
}
function Parse-Ver([string]$v) {
    $m = [regex]::Match(($v -replace '^\s*[vV]', ''), '^[\d\.]+')
    if (-not $m.Success) { return @() }
    return @($m.Value.Split('.') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
}
function Is-Newer([string]$a, [string]$b) {
    $x = Parse-Ver $a; $y = Parse-Ver $b
    if ($x.Count -eq 0 -or $y.Count -eq 0) { return $false }
    for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
        $p = if ($i -lt $x.Count) { $x[$i] } else { 0 }; $q = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($p -ne $q) { return ($p -gt $q) }
    }
    return $false
}

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
# 0.6.8: repo slug + zip prefix in one place (mod/brand.json); built-in defaults if it is missing.
$Brand = @{ repo = 'trustbendover/BalatroHighStakes'; repo_old = 'trustbendover/BalatroMultiplayer3P'; asset_prefix = 'BalatroMultiplayer3P' }
foreach ($bj in (Join-Path (Split-Path -Parent $Here) 'brand.json'), (Join-Path $Here 'payload\BalatroMultiplayer3P\brand.json'), (Join-Path $Here 'brand.json')) {
    if (Test-Path -LiteralPath $bj) {
        try { $b = Get-Content -LiteralPath $bj -Raw | ConvertFrom-Json; foreach ($k in 'repo', 'repo_old', 'asset_prefix') { if ($b.$k) { $Brand[$k] = [string]$b.$k } } } catch {}
        break
    }
}
if (-not $Repo) { $Repo = $Brand.repo }
if (-not $FallbackRepo) { $FallbackRepo = $Brand.repo_old }
$Repos = @($Repo); if ($FallbackRepo -and $FallbackRepo -ne $Repo) { $Repos += $FallbackRepo }
$PS = (Get-Process -Id $PID).Path   # same PowerShell that runs us (powershell.exe on Windows)
if (-not $env:TEMP) { $env:TEMP = [IO.Path]::GetTempPath().TrimEnd('/', '\') }
# The installer replaces the mod folder this script lives in, so run from a temp copy.
if (-not $CheckOnly -and $Here -notlike "$env:TEMP*") {
    $tmpDir = Join-Path $env:TEMP ('mp3p-updater-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $tmpDir
    if (-not $CurrentVersion) {
        $mj = Join-Path (Split-Path -Parent $Here) 'Multiplayer.json'
        if (Test-Path -LiteralPath $mj) { $CurrentVersion = (Get-Content -LiteralPath $mj -Raw | ConvertFrom-Json).version }
    }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $tmpDir 'update.ps1'), '-Repo', $Repo, '-FallbackRepo', $FallbackRepo, '-WaitMinutes', $WaitMinutes, '-ApiBase', $ApiBase, '-RawBase', $RawBase)
    if ($InstallerArgs) { $a += @('-InstallerArgs', $InstallerArgs) }
    if ($CurrentVersion) { $a += @('-CurrentVersion', $CurrentVersion) }
    foreach ($s in 'FromGame', 'Force', 'NoPrompt', 'NoPause') { if ((Get-Variable $s).Value) { $a += "-$s" } }
    & $PS @a
    exit $LASTEXITCODE
}
if (-not $CurrentVersion) {
    foreach ($mj in (Join-Path (Split-Path -Parent $Here) 'Multiplayer.json'), (Join-Path $env:APPDATA 'Balatro\Mods\BalatroMultiplayer3P\Multiplayer.json')) {
        if (Test-Path -LiteralPath $mj) { $CurrentVersion = (Get-Content -LiteralPath $mj -Raw | ConvertFrom-Json).version; break }
    }
}

Say "Balatro High Stakes updater" Cyan
Say "  Installed: $(if ($CurrentVersion) { $CurrentVersion } else { 'not found' })"
$headers = @{ 'User-Agent' = 'BalatroHighStakes-updater'; 'Accept' = 'application/vnd.github+json' }

# ---------- find the latest release ----------
$tag = $null; $installerUrl = $null; $sumsUrl = $null; $zipName = $null
# new repo name first, then the old one (0.6.8 rename; GitHub also redirects the old name)
foreach ($r in $Repos) {
    try {
        $rel = Invoke-RestMethod -Uri "$ApiBase/repos/$r/releases/latest" -Headers $headers -TimeoutSec 20
        $inst = $rel.assets | Where-Object { $_.name -like '*Installer.zip' } | Select-Object -First 1
        $sums = $rel.assets | Where-Object { $_.name -like 'SHA256SUMS*' } | Select-Object -First 1
        if ($inst) { $tag = $rel.tag_name; $installerUrl = $inst.browser_download_url; $zipName = $inst.name; $sumsUrl = $null; if ($sums) { $sumsUrl = $sums.browser_download_url }; break }
    } catch { Say "  GitHub API not reachable for $r ($($_.Exception.Message))" Yellow }
}
if (-not $installerUrl) {
    $lastErr = $null
    foreach ($r in $Repos) {
        try {
            $vj = Invoke-RestMethod -Uri "$RawBase/$r/main/version.json" -Headers $headers -TimeoutSec 20
            $tag = if ($vj.tag) { $vj.tag } else { 'v' + ($vj.version -replace '~.*$', '') }
            $zipName = "$($Brand.asset_prefix)-$tag-Installer.zip"
            $installerUrl = "https://github.com/$r/releases/download/$tag/$zipName"
            $sumsUrl = "https://github.com/$r/releases/download/$tag/SHA256SUMS-$tag.txt"
            break
        } catch { $lastErr = $_.Exception.Message }
    }
    if (-not $installerUrl) { Say "  Could not check for updates (offline?): $lastErr" Red; if ($CheckOnly) { exit 1 }; Done 1 }
}
Say "  Latest:    $tag"
$newer = Is-Newer $tag $CurrentVersion
if ($CheckOnly) {
    if ($newer) { Say "UPDATE AVAILABLE: $tag" Green; exit 10 } else { Say "Up to date." Green; exit 0 }
}
if (-not $newer -and -not $Force) { Say "You already have the latest version." Green; Done 0 }

# ---------- download + verify ----------
$work = Join-Path $env:TEMP ('mp3p-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$zip = Join-Path $work $zipName
Say "Downloading $zipName ..."
Invoke-WebRequest -Uri $installerUrl -Headers @{ 'User-Agent' = 'BalatroHighStakes-updater' } -OutFile $zip -UseBasicParsing -TimeoutSec 300
if (-not $sumsUrl) { Say "No SHA256SUMS file in this release - refusing to install an unverified download." Red; Done 1 }
$sumsText = (Invoke-WebRequest -Uri $sumsUrl -Headers @{ 'User-Agent' = 'BalatroHighStakes-updater' } -UseBasicParsing -TimeoutSec 60).Content
if ($sumsText -is [byte[]]) { $sumsText = [Text.Encoding]::UTF8.GetString($sumsText) }
$expected = $null
foreach ($line in ($sumsText -split "`r?`n")) {
    if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $zipName) { $expected = $Matches[1].ToLower() }
}
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
if (-not $expected -or $expected -ne $actual) {
    Say "SHA256 check FAILED (expected $expected, got $actual). Nothing was installed." Red
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Done 1
}
Say "  SHA256 OK ($actual)" Green

# ---------- wait for Balatro to close ----------
$deadline = (Get-Date).AddMinutes($WaitMinutes); $told = $false
while (Get-Process -Name 'Balatro' -ErrorAction SilentlyContinue) {
    if (-not $told) { Say ""; Say ">>> Close Balatro now. The update installs as soon as the game is closed. <<<" Yellow; $told = $true }
    if ((Get-Date) -gt $deadline) { Say "Balatro is still running - update cancelled. Run Update.bat later." Red; Done 1 }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 1

# ---------- install (update mode: keeps .env) ----------
$ex = Join-Path $work 'x'
Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force
$installer = Get-ChildItem -LiteralPath $ex -Recurse -Filter 'install.ps1' | Select-Object -First 1
if (-not $installer) { Say "install.ps1 not found in the download." Red; Done 1 }
Say "Installing $tag ..."
$ia = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer.FullName, '-NoPrompt', '-NoPause', '-SkipConnectionTest', '-SkipProcessCheck')
# 0.6.8: a newer Steamodded/Lovely is never replaced silently. Interactive updater: the player is
# asked (tested version recommended); -NoPrompt: kept, with a message. Only for installers that know it.
if (($InstallerArgs -notmatch '-DepsPolicy') -and ((Get-Content -LiteralPath $installer.FullName -Raw) -match 'DepsPolicy')) {
    $ia += @('-DepsPolicy', $(if ($NoPrompt) { 'keep' } else { 'ask' }))
}
if ($InstallerArgs) { $ia += ($InstallerArgs -split ' ' | Where-Object { $_ }) }
& $PS @ia
$code = $LASTEXITCODE
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { Say "Installer failed (exit $code)." Red; Done $code }
Say ""
Say "Updated to $tag. Start Balatro again from Steam." Green
Done 0
