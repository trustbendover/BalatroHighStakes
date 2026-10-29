-- Balatro High Stakes (fork of Balatro Multiplayer): non-blocking update check + "Update available" button.
-- GPL-3.0. Never blocks the game, never crashes: every step is pcall'd and silent when offline.
-- Disable with .env: update_check=false
MP.UPDATER = MP.UPDATER or {}
local U = MP.UPDATER

-- 0.6.8: the repo is renamed to BalatroHighStakes with 0.6.8. Try the new name first, then the old one
-- (GitHub also redirects the old name, but this keeps working before the rename and if a redirect fails).
local BRAND = (MP and MP.BRAND) or {}
U.REPOS = {}
for _, r in ipairs({ BRAND.repo or "trustbendover/BalatroHighStakes", BRAND.repo_old or "trustbendover/BalatroMultiplayer3P" }) do
	local dup = false
	for _, x in ipairs(U.REPOS) do if x == r then dup = true end end
	if not dup then U.REPOS[#U.REPOS + 1] = r end
end
U.REPO = U.REPOS[1]
local function urls(fmt)
	local t = {}
	for i, r in ipairs(U.REPOS) do t[i] = fmt:format(r) end
	return t
end
U.API_URLS = urls("https://api.github.com/repos/%s/releases/latest")
U.RAW_URLS = urls("https://raw.githubusercontent.com/%s/main/version.json")
-- 0.6.8: tested versions (compat.json) from the latest release; raw main as fallback
U.COMPAT_RAW_URLS = urls("https://raw.githubusercontent.com/%s/main/mod/compat.json")
U.API_URL, U.RAW_URL, U.COMPAT_RAW_URL = U.API_URLS[1], U.RAW_URLS[1], U.COMPAT_RAW_URLS[1]
U.RELEASES_URL = "https://github.com/" .. U.REPO .. "/releases/latest"
U.TIMEOUT = 15
U.state = U.state or "idle" -- idle | checking | none | available | offline | no_https | started

--- "0.6.6~3P", "v0.6.6", "0.6.6-MULTIPLAYER3P" -> { 0, 6, 6 }
function U.parse_version(v)
	if type(v) ~= "string" then return nil end
	local core = v:gsub("^%s*[vV]", ""):match("^[%d%.]+")
	if not core then return nil end
	local t = {}
	for n in core:gmatch("%d+") do t[#t + 1] = tonumber(n) end
	return #t > 0 and t or nil
end

--- true when version a is newer than b
function U.is_newer(a, b)
	local x, y = U.parse_version(a), U.parse_version(b)
	if not x or not y then return false end
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then return p > q end
	end
	return false
end

--- GitHub releases/latest JSON -> tag (only if it has an Installer zip asset), or nil
function U.parse_release(body)
	if type(body) ~= "string" then return nil end
	local tag = body:match('"tag_name"%s*:%s*"([^"]+)"')
	if not tag then return nil end
	if body:find('"draft"%s*:%s*true') or body:find('"prerelease"%s*:%s*true') then return nil end
	if not body:find('Installer%.zip"') then return nil end
	return tag
end

--- GitHub releases/latest JSON -> download URL of its compat.json asset, or nil
function U.parse_compat_asset(body)
	if type(body) ~= "string" then return nil end
	return body:match('"browser_download_url"%s*:%s*"(https://[^"]-/compat%.json)"')
end

--- version.json in the repo: { "version": "0.6.6~3P", "tag": "v0.6.6" }
function U.parse_version_json(body)
	if type(body) ~= "string" then return nil end
	return body:match('"tag"%s*:%s*"([^"]+)"') or body:match('"version"%s*:%s*"([^"]+)"')
end

function U.current_version()
	local ok, v = pcall(function() return SMODS.Mods["Multiplayer"].version end)
	return ok and v or nil
end

function U.mod_dir()
	local ok, p = pcall(function() return SMODS.Mods["Multiplayer"].path end)
	return ok and p or (MP and MP.path)
end

local function log(m) pcall(sendInfoMessage, m, "MULTIPLAYER-UPDATE") end

local function get_https()
	local ok, h = pcall(require, "SMODS.https")
	if ok and type(h) == "table" and type(h.asyncRequest) == "function" then return h end
	return nil
end

local function finish(tag)
	if tag and U.is_newer(tag, U.current_version()) then
		U.latest = tag:gsub("^[vV]", "")
		U.state = "available"
		log("Update available: " .. tag .. " (installed " .. tostring(U.current_version()) .. ")")
	else
		U.state = "none"
		log("Up to date (" .. tostring(U.current_version()) .. ", latest " .. tostring(tag) .. ")")
	end
	U.refresh_button()
end

local function request(h, url, cb)
	local deadline = love.timer.getTime() + U.TIMEOUT
	local done = false
	local ok, err = pcall(h.asyncRequest, url, { headers = { ["User-Agent"] = "BalatroHighStakes", ["Accept"] = "application/vnd.github+json" } },
		function(code, body)
			if done then return end
			done = true
			if love.timer.getTime() > deadline then return cb(nil) end
			local ok2, e2 = pcall(cb, code == 200 and body or nil)
			if not ok2 then log("update callback error: " .. tostring(e2)) end
		end)
	if not ok then log("update request failed: " .. tostring(err)); done = true; return cb(nil) end
	-- timeout watchdog (REAL timer, works while paused)
	pcall(function()
		G.E_MANAGER:add_event(Event({ trigger = "after", delay = U.TIMEOUT, blocking = false, blockable = false, no_delete = true, timer = "REAL",
			func = function() if not done then done = true; log("update check timed out"); pcall(cb, nil) end return true end }))
	end)
end

--- .env switch turned off? core.lua's .env reader turns "false" into the boolean false, so accept
--- false, "false" and "0" (0.6.8 fix: update_check=false was ignored before).
function U.env_off(key)
	local v = MP.ENV and MP.ENV[key]
	return v == false or v == "false" or v == "0" or v == 0
end

--- 0.6.8: fetch the newest compat.json (release asset, else the copy on main) once per session and
--- hand it to the compat guard, which validates, merges and caches it. Small, async, fail-silent.
function U.fetch_compat(h, release_body)
	if U.compat_state or not (MP.COMPAT_GUARD and MP.COMPAT_GUARD.apply_remote) then return end
	if U.env_off("compat_check") then return end
	U.compat_state = "fetching"
	local asset = U.parse_compat_asset(release_body)
	local list = asset and { asset } or U.COMPAT_RAW_URLS
	U.request_first(h, list, function(b) return b end, function(body)
		if not body then U.compat_state = "failed"; return end
		local ok, applied = pcall(MP.COMPAT_GUARD.apply_remote, body)
		U.compat_state = (body and ok and applied) and "done" or "failed"
		log("compat.json from the latest release: " .. U.compat_state)
	end)
end

--- Try the urls in order; the first answer that `accept(body)` turns into a value wins.
--- cb(value, body) or cb(nil) when every url failed.
function U.request_first(h, list, accept, cb, i)
	i = i or 1
	if not list[i] then return cb(nil) end
	request(h, list[i], function(body)
		local v = body and accept(body)
		if v then return cb(v, body) end
		U.request_first(h, list, accept, cb, i + 1)
	end)
end

--- Start the check once per session. Safe to call many times.
function U.check()
	if U.state ~= "idle" then return end
	if U.env_off("update_check") then U.state = "none"; return end
	local h = get_https()
	if not h then
		U.state = "no_https"; log("no https backend; offering the PowerShell updater instead"); U.refresh_button(); return
	end
	U.state = "checking"
	U.request_first(h, U.API_URLS, U.parse_release, function(tag, body)
		pcall(U.fetch_compat, h, body)
		if tag then return finish(tag) end
		U.request_first(h, U.RAW_URLS, U.parse_version_json, function(tag2)
			if tag2 then return finish(tag2) end
			U.state = "offline"; log("update check: no answer (offline?)")
		end)
	end)
end

--- Windows path of the updater script inside the installed mod folder
function U.updater_path()
	local dir = U.mod_dir()
	if not dir then return nil end
	return (dir:gsub("[/\\]+$", "") .. "/updater/update.ps1"):gsub("/", "\\")
end

function U.start_updater()
	local ok, err = pcall(function()
		local ps1 = U.updater_path()
		if not ps1 or love.system.getOS() ~= "Windows" then
			love.system.openURL(U.RELEASES_URL); U.state = "started"; return
		end
		local f = io.open(ps1, "r")
		if not f then love.system.openURL(U.RELEASES_URL); U.state = "started"; return end
		f:close()
		local cmd = ('start "MP3P updater" powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -FromGame'):format(ps1)
		log("starting updater: " .. cmd)
		os.execute(cmd)
		U.state = "started"
	end)
	if not ok then log("could not start updater: " .. tostring(err)); pcall(love.system.openURL, U.RELEASES_URL); U.state = "started" end
	U.refresh_button()
end

function U.button_label()
	if U.state == "available" then return "Update available: v" .. tostring(U.latest) end
	if U.state == "no_https" then return "Check for updates" end
	if U.state == "started" then return "Updater started: close & restart Balatro" end
	return nil
end

function U.remove_button()
	if G and G.MP3P_UPDATE_UI then pcall(function() G.MP3P_UPDATE_UI:remove() end); G.MP3P_UPDATE_UI = nil end
end

function U.refresh_button()
	U.remove_button()
	local label = U.button_label()
	if not label or not G or not G.STAGES or G.STAGE ~= G.STAGES.MAIN_MENU or not G.ROOM_ATTACH then return end
	pcall(function()
		G.MP3P_UPDATE_UI = UIBox({
			definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
				UIBox_button({ label = { label }, colour = U.state == "started" and G.C.GREEN or G.C.ORANGE,
					button = U.state == "started" and "mp3p_update_noop" or "mp3p_start_update", minw = 4.2, minh = 0.6, scale = 0.4 }),
			} },
			config = { align = "tli", bond = "Weak", offset = { x = 0.2, y = 0.2 }, major = G.ROOM_ATTACH },
		})
	end)
end

if G and G.FUNCS then
	G.FUNCS.mp3p_start_update = function() U.start_updater() end
	G.FUNCS.mp3p_update_noop = function() end
end

--- called from Game:main_menu
function U.on_main_menu()
	pcall(function()
		G.E_MANAGER:add_event(Event({ trigger = "after", delay = 2, blocking = false, blockable = false, no_delete = true, timer = "REAL",
			func = function() pcall(U.check); pcall(U.refresh_button); return true end }))
	end)
end

return U
