-- Vanilla select_blind queues a 0.2s event that indexes G.blind_select.
-- run from mod/: luajit tests/test_blind_select_guard.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local B = dofile("lib/blind_select_guard.lua")

ok(B.allow({ blind_select = true, context = true }) == true, "a live blind select with a button may run")
ok(B.allow({ blind_select = nil, context = true }) == false, "a torn-down blind select is refused")
ok(B.allow({ blind_select = true, selecting = true, context = true }) == false, "a second select while the first is in flight is refused")
ok(B.allow({ blind_select = true, context = nil }) == false, "a select with no blind context is refused")

G = { blind_select = { alignment = { offset = {} } } }
local queued = {}
local mgr = { add_event = function(self, ev) queued[#queued + 1] = ev end }
local cleared = 0
local dealt = false
-- Same shape as vanilla select_blind: a before-event removes the panel,
-- then new_round queues the draw. Both are queued while the guard is on.
B.protect(mgr, function()
	mgr:add_event({
		trigger = "before", delay = 0.2, blocking = true,
		func = function()
			G.blind_select.alignment.offset.y = 40
			G.blind_select = nil
			return true
		end,
	})
	mgr:add_event({
		func = function()
			dealt = true
			return true
		end,
	})
end, function() return G.blind_select end, function() cleared = cleared + 1 end)
ok(#queued == 2, "the panel event and the draw are both queued")
ok(queued[1].func() == true and G.blind_select == nil, "the before-event still removes the panel")
ok(queued[2].func() == true and dealt, "the draw still runs after the panel is gone")

queued = {}
cleared = 0
G.blind_select = nil
B.protect(mgr, function()
	mgr:add_event({
		trigger = "before", delay = 0.2,
		func = function()
			return G.blind_select.alignment.offset
		end,
	})
end, function() return G.blind_select end, function() cleared = cleared + 1 end)
ok(queued[1].func() == true and cleared == 1, "a stale event that indexes a nil blind_select does not escape")

-- Gambel Time uses this same select for the opening blind. The table spin
-- and the shop payout flag are not what deals the cards.
local Rules = dofile("networking/gambel_rules.lua")
ok(Rules.table_spin("seed", 1) ~= nil, "ante 1 still has a table spin")
ok(Rules.phase_bonus("build") == 0, "the first blind's build-up does not wait on a payout")

local src = io.open("ui/game/functions.lua"):read("*a")
ok(src:find("MP.BLIND_GUARD", 1, true) and src:find("selecting_blind", 1, true), "select_blind consults the guard before calling vanilla")
ok(src:find("next_blind_context = e", 1, true), "selecting a blind remembers the button for a later retry")

-- A draw error that is not the missing panel must still surface. Wild Odds
-- must not be swallowed just because the guard wraps the queue.
queued = {}
local mgr2 = { add_event = function(self, ev) queued[#queued + 1] = ev end }
B.protect(mgr2, function()
	mgr2:add_event({ func = function() error("wild_odds broke the draw") end })
end, function() return true end, function() end)
local surfaced, err = pcall(queued[1].func)
ok(not surfaced and tostring(err):find("wild_odds", 1, true), "a Wild Odds failure is not treated as a finished event")

-- Match start -> first blind, host and guest. Normal mode and Gambel Time.
local Core = dofile("networking/p2p_server.lua")
local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	c.box = msgs
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local function first_blind(mode, lives)
	local S = Core.new({ now = function() return 1000 end, log = function() end })
	local host, guest = client(S, "Ann~1"), client(S, "Bob~2")
	S:receive(host, { action = "createLobby", gameMode = mode })
	local code = host.last("joinedLobby").code
	S:receive(guest, { action = "joinLobby", code = code })
	if lives then S:receive(host, { action = "lobbyOptions", match_settings = 1, starting_lives = lives }) end
	guest.isReadyLobby = true
	S:receive(host, { action = "startGame" })
	ok(host.last("startGame") and guest.last("startGame"), mode .. ": host and guest both enter the match")
	ok(host.lobby and #host.lobby.players == 2, mode .. ": the host's seat is still in the roster")
	S:receive(host, { action = "readyBlind" })
	S:receive(guest, { action = "readyBlind" })
	ok(host.last("startBlind") and guest.last("startBlind"), mode .. ": the first blind starts for both")
end
first_blind("attrition")
first_blind("gambel_time", 4)
local solo = Core.new({ now = function() return 1000 end, log = function() end })
local house = client(solo, "Ada~1")
solo:receive(house, { action = "createLobby", gameMode = "gambel_time" })
solo:receive(house, { action = "startGame" })
ok(house.last("startGame") and house.lobby.isInGame, "solo Gambel Time starts against The House")
solo:receive(house, { action = "setAnte", ante = 1 })
local table_msg = house.last("gambelTable")
ok(table_msg and table_msg.ante == 1 and type(table_msg.spin) == "string", "solo ante 1 gets a table spin before the first hand")
-- The reported run landed on wild_odds. Applying it only marks the local flag.
MP = MP or {}
MP.GAME = { gambel_wild = false }
MP.LOBBY = { config = { gamemode = "gamemode_mp_gambel_time" } }
MP.load_mp_file = function(p) return dofile(p) end
dofile("lib/smods_compat.lua")
local saved_g = G
dofile("lib/gambel.lua")
G = {
	blind_select = { alignment = { offset = {} } },
	GAME = {
		round_resets = { ante = 1, hands = 4, discards = 4 },
		current_round = { hands_left = 4, discards_left = 4 },
		dollars = 4, interest_amount = 1, interest_cap = 5, inflation = 0,
	},
}
MP.GAMBEL.apply_table("wild_odds", 1)
ok(MP.GAME.gambel_wild == true, "wild_odds at ante 1 is applied immediately")
ok(MP.GAME.gambel_committed == nil, "the table spin does not wait for a wheel payout")
local doubled_n, doubled_d = MP.UTILS.wrap_probability_vars(function(_, n, d) return n, d end)({ ability = {} }, 1, 4, "wild", false, nil)
ok(doubled_n == 2 and doubled_d == 4, "wild odds doubles the chance and does not throw")
local solo_dealt = false
local solo_q = {}
local solo_mgr = { add_event = function(self, ev) solo_q[#solo_q + 1] = ev end }
B.protect(solo_mgr, function()
	solo_mgr:add_event({ func = function()
		G.blind_select.alignment.offset.y = 1
		G.blind_select = nil
		return true
	end })
	solo_mgr:add_event({ func = function() solo_dealt = true; return true end })
end, function() return G.blind_select end, function() end)
solo_q[1].func()
solo_q[2].func()
ok(solo_dealt, "after wild_odds, the opening draw still runs once the panel closes")
G = saved_g
solo:receive(house, { action = "readyBlind" })
ok(not house.last("startBlind"), "solo Gambel Time deals its own first blind, with no Nemesis to wait for")

print("PASS: blind select guard")
