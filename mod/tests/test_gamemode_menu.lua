-- luajit tests/test_gamemode_menu.lua (run from mod/)
-- Every registered gamemode has a button on the Gamemodes menu.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { UTILS = {}, UI = {}, LOBBY = { config = {} } }
G = { UIDEF = {}, FUNCS = {}, UIT = {}, C = {} }
localize = function(k) return k end
MP.load_mp_file = function(p) return dofile(p) end
dofile("lib/string_utils.lua")
dofile("lib/modes.lua")
dofile("ui/main_menu/play_button/gamemode_selection.lua")

local reached, order, ffa = {}, {}, nil
for _, g in ipairs(MP.UI.GAMEMODE_GROUPS) do
	if g.name == "k_ffa" then ffa = g.entries end
	for _, e in ipairs(g.entries) do
		local mode = MP.UI.gamemode_entry(e)
		reached[mode] = true
		order[#order + 1] = e
	end
end
local keys = {}
for key in pairs(MP.MODES.LIMITS) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do
	ok(reached[key], key .. " is reachable from the Gamemodes menu")
end
local files = io.popen("ls gamemodes"):read("*a")
for name in files:gmatch("([%w_]+)%.lua") do
	if name:sub(1, 1) ~= "_" then
		local src = io.open("gamemodes/" .. name .. ".lua"):read("*a")
		local key = src:match('key%s*=%s*"([^"]+)"')
		ok(key and reached[key], "gamemodes/" .. name .. ".lua (" .. tostring(key) .. ") is on the menu")
	end
end
ok(ffa and ffa[#ffa - 1] == "gambel_time" and ffa[#ffa] == "heat_rush", "Heat Rush is Free-for-all, after Gambel Time")

MP.UI.select_gamemode_entry("heat_rush")
ok(MP.LOBBY.config.gamemode == "gamemode_mp_heat_rush" and MP.LOBBY.config.teams_format == 0, "choosing Heat Rush sets that mode")
ok(MP.MODES.start_problem(1, "heat_rush") == nil and MP.MODES.start_problem(8, "heat_rush") == nil, "Heat Rush can start with 1 to 8 players")
ok(MP.MODES.start_problem(0, "heat_rush") ~= nil and MP.MODES.start_problem(9, "heat_rush") ~= nil, "Heat Rush refuses 0 and 9")
ok(MP.MODES.default_lives("heat_rush") == 4, "Heat Rush starts with 4 lives")
localize = function(k) if k == "k_heat_rush" then return "Heat Rush" end return k end
ok(MP.MODES.display_name("gamemode_mp_heat_rush") == "Heat Rush", "the lobby and end-of-match name is Heat Rush")

local cb = io.open("ui/main_menu/play_button/play_button_callbacks.lua"):read("*a")
ok(cb:find('gamemode == "gamemode_mp_survival"', 1, true) and cb:find("disable_live_and_timer_hud = false", 1, true), "only Survival hides the lives HUD")
ok(not cb:find("gamemode_mp_heat_rush", 1, true), "Heat Rush keeps the normal lives HUD and the normal timer")

local Browser = dofile("networking/lobby_browser.lua")
for _, key in ipairs(keys) do
	ok(Browser.MODES[key], "the lobby list accepts " .. key)
end
local row = Browser.accept({
	mp3p_discover = "1", mp3p_mod = "hs", mp3p_version = "0.7.8", mp3p_name = "Ada",
	mp3p_mode = "heat_rush", mp3p_players = "1", mp3p_max = "8", mp3p_state = "wait", mp3p_watch = "1",
}, { version = "0.7.8" })
ok(row and row.mode == "heat_rush" and row.mode_key == "k_heat_rush", "a Heat Rush lobby is labeled k_heat_rush")

for _, lang in ipairs({ "en-us", "nl" }) do
	local d = dofile("localization/" .. lang .. ".lua").misc.dictionary
	for _, suffix in ipairs({ "", "_short", "_win", "_rules", "_description" }) do
		local k = "k_heat_rush" .. suffix
		ok(type(d[k]) == "string" and d[k] ~= "", lang .. " has " .. k)
	end
end
local en = dofile("localization/en-us.lua").misc.dictionary
local nl = dofile("localization/nl.lua").misc.dictionary
ok(en.k_heat_rush == "Heat Rush" and nl.k_heat_rush == "Heat Rush", "English and Dutch both name it Heat Rush")

local music = io.open("lib/heat.lua"):read("*a")
ok(music:find('key = "music_heat_rush"', 1, true) and music:find("select_music_track", 1, true), "the Heat Rush track starts and stops with the mode")
ok(music:find("H.KEY", 1, true), "music follows the Heat Rush mode key")

print("PASS: gamemode menu")
