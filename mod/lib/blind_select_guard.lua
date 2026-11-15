-- Balatro's G.FUNCS.select_blind (functions/button_callbacks.lua, the
-- trigger='before', delay=0.2 event around line 2572 in 1.0.1o) does
-- G.blind_select.alignment.offset = ... with no nil check. A second select,
-- or leaving the run during that 0.2s, removes G.blind_select first and the
-- queued event crashes. This file only decides when a select is still safe
-- and wraps the events the vanilla function queues.
MP = MP or {}
MP.BLIND_GUARD = MP.BLIND_GUARD or {}
local B = MP.BLIND_GUARD

function B.allow(s)
	s = s or {}
	if s.selecting then return false end
	if not s.blind_select then return false end
	if not s.context then return false end
	return true
end

function B.shield(ev, still, clear)
	if type(ev) ~= "table" or type(ev.func) ~= "function" then return ev end
	local fn = ev.func
	-- Vanilla select_blind queues several events. The 0.2s one removes
	-- G.blind_select. The later one is new_round's draw. Skipping every
	-- event once the panel is gone also skips that draw, so round 1 starts
	-- with an empty hand. Run the event. Only a crash on a nil panel is swallowed.
	ev.func = function(...)
		local ok, ret = pcall(fn, ...)
		if not ok then
			if tostring(ret):find("blind_select", 1, true) then
				if clear then clear() end
				return true
			end
			error(ret, 0)
		end
		if still and not still() and clear then clear() end
		return ret
	end
	return ev
end

function B.protect(mgr, during, still, clear)
	if not (mgr and mgr.add_event) then return during() end
	local add = mgr.add_event
	mgr.add_event = function(self, ev, ...)
		if type(ev) == "table" then B.shield(ev, still, clear) end
		return add(self, ev, ...)
	end
	local ok, err = pcall(during)
	mgr.add_event = add
	if not ok then
		if clear then clear() end
		error(err, 0)
	end
end

return B
