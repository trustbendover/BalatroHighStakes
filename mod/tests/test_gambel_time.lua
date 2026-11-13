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
local function ace_ok(f)
	local red = f.drawn == "red" and (f.suit == "H" or f.suit == "D")
	local black = f.drawn == "black" and (f.suit == "S" or f.suit == "C")
	return f.ok and (red or black) and f.won == ((f.choice or "red") == f.drawn)
end
local plain = R.flip("seed", "p", 3, 11)
local as_red = R.flip("seed", "p", 3, 11, "red")
local as_black = R.flip("seed", "p", 3, 11, "black")
local junk = R.flip("seed", "p", 3, 11, "blue")
ok(ace_ok(plain) and plain.choice == nil and plain.won == again.won and plain.drawn == as_red.drawn and plain.suit == as_red.suit, "no guess still draws an Ace and wins on red")
ok(ace_ok(as_red) and as_red.choice == "red" and as_red.won == (as_red.drawn == "red"), "red wins only when the Ace is red")
ok(ace_ok(as_black) and as_black.choice == "black" and as_black.won == (as_black.drawn == "black") and as_black.won ~= as_red.won, "black is the other side of the same Ace")
ok(as_red.drawn == as_black.drawn and as_red.suit == as_black.suit and junk.choice == nil and junk.won == plain.won, "the guess does not change the card")
local reds, blacks = 0, 0
for ante = 1, 48 do
	local f = R.flip("house", "p" .. (ante % 8), ante, 10)
	if f.drawn == "red" then reds = reds + 1 else blacks = blacks + 1 end
	ok(ace_ok(f), "draw " .. ante .. " is one Ace")
end
ok(reds >= 12 and blacks >= 12, "red and black both come up")
ok(#R.WHEEL == 7, "the wheel has 7 wedges")
local wedges = {
	{ id = "cash", amount = 8 },
	{ id = "cash", amount = 20 },
	{ id = "tag" },
	{ id = "edition" },
	{ id = "tax", amount = 4 },
	{ id = "discard" },
	{ id = "perish" },
}
for i, msg in ipairs(wedges) do
	ok(R.wheel_index(msg) == i, "wedge " .. i .. " is " .. msg.id)
	local rot = R.wheel_rotation(i, 4)
	ok(R.wheel_under(rot) == i, "the pointer stops on wedge " .. i)
	ok(R.wheel_under(R.wheel_ease(1) * rot) == i, "eased landing is the same wedge")
end
ok(R.wheel_index({ id = "cash", amount = 20 }) == 2 and R.wheel_index({ id = "tax", delta = -4 }) == 5, "cash amounts and a tax delta pick the right wedge")
ok(R.wheel_ease(0) == 0 and R.wheel_ease(1) == 1 and R.wheel_ease(0.5) > 0.7, "the spin starts fast and eases out")
ok(R.keep_bet(1, 1, true) == true and R.keep_bet(1, 2, true) == false and R.keep_bet(nil, 1, false) == false, "a shop bet lasts for that ante only")

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
ok(R.music_priority({ mode = "gamemode_mp_gambel_time", in_lobby = false, watching = true, stage = "menu" }) == nil, "a dead player who left the lobby does not keep the track")
ok(R.music_priority({ mode = "gamemode_mp_gambel_time", in_lobby = false, stage = "run" }) == nil, "no lobby means no Gambel Time music, even on a run stage")
ok(R.music_priority({ mode = "gamemode_mp_gambel_time", in_lobby = true, watching = true, stage = "menu" }) == 10, "a watcher who is still in the lobby hears the track")
local music = io.open("lib/gambel.lua"):read("*a")
ok(music:find('key = "music_gambel_time"', 1, true) and music:find('path = "music_gambel_time.ogg"', 1, true) and music:find("sync = false", 1, true), "the sound is registered for assets/sounds/music_gambel_time.ogg")
ok(music:find("NFS.getInfo", 1, true), "a missing ogg is skipped instead of crashing")
ok(music:find("in_lobby = in_lobby", 1, true) and music:find("spec.state.active or spec.state.joined", 1, true) and music:find("G.STATE ~= G.STATES.MENU", 1, true), "the track checks the lobby code and a real spectator, not a leftover life of 0")
local leave = io.open("ui/lobby/lobby.lua"):read("*a")
ok(leave:find("MP.SPECTATE.on_match_end", 1, true), "leaving the lobby clears the spectator match flag")

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
local won = solo.last("matchStats")
ok(won and won.winnerId == solo.c.id and #won.rows == 1, "beating The House sends a one-row match stats table")

S = server()
local dead = player(S, "Bea")
S:receive(dead.c, { action = "createLobby", gameMode = "gambel_time" })
S:receive(dead.c, { action = "lobbyOptions", match_settings = 1, starting_lives = 2, gambel_ante = 8 })
S:receive(dead.c, { action = "startGame" })
S:receive(dead.c, { action = "failRound" })
dead.c.roundLivesBlocker = nil
S:receive(dead.c, { action = "failRound" })
local lost = dead.last("loseGame")
local tabled = dead.last("matchStats")
ok(lost and lost.finished == true and not dead.c.lobby.isInGame, "the last life against The House finishes the match")
ok(tabled and #tabled.rows == 1 and tabled.rows[1].id == dead.c.id, "a solo loss sends match stats for that one player")

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
S:receive(bet.c, { action = "gambelBet", kind = "double", choice = "red", money = 20, ante = 2 })
local red_bet = bet.last("gambelBetResult")
local expect_red = Core.GAMBEL.flip(bet.c.lobby.seed, bet.c.id, 2, 20, "red")
ok(red_bet.choice == "red" and red_bet.drawn == expect_red.drawn and red_bet.suit == expect_red.suit and red_bet.won == expect_red.won, "the host draws the Ace for a red guess")
ok(red_bet.won == (red_bet.drawn == "red") and ((red_bet.drawn == "red" and (red_bet.suit == "H" or red_bet.suit == "D")) or (red_bet.drawn == "black" and (red_bet.suit == "S" or red_bet.suit == "C"))), "the suit matches the colour")
S:receive(bet.c, { action = "gambelBet", kind = "double", choice = "black", money = 20, ante = 3 })
local black_bet = bet.last("gambelBetResult")
local same = Core.GAMBEL.flip(bet.c.lobby.seed, bet.c.id, 3, 20)
local opp = Core.GAMBEL.flip(bet.c.lobby.seed, bet.c.id, 3, 20, "black")
ok(same.drawn == opp.drawn and same.won ~= opp.won, "the card stays put when the guess changes")
ok(black_bet.choice == "black" and black_bet.drawn == opp.drawn and black_bet.suit == opp.suit and black_bet.won == opp.won, "the host scores black against that Ace")
bet.c.lobby.gambelTwist = "pot"
bet.c.lobby.gambelAnte = 3
local snap = S:snapshot(bet.c.lobby.code, bet.c.id)
local _, kept = Core.restore(snap, { now = function() return 2000 end, log = function() end, newHostId = bet.c.id, oldHostId = "old" })
local kept_bet = false
for _, sl in ipairs(kept.slots) do if sl.old and sl.old.gambelBetAnte == 3 then kept_bet = true end end
ok(kept_bet and kept.gambelTwist == "pot" and kept.gambelAnte == 3, "a takeover keeps the shop bet and the chaos spin")

local en = dofile("localization/en-us.lua").misc.dictionary
local nl = dofile("localization/nl.lua").misc.dictionary
ok(en.k_gambel_time == "Gambel Time" and nl.k_gambel_time == "Gambel Time", "the mode name stays Gambel Time")
ok(en.k_gambel_house_win:find("House", 1, true) and nl.k_gambel_house:find("Huis", 1, true), "The House has a Dutch name")
ok(en.b_gambel_red == "Red Ace" and en.b_gambel_black == "Black Ace", "English Red and Black")
ok(nl.b_gambel_red == "Rode Aas" and nl.b_gambel_black == "Zwarte Aas", "Dutch Red and Black")
ok(en.b_gambel_back == "Back" and en.b_gambel_continue == "Continue" and nl.b_gambel_back == "Terug" and nl.b_gambel_continue == "Verder", "back and continue")
ok(en.b_gambel_spin == "Spin!" and nl.b_gambel_spin == "Draai!", "Spin! in English and Dutch")
ok(en.k_gambel_ace_h == "Ace of Hearts" and en.k_gambel_ace_s == "Ace of Spades", "English ace names")
ok(nl.k_gambel_ace_h == "Harten Aas" and nl.k_gambel_ace_d == "Ruiten Aas" and nl.k_gambel_ace_s == "Schoppen Aas" and nl.k_gambel_ace_c == "Klaveren Aas", "Dutch ace names")
ok(en.k_gambel_ace_ask == "RED OR BLACK ACE?" and nl.k_gambel_ace_ask == "RODE OF ZWARTE AAS?", "the subtitle stays a static question")
ok(en.k_gambel_stake == "STAKE: $" and nl.k_gambel_stake == "INZET: $", "the stake pill is labeled")
ok(en.k_gambel_win == "WIN +$" and nl.k_gambel_win == "WINST +$", "a win bar reads WIN +$")
ok(en.k_gambel_lose == "LOSE -$" and nl.k_gambel_lose == "VERLIES -$", "a loss bar reads LOSE -$")
ok(en.k_gambel_half == "BET HALF YOUR CASH - WIN IT OR LOSE IT" and nl.k_gambel_half == "ZET DE HELFT VAN JE GELD IN - WIN HET OF VERLIES HET", "the tagline sits under the bar")
ok(en.k_gambel_wheel_tax == "-$4 Tax" and nl.k_gambel_wheel_tax == "-$4 Belasting", "the tax wedge is named")
ok(en.k_gambel_wheel_discard == "-1 Discard" and nl.k_gambel_wheel_discard == "-1 Weggooi", "the discard wedge is named")
local shop = io.open("lib/gambel.lua"):read("*a")
ok(shop:find("G.UIDEF.shop", 1, true) and shop:find("n = G.UIT.R", 1, true) and shop:find("mp_gambel_double", 1, true) and shop:find("mp_gambel_wheel", 1, true), "both shop buttons are a row inside the shop")
ok(shop:find("set_edition", 1, true) and shop:find("add_tag", 1, true) and shop:find("set_perishable", 1, true) and shop:find("arm_discard", 1, true), "wheel prizes change the run, they are not only a toast")
ok(shop:find("pitch = 1", 1, true) and shop:find("volume = 1", 1, true) and shop:find("sync = false", 1, true), "the song plays at pitch 1 and full volume")
ok(shop:find("function G.FUNCS.mp_gambel_double(e)", 1, true) and shop:find("function G.FUNCS.mp_gambel_wheel(e)", 1, true), "both buttons receive the click")
ok(shop:find("open_double", 1, true) and shop:find("overlay_menu", 1, true) and shop:find("CardArea", 1, true), "Double or Nothing opens a card overlay and does not spend the bet yet")
ok(shop:find('MP.GAMBEL.pick_double("red")', 1, true) and shop:find('R.bet("double", choice)', 1, true), "Red or Black is what spends the bet")
ok(shop:find("open_wheel", 1, true) and shop:find('R.bet("wheel")', 1, true) and shop:find('R.casino_frame(L("b_gambel_wheel"', 1, true) and shop:find('R.casino_frame(L("b_gambel_double"', 1, true), "Gambel Wheel opens the same felt table, and Spin spends the bet")
ok(shop:find("if not (love and love.graphics", 1, true) and shop:find("love.graphics.polygon", 1, true) and shop:find("G.TILESIZE", 1, true), "the wheel canvas is skipped without Love2D and drawn in pixels")
ok(shop:find("gambel_bet_for", 1, true) and shop:find("sync_bet_ante", 1, true) and shop:find("drop_cards", 1, true), "the ante lock survives a shop rebuild, and a closed card is removed")
ok(shop:find("function R.make_double_card", 1, true) and shop:find('sprite_facing = "back"', 1, true) and shop:find("emplace(card, nil, true)", 1, true), "the card is created face down and emplace does not flip it")
ok(shop:find("no_ui = true", 1, true) and shop:find("states.hover.can = false", 1, true) and shop:find("card.hover = function() end", 1, true), "hovering the Ace does not open the card tooltip")
ok(shop:find("function R.tick_double", 1, true) and shop:find("flip_dur = 0.70", 1, true) and shop:find("hold_dur = 0.55", 1, true)
	and shop:find("pinch.x = false", 1, true) and shop:find("set_sprites", 1, true) and shop:find('sprite_facing = "front"', 1, true)
	and shop:find("R.ace_name", 1, true) and shop:find("R.reshow_double", 1, true) and shop:find("0.96, 0.62, 0.08, 1", 1, true)
	and shop:find("k_gambel_ace_ask", 1, true) and shop:find("k_gambel_half", 1, true)
	and not shop:find("k_gambel_flipping", 1, true) and not shop:find('ref_value = "card_name"', 1, true)
	and not shop:find("mp_gambel_choices_vis", 1, true),
	"the Ace turns over and holds, then the result bar replaces the choices")
ok(shop:find("bulbs = 28", 1, true) and shop:find("% 3 == 0", 1, true) and shop:find("love.timer.getTime", 1, true) and shop:find("1, 0.98, 0.84, 1", 1, true) and shop:find("0.42, 0.24, 0.08, 1", 1, true), "the wheel rim carries chasing marquee bulbs")
ok(shop:find("R.WHEEL_BOX = 5.0", 1, true) and shop:find("wheel_slices", 1, true)
	and shop:find("minw = R.WHEEL_BOX", 1, true) and shop:find("minw = 1.25", 1, true)
	and shop:find("colour = { 0.03, 0.08, 0.06, 0.45 }", 1, true)
	and shop:find("g.scale(0.26, 0.26)", 1, true) and shop:find("half - 0.88", 1, true)
	and shop:find("0, tip + 0.04 * ts", 1, true),
	"the pointer aims down at the rim, and the prize list sits clear of the wheel")
ok(shop:find("STEAM_P2P", 1, true) and shop:find("R.flip", 1, true), "a lobby bet goes to the host, and a solo run with no Steam still rolls")
local credits = io.open("CREDITS.md"):read("*a")
ok(credits:find("Bass Gas M", 1, true), "the song credits Bass Gas M")

local saved_g = G
MP.load_mp_file = function(p) return dofile(p) end
dofile("lib/gambel.lua")
ok(MP.GAMBEL.make_wheel() == nil, "headless Lua does not build a Love2D wheel")
local R = MP.GAMBEL
MP.GAME = MP.GAME or {}
R.double_view = { picked = "red", stake = 4, prompt = "Pick", result = "stale", show_close = true, face = "back" }
R.reveal_double({ suit = "S", drawn = "black" }, "-$4")
ok(R.double_view.result == "" and not R.double_view.show_close and not R.double_view.outcome, "the win or loss stays hidden when the flip starts")
ok(R.double_view.prompt == "Pick" and R.double_view.face == "back" and R.double_view.flip.outcome == "loss", "the header stays put while the card is still face down")
ok(R.double_view.flip.flip_dur == 0.70 and R.double_view.flip.hold_dur == 0.55, "the flip holds the face-up Ace before the bar")
R.tick(0.30)
ok(R.double_view.result == "" and not R.double_view.show_close and R.double_view.face == "back", "the first half of the flip is still the back")
R.tick(0.10)
ok(R.double_view.face == "front" and R.double_view.suit_mark == "S" and R.double_view.result == "", "the face swaps at the midpoint, still without the payout")
R.tick(0.30)
ok(R.double_view.flip and R.double_view.flip.drawn == "Ace of Spades" and R.double_view.result == "" and not R.double_view.show_close, "the face-up Ace is held before the payout")
R.tick(0.55)
ok(R.double_view.show_close and R.double_view.result == "-$4" and R.double_view.outcome == "loss", "the payout appears only after the hold")
ok(MP.GAME.gambel_notice == "-$4", "the toast waits until the hold finishes")
local win_text, win_col = R.payout_line({ stake = 12, outcome = "win" })
ok(win_text == "WIN +$12" and win_col[1] == 0.96 and win_col[2] == 0.62 and win_col[3] == 0.08, "a win bar is gold and names the stake")
G = G or {}
G.C = G.C or {}
local red = { 0.9, 0.12, 0.16, 1 }
G.C.RED = red
local lose_text, lose_col = R.payout_line({ stake = 12, outcome = "loss" })
ok(lose_text == "LOSE -$12" and lose_col == red, "a loss bar uses Balatro red")
ok(R.payout_line({ outcome = "house", result = "" }) == "The House holds", "a timeout stays on the neutral house line")
R.double_view = { picked = "black", prompt = "", result = "", show_close = false, face = "back" }
R.reveal_double({ suit = "H", drawn = "red" }, "+$8")
R.close_double()
ok(MP.GAME.gambel_notice == "+$8" and R.double_view == nil, "closing during the flip still announces the result")

local function collect_text(node, acc)
	acc = acc or {}
	if type(node) ~= "table" then return acc end
	if node.config and type(node.config.text) == "string" then acc[#acc + 1] = node.config.text end
	if node.nodes then for _, child in ipairs(node.nodes) do collect_text(child, acc) end end
	if node.config and node.config.object and type(node.config.object) == "table" then acc._area = node.config.object end
	return acc
end
local function has_colour(node, r, g, b)
	if type(node) ~= "table" then return false end
	local c = node.config and node.config.colour
	if type(c) == "table" and math.abs((c[1] or 0) - r) < 1e-6 and math.abs((c[2] or 0) - g) < 1e-6 and math.abs((c[3] or 0) - b) < 1e-6 then return true end
	if node.nodes then for _, child in ipairs(node.nodes) do if has_colour(child, r, g, b) then return true end end end
	return false
end
UIBox_button = function(args)
	return { n = "C", config = { id = args.id, button = args.button, colour = args.colour }, nodes = {
		{ n = "T", config = { text = args.label and args.label[1] or "" } },
	} }
end
G.UIT = { ROOT = "ROOT", R = "R", C = "C", T = "T", O = "O" }
G.C.WHITE = G.C.WHITE or { 1, 1, 1, 1 }
G.C.BLACK = G.C.BLACK or { 0, 0, 0, 1 }
G.C.GREY = G.C.GREY or { 0.4, 0.4, 0.4, 1 }
G.C.BLUE = G.C.BLUE or { 0.2, 0.45, 1, 1 }
G.C.CLEAR = G.C.CLEAR or { 0, 0, 0, 0 }
G.FUNCS = G.FUNCS or {}
local kept = { id = "ace", facing = "front", sprite_facing = "front", pinch = { x = false }, no_ui = true, REMOVED = false, config = {}, states = { hover = {}, click = {}, drag = {} } }
local area = { id = "area", REMOVED = false, config = {}, role = { major = "old" }, parent = nil }
R.double_view = { stake = 12, show_close = false, outcome = nil, face = "back", result = "", picked = false, card = kept, area = area }
local choosing = table.concat(collect_text(R.double_definition()), "|")
ok(choosing:find("DOUBLE", 1, true) and choosing:find("OR NOTHING", 1, true) and choosing:find("RED OR BLACK ACE?", 1, true)
	and choosing:find("STAKE: $12", 1, true) and choosing:find("Red Ace", 1, true) and choosing:find("Black Ace", 1, true) and choosing:find("Back", 1, true)
	and not choosing:find("WIN +$", 1, true) and not choosing:find("Flipping", 1, true),
	"before the flip the promo header and the choice buttons stay put")
ok(not has_colour(R.double_definition(), 0.62, 0.10, 0.14), "the double modal does not use the jumping crimson caption bar")
R.double_view.show_close = true
R.double_view.outcome = "win"
R.double_view.face = "front"
R.double_view.suit_mark = "H"
local rebuilt = 0
local linked, blob, gold
G.OVERLAY_MENU = { config = { object = area }, children = { { config = { object = area }, children = {} } } }
G.FUNCS.overlay_menu = function(args)
	rebuilt = rebuilt + 1
	local texts = collect_text(args.definition)
	linked = texts._area
	blob = table.concat(texts, "|")
	gold = has_colour(args.definition, 0.96, 0.62, 0.08)
end
R.reshow_double()
ok(rebuilt == 1 and type(blob) == "string" and blob:find("WIN +$12", 1, true) and blob:find("BET HALF YOUR CASH - WIN IT OR LOSE IT", 1, true)
	and blob:find("Continue", 1, true) and not blob:find("Red Ace", 1, true), "the result bar replaces the choices in the rebuilt modal")
ok(gold, "the win bar is the promo gold")
ok(linked == area and kept.facing == "front" and kept.no_ui == true and kept.pinch.x == false, "the rebuild keeps the revealed Ace face up and muted")
ok(G.OVERLAY_MENU.children[1].config.object == nil, "the dying menu lets go of the Ace before it is removed")
R.double_view.outcome = "loss"
local loss = table.concat(collect_text(R.double_definition()), "|")
ok(loss:find("LOSE -$12", 1, true) and has_colour(R.double_definition(), red[1], red[2], red[3]), "a loss rebuilds a red LOSE bar")
R.double_view.outcome = "house"
R.double_view.result = ""
ok(table.concat(collect_text(R.double_definition()), "|"):find("The House holds", 1, true), "a house timeout stays a neutral bar")
G = saved_g

print("PASS: gambel time")
