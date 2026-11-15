-- Live POV spectate: compact snapshots, throttle, and relay only to watchers.
-- luajit tests/test_spectator_pov.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local POV = dofile("networking/spectator_pov.lua")
local Core = dofile("networking/p2p_server.lua")

local ace = {
	base = { value = "A", suit = "Hearts" },
	edition = { foil = true },
	ability = { eternal = true },
}
local described = POV.card(ace)
ok(described.r == "A" and described.s == "H" and described.e == "foil" and described.st == "eternal", "a card keeps rank, suit, edition and sticker")
local joker = POV.card({ config = { center = { key = "j_joker" } }, edition = { holo = true }, ability = { rental = true }, cost = 6 })
ok(joker.k == "j_joker" and joker.e == "holo" and joker.st == "rental" and joker.cost == 6, "a joker keeps its key, edition, sticker and cost")

local snap = POV.capture({
	phase = "shop", ante = 3, blind = "The Mouth", money = 12, hands = 4, discards = 2,
	score = "1500", chips = "300", mult = "5",
	hand = { ace }, jokers = { { config = { center = { key = "j_joker" } }, edition = { polychrome = true } } },
	cons = { { config = { center = { key = "c_jupiter" } } } },
	played = { { base = { value = "K", suit = "Spades" } } },
	shop = { { config = { center = { key = "j_gros_michel" } }, cost = 5 } },
})
ok(snap.phase == "shop" and snap.hand[1].e == "foil" and snap.jokers[1].e == "poly" and snap.shop[1].k == "j_gros_michel", "a shop snapshot keeps the board and the shop")
ok(POV.capture({ phase = "play", hand = { ace } }).shop == nil, "shop cards are omitted while the player is not in the shop")
local lines = POV.lines(snap)
ok(lines[1]:find("Shop", 1, true) and lines[4]:find("AH foil eternal", 1, true) and lines[7]:find("gros michel", 1, true), "the board text shows phase, hand and shop")
ok(not POV.due("a", "b", 10, 9.8) and POV.due("a", "b", 10, 9.5) and not POV.due("same", "same", 10, 9) and POV.due("same", "same", 12, 9), "snapshots wait out the gap, skip an unchanged board, and heartbeat")

local clock = { t = 5000 }
local function server()
	return Core.new({ now = function() return clock.t end, log = function() end })
end
local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	c.box = msgs
	function c.count(a) local n = 0 for _, m in ipairs(msgs) do if m.action == a then n = n + 1 end end return n end
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local function hand_snap(text)
	return { phase = "play", ante = 2, blind = "Small Blind", money = 8, hands = 3, discards = 1,
		score = "40", chips = "20", mult = "2", sig = text,
		hand = { { r = "A", s = "H", e = "foil", st = "eternal" } },
		jokers = { { k = "j_joker", e = "holo", st = "" } },
		played = { { r = "K", s = "S" } } }
end

local S = server()
local ann, bob = client(S, "Ann~1"), client(S, "Bob~2")
S:receive(ann, { action = "createLobby", gameMode = "attrition" })
local code = ann.last("joinedLobby").code
S:receive(bob, { action = "joinLobby", code = code })
S:receive(bob, { action = "readyLobby" })
S:receive(ann, { action = "startGame" })
local cam = client(S, "Cam~3")
S:receive(cam, { action = "joinLobby", code = code, spectate = true })
ok(cam.spectator, "a late joiner during the match is a spectator")

local before = bob.count("spectateSnap") + ann.count("spectateSnap")
S:receive(bob, { action = "spectateWatch", playerId = ann.id })
S:receive(ann, { action = "spectateSnap", playerId = bob.id, phase = "play", hand = { { r = "A", s = "H", e = "foil", st = "eternal" } }, sig = "secret" })
ok(bob.count("spectateSnap") == before and cam.count("spectateSnap") == 0, "an active opponent cannot subscribe or receive a hand")

S:receive(cam, { action = "spectateWatch", playerId = ann.id })
local demand = ann.last("spectateDemand")
ok(demand and demand.on == true, "the followed player is asked for a board only once someone is watching")
ok(not bob.last("spectateDemand"), "the other active player is not asked for a board")
S:receive(ann, { action = "spectateSnap", playerId = "forged", phase = "play", ante = 4, money = 15, hands = 2, discards = 3,
	score = "99", chips = "33", mult = "3", sig = "board-1",
	hand = { { r = "A", s = "H", e = "foil", st = "eternal" } },
	jokers = { { k = "j_joker", e = "holo" } }, played = { { r = "K", s = "S" } } })
local seen = cam.last("spectateSnap")
ok(seen and seen.playerId == ann.id and seen.hand[1].r == "A" and seen.hand[1].e == "foil" and seen.jokers[1].e == "holo", "the watcher receives the followed player's hand, edition and joker")
ok(seen.played[1].r == "K" and seen.chips == "33" and seen.mult == "3" and seen.hands == 2, "the watcher sees the played hand, chips x mult and hands left")
ok(bob.count("spectateSnap") == before, "the active opponent still receives none of it")

clock.t = clock.t + 0.1
S:receive(ann, { action = "spectateSnap", phase = "play", sig = "board-2", hand = { { r = "2", s = "C" } } })
ok(cam.last("spectateSnap").sig == "board-1", "a second snapshot inside the gap is dropped")
clock.t = clock.t + 0.5
S:receive(ann, { action = "spectateSnap", phase = "shop", sig = "shop-1", shop = { { k = "j_gros_michel", cost = 5 } }, hand = {} })
ok(cam.last("spectateSnap").phase == "shop" and cam.last("spectateSnap").shop[1].cost == 5, "the shop row is relayed only in the shop phase")

S:receive(cam, { action = "spectateWatch", playerId = bob.id })
ok(ann.last("spectateDemand").on == false and bob.last("spectateDemand").on == true, "switching the followed player stops the old demand and starts the new one")
S:receive(cam, { action = "spectateWatch", playerId = "" })
ok(bob.last("spectateDemand").on == false, "clearing the follow stops the demand")
clock.t = clock.t + 1
local n = cam.count("spectateSnap")
S:receive(bob, { action = "spectateSnap", phase = "play", sig = "nope", hand = { { r = "Q", s = "D" } } })
ok(cam.count("spectateSnap") == n, "with nobody watching, the board is not relayed")

-- An eliminated player may watch. A forged watch map still cannot reach an active opponent.
bob.eliminated = true
S:receive(bob, { action = "spectateWatch", playerId = ann.id })
ok(ann.last("spectateDemand").on == true, "an eliminated player can follow someone")
ann.lobby.povWatch[bob.id] = ann.id
clock.t = clock.t + 1
S:receive(ann, { action = "spectateSnap", phase = "play", sig = "elim", hand = { { r = "A", s = "S" } } })
ok(bob.last("spectateSnap").sig == "elim" and cam.count("spectateSnap") == n, "only the subscribed eliminated player receives that board")

-- Deathmatch and teams use the same relay: mode does not widen who may see the hand.
ann.lobby.gameMode = "deathmatch"
clock.t = clock.t + 1
S:receive(ann, { action = "spectateSnap", phase = "select", sig = "dm", blind = "Big Blind", ante = 6 })
ok(bob.last("spectateSnap").phase == "select" and bob.last("spectateSnap").blind == "Big Blind", "deathmatch still delivers the blind and ante to the watcher")
ann.lobby.gameMode = "teams"
clock.t = clock.t + 1
S:receive(ann, { action = "spectateSnap", phase = "play", sig = "teams" })
ok(bob.last("spectateSnap").sig == "teams", "teams still delivers only to the watcher")

S:disconnect(ann)
ok(bob.last("spectateSnap").phase == "gone", "when the followed player drops, the watcher is told they are gone")

-- The panel shows the board and does not put a click on the cards.
MP = { GAME = { enemies = {}, lives = 0 }, LOBBY = { code = "ABCD", names_by_id = {} } }
G = { UIT = { ROOT = 0, R = 1, C = 2, T = 3 }, C = { GOLD = {}, GREEN = {}, ORANGE = {}, RED = {}, BLACK = {},
	UI = { TEXT_LIGHT = {}, TEXT_INACTIVE = {} } } }
function localize() return "ERROR" end
dofile("lib/fit.lua")
dofile("lib/spectator.lua")
local SP = MP.SPECTATE
local id = "p1"
MP.GAME.enemies[id] = { id = id, username = "Ann", lives = 4, raw_score = "10", hands = 3, ante = 2 }
SP.state.follow = id
SP.boards[id] = snap
SP.refresh()
ok(SP.view.pov1:find("Shop", 1, true) and SP.view.pov4:find("AH", 1, true), "the spectator panel paints the followed player's board")
_G.create_UIBox_generic_options = function(a) return { n = G.UIT.ROOT, config = {}, nodes = a.contents } end
_G.UIBox_button = function(a) return { n = G.UIT.C, config = { minw = a.minw, button = a.button }, nodes = {} } end
local ui = SP.ui()
local function walk(node, hit)
	if type(node) ~= "table" then return end
	if node.config and node.config.ref_value and tostring(node.config.ref_value):find("^pov") and node.config.button then hit[1] = true end
	for _, c in ipairs(node.nodes or {}) do walk(c, hit) end
end
local hit = {}
walk(ui, hit)
ok(not hit[1], "the board text has no button, so a click cannot play a card")
local buttons = {}
local function walkb(node)
	if type(node) ~= "table" then return end
	if node.config and node.config.button then buttons[node.config.button] = true end
	for _, c in ipairs(node.nodes or {}) do walkb(c) end
end
walkb(ui)
ok(buttons.mp_sp_prev and buttons.mp_sp_next and buttons.mp_sp_back and buttons.mp_sp_stats, "Prev, Next, Back and the stats toggle stay on the panel")

print("PASS: spectator pov")
