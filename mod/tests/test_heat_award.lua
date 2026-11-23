-- luajit tests/test_heat_award.lua (run from mod/)
-- Select a blind, play hands, then end the round the way Balatro does.
-- Heat must stay above 0 after both the personal update and the leaderboard.
local function ok(c, m) assert(c, m); print("ok: " .. m) end

local sent = {}
Client = { send = function(m) sent[#sent + 1] = m end }
MP = { LOBBY = { config = { gamemode = "gamemode_mp_heat_rush" }, code = "HEAT1" }, GAME = {} }
G = {
	GAME = { current_round = { hands_played = 0 }, blind = nil },
	STAGE = 2, STAGES = { RUN = 2 }, STATES = { MENU = 0 }, STATE = 1,
}
Blind = {}
function Blind:defeat() end
function end_round()
	G.GAME.blind:defeat()
end

dofile("lib/heat.lua")
local H = MP.HEAT

local blind_defeat_ref = Blind.defeat
function Blind:defeat(silent)
	blind_defeat_ref(self, silent)
	if MP.HEAT and MP.HEAT.report then MP.HEAT.report(self) end
end

local function play(blind_name, hands, seconds_ago)
	sent = {}
	G.GAME.current_round.hands_played = 0
	H.arm()
	H.started = H.now() - seconds_ago
	G.GAME.current_round.hands_played = hands
	local boss = blind_name == "Boss"
	G.GAME.blind = setmetatable({
		boss = boss, name = blind_name,
		get_type = function() return blind_name == "Big Blind" and "Big" or (boss and "Boss" or "Small") end,
	}, { __index = Blind })
	end_round()
	ok(#sent == 1 and sent[1].action == "heatReport", "ending the round reports one Heat award for " .. blind_name)
	return sent[1]
end

local Core = dofile("networking/p2p_server.lua")
local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	function c.all() return msgs end
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end

local function apply_after(c, from)
	local g = { heat = 0, heat_total = 0, heat_best = 0, heat_overdrive = false }
	for i = from, #c.all() do
		local m = c.all()[i]
		if m.action == "heatState" or m.action == "heatBoard" then H.absorb(g, m) end
	end
	return g
end

local S = Core.new({ now = function() return 1 end, log = function() end })
local ada = client(S, "Ada~1")
S:receive(ada, { action = "createLobby", gameMode = "heat_rush" })
S:receive(ada, { action = "startGame" })
local before = #ada.all()
local report = play("Small Blind", 1, 40)
S:receive(ada, report)
local solo = apply_after(ada, before + 1)
ok(solo.heat > 0, "solo: after heatState and the leaderboard, Heat is still above 0 (got " .. tostring(solo.heat) .. ")")
ok(solo.heat_total > 0 and solo.heat_total >= solo.heat, "solo: the total keeps the Heat that was just earned")

local S2 = Core.new({ now = function() return 1 end, log = function() end })
local ann, bob = client(S2, "Ann~1"), client(S2, "Bob~2")
S2:receive(ann, { action = "createLobby", gameMode = "heat_rush" })
S2:receive(bob, { action = "joinLobby", code = ann.last("joinedLobby").code })
S2:receive(bob, { action = "readyLobby" })
S2:receive(ann, { action = "startGame" })
local ann_at = #ann.all()
local bob_at = #bob.all()
local prep = play("Big Blind", 2, 50)
S2:receive(ann, prep)
local ann_g = apply_after(ann, ann_at + 1)
ok(ann_g.heat > 0, "2-player host: Heat stays above 0 after the leaderboard")
S2:receive(bob, play("Small Blind", 1, 30))
local bob_g = apply_after(bob, bob_at + 1)
ok(bob_g.heat > 0, "2-player guest: Heat stays above 0 after the leaderboard")
-- a later leaderboard, with no personal heat field, must not wipe a meter that already filled
local wiped = H.absorb({ heat = bob_g.heat, heat_total = bob_g.heat_total, heat_best = bob_g.heat_best, heat_overdrive = bob_g.heat_overdrive }, { action = "heatBoard", rows = {} })
ok(wiped.heat == bob_g.heat, "a leaderboard message does not reset the local meter")

local opened
G.FUNCS = {
	overlay_menu = function(a) opened = a end,
	exit_overlay_menu = function() opened = nil end,
}
G.UIT = {}
G.C = { UI = { TEXT_LIGHT = {} }, GOLD = {}, WHITE = {}, ORANGE = {}, RED = {} }
G.SETTINGS = {}
MP.UI = { UTILS = {
	create_column = function(_, nodes) return nodes end,
	create_row = function(_, nodes) return nodes end,
	create_text_node = function(text) return { text = text } end,
} }
function create_UIBox_generic_options(t) return t end
function UIBox_button(t) return t end
function localize(k)
	if k == "k_heat_rush_rules" then return "Each clear pays +25 Heat. At 100 the next hand is Overdrive, x1.5." end
	if k == "k_heat_how" then return "How to play" end
	if k == "b_heat_how_ok" then return "Got it" end
	return k
end
H.on_match_start()
ok(opened ~= nil, "the first Heat Rush match opens How to play")
G.FUNCS.mp_heat_how_ok()
ok(H.how_seen(), "Got it remembers that the explanation was read")
opened = nil
H.on_match_start()
ok(opened == nil, "the next match does not open it again")
H.show_how()
ok(opened ~= nil, "the meter can open How to play again")

print("PASS: heat award")
