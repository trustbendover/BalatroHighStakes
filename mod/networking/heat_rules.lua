-- Heat Rush. Pure rules shared by the in-game host and the tests.
-- Clearing a blind quickly fills a meter. A full meter makes the next hand score x1.5.
-- Slow play adds nothing and never takes Heat away.
local H = {}

H.KEY = "heat_rush"
H.MAX = 100
H.MULT = 1.5
H.CASH = 3
H.SOLO_ANTE = 8
H.TAG = "tag_charm"
H.PAR_SECONDS = { small = 90, big = 120, boss = 150 }
H.PAR_HANDS = { small = 2, big = 3, boss = 4 }
H.CLEAR = 25
H.PER_HAND = 15
H.TIME = 25

function H.kind(blind)
	blind = tostring(blind or "small")
	if blind == "big" or blind == "boss" then return blind end
	return "small"
end

--- Heat earned for clearing one blind. Never negative.
function H.gain(blind, hands, seconds)
	local k = H.kind(blind)
	local g = H.CLEAR
	local saved = (H.PAR_HANDS[k] or 2) - math.max(0, math.floor(tonumber(hands) or 0))
	if saved > 0 then g = g + math.min(2, saved) * H.PER_HAND end
	if (tonumber(seconds) or 1e9) <= (H.PAR_SECONDS[k] or 90) then g = g + H.TIME end
	return g
end

--- New meter, and whether the next hand is Overdrive. The meter stays full until that hand.
function H.apply(heat, gain)
	heat = math.max(0, math.floor(tonumber(heat) or 0))
	if heat >= H.MAX then return H.MAX, true end
	local next_heat = math.min(H.MAX, heat + math.max(0, math.floor(tonumber(gain) or 0)))
	return next_heat, next_heat >= H.MAX
end

function H.spend(armed)
	if armed then return 0, false end
	return nil, false
end

--- Under par: a free reroll when very fast, otherwise +$3. Over par: nothing.
function H.reward(blind, seconds)
	local par = H.PAR_SECONDS[H.kind(blind)] or 90
	seconds = tonumber(seconds) or (par + 1)
	if seconds <= par * 0.75 then return "reroll", 0 end
	if seconds <= par then return "cash", H.CASH end
	return nil, 0
end

function H.boss_tag(blind, seconds)
	if H.kind(blind) ~= "boss" then return nil end
	if (tonumber(seconds) or 1e9) <= H.PAR_SECONDS.boss then return H.TAG end
	return nil
end

--- Multiply a plain integer score. Non-numeric scores are left alone.
function H.boost(score, armed)
	if not armed then return tostring(score or "0") end
	local n = tonumber(score)
	if not n then return tostring(score or "0") end
	return tostring(math.floor(n * H.MULT + 0.5))
end

--- Highest total Heat, then ante, then score.
function H.rank(rows)
	table.sort(rows or {}, function(a, b)
		if (a.heat or 0) ~= (b.heat or 0) then return (a.heat or 0) > (b.heat or 0) end
		if (a.ante or 0) ~= (b.ante or 0) then return (a.ante or 0) > (b.ante or 0) end
		if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
		return tostring(a.id) < tostring(b.id)
	end)
	return rows
end

-- The strip sits just above the joker row. These are game units, the same at every resolution.
H.BADGE_H = 0.5
H.BADGE_W = 7.2
H.BADGE_GAP = 0.1
H.HOVER = 0.22

function H.overlap(a, b, gap)
	gap = gap or 0
	if not (a and b) then return false end
	return a.x < b.x + b.w + gap and b.x < a.x + a.w + gap
		and a.y < b.y + b.h + gap and b.y < a.y + a.h + gap
end

--- How far above the joker area the cards can reach, including a raised hover.
function H.joker_lift(area, cards)
	local lift = H.HOVER
	local top = area and area.T and area.T.y
	if not top then return lift end
	for _, c in ipairs(cards or {}) do
		local t = c and c.T
		if t then
			local overflow = 0
			if t.h and area.T.h then overflow = math.max(0, (t.h - area.T.h) / 2) end
			local risen = 0
			if t.y then risen = math.max(0, top - t.y) end
			local extra = c.highlighted and H.HOVER or 0
			lift = math.max(lift, overflow + H.HOVER, risen + extra)
		end
	end
	return lift
end

--- {x,y,w,h} for the Heat strip. Above every joker, inside the room, clear of other HUD boxes.
function H.layout_badge(area, cards, blockers, room)
	if not (area and area.T and area.T.y and area.T.x and area.T.w) then return nil end
	local lift = H.joker_lift(area, cards)
	local y = area.T.y - lift - H.BADGE_GAP - H.BADGE_H
	local w = H.BADGE_W
	local x = area.T.x + (area.T.w - w) / 2
	if room and room.w then
		local left = room.x or 0
		if x < left then x = left end
		if x + w > left + room.w then x = left + room.w - w end
	end
	local box = { x = x, y = y, w = w, h = H.BADGE_H }
	for _, b in ipairs(blockers or {}) do
		if b and b.w and b.h and H.overlap(box, b, 0.08) then
			local ceiling = area.T.y - lift - H.BADGE_GAP
			if b.y + b.h <= ceiling and (b.x + b.w / 2) > area.T.x and (b.x + b.w / 2) < area.T.x + area.T.w then
				local under = b.y + b.h + 0.08
				if under + box.h <= ceiling then box.y = under end
			elseif b.x >= x then
				box.x = b.x - 0.08 - box.w
			else
				box.x = b.x + b.w + 0.08
			end
		end
	end
	if room and room.w then
		local left = room.x or 0
		if box.x < left then box.x = left end
		if box.x + box.w > left + room.w then box.x = math.max(left, left + room.w - box.w) end
	end
	box.above = area.T.y - lift
	return box
end

--- Apply one network message to the local meter. A leaderboard (rows only) must not
--- clear the player's own Heat: that message has no heat field.
function H.absorb(g, msg)
	g = g or {}
	if type(msg) ~= "table" then return g end
	if msg.rows then g.heat_board = msg.rows end
	if msg.heat == nil then return g end
	g.heat = tonumber(msg.heat) or 0
	g.heat_total = tonumber(msg.total) or g.heat_total or 0
	g.heat_best = tonumber(msg.best) or g.heat_best or 0
	g.heat_overdrive = msg.overdrive and true or false
	g.reward = msg.reward
	g.tag = msg.tag
	return g
end

--- 0 yellow, mid orange, full red.
function H.meter_color(heat, max)
	local cap = tonumber(max) or H.MAX or 100
	local t = 0
	if cap > 0 then t = math.max(0, math.min(1, (tonumber(heat) or 0) / cap)) end
	local function lerp(a, b, u) return a + (b - a) * u end
	if t < 0.5 then
		local u = t / 0.5
		return lerp(1, 1, u), lerp(0.86, 0.45, u), lerp(0.2, 0.08, u)
	end
	local u = (t - 0.5) / 0.5
	return lerp(1, 0.82, u), lerp(0.45, 0.08, u), lerp(0.08, 0.05, u)
end

--- Fill grows from the bottom of the meter.
function H.meter_fill(box, heat, max)
	if not box then return nil end
	local cap = tonumber(max) or H.MAX or 100
	local t = 0
	if cap > 0 then t = math.max(0, math.min(1, (tonumber(heat) or 0) / cap)) end
	local h = box.h * t
	return { x = box.x, y = box.y + box.h - h, w = box.w, h = h }
end

H.METER_W = 0.38
H.METER_H = 3.4
H.METER_LABEL = 0.95

--- Displayed fill eases toward the real Heat instead of jumping.
function H.ease_heat(shown, target, dt)
	shown = tonumber(shown) or 0
	target = tonumber(target) or 0
	local step = 1 - math.exp(-(tonumber(dt) or 0) * 7)
	local nextv = shown + (target - shown) * step
	if math.abs(target - nextv) < 0.04 then return target end
	return nextv
end

--- Short marks at 25, 50 and 75, measured from the bottom of the pill.
function H.meter_ticks(box)
	local out = {}
	if not box then return out end
	for _, mark in ipairs({ 25, 50, 75 }) do
		local t = mark / 100
		out[#out + 1] = { mark = mark, x = box.x, y = box.y + box.h * (1 - t), w = box.w }
	end
	return out
end

--- Seconds of flash when Heat first reaches the cap. Zero otherwise.
function H.meter_burst(prev, heat, max)
	local cap = tonumber(max) or H.MAX or 100
	if (tonumber(prev) or 0) < cap and (tonumber(heat) or 0) >= cap then return 0.42 end
	return 0
end

--- Vertical meter on the right, below a top-right chat and above a bottom-right deck.
function H.layout_meter(room, blockers)
	if not (room and room.w and room.h) then return nil end
	local gap = 0.16
	local left = room.x or 0
	local top = room.y or 0
	local x = left + room.w - gap - H.METER_W
	local top_limit = top + 0.25
	local bot_limit = top + room.h - 0.25
	for _, b in ipairs(blockers or {}) do
		if b and b.w and b.h and (b.x or 0) + b.w > x - 0.3 then
			local mid = (b.y or 0) + b.h / 2
			if mid < top + room.h / 2 then
				top_limit = math.max(top_limit, (b.y or 0) + b.h + gap)
			else
				bot_limit = math.min(bot_limit, (b.y or 0) - gap)
			end
		end
	end
	bot_limit = bot_limit - H.METER_LABEL
	local h = math.min(H.METER_H, bot_limit - top_limit)
	if h < 1.4 then h = 1.4 end
	local y = top_limit
	if y + h > bot_limit then y = math.max(top, bot_limit - h) end
	if x < left then x = left end
	return { x = x, y = y, w = H.METER_W, h = h, label_h = H.METER_LABEL }
end

function H.hit_meter(box, x, y)
	if not (box and x and y) then return false end
	local h = (box.h or 0) + (box.label_h or 0)
	return x >= box.x and x <= box.x + (box.w or 0) and y >= box.y and y <= box.y + h
end

function H.meter_overlaps(box, blockers, gap)
	if not box then return false end
	local label = { x = box.x, y = box.y + box.h, w = box.w, h = box.label_h or 0 }
	for _, b in ipairs(blockers or {}) do
		if H.overlap(box, b, gap or 0) or (label.h > 0 and H.overlap(label, b, gap or 0)) then return true end
	end
	return false
end

--- Flames travel the whole bar. side -1 is the left edge, 1 the right. y is 0 at the bottom.
function H.flame_tick(parts, dt, on, now)
	local out = {}
	dt = tonumber(dt) or 0
	now = tonumber(now) or 0
	for _, p in ipairs(parts or {}) do
		p.y = (p.y or 0) + (p.vy or 0.35) * dt
		p.life = (p.life or 0) - dt
		if p.life > 0 and (p.y or 0) < 1.25 then out[#out + 1] = p end
	end
	if on and #out < 36 then
		local spots = { 0.08, 0.28, 0.48, 0.68, 0.88 }
		for i, spot in ipairs(spots) do
			if #out >= 36 then break end
			local side = (i % 2 == 0) and 1 or -1
			out[#out + 1] = { side = side, y = spot, vy = 0.22 + (i % 3) * 0.06, life = 0.62, kind = (i % 3 == 0) and "ember" or "lick" }
		end
	end
	return out
end

function H.music_priority(state)
	state = state or {}
	if state.in_lobby == false then return nil end
	local mode = tostring(state.mode or "")
	if not mode:find(H.KEY, 1, true) then return nil end
	if state.watching or state.stage == "run" then return 10 end
	return nil
end

return H
