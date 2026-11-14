-- Vanilla select_blind queues a 0.2s event that indexes G.blind_select.
-- run from mod/: luajit tests/test_blind_select_guard.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local B = dofile("lib/blind_select_guard.lua")

ok(B.allow({ blind_select = true, context = true }) == true, "a live blind select with a button may run")
ok(B.allow({ blind_select = nil, context = true }) == false, "a torn-down blind select is refused")
ok(B.allow({ blind_select = true, selecting = true, context = true }) == false, "a second select while the first is in flight is refused")
ok(B.allow({ blind_select = true, context = nil }) == false, "a select with no blind context is refused")

local blind = { alignment = { offset = {} } }
local queued = {}
local mgr = { add_event = function(self, ev) queued[#queued + 1] = ev end }
local cleared = 0
B.protect(mgr, function()
	mgr:add_event({
		trigger = "before", delay = 0.2, blocking = true,
		func = function()
			blind.alignment.offset.y = 40
			return true
		end,
	})
end, function() return blind end, function() cleared = cleared + 1 end)
ok(#queued == 1, "the vanilla before-event is still queued")
blind = nil
local ran = queued[1].func()
ok(ran == true and cleared == 1, "the event returns once G.blind_select is already nil")

blind = { alignment = { offset = {} } }
queued = {}
cleared = 0
B.protect(mgr, function()
	mgr:add_event({
		trigger = "before", delay = 0.2,
		func = function()
			return blind.alignment.offset
		end,
	})
end, function() return blind end, function() cleared = cleared + 1 end)
blind = nil
ok(queued[1].func() == true and cleared == 1, "indexing a nil blind_select inside the event does not escape")

local src = io.open("ui/game/functions.lua"):read("*a")
ok(src:find("MP.BLIND_GUARD", 1, true) and src:find("selecting_blind", 1, true), "select_blind consults the guard before calling vanilla")

print("PASS: blind select guard")
