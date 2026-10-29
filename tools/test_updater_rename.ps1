# Balatro High Stakes - updater repo-rename fallback test (Windows PowerShell 5.1, sandbox in TEMP, no network).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_updater_rename.ps1
# Fakes api.github.com / raw.githubusercontent.com with file:// folders and runs update.ps1 -CheckOnly.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:fails = 0; $script:passes = 0
function Ok($c, $m) { if ($c) { $script:passes++; Write-Host "ok: $m" } else { $script:fails++; Write-Host "FAIL: $m" -ForegroundColor Red } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('hs-rename-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
function W($p, $t) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [IO.File]::WriteAllText($p, $t) }
function Rel($tag) { '{ "tag_name": "' + $tag + '", "assets": [ { "name": "BalatroMultiplayer3P-' + $tag + '-Installer.zip", "browser_download_url": "https://example.invalid/' + $tag + '.zip" }, { "name": "SHA256SUMS-' + $tag + '.txt", "browser_download_url": "https://example.invalid/sums" } ] }' }
function Run($extra) {
    $api = 'file:///' + ((Join-Path $root 'api') -replace '\\', '/')
    $raw = 'file:///' + ((Join-Path $root 'raw') -replace '\\', '/')
    $ps1 = Join-Path $root 'mod\updater\update.ps1'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -CheckOnly -CurrentVersion '0.6.7~3P' -ApiBase $api -RawBase $raw @extra 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out }
}
function Reset { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }; W (Join-Path $root 'mod\updater\update.ps1') ([IO.File]::ReadAllText((Join-Path $Repo 'mod\updater\update.ps1'))) }
try {
    $new = 'trustbendover/BalatroHighStakes'; $old = 'trustbendover/BalatroMultiplayer3P'
    # 1. before the rename: only the old repo answers
    Reset; W (Join-Path $root "api\repos\$old\releases\latest") (Rel 'v0.6.8')
    $r = Run @(); Ok ($r.code -eq 10 -and $r.out -match 'Latest:\s+v0\.6\.8' -and $r.out -match [regex]::Escape($new)) 'new name missing -> falls back to the old repo name'
    # 2. after the rename: the new name answers first
    W (Join-Path $root "api\repos\$new\releases\latest") (Rel 'v0.6.9')
    $r = Run @(); Ok ($r.code -eq 10 -and $r.out -match 'Latest:\s+v0\.6\.9') 'new repo name is tried first'
    # 3. API down for both: version.json on main (old name) still works, zip name from the asset prefix
    Reset; W (Join-Path $root "raw\$old\main\version.json") '{ "version": "0.6.8~3P", "tag": "v0.6.8" }'
    $r = Run @(); Ok ($r.code -eq 10 -and $r.out -match 'Latest:\s+v0\.6\.8') 'API down -> version.json from the old name'
    # 4. nothing answers -> error exit, no crash
    Reset; $r = Run @(); Ok ($r.code -eq 1) 'offline -> exit 1'
    # 5. brand.json next to the mod sets the slugs
    Reset; W (Join-Path $root 'mod\brand.cfg') '{ "repo": "someone/NewName", "repo_old": "someone/OldName", "asset_prefix": "BalatroMultiplayer3P" }'
    W (Join-Path $root 'api\repos\someone\OldName\releases\latest') (Rel 'v0.7.0')
    $r = Run @(); Ok ($r.code -eq 10 -and $r.out -match 'Latest:\s+v0\.7\.0' -and $r.out -match 'someone/NewName') 'repo names come from brand.json'
    # 6. -Repo still overrides (old 0.6.6/0.6.7 command lines)
    $r = Run @('-Repo', 'someone/OldName'); Ok ($r.code -eq 10 -and $r.out -notmatch 'someone/NewName') '-Repo override still works'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Host ""
if ($script:fails -gt 0) { Write-Host "$($script:fails) FAILED, $($script:passes) passed" -ForegroundColor Red; exit 1 }
Write-Host "PASS: updater rename ($($script:passes) checks)" -ForegroundColor Green
exit 0
