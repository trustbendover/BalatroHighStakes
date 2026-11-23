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
ok(POV.due("a", "b", 10, 10) and not POV.due("b", "b", 10, 10), "a changed board is still sent when the clock does not move")
ok(POV.guess_event(
	{ phase = "play", blind = "Small Blind", hand = { {}, {} }, played = {}, chips = "0", mult = "0" },
	{ phase = "play", blind = "Small Blind", hand = { {} }, played = { {} }, chips = "0", mult = "0" }
) == "play", "moving a card into the played row is a play")
ok(POV.guess_event(
	{ phase = "play", blind = "Small Blind", hand = { {}, {} }, played = {}, chips = "0", mult = "0" },
	{ phase = "play", blind = "Small Blind", hand = { {} }, played = {}, chips = "0", mult = "0" }
) == "discard", "a smaller hand with nothing played is a discard")
ok(POV.guess_event(
	{ phase = "shop", blind = "Small Blind", hand = {}, played = {}, jokers = {}, shop = { { k = "j_joker" } }, chips = "0", mult = "0" },
	{ phase = "shop", blind = "Small Blind", hand = {}, played = {}, jokers = { { k = "j_joker" } }, shop = {}, chips = "0", mult = "0" }
) == "joker", "buying a shop joker is a joker event")
ok(POV.guess_event(
	{ phase = "select", blind = "Small Blind", hand = {}, played = {}, chips = "0", mult = "0" },
	{ phase = "select", blind = "Big Blind", hand = {}, played = {}, chips = "0", mult = "0" }
) == "blind", "a new blind name is a blind event")

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
clock.t = clock.t + 1
S:receive(ann, { action = "spectateSnap", phase = "play", sig = "up-1", ev = "select",
	hand = { { r = "A", s = "H", up = 1, en = "m_bonus", sl = "Gold" } } })
local marked = cam.last("spectateSnap")
ok(marked.hand[1].up == 1 and marked.hand[1].en == "m_bonus" and marked.hand[1].sl == "Gold" and marked.ev == "select",
	"a raised, enhanced, sealed card and its select event reach only the watcher")

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

local raised = POV.card({ base = { value = "A", suit = "Hearts" }, highlighted = true, seal = "Gold", config = { center = { key = "m_bonus" } } })
ok(raised.up == 1 and raised.sl == "Gold" and raised.en == "m_bonus", "a raised enhanced sealed card keeps those marks")
ok(POV.guess_event(
	{ phase = "play", hand = { { up = 0 } }, played = {}, chips = "0", mult = "0" },
	{ phase = "play", hand = { { up = 1 } }, played = {}, chips = "0", mult = "0" }
) == "select", "raising a card is a select event")
ok(POV.guess_event(
	{ phase = "play", hand = { {} }, played = {}, chips = "1", mult = "1" },
	{ phase = "play", hand = { {} }, played = {}, chips = "8", mult = "4" }
) == "score", "chips x mult changing is a score event")
local bag = POV.realize({ hand = { { r = "A", s = "H", up = 1 } }, played = { { r = "K", s = "S" } } }, function(d)
	return { d = d, highlighted = false, REMOVED = false, states = { collide = { can = true }, drag = { can = true } },
		remove = function(self) self.REMOVED = true end }
end)
local kept = bag.objects[1]
ok(#bag.objects == 2 and kept.highlighted and kept.states.collide.can == false and kept.states.drag.can == false, "watched cards are raised copies and cannot be clicked")
POV.cleanup(bag)
ok(kept.REMOVED and #bag.objects == 0 and #bag.areas == 0, "switch, leave and match end remove every watched card")

-- Two peers. The host clock stays on one second (os.time does this) across several
-- table changes. Each change has to show up on the watcher's cards and text.
local clock2 = { t = 9000 }
local S2 = Core.new({ now = function() return clock2.t end, log = function() end })
local function peer(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	function c.count(a) local n = 0 for _, m in ipairs(msgs) do if m.action == a then n = n + 1 end end return n end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local live_host, live_other = peer(S2, "Ada~1"), peer(S2, "Bea~2")
S2:receive(live_host, { action = "createLobby", gameMode = "attrition" })
local live_code = live_host.last("joinedLobby").code
S2:receive(live_other, { action = "joinLobby", code = live_code })
S2:receive(live_other, { action = "readyLobby" })
S2:receive(live_host, { action = "startGame" })
local live_watch = peer(S2, "Cam~3")
S2:receive(live_watch, { action = "joinLobby", code = live_code, spectate = true })
S2:receive(live_watch, { action = "spectateWatch", playerId = live_host.id })
ok(live_host.last("spectateDemand").on == true, "the watcher selecting a player reaches that player as a demand")
local reminded = live_host.count("spectateDemand")
S2:receive(live_watch, { action = "spectateWatch", playerId = live_host.id })
ok(live_host.count("spectateDemand") == reminded + 1, "selecting the same player again reminds the target it is being watched")

G.CARD_W, G.CARD_H, G.UIT.O = 1, 1.4, 4
G.STATES = { SELECTING_HAND = 1, SHOP = 2, BLIND_SELECT = 3 }
function CardArea()
	local area = { cards = {}, REMOVED = false }
	function area:emplace(c) self.cards[#self.cards + 1] = c end
	function area:remove_card(c)
		for i, x in ipairs(self.cards) do if x == c then table.remove(self.cards, i) return end end
	end
	function area:remove() self.REMOVED = true end
	return area
end
G.GAME = {
	dollars = 8, chips = 0,
	round_resets = { ante = 2 },
	current_round = { hands_left = 4, discards_left = 3, current_hand = { chips = 0, mult = 0 } },
	blind = { name = "Small Blind" },
}
G.STATE = G.STATES.SELECTING_HAND
G.hand = { cards = {} }
G.jokers = { cards = {} }
G.consumeables = { cards = {} }
G.play = { cards = {} }
G.shop_jokers = { cards = {} }
MP.GAME.enemies[live_host.id] = { id = live_host.id, username = "Ada", lives = 4, raw_score = "0", hands = 4, ante = 2 }
SP.state.follow = live_host.id
SP.state.active = true
SP.demand = true
SP._mem = nil
local sent_to_host = 0
Client = { send = function(m)
	if m.action == "spectateSnap" then sent_to_host = sent_to_host + 1 end
	S2:receive(live_host, m)
end }
local panel = SP.ui()
local function frozen(node, hit)
	if type(node) ~= "table" then return end
	if node.config and node.config.ref_value and tostring(node.config.ref_value):find("^pov") then
		if node.config.maxw then hit.maxw = true end
		if node.config.ref_table ~= SP.view then hit.noref = true end
	end
	if node.config and node.config.object == SP.areas.hand then hit.area = true end
	for _, c in ipairs(node.nodes or {}) do frozen(c, hit) end
end
local shape = {}
frozen(panel, shape)
ok(not shape.maxw and not shape.noref and shape.area, "the board text stays bound to the live table, and the hand is a card row")

local function show()
	SP.maybe_send(clock2.t)
	local got = live_watch.last("spectateSnap")
	ok(got ~= nil, "the watcher received this snapshot")
	SP.on_snap(got)
	return got
end
local function ranks(area)
	local bits = {}
	for _, c in ipairs(area and area.cards or {}) do bits[#bits + 1] = c.desc and (c.desc.r or c.desc.k) or "?" end
	return table.concat(bits, ",")
end

G.hand.cards = {
	{ base = { value = "A", suit = "Hearts" } },
	{ base = { value = "K", suit = "Spades" } },
}
show()
ok(ranks(SP.areas.hand) == "A,K" and SP.view.pov4:find("AH", 1, true), "the opening hand is on the watcher")
local watched_card = SP.areas.hand.cards[1]
ok(watched_card.states.collide.can == false and watched_card.states.drag.can == false, "watched cards cannot be clicked")

G.hand.cards = { { base = { value = "A", suit = "Hearts" } } }
G.play.cards = { { base = { value = "K", suit = "Spades" } } }
show()
ok(ranks(SP.areas.hand) == "A" and ranks(SP.areas.played) == "K" and SP.view.pov1:find("PLAY", 1, true),
	"playing a card updates the watcher hand, the played row and the event")
ok(live_other.count("spectateSnap") == 0, "the active opponent still receives none of the live boards")

G.hand.cards = {}
G.play.cards = {}
show()
ok(ranks(SP.areas.hand) == "" and SP.view.pov1:find("DISCARD", 1, true), "a discard clears the watched hand and shows the event")

clock2.t = clock2.t + 1
G.STATE = G.STATES.SHOP
G.shop_jokers.cards = { { config = { center = { key = "j_gros_michel" } }, cost = 5 } }
show()
ok(ranks(SP.areas.shop) == "j_gros_michel", "the shop row shows the joker that is for sale")

G.shop_jokers.cards = {}
G.jokers.cards = { { config = { center = { key = "j_gros_michel" } }, cost = 5 } }
show()
ok(ranks(SP.areas.jokers) == "j_gros_michel" and ranks(SP.areas.shop) == "" and SP.view.pov1:find("JOKER", 1, true),
	"buying the joker moves it onto the watcher and off the shop row")

G.STATE = G.STATES.BLIND_SELECT
G.GAME.blind.name = "Big Blind"
show()
ok(SP.view.pov1:find("BLIND", 1, true) and SP.view.pov1:find("Big Blind", 1, true), "a blind change updates the watcher")
ok(sent_to_host >= 6 and live_watch.count("spectateSnap") >= 6, "every successive change was relayed, not only the first")
ok(live_other.count("spectateSnap") == 0, "after the whole series the opponent still has no board")

print("PASS: spectator pov")
