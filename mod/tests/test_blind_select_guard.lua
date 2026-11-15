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
solo:receive(house, { action = "readyBlind" })
ok(not house.last("startBlind"), "solo Gambel Time deals its own first blind, with no Nemesis to wait for")

print("PASS: blind select guard")
