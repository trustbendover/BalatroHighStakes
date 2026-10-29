-- luajit tests/test_dev_autoplay.lua (run from mod/): DEV-ONLY bot decisions + the release gate.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
_G.MP = {}
local A = dofile("dev/autoplay.lua")
local function C(r, s, id) return { rank = r, suit = s, ref = id } end
local function set(t) local o = {} for _, v in ipairs(t) do o[v] = true end return o end
local p = A.pick_cards({ C(2, "H", 1), C(5, "H", 2), C(9, "H", 3), C(11, "H", 4), C(13, "H", 5), C(13, "S", 6), C(3, "D", 7) })
ok(#p == 5 and not set(p)[6] and not set(p)[7], "five of a suit -> flush")
p = A.pick_cards({ C(4, "H", 1), C(4, "S", 2), C(9, "D", 3), C(9, "C", 4), C(14, "H", 5), C(2, "S", 6) })
ok(#p == 4 and set(p)[1] and set(p)[3], "two pairs")
p = A.pick_cards({ C(7, "H", 1), C(7, "S", 2), C(7, "D", 3), C(14, "C", 4) })
ok(#p == 3 and not set(p)[4], "three of a kind, no kicker")
p = A.pick_cards({ C(2, "H", 1), C(5, "S", 2), C(9, "D", 3), C(11, "C", 4), C(14, "H", 5), C(13, "S", 6), C(3, "D", 7) })
ok(#p == 5 and set(p)[5] and set(p)[6] and not set(p)[1], "nothing -> five highest")

local function S(t)
	local s = { locked = false, button_present = {}, stage = "run", players = 2, want_players = 2, ready_allowed = true, highlighted = 0, hand_size = 8 }
	for k, v in pairs(t) do s[k] = v end
	return s
end
ok(A.decide(S({ stage = "lobby", is_host = false, lobby_ready = false, button_present = { lobby_ready_up = true } })) == "lobby_ready_up", "guest: Ready in the lobby")
ok(A.decide(S({ stage = "lobby", is_host = false, lobby_ready = false, ready_allowed = false, button_present = { lobby_ready_up = true } })) == nil, "guest: Ready waits for the scenario delay")
ok(A.decide(S({ stage = "lobby", is_host = true, can_start = true, players = 3, want_players = 3, button_present = { lobby_start_game = true } })) == "lobby_start_game", "host: Start when everyone is in and ready")
ok(A.decide(S({ stage = "lobby", is_host = true, can_start = false, players = 3, want_players = 3, button_present = { lobby_start_game = true } })) == nil, "host: no Start while someone is not ready")
ok(A.decide(S({ stage = "lobby", is_host = true, can_start = true, players = 2, want_players = 3, button_present = { lobby_start_game = true } })) == nil, "host: waits for the expected player count")
ok(A.decide(S({ state = "BLIND_SELECT", button_present = { mp_toggle_ready = true, select_blind = true } })) == "mp_toggle_ready", "PvP blind: press Ready")
ok(A.decide(S({ state = "BLIND_SELECT", blind_ready = true, button_present = { mp_toggle_ready = true } })) == nil, "PvP blind: already ready -> wait")
ok(A.decide(S({ state = "BLIND_SELECT", button_present = { select_blind = true } })) == "select_blind", "normal blind: select")
ok(A.decide(S({ state = "SELECTING_HAND" })) == "@pick" and A.decide(S({ state = "SELECTING_HAND", highlighted = 3, button_present = { play_cards_from_highlighted = true } })) == "play_cards_from_highlighted", "hand: pick, then play")
ok(A.decide(S({ state = "ROUND_EVAL", button_present = { cash_out = true } })) == "cash_out", "cash out")
ok(A.decide(S({ state = "SHOP" })) == "@buy" and A.decide(S({ state = "SHOP", shop_bought = true, button_present = { toggle_shop = true } })) == "toggle_shop", "shop: try one buy, then next round")
ok(A.decide(S({ state = "SHOP", button_present = { skip_booster = true } })) == "skip_booster", "booster pack: skip")
ok(A.decide(S({ button_present = { mp_return_to_lobby = true } })) == "mp_return_to_lobby", "match end: back to the lobby")
ok(A.decide(S({ locked = true, state = "SELECTING_HAND" })) == nil, "controller locked: wait")

-- release gate: core.lua only loads dev code with BOTH the marker file and the env var
local core = io.open("core.lua"):read("*a")
ok(core:find('os.getenv("HS_DEV_LOCAL") == "1" and NFS.getInfo(MP.path .. "/dev/DEV_BUILD")', 1, true), "core.lua: dev mode needs HS_DEV_LOCAL=1 AND dev/DEV_BUILD")
ok(select(2, core:gsub("dev/dev_local.lua", "")) == 1 and core:find("if MP.DEV and MP.DEV.new_backend then", 1, true), "core.lua: one guarded load; Steam backend otherwise")
for _, f in ipairs({ "dev/dev_local.lua", "dev/autoplay.lua", "dev/scenarios.lua", "dev/capture.lua", "dev/file_backend.lua" }) do
	ok(io.open(f):read("*a"):find("DEV ONLY", 1, true), f .. " is marked DEV ONLY")
end
local C2 = dofile("dev/capture.lua")
ok(C2.file_name("dev3", 7, "pvp ante/2") == "dev3_007_pvp_ante_2.png", "screenshot names are safe file names")
-- match over: never play on, screenshot the stats once, then back to the lobby
ok(A.over_decide({ over = false }) == "play", "running match: play")
ok(A.over_decide({ over = true, stats_open = false, over_for = 5 }) == "idle", "run over, no stats yet: idle (no plays)")
ok(A.over_decide({ over = true, stats_open = true, stats_open_for = 3, over_for = 6 }) == "shot", "stats screen up: screenshot")
ok(A.over_decide({ over = true, stats_open = true, stats_open_for = 3, stats_shot = true, match_done = true, over_for = 25 }) == "lobby", "then back to the lobby")
ok(A.over_decide({ over = true, over_for = 99, match_done = false }) == "idle", "eliminated mid-match: stays (spectates) until the match is decided")
print("PASS: dev autoplay")
