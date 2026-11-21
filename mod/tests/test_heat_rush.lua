-- Heat Rush rules, Overdrive, rewards, music, and host sync.
-- luajit tests/test_heat_rush.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local H = dofile("networking/heat_rules.lua")

ok(H.gain("small", 2, 90) == 50, "par hands and par time: clear + time, no extra hands")
ok(H.gain("small", 0, 40) == 80, "two hands under par and a fast clear: 25+30+25")
ok(H.gain("boss", 8, 400) == 25, "a slow clear still earns the base and nothing is taken away")
local heat, armed = H.apply(80, 25)
ok(heat == 100 and armed, "reaching 100 arms Overdrive and holds the meter")
heat, armed = H.apply(100, 25)
ok(heat == 100 and armed, "a full meter does not grow past 100")
local left, still = H.spend(true)
ok(left == 0 and still == false, "playing the Overdrive hand empties the meter")
ok(H.boost("100", true) == "150" and H.boost("100", false) == "100", "Overdrive is x1.5, and only on that hand")
ok(H.reward("small", 60) == "reroll", "well under par: a free reroll")
ok(H.reward("small", 80) == "cash", "under par, but not that fast: +$3")
ok(H.reward("small", 200) == nil, "over par: no reward and no penalty")
ok(H.boss_tag("boss", 150) == "tag_charm" and H.boss_tag("boss", 151) == nil and H.boss_tag("big", 10) == nil, "only a boss inside the clock gives a Tag")
local board = H.rank({
	{ id = "b", heat = 40, ante = 5, score = 9 },
	{ id = "a", heat = 40, ante = 6, score = 1 },
	{ id = "c", heat = 90, ante = 2, score = 0 },
})
ok(board[1].id == "c" and board[2].id == "a", "the board sorts by Heat, then ante, then score")
ok(H.music_priority({ mode = "gamemode_mp_heat_rush", stage = "run" }) == 10, "the track plays during a Heat Rush run")
ok(H.music_priority({ mode = "gamemode_mp_heat_rush", watching = true, stage = "menu" }) == 10, "a watcher hears it")
ok(H.music_priority({ mode = "gamemode_mp_heat_rush", stage = "menu" }) == nil, "the menu does not play it")
ok(H.music_priority({ mode = "gamemode_mp_heat_rush", in_lobby = false, stage = "run" }) == nil, "leaving the lobby stops it")
ok(H.music_priority({ mode = "gamemode_mp_attrition", stage = "run" }) == nil, "other modes keep their own music")

local Core = dofile("networking/p2p_server.lua")
ok(Core.start_error("heat_rush", 1) == nil and Core.start_error("heat_rush", 8) == nil and Core.start_error("heat_rush", 9) ~= nil, "solo and 2-8 can start; 9 cannot")
local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local S = Core.new({ now = function() return 1 end, log = function() end })
local ada = client(S, "Ada~1")
S:receive(ada, { action = "createLobby", gameMode = "heat_rush" })
S:receive(ada, { action = "startGame" })
ok(ada.lives == 4, "solo Heat Rush starts with 4 lives")
S:receive(ada, { action = "heatReport", blind = "small", hands = 0, seconds = 50 })
local st = ada.last("heatState")
ok(st and st.heat == 80 and st.reward == "reroll" and st.overdrive == false and st.best == 80, "a fast small blind fills Heat and pays a reroll")
local board = ada.last("heatBoard")
ok(board and board.rows[1].id == ada.id and board.rows[1].total == 80, "the live board carries that Heat")
S:receive(ada, { action = "heatReport", blind = "big", hands = 1, seconds = 40 })
ok(ada.overdrive and ada.heat == 100 and ada.last("heatState").overdrive, "the next clear fills the meter and arms Overdrive")
S:receive(ada, { action = "heatSpend" })
ok(ada.heat == 0 and not ada.overdrive and ada.heatTotal == 160, "the Overdrive hand spends the meter and keeps the total")
S:receive(ada, { action = "heatReport", blind = "boss", hands = 4, seconds = 100 })
ok(ada.last("heatState").tag == "tag_charm", "a boss inside 150s gives a Tag")
S:receive(ada, { action = "heatReport", blind = "boss", hands = 9, seconds = 400 })
ok(ada.last("heatState").tag == nil and ada.last("heatState").reward == nil, "a slow boss has no penalty")
S:receive(ada, { action = "setAnte", ante = 9 })
ok(ada.last("winGame") and ada.last("winGame").reason == "heat", "solo ends after ante 8")

local music = io.open("lib/heat.lua"):read("*a")
ok(music:find('key = "music_heat_rush"', 1, true) and music:find('path = "music_heat_rush.ogg"', 1, true), "the sound is registered for music_heat_rush.ogg")
local credits = io.open("CREDITS.md"):read("*a")
ok(credits:find("Lille Lilienthal", 1, true), "the song credits Lille Lilienthal")
local en = dofile("localization/en-us.lua").misc.dictionary
local nl = dofile("localization/nl.lua").misc.dictionary
ok(en.k_hs_heat_music == "Music: Heat Rush track by Lille Lilienthal", "English credit line")
ok(nl.k_hs_heat_music == "Muziek: Heat Rush track door Lille Lilienthal", "Dutch credit line")

print("PASS: heat rush")
