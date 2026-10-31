-- TEST ONLY (dev-local / unit tests): wraps a transport backend and injects network chaos.
-- spec "lat=150,jit=100,loss=0.05,cut_every=90,cut_for=12" (ms / probability / seconds):
--   lat+jit: every P2P frame is delayed lat..lat+jit ms
--   loss:    probability a frame is "lost" and resent: Steam P2P sends reliable + in order, so a lost
--            packet shows up as an extra 200-1000 ms delay of that frame and everything behind it
--   Frames to one peer stay in order (like Steam reliable messages).
--   cut_every/cut_for: roughly every cut_every s the link is down for cut_for s (sudden disconnect)
local C = {}
function C.parse(spec)
	local o = {}
	for k, v in tostring(spec or ""):gmatch("(%w+)=([%d%.]+)") do o[k] = tonumber(v) end
	return o
end
function C.wrap(B, spec, opts)
	opts = opts or {}
	local o = type(spec) == "table" and spec or C.parse(spec)
	local clock = opts.clock or (love and love.timer and love.timer.getTime) or os.clock
	local rnd = opts.random or math.random
	local q, W = {}, setmetatable({}, { __index = B })
	W.stats = { sent = 0, lost = 0, cut = 0 }
	local cut_until, next_cut = -1, (o.cut_every and clock() + o.cut_every * (0.5 + rnd())) or nil
	local function link_down(t)
		if next_cut and t >= next_cut then cut_until = t + (o.cut_for or 10); next_cut = t + o.cut_every * (0.5 + rnd()); W.stats.cut = W.stats.cut + 1
			if opts.log then opts.log("CHAOS: link down for " .. (o.cut_for or 10) .. " s") end end
		return t < cut_until
	end
	local function flush()
		local t = clock()
		local keep = {}
		for _, m in ipairs(q) do if t >= m.at then B.send(m.peer, m.data) else keep[#keep + 1] = m end end
		q = keep
	end
	function W.send(peer, data)
		W.stats.sent = W.stats.sent + 1
		local t = clock()
		if link_down(t) then W.stats.cut = W.stats.cut; return true end -- link cut: really gone
		local d = ((o.lat or 0) + rnd() * (o.jit or 0)) / 1000
		if rnd() < (o.loss or 0) then W.stats.lost = W.stats.lost + 1; d = d + 0.2 + rnd() * 0.8 end
		W.last_at = W.last_at or {}
		local at = math.max(t + d, W.last_at[peer] or 0) -- in order per peer
		W.last_at[peer] = at
		if at <= t then return B.send(peer, data) end
		q[#q + 1] = { peer = peer, data = data, at = at }
		return true
	end
	function W.receive()
		flush()
		local r = B.receive()
		if link_down(clock()) then return {} end
		return r
	end
	function W.poll(...) flush(); if B.poll then return B.poll(...) end end
	return W
end
return C
