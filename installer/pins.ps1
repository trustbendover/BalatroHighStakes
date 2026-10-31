# Balatro High Stakes - dependency pins (dot-sourced by install.ps1 and the tests). GPL-3.0.
# The tested Steamodded / Lovely versions come from compat.json (the same file the mod's startup
# guard and the release build use). A newer version that is already installed is never replaced
# silently: the player chooses, or (no prompt, e.g. the updater) it is kept with a clear message.

function Read-Compat([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# "1.0.0~BETA-1620a-STEAMODDED" -> "1.0.0~BETA-1620a"; "v0.10.0" -> "0.10.0"
function ConvertTo-CleanVersion([string]$v) {
    if (-not $v) { return $null }
    $v = $v.Trim() -replace '^[vV]', '' -replace '-STEAMODDED$', '' -replace '-FULL$', ''
    if (-not $v) { return $null }
    return $v
}

# tokens like the mod's compat guard: numbers, words, and "~" (pre-release marker)
function Get-VersionTokens([string]$v) {
    $v = ConvertTo-CleanVersion $v
    $t = New-Object System.Collections.ArrayList
    if (-not $v) { return ,$t }
    foreach ($m in [regex]::Matches($v.ToLower(), '\d+|[a-z]+|~')) {
        $s = $m.Value
        if ($s -match '^\d+$') { [void]$t.Add([int64]$s) } else { [void]$t.Add($s) }
    }
    return ,$t
}

function Test-Tilde($t) { return ($t -is [string]) -and ($t -eq '~') }

# -1 / 0 / 1 (same rules as CG.cmp in mod/lib/compat_guard.lua)
function Compare-ModVersion([string]$a, [string]$b) {
    $ta = Get-VersionTokens $a; $tb = Get-VersionTokens $b
    $n = [Math]::Max($ta.Count, $tb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -ge $ta.Count) { if (Test-Tilde $tb[$i]) { return 1 } else { return -1 } }
        if ($i -ge $tb.Count) { if (Test-Tilde $ta[$i]) { return -1 } else { return 1 } }
        $x = $ta[$i]; $y = $tb[$i]
        if ($x -is [string] -and $y -is [string] -and $x -eq $y) { continue }
        if ($x -isnot [string] -and $y -isnot [string] -and $x -eq $y) { continue }
        if (Test-Tilde $x) { return -1 }
        if (Test-Tilde $y) { return 1 }
        if (($x -is [string]) -eq ($y -is [string])) { if ($x -lt $y) { return -1 } else { return 1 } }
        if ($x -is [string]) { return 1 } else { return -1 }
    }
    return 0
}

# Steamodded version from its version.lua ('return "1.0.0~BETA-1620a-STEAMODDED"')
function Get-SmodsVersion([string]$folder) {
    $f = Join-Path $folder 'version.lua'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $raw = Get-Content -LiteralPath $f -Raw
    if ($raw -match 'return\s*"([^"]+)"') { return (ConvertTo-CleanVersion $Matches[1]) }
    return $null
}

function Get-FileSha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($path)
    try { return (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $fs.Close() }
}

# Lovely's winmm.dll has no version resource: the pinned hash is exact, otherwise read the
# "lovely-injector ... version X.Y.Z" metadata string inside the dll. $null = unknown.
function Get-LovelyVersion([string]$dll, $pin) {
    if (-not (Test-Path -LiteralPath $dll)) { return $null }
    if ($pin -and $pin.winmm_sha256 -and ((Get-FileSha256 $dll) -eq $pin.winmm_sha256)) { return [string]$pin.version }
    try {
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($dll))
        $m = [regex]::Match($text, 'lovely-injector[\x00-\x20]*version[\x00-\x20]*(\d+\.\d+\.\d+)')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch {}
    return $null
}

# What to do with one dependency.
#   installed: version found ($null = not installed), present: is something there at all
#   policy: ask | tested | keep ; answer: the player's choice when asked ('1' tested / '2' keep)
# -> @{ action = install|keep|same|ask ; why = ... }
function Resolve-DepAction([string]$installed, [bool]$present, [string]$tested, [string]$policy, [string]$answer = '') {
    if (-not $present) { return @{ action = 'install'; why = 'not installed' } }
    if ($installed -and (Compare-ModVersion $installed $tested) -eq 0) { return @{ action = 'same'; why = 'already the tested version' } }
    if ($installed -and (Compare-ModVersion $installed $tested) -lt 0) { return @{ action = 'install'; why = "older than the tested $tested" } }
    $why = if ($installed) { "newer than the tested $tested" } else { "unknown version (tested: $tested)" }
    switch ($policy) {
        'tested' { return @{ action = 'install'; why = $why } }
        'keep' { return @{ action = 'keep'; why = $why } }
        default {
            if ($answer -match '^\s*2') { return @{ action = 'keep'; why = $why } }
            if ($answer -match '^\s*1' -or $answer -eq 'enter') { return @{ action = 'install'; why = $why } }
            return @{ action = 'ask'; why = $why }
        }
    }
}

# Ask the player (only for a newer / unknown version). Enter = install the tested one.
function Read-DepChoice([string]$name, [string]$installed, [string]$tested) {
    $shown = if ($installed) { $installed } else { 'an unknown version' }
    Write-Host ""
    Write-Host "$name $shown is installed. Balatro High Stakes was tested with $name $tested." -ForegroundColor Yellow
    Write-Host "  1 = Install the tested version (recommended) - yours is backed up"
    Write-Host "  2 = Keep yours (multiplayer may break; the game will warn you)"
    $a = Read-Host "Choice [1]"
    if ([string]::IsNullOrWhiteSpace($a)) { return 'enter' }
    return $a.Trim()
}

# ---------------------------------------------------------------- optional All-in-Jest (0.6.8)
# Never bundled: downloaded from the author's official GitHub (with permission), pinned by sha256 in
# compat.json. Default No. An existing All-in-Jest is never replaced without asking.

# All-in-Jest folders in Mods: any folder whose metadata.json has "id": "allinjest"
function Find-AijFolders([string]$modsRoot) {
    $out = @()
    if (-not $modsRoot -or -not (Test-Path -LiteralPath $modsRoot)) { return ,$out }
    foreach ($d in Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue) {
        $m = Join-Path $d.FullName 'metadata.json'
        if (Test-Path -LiteralPath $m) {
            try { $j = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ([string]$j.id -eq 'allinjest') { $out += [pscustomobject]@{ path = $d.FullName; version = [string]$j.version } }
        }
    }
    return ,$out
}

# choice: the answer to "Install All-in-Jest?" (y/yes/j/ja = yes; anything else / empty = No)
# overwrite: the answer to "Replace your All-in-Jest X?" (same rule; empty = No)
# -> @{ action = skip|install|same|keep|ask_overwrite|replace ; why = ... }
function Resolve-AijAction([string]$choice, $existing, [string]$pinVersion, $overwrite = $null) {
    $yes = { param($a) return ($a -and ($a.Trim().ToLower() -match '^(y|yes|j|ja)$')) }
    if (-not (& $yes $choice)) { return @{ action = 'skip'; why = 'not chosen (default No)' } }
    if (-not $existing -or @($existing).Count -eq 0) { return @{ action = 'install'; why = 'not installed' } }
    $v = [string](@($existing)[0].version)
    if ($v -and (Compare-ModVersion $v $pinVersion) -eq 0) { return @{ action = 'same'; why = "All-in-Jest $v already installed" } }
    if ($null -eq $overwrite) { return @{ action = 'ask_overwrite'; why = "All-in-Jest $v is installed" } }
    if (& $yes $overwrite) { return @{ action = 'replace'; why = "replace $v (backed up)" } }
    return @{ action = 'keep'; why = "kept your All-in-Jest $v" }
}

# Download (or take $localZip, test hook), check the pinned sha256, extract to Mods\<folder>.
# Returns the installed folder; throws on a hash mismatch (nothing is written then).
function Install-AijPin($pin, [string]$modsRoot, [string]$tmpDir, [string]$localZip = '') {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $zip = Join-Path $tmpDir 'all-in-jest.zip'
    if ($localZip) { Copy-Item -LiteralPath $localZip -Destination $zip -Force }
    else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri ([string]$pin.url) -OutFile $zip -UseBasicParsing
    }
    $h = Get-FileSha256 $zip
    if ($h -ne ([string]$pin.sha256).ToLower()) { Remove-Item -LiteralPath $zip -Force; throw "All-in-Jest download does not match the pinned sha256 (got $h)" }
    $x = Join-Path $tmpDir 'aij_x'
    if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $x -Force
    $inner = Get-ChildItem -LiteralPath $x -Directory | Select-Object -First 1
    $src = if ($inner -and -not (Test-Path -LiteralPath (Join-Path $x 'metadata.json'))) { $inner.FullName } else { $x }
    $dest = Join-Path $modsRoot ([string]$pin.folder)
    Move-Item -LiteralPath $src -Destination $dest -Force
    Remove-Item -LiteralPath $x -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    return $dest
}
