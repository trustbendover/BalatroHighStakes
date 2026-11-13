-- Gambel Time: 1 player against The House, 2-8 free-for-all, host-rolled spins.
-- run from mod/: luajit tests/test_gambel_time.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local R = dofile("networking/gambel_rules.lua")
MP = {}
local M = dofile("lib/modes.lua")

local function better(a, b) return a > b end
local function ids(list)
	local t = {}
	for _, id in ipairs(list) do t[id] = true end
	return t
end

for _, n in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8 }) do
	ok(M.start_problem(n, "gambel_time") == nil, "gambel starts with " .. n)
end
ok(M.start_problem(0, "gambel_time") ~= nil and M.start_problem(9, "gambel_time") ~= nil, "gambel refuses 0 and 9")
ok(M.limits("gambel_time").min == 1 and M.limits("gambel_time").max == 8 and M.default_lives("gambel_time") == 3, "1-8 players, 3 lives")
for _, mode in ipairs({ "attrition", "showdown", "koth", "survival", "deathmatch", "duel" }) do
	ok(M.start_problem(1, mode) ~= nil, mode .. " still needs more than 1")
end

ok(R.lives(nil) == 3 and R.lives(1) == 2 and R.lives(3) == 3 and R.lives(9) == 5, "lives stay inside 2-5")
ok(R.ante_target({}) == 6 and R.ante_target({ gambel_ante = 4 }) == 4 and R.ante_target({ gambel_ante = 99 }) == 12, "target ante defaults to 6")
ok(R.blind_phase("Small") == "build" and R.blind_phase("Big") == "drop" and R.blind_phase("Boss") == "final", "small builds, big drops, the boss is the final drop")
ok(R.phase_bonus("drop") == 3 and R.phase_bonus("build") == 0, "the drop pays a small cash bump")
ok(R.prize_plan("edition", { plain_joker = true }).kind == "edition", "an open joker takes a real edition")
ok(R.prize_plan("edition", {}).kind == "cash" and R.prize_plan("edition", {}).amount == 8, "no joker: the edition pays $8")
ok(R.prize_plan("tag").kind == "tag" and R.prize_plan("discard").kind == "discard", "a tag and a discard are real effects")
ok(R.prize_plan("perish", { mortal_joker = true }).kind == "perish", "a non-eternal joker can turn perishable")
ok(R.prize_plan("perish", {}).kind == "tax" and R.prize_plan("perish", {}).amount == 4, "no joker: perish is a $4 tax")
ok(R.prize_plan("cash", { amount = 20 }).amount == 20 and R.prize_plan("tax", { amount = 4 }).amount == 4, "cash and tax keep their amounts")
ok(R.cut(1) == 0 and R.cut(2) == 1 and R.cut(5) == 1 and R.cut(6) == 2 and R.cut(8) == 2, "bottom 1 until 6, then bottom 2")

local function row(id, score, hands) return { id = id, score = score, hands = hands or 1 } end
local three = R.resolve({ row("a", 10), row("b", 30), row("c", 20) }, nil, better)
ok(ids(three.losers).a and #three.losers == 1 and three.lives == 1 and not three.hold, "3 players: the lowest score loses one life")
local tie = R.resolve({ row("a", 10), row("b", 10), row("c", 10) }, nil, better)
ok(#tie.losers == 0 and tie.hold, "a full tie holds: The House holds")
local six = {}
for i = 1, 6 do six[i] = row(tostring(i), i * 10) end
local low = ids(R.resolve(six, nil, better).losers)
ok(low["1"] and low["2"] and not low["3"], "6 players: the bottom two lose")
local eight = {}
for i = 1, 8 do eight[i] = row(tostring(i), i) end
local bottom = ids(R.resolve(eight, nil, better).losers)
ok(bottom["1"] and bottom["2"] and not bottom["3"], "8 players: the bottom two lose")

local rev = R.resolve({ row("a", 1, 0), row("b", 10, 1), row("c", 40, 1) }, "reverse", better)
ok(ids(rev.losers).a and not ids(rev.losers).b, "reverse: a throw with no hand does not win")
local rev2 = R.resolve({ row("a", 1, 1), row("b", 10, 1), row("c", 40, 1) }, "reverse", better)
ok(ids(rev2.losers).c and not ids(rev2.losers).a, "reverse: the lowest real score is safe")
local dbl = R.resolve({ row("a", 1), row("b", 2) }, "double", better)
ok(ids(dbl.losers).a and dbl.lives == 2, "double trouble costs 2 lives")
local solo = R.resolve({ row("a", 1) }, "double", better)
ok(#solo.losers == 0, "solo has no nemesis loser")

local pay = R.payout({
	{ id = "win", score = 20, room = true },
	{ id = "lose", score = 5, give = true },
}, "pot", { "lose" }, better)
ok(pay and pay.to == "win" and pay.cash == 8 and pay.joker, "joker pot moves a card only when there is room and a card to give")
local cash = R.payout({
	{ id = "win", score = 20, room = false },
	{ id = "lose", score = 5, give = false },
}, "pot", { "lose" }, better)
ok(cash and cash.to == "win" and not cash.joker, "a full slot or an empty joker row stays cash")

ok(R.stake(0) == 0 and R.stake(1) == 0 and R.stake("nan") == 0 and R.stake(-4) == 0, "nothing safe to bet at $0 or $1")
ok(R.stake(10) == 5 and R.stake(1000) == 50, "the stake is half, capped")
local broke = R.flip("seed", "p", 1, 0)
ok(broke.ok == false and broke.delta == 0 and broke.money == 0, "a $0 flip does not move money")
for ante = 1, 8 do
	local flip = R.flip("seed", "p", ante, 11)
	ok(flip.ok and flip.money >= 0 and (flip.delta == flip.stake or flip.delta == -flip.stake), "flip " .. ante .. " stays at or above $0")
	local wheel = R.wheel("seed", "p", ante, 3)
	ok(wheel.money >= 0 and wheel.money <= 3 + 20, "wheel " .. ante .. " cannot go negative")
end
local again = R.flip("seed", "p", 3, 11)
local once = R.flip("seed", "p", 3, 11)
ok(again.won == once.won and again.delta == once.delta, "the same seed and ante flip the same way")

local spin = R.table_spin("house", 2)
local found = false
for _, id in ipairs(R.SPINS) do if id == spin then found = true end end
ok(found and R.table_spin("house", 2) == spin, "a table spin is one of the six and it stays put")
local twist = R.twist("house", 1, 1, 1)
ok(twist == "double" or twist == "house" or twist == "allin", "solo chaos is a house twist")
local crowd = R.twist("house", 1, 1, 4)
ok(crowd == "reverse" or crowd == "double" or crowd == "pot" or crowd == "sabotage" or crowd == "allin", "a full table gets a versus twist")

ok(R.music_priority({ mode = "gamemode_mp_gambel_time", stage = "run" }) == 10, "the track plays during a Gambel Time run")
ok(R.music_priority({ mode = "gamemode_mp_gambel_time", watching = true, stage = "menu" }) == 10, "a watcher hears it too")
ok(R.music_priority({ mode = "gamemode_mp_attrition", stage = "run" }) == nil, "other modes keep their own music")
ok(R.music_priority({ mode = "gamemode_mp_gambel_time", stage = "menu" }) == nil, "the menu does not play it")
local music = io.open("lib/gambel.lua"):read("*a")
ok(music:find('key = "music_gambel_time"', 1, true) and music:find('path = "music_gambel_time.ogg"', 1, true) and music:find("sync = false", 1, true), "the sound is registered for assets/sounds/music_gambel_time.ogg")
ok(music:find("NFS.getInfo", 1, true), "a missing ogg is skipped instead of crashing")

-- Host: one player can start, a failed boss can cost 2, the target ante wins, and a second bet is refused.
local Core = dofile("networking/p2p_server.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
assert(Core.GAMBEL and Core.GAMBEL.resolve, "the host loads the gambel rules")
local function server()
	return Core.new({ log = function() end, now = function() return 1000 end })
end
local function player(S, name)
	local p = { msgs = {} }
	p.c = S:connect(function(t) p.msgs[#p.msgs + 1] = t end)
	function p.last(a)
		for i = #p.msgs, 1, -1 do if p.msgs[i].action == a then return p.msgs[i] end end
	end
	S:receive(p.c, { action = "username", username = name, modHash = "t" })
	return p
end

local S = server()
local solo = player(S, "Ada")
S:receive(solo.c, { action = "createLobby", gameMode = "gambel_time" })
S:receive(solo.c, { action = "lobbyOptions", match_settings = 1, starting_lives = 9, gambel_ante = 8 })
S:receive(solo.c, { action = "startGame" })
ok(solo.last("startGame") and solo.c.lives == 5 and solo.c.lobby.isInGame and not solo.last("winGame"), "solo starts at the life cap and the match stays open")
S:receive(solo.c, { action = "gambelBoss", ante = 1 })
solo.c.lobby.gambelTwist = "double"
solo.c.lobby.gambelBossOpen = true
S:receive(solo.c, { action = "failRound" })
ok(solo.c.lives == 3, "a double-trouble boss costs 2 lives against The House")
S:receive(solo.c, { action = "setAnte", ante = 9 })
ok(solo.last("winGame") and solo.last("winGame").reason == "house" and not solo.c.lobby.isInGame, "clearing the target ante beats The House")

S = server()
local host = player(S, "Ann")
S:receive(host.c, { action = "createLobby", gameMode = "attrition" })
S:receive(host.c, { action = "startGame" })
ok(host.last("error") and host.last("error").message:find("2", 1, true), "attrition still refuses a solo start")

S = server()
local ps = {}
ps[1] = player(S, "Ann")
S:receive(ps[1].c, { action = "createLobby", gameMode = "gambel_time" })
local code = ps[1].last("joinedLobby").code
S:receive(ps[1].c, { action = "lobbyOptions", match_settings = 1, starting_lives = 3 })
for i = 2, 3 do
	ps[i] = player(S, "P" .. i)
	S:receive(ps[i].c, { action = "joinLobby", code = code })
	ps[i].c.isReadyLobby = true
end
S:receive(ps[1].c, { action = "startGame" })
ok(ps[1].c.lives == 3 and ps[3].last("startGame"), "three players start")
for _, p in ipairs(ps) do S:receive(p.c, { action = "readyBlind" }) end
ps[1].c.lobby.gambelTwist = "reverse"
local scores = { 50, 10, 30 }
for i, p in ipairs(ps) do S:receive(p.c, { action = "playHand", score = tostring(scores[i]), handsLeft = 0 }) end
ok(ps[1].c.lives == 2 and ps[2].c.lives == 3 and ps[3].c.lives == 3, "reverse stakes: the high score loses, the low score is safe")

S = server()
local bet = player(S, "Bea")
S:receive(bet.c, { action = "createLobby", gameMode = "gambel_time" })
S:receive(bet.c, { action = "startGame" })
S:receive(bet.c, { action = "gambelBet", kind = "double", money = 0, ante = 1 })
ok(bet.last("gambelBetResult").ok == false, "no stake at $0")
S:receive(bet.c, { action = "gambelBet", kind = "double", money = 20, ante = 1 })
local first = bet.last("gambelBetResult")
ok(first.ok and first.money == nil and (first.delta == 10 or first.delta == -10), "the host flips half of $20")
S:receive(bet.c, { action = "gambelBet", kind = "wheel", money = 20, ante = 1 })
ok(bet.last("gambelBetResult").reason == "once", "a second bet in the same ante is refused")

local en = dofile("localization/en-us.lua").misc.dictionary
local nl = dofile("localization/nl.lua").misc.dictionary
ok(en.k_gambel_time == "Gambel Time" and nl.k_gambel_time == "Gambel Time", "the mode name stays Gambel Time")
ok(en.k_gambel_house_win:find("House", 1, true) and nl.k_gambel_house:find("Huis", 1, true), "The House has a Dutch name")
local shop = io.open("lib/gambel.lua"):read("*a")
ok(shop:find("n = G.UIT.R", 1, true) and shop:find("mp_gambel_double", 1, true) and shop:find("mp_gambel_wheel", 1, true), "the two shop buttons sit in one row")
ok(shop:find("set_edition", 1, true) and shop:find("add_tag", 1, true) and shop:find("set_perishable", 1, true) and shop:find("arm_discard", 1, true), "wheel prizes change the run, they are not only a toast")
ok(shop:find("pitch = 1", 1, true) and shop:find("sync = false", 1, true), "the song plays at its own pitch")
ok(shop:find("function G.FUNCS.mp_gambel_double(e)", 1, true) and shop:find("function G.FUNCS.mp_gambel_wheel(e)", 1, true), "both buttons receive the click")
ok(shop:find("box:remove()", 1, true), "the shop panel is removed when you leave")
local credits = io.open("CREDITS.md"):read("*a")
ok(credits:find("B ass gas M", 1, true), "the song credits B ass gas M")

print("PASS: gambel time")
