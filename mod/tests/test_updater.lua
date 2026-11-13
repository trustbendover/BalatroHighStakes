-- luajit tests/test_updater.lua (run from mod root)
MP = { ENV = {} }
local logs = {}
function sendInfoMessage(m) logs[#logs + 1] = m end
SMODS = { Mods = { Multiplayer = { version = "0.6.6~3P", path = "C:/Users/x/AppData/Roaming/Balatro/Mods/BalatroMultiplayer3P/" } } }
local now = 0
love = { timer = { getTime = function() return now end }, system = { getOS = function() return "Windows" end, openURL = function(u) love.opened = u end } }
local events = {}
G = { E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end }, FUNCS = {} }
function Event(t) return t end
-- fake SMODS.https
local pending = {}
package.preload["SMODS.https"] = function()
	return { asyncRequest = function(url, opts, cb) pending[#pending + 1] = { url = url, cb = cb, opts = opts } end }
end
local U = dofile("lib/updater.lua")
local function ok(c, m) assert(c, m); print("ok: " .. m) end

ok(U.is_newer("v0.6.7", "0.6.6~3P") and not U.is_newer("v0.6.6", "0.6.6~3P") and not U.is_newer("0.6.5", "0.6.6~3P"), "version compare")
ok(U.is_newer("v0.6.8", "0.6.7~3P") and not U.is_newer("v0.6.7", "0.6.8") and not U.is_newer("0.6.7~3P", "0.6.8") and not U.is_newer("v0.6.8", "0.6.8"), "0.6.8 without ~3P: 0.6.7~3P is older, same version is not an update")
ok(U.is_newer("v0.7", "0.6.9~3P") and U.is_newer("0.6.10", "0.6.9") and not U.is_newer("garbage", "0.6.6"), "version compare edge cases")
ok(U.is_newer("v0.6.9", "0.6.8.2") and not U.is_newer("0.6.8.2", "v0.6.9") and not U.is_newer("v0.6.9", "0.6.9"), "0.6.9 is newer than 0.6.8.2 and not newer than itself")
ok(U.is_newer("v0.6.9.1", "0.6.9") and U.is_newer("v0.6.9.1", "0.6.8.2"), "0.6.9.1 is newer than 0.6.9 and 0.6.8.2")
ok(U.is_newer("v0.7.0", "0.6.9.1") and not U.is_newer("0.6.9.1", "v0.7.0") and not U.is_newer("v0.7.0", "0.7.0"), "0.7.0 is newer than 0.6.9.1 and not newer than itself")
ok(U.parse_release('{"tag_name":"v0.6.7","draft":false,"prerelease":false,"assets":[{"name":"BalatroMultiplayer3P-v0.6.7-Installer.zip"}]}') == "v0.6.7", "parse release")
ok(U.parse_release('{"tag_name":"v0.6.7","assets":[]}') == nil, "release without installer ignored")
ok(U.parse_release('{"message":"Not Found"}') == nil and U.parse_release(nil) == nil, "404 / nil body")
ok(U.parse_version_json('{ "version": "0.6.7~3P", "tag": "v0.6.7" }') == "v0.6.7", "parse version.json")
ok(U.updater_path() == "C:\\Users\\x\\AppData\\Roaming\\Balatro\\Mods\\BalatroMultiplayer3P\\updater\\update.ps1", "updater path")

-- newer release found -> available
U.check()
ok(U.state == "checking" and pending[1].url == U.API_URL, "check uses GitHub API")
U.check(); ok(#pending == 1, "only one check per session")
pending[1].cb(200, '{"tag_name":"v0.6.7","assets":[{"name":"BalatroMultiplayer3P-v0.6.7-Installer.zip"}]}')
ok(U.state == "available" and U.latest == "0.6.7" and U.button_label() == "Update available: v0.6.7", "update available")

-- 0.6.8 repo rename: new name first, old name as fallback (GitHub redirects too)
ok(U.REPOS[1] == "trustbendover/BalatroHighStakes" and U.REPOS[2] == "trustbendover/BalatroMultiplayer3P" and #U.REPOS == 2, "repo names: new first, old fallback")
ok(U.API_URL == "https://api.github.com/repos/trustbendover/BalatroHighStakes/releases/latest"
	and U.API_URLS[2] == "https://api.github.com/repos/trustbendover/BalatroMultiplayer3P/releases/latest", "API urls for both names")
ok(U.RELEASES_URL == "https://github.com/trustbendover/BalatroHighStakes/releases/latest", "releases page uses the new name")
U.state = "idle"; pending = {}
U.check(); pending[1].cb(404, '{"message":"Not Found"}')
ok(pending[2] and pending[2].url == U.API_URLS[2], "new name 404 -> old name")
pending[2].cb(200, '{"tag_name":"v0.6.8","assets":[{"name":"BalatroMultiplayer3P-v0.6.8-Installer.zip"}]}')
ok(U.state == "available" and U.latest == "0.6.8", "update found under the old name")

-- API fails for both names -> raw version.json (new, then old); up to date
U.state = "idle"; pending = {}
U.check(); pending[1].cb(403, "rate limited"); pending[2].cb(403, "rate limited")
ok(pending[3] and pending[3].url == U.RAW_URL, "falls back to version.json")
pending[3].cb(404, nil)
ok(pending[4] and pending[4].url == U.RAW_URLS[2], "version.json: new name 404 -> old name")
pending[4].cb(200, '{"version":"0.6.6~3P","tag":"v0.6.6"}')
ok(U.state == "none" and U.button_label() == nil, "up to date -> no button")

-- offline: everything fails -> silent
U.state = "idle"; pending = {}
U.check(); pending[1].cb(nil, nil); pending[2].cb(nil, nil); pending[3].cb(0, nil); pending[4].cb(0, nil)
ok(U.state == "offline" and #pending == 4, "offline is silent")

-- timeout: watchdog fires, late answer ignored
U.state = "idle"; pending = {}; events = {}
U.check()
for _ = 1, 2 do local ev = events; events = {}; for _, e in ipairs(ev) do e.func() end end
ok(pending[3] and pending[3].url == U.RAW_URL, "timeout falls through to version.json")
now = 100; pending[1].cb(200, '{"tag_name":"v9.9.9","assets":[{"name":"x-Installer.zip"}]}')
ok(U.state ~= "available", "late answer after timeout ignored")

-- request throwing -> no crash
U.state = "idle"
package.loaded["SMODS.https"] = { asyncRequest = function() error("boom") end }
U.check(); ok(U.state == "offline", "throwing backend handled")
-- no backend
U.state = "idle"; package.loaded["SMODS.https"] = nil; package.preload["SMODS.https"] = nil
U.check(); ok(U.state == "no_https" and U.button_label() == "Check for updates", "no https -> PowerShell updater button")
-- opt-out
U.state = "idle"; MP.ENV.update_check = "false"; U.check(); ok(U.state == "none", ".env update_check=false")
U.state = "idle"; MP.ENV.update_check = false; U.check(); ok(U.state == "none", ".env update_check=false as parsed by core.lua (boolean false)")
U.state = "idle"; MP.ENV.update_check = true; ok(not U.env_off("update_check"), "update_check=true keeps the check on")
MP.ENV.update_check = false
-- start updater when script missing -> opens releases page, never crashes
U.start_updater(); ok(U.state == "started" and love.opened == U.RELEASES_URL, "missing updater -> releases page")
print("PASS test_updater")
