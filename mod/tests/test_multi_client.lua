-- luajit tests/test_multi_client.lua (run from mod root)
-- Client helpers for 2-8 player lobbies: mode limits, Teams state, compact HUD, focus/nemesis.
MP = { LOBBY = { config = { gamemode = "gamemode_mp_attrition" }, player_count = 8, my_id = "me" }, GAME = { enemy = {} }, UTILS = {} }
function MP.UTILS.string_split(s, sep) local t = {} for x in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = x end return t end
function number_format(n) return tostring(n) end
function sendInfoMessage() end
MP.is_pvp_boss = function() return true end
G = { GAME = { current_round = { hands_played = 1 } }, C = { BLUE = "blue", RED = "red", GREEN = "green", GOLD = "gold", UI = {} } }
dofile("lib/insane_int.lua"); dofile("lib/modes.lua"); dofile("lib/teams.lua"); dofile("lib/three_player.lua")
MP.MODES.TEAMS_RULES = dofile("networking/teams_rules.lua")
local I = MP.INSANE_INT
local n = 0
local function ok(c, m) assert(c, m); n = n + 1 end

-- ===== mode limits =====
local M = MP.MODES
ok(M.key("gamemode_mp_duel") == "duel" and M.key("teams") == "teams", "mode key")
ok(M.start_problem(2, "gamemode_mp_duel") == nil, "duel: 2 players ok")
ok(M.start_problem(3, "gamemode_mp_duel"):find("exactly 2"), "duel: 3 players refused")
ok(M.start_problem(1, "gamemode_mp_duel"):find("exactly 2"), "duel: 1 player refused")
for _, mode in ipairs({ "attrition", "showdown", "koth", "survival" }) do
	ok(M.start_problem(1, mode):find("at least 2"), mode .. ": 1 player refused")
	for p = 2, 8 do ok(M.start_problem(p, mode) == nil, mode .. ": " .. p .. " players ok") end
	ok(M.start_problem(9, mode):find("max 8"), mode .. ": 9 refused")
end
for _, p in ipairs({ 2, 3, 9 }) do ok(M.start_problem(p, "teams", {}) ~= nil, "teams: " .. p .. " refused") end
for _, p in ipairs({ 4, 5, 6, 7, 8 }) do ok(M.start_problem(p, "teams", {}) == nil, "teams: " .. p .. " ok") end
ok(M.start_problem(5, "teams", { teams_format = 2 }) ~= nil and M.start_problem(6, "teams", { teams_format = 3 }) == nil and M.start_problem(7, "teams", { teams_format = 4 }) ~= nil, "locked formats keep their exact counts")
ok(M.default_lives("gamemode_mp_duel") == 4 and M.default_lives("gamemode_mp_koth") == 3 and M.default_lives("attrition") == nil, "default lives")

-- ===== Teams helpers =====
local T = MP.TEAMS
ok(T.next_size(4, 2) == 2 and T.next_size(6, 2) == 3 and T.next_size(6, 3) == 2 and T.next_size(8, 2) == 4 and T.next_size(8, 4) == 2, "team size cycle")
local seq = { 3, 1, 2 }
local k = 0
local sh = T.shuffle(4, function(a, b) k = k + 1; return math.min(b, math.max(a, seq[k] or a)) end)
local seen = {}
for d in sh:gmatch("%d") do seen[d] = true end
ok(seen["1"] and seen["2"] and seen["3"] and seen["4"], "shuffle is a permutation: " .. sh)
ok(not T.is_teammate("b1"), "no teammates outside Teams mode")
MP.LOBBY.config.gamemode = "gamemode_mp_teams"
MP.LOBBY.player_list = { { id = "me", team = "A" }, { id = "b1", team = "B" }, { id = "a2", team = "A" }, { id = "b2", team = "B" } }
ok(T.is_teammate("a2") and not T.is_teammate("b1") and not T.is_teammate("me"), "lobby preview teammates")
ok(T.seat_label({ username = "Bob", team = "B" }) == "[B] Bob", "seat label")
T.on_update({ you = "me", team = "A", teamSize = 2, teams = {
	A = { lives = 3, members = { { id = "me" }, { id = "a2" } } },
	B = { lives = 4, members = { { id = "b1" }, { id = "b2" } } } } })
ok(T.my_team() == "A" and T.team_of("b2") == "B", "teamsUpdate state")
ok(#T.messages({ team = "A", lastLoser = "A" }) == 1 and T.messages({ team = "A", lastLoser = "A" })[1]:find("Your team"), "msg: we lost")
ok(T.messages({ team = "A", lastLoser = "B" })[1]:find("Team B"), "msg: other team lost")
ok(T.messages({ team = "A", lastLoser = "none" })[1]:find("Tie"), "msg: tie")
ok(#T.messages({ team = "A" }) == 0, "msg: snapshot has none")
MP.GAME.score = I.from_string("100")
MP.GAME.enemies = {
	a2 = { id = "a2", username = "Ally", real_score = I.from_string("5000"), lives = 3, hands = 1 },
	b1 = { id = "b1", username = "Bob", real_score = I.from_string("300"), lives = 4, hands = 2 },
	b2 = { id = "b2", username = "Carl", real_score = I.from_string("200"), lives = 4, hands = 2 },
}
local tot = T.totals()
ok(#tot == 2 and I.to_string(tot[1].score) == "5100" and I.to_string(tot[2].score) == "500" and tot[1].mine, "team totals")
ok(MP.THREEP.pick_focus().id == "b1", "focus skips the teammate even with a higher score")
MP.THREEP.refresh_hud()
ok(MP.GAME.enemy.hud_title:find("Team A %(you%) 5100 3L | Team B 500 4L") and MP.GAME.enemy.hud_title:find("+Ally", 1, true), MP.GAME.enemy.hud_title)
ok(MP.THREEP.pick_nemesis(false).id ~= "a2", "nemesis is never a teammate")
MP.GAME.elim_order = { "b2", "a2" }
ok(MP.THREEP.pick_nemesis(true).id == "b2", "won: last eliminated rival (not the teammate)")

-- ===== 7 opponents (8-player FFA): compact HUD =====
MP.LOBBY.config.gamemode = "gamemode_mp_attrition"
MP.GAME.teams = nil; MP.GAME.elim_order = nil
MP.GAME.enemies = {}
for i = 1, 7 do
	MP.GAME.enemies["p" .. i] = { id = "p" .. i, username = "P" .. i, real_score = I.from_string(tostring(i * 100)), lives = 2, hands = 1, eliminated = i == 1 }
end
MP.THREEP.refresh_hud()
ok(MP.GAME.enemy.hud_title == "P7 700 2L | P6 600 2L | P5 500 2L | +3 | 1 out", MP.GAME.enemy.hud_title)
ok(MP.THREEP.pick_focus().id == "p7", "focus = top score of 7")
local line3 = MP.THREEP.hud_line({ { username = "A", score_text = "1", hands = 2, lives = 3 }, { username = "B", score_text = "2", hands = 1, lives = 1, eliminated = true } })
ok(line3 == "A 1 (2h) 3L | B X", "short list keeps the full format: " .. line3)

-- ===== seats 1..8 =====
MP.LOBBY.seats = {}
for i = 1, 8 do MP.LOBBY.seats[i] = { username = "S" .. i, config = { Mods = {} } } end
ok(MP.THREEP.lobby_player("seat8").username == "S8" and MP.THREEP.seat_index("seat6") == 6 and MP.THREEP.seat_index("guest") == 2, "seat lookups")
ok(MP.THREEP.seat_count() == 8, "8 seats")
print("ok: " .. n .. " client checks")
print("PASS test_multi_client")
