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

function H.music_priority(state)
	state = state or {}
	if state.in_lobby == false then return nil end
	local mode = tostring(state.mode or "")
	if not mode:find(H.KEY, 1, true) then return nil end
	if state.watching or state.stage == "run" then return 10 end
	return nil
end

return H
