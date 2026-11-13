-- luajit tests/test_versus_formats.lua (run from mod/): 0.6.8 grouped Gamemodes menu + Versus 2v2/3v3/4v4
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { UTILS = {}, UI = {}, LOBBY = { config = {} } }
G = { UIDEF = {}, FUNCS = {}, UIT = {}, C = {} }
localize = function(k) return k end
MP.load_mp_file = function(p) return dofile(p) end
dofile("lib/string_utils.lua")
dofile("lib/modes.lua")
local T = dofile("networking/teams_rules.lua")
-- rules: a fixed format needs exactly 2 x format players, no fallback to another split
for f = 2, 4 do
	local size, count = T.plan(2 * f, { teams_format = f, teams_size = 2 })
	ok(size == f and count == 2, f .. "v" .. f .. " with " .. 2 * f .. " players: two teams of " .. f)
	for _, n in ipairs({ 4, 6, 8 }) do
		if n ~= 2 * f then ok(T.plan(n, { teams_format = f }) == nil, f .. "v" .. f .. " refuses " .. n .. " players") end
	end
end
ok(T.plan(8, { teams_format = 0, teams_size = 2 }) == 2, "format 0 = free Teams (2v2v2v2 still possible)")
local s5, c5 = T.plan(5, {})
ok(s5 == 3 and c5 == 2 and T.matchup(5, {}) == "3v2", "5 players are 3v2")
local s7, c7 = T.plan(7, {})
ok(s7 == 4 and c7 == 2 and T.matchup(7, {}) == "4v3", "7 players are 4v3")
ok(T.plan(3, {}) == nil and T.plan(9, {}) == nil, "3 and 9 stay outside Teams")
ok(T.plan(5, { teams_format = 2 }) == nil and T.plan(7, { teams_format = 4 }) == nil, "locked 2v2/4v4 refuse an odd count")
ok(T.plan(4, {}) == 2 and T.plan(6, { teams_size = 3 }) == 3 and T.plan(8, { teams_size = 4 }) == 4, "even 4/6/8 stay even")
local five = T.assign({ "p1", "p2", "p3", "p4", "p5" }, {})
ok(five.p1 == "A" and five.p2 == "A" and five.p3 == "A" and five.p4 == "B" and five.p5 == "B", "first three seats are the larger side")
local seven = T.assign({ "p1", "p2", "p3", "p4", "p5", "p6", "p7" }, { teams_order = "7,6,5,4,3,2,1" })
ok(seven.p1 == "B" and seven.p4 == "A" and seven.p7 == "A", "host order puts the larger side first")
local M = MP.MODES
ok(M.start_problem(5, "gamemode_mp_teams", {}) == nil, "client: 5 starts")
ok(M.start_problem(7, "gamemode_mp_teams", {}) == nil, "client: 7 starts")
ok(M.start_problem(3, "gamemode_mp_teams", {}) ~= nil, "client: 3 does not start")
ok(M.start_problem(4, "gamemode_mp_teams", {}) == nil and M.start_problem(6, "gamemode_mp_teams", { teams_size = 3 }) == nil and M.start_problem(8, "gamemode_mp_teams", { teams_size = 4 }) == nil, "client: even 4/6/8 still start")
ok(M.start_problem(6, "gamemode_mp_teams", { teams_format = 3 }) == nil, "client: 3v3 starts with 6")
ok(M.start_problem(4, "gamemode_mp_teams", { teams_format = 3 }) ~= nil, "client: 3v3 blocks 4")
ok(M.start_problem(5, "gamemode_mp_teams", { teams_format = 2 }) ~= nil and M.start_problem(4, "gamemode_mp_teams", { teams_format = 2 }) == nil, "client: 2v2 stays exactly 4")
ok(M.start_problem(7, "gamemode_mp_teams", { teams_format = 4 }) ~= nil and M.start_problem(8, "gamemode_mp_teams", { teams_format = 4 }) == nil, "client: 4v4 stays exactly 8")
ok(M.display_name("gamemode_mp_teams", { teams_format = 4 }) == "4v4", "lobby name 4v4")
ok(M.players_label("teams", 2):find("4"), "2v2 card says 4 players")
-- server mirrors it
local src = io.open("networking/p2p_server.lua"):read("*a")
ok(src:find("teams_format", 1, true), "server start_error knows the format")
-- menu: groups and entries
dofile("ui/main_menu/play_button/gamemode_selection.lua")
local g = MP.UI.gamemode_menu_groups()
ok(g[1].name == "k_versus" and g[2].name == "k_ffa" and g[3].name == "k_challenge", "Versus first, then Free-for-all, Challenge")
local ids = {}
for _, grp in ipairs(g) do for _, b in ipairs(grp.buttons) do ids[#ids + 1] = b.button_id:match("(.+)_%w+_button") end end
ok(table.concat(ids, ",") == "duel,teams2,teams3,teams4,teams,attrition,showdown,koth,deathmatch,gambel_time,survival", "entries in order, Teams can be 3v2 or 4v3")
MP.UI.select_gamemode_entry("teams3")
ok(MP.LOBBY.config.gamemode == "gamemode_mp_teams" and MP.LOBBY.config.teams_format == 3 and MP.LOBBY.config.teams_size == 3, "3v3 -> teams mode, format 3")
MP.UI.select_gamemode_entry("teams")
ok(MP.LOBBY.config.gamemode == "gamemode_mp_teams" and MP.LOBBY.config.teams_format == 0, "Teams itself is not locked to an even format")
MP.UI.select_gamemode_entry("koth")
ok(MP.LOBBY.config.gamemode == "gamemode_mp_koth" and MP.LOBBY.config.teams_format == 0, "other mode clears the format")
local cb = io.open("ui/main_menu/play_button/play_button_callbacks.lua"):read("*a")
ok(cb:find("gamemode_entry", 1, true) and cb:find("teams_format", 1, true), "start_lobby restores the Versus format after the config reset")
-- localization: every entry has a short line in EN and NL, Versus/Free-for-all stay English in NL
for _, lang in ipairs({ "en-us", "nl" }) do
	local s = io.open("localization/" .. lang .. ".lua"):read("*a")
	for _, e in ipairs(ids) do ok(s:find("k_" .. e .. "_short = ", 1, true), lang .. " has k_" .. e .. "_short") end
	ok(s:find('k_versus = "Duels"', 1, true) and s:find('k_ffa = "Free-for-all"', 1, true), lang .. " header Duels + Free-for-all")
	for _, m in ipairs({ "koth", "teams", "deathmatch" }) do ok(s:find("k_" .. m .. "_rules = ", 1, true), lang .. " full rules for " .. m) end
end
-- dictionary keys with #n# are translated (they used to fall back to English in NL)
localize = function(k) if k == "k_mode_players_range" then return "#1#-#2# spelers" end return k end
ok(M.players_label("koth") == "2-8 spelers", "player count uses the translated dictionary text")
localize = function(k) return ({ k_duel = "1v1", k_duel_sub = "Duels", k_teams_sub = "Duels", k_koth = "King of the Hill" })[k] or k end
ok(M.full_name("gamemode_mp_duel") == "1v1 Duels" and M.full_name("gamemode_mp_teams", { teams_format = 3 }) == "3v3 Duels", "Versus names: 1v1 Duels / 3v3 Duels")
ok(not io.open("ui/main_menu/play_button/gamemode_selection.lua"):read("*a"):find("sublabel =", 1, true), "no subtitles under the entries")
ok(M.display_name("gamemode_mp_duel") == "1v1" and M.subtitle("gamemode_mp_koth") == nil, "label 1v1, no subtitle outside Versus")
for _, lang in ipairs({ "en-us", "nl" }) do local s2 = io.open("localization/" .. lang .. ".lua"):read("*a")
	ok(s2:find('k_duel = "1v1"', 1, true) and s2:find("k_teams_sub = ", 1, true) and s2:find("k_duel_sub = ", 1, true), lang .. " Versus labels + subtitles") end
ok(io.open("ui/lobby/_lobby_options/main_options.lua"):read("*a"):find("header_top = true", 1, true), "category headers sit above their modes")
print("PASS: versus formats")
