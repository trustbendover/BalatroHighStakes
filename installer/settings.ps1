# Balatro High Stakes - .env settings helper for the installer (Windows PowerShell 5.1+). GPL-3.0.
# Since 0.6.8 the mod plays over Steam peer-to-peer ONLY (no server / address / playit / Tailscale).
# Convert-EnvToSteam turns an existing .env into a Steam one and keeps every other setting.

$script:SteamOnlyNote = '# old setting (Balatro High Stakes is Steam-only since 0.6.8): '

function New-SteamEnv {
    return "# Written by the Balatro High Stakes installer`r`n# Steam peer-to-peer only: the host's Balatro is the server, friends join with the lobby code`r`nmode=steam`r`n"
}

# Returns @{ text = <new .env text>; changed = $true/$false; old = '<what it was, in plain words>' }
# - last mode= line is steam          -> unchanged (byte-identical)
# - other mode, or no mode line (the old default was a TCP server) -> mode/server_url/server_port lines
#   are commented out, mode=steam is added, everything else stays as it was
function Convert-EnvToSteam([string]$text) {
    if ($null -eq $text -or $text.Trim() -eq '') { return @{ text = (New-SteamEnv); changed = $true; old = 'empty settings file' } }
    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"
    $mode = $null; $url = $null; $port = $null
    foreach ($l in $lines) {
        if ($l -match '^\s*mode\s*=\s*(.*?)\s*$') { $mode = $Matches[1] }
        elseif ($l -match '^\s*server_url\s*=\s*(.*?)\s*$') { $url = $Matches[1] }
        elseif ($l -match '^\s*server_port\s*=\s*(.*?)\s*$') { $port = $Matches[1] }
    }
    if ($mode -and $mode.ToLower() -eq 'steam') { return @{ text = $text; changed = $false; old = 'Steam' } }
    $old = if ($mode) { "mode=$mode" } else { 'server mode' }
    if ($url) { $old += " (server $url$(if ($port) { ":$port" }))" }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -match '^\s*(mode|server_url|server_port)\s*=') { $out.Add($script:SteamOnlyNote + $l.Trim()) } else { $out.Add($l) }
    }
    # drop trailing empty lines, then add the Steam line
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    $out.Add('mode=steam')
    return @{ text = (($out -join $nl) + $nl); changed = $true; old = $old }
}
