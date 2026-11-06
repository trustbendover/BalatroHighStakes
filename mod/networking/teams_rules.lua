-- Balatro High Stakes: "Teams" rules (pure Lua, no LOVE/Balatro deps).
-- Used by the in-game Steam P2P host (networking/p2p_server.lua) and the client (lobby preview).
-- The TypeScript server has the same rules in server/src/teams.ts; both are checked against
-- tests/teams_vectors.json. GPL-3.0, based on Balatro Multiplayer.
--
--  * 4 to 8 players. Even counts split evenly into teams of `teams_size` (2, 3 or 4):
--    4 = 2v2, 6 = 2v2v2 or 3v3, 8 = 2v2v2v2 or 4v4. A locked 2v2/3v3/4v4 still needs that exact count.
--  * 5 players are two teams, 3v2. 7 players are two teams, 4v3. Not 2v1 and not 5v3.
--  * The host decides who plays together. Seats in lobby order (or teams_order "3,1,2,4") are
--    cut into consecutive teams. On 3v2 and 4v3 the first seats in that order are the larger side.
--  * Every PvP blind: team score = the SUM of the teammates' scores. The lowest sum loses one
--    shared team life; a tie for lowest costs nobody a life.
--  * A short or absent side is scaled up to the larger side with the same average fill used when
--    a teammate is away (sum * larger / present), so 2 players are not automatically behind 3.
--  * Shared team lives (default 4). A team at 0 lives is out; the last team left wins.
local T = {}

T.DEFAULTS = { starting_lives = 4, size = 2, min_players = 4, max_players = 8 }
T.LETTERS = { "A", "B", "C", "D" }

function T.config(options)
	options = options or {}
	local c = { starting_lives = T.DEFAULTS.starting_lives }
	local s = tonumber(options.starting_lives)
	if s and s >= 1 and s <= 20 then c.starting_lives = math.floor(s) end
	return c
end

--- Team size for n players. Returns size, team_count or nil, reason.
function T.plan(n, options)
	n = tonumber(n) or 0
	if n < T.DEFAULTS.min_players then return nil, "needs at least 4 players" end
	if n > T.DEFAULTS.max_players then return nil, "at most 8 players" end
	-- 0.6.8 Versus formats (2v2 / 3v3 / 4v4): exactly two teams of teams_format players
	local fmt = math.floor(tonumber((options or {}).teams_format) or 0)
	if fmt >= 2 and fmt <= 4 then
		if n ~= 2 * fmt then return nil, "needs exactly " .. (2 * fmt) .. " players" end
		return fmt, 2
	end
	-- Odd versus: two teams, the first seats in host order are the larger side.
	if n == 5 then return 3, 2 end
	if n == 7 then return 4, 2 end
	local size = math.floor(tonumber((options or {}).teams_size) or T.DEFAULTS.size)
	if size < 2 or size > 4 then size = T.DEFAULTS.size end
	if n % size ~= 0 or n / size < 2 then
		-- fall back to teams of 2 (always fits an even count)
		if n % 2 ~= 0 then return nil, "needs an even split" end
		size = 2
	end
	return size, n / size
end

--- "3v2" / "4v3" when the sides differ, "2v2" when two equal teams, else nil.
function T.matchup(n, options)
	local size, count = T.plan(n, options)
	if not size or count ~= 2 then return nil end
	local other = n - size
	if other < 1 then return nil end
	return tostring(size) .. "v" .. tostring(other)
end

--- Seat order (1-based seat numbers) from the teams_order option; identity when invalid.
function T.order(n, options)
	local raw = tostring((options or {}).teams_order or "")
	local seen, list = {}, {}
	for num in raw:gmatch("%d+") do
		local v = tonumber(num)
		if v < 1 or v > n or seen[v] then list = nil; break end
		seen[v] = true
		list[#list + 1] = v
	end
	if not list or #list ~= n then
		list = {}
		for i = 1, n do list[i] = i end
	end
	return list
end

--- { [id] = "A" | "B" | ... } for the ids in lobby order, or nil + reason.
function T.assign(ids, options)
	local size, count = T.plan(#ids, options)
	if not size then return nil, count end
	local order = T.order(#ids, options)
	local r = {}
	for pos, seat in ipairs(order) do
		r[ids[seat]] = T.LETTERS[math.floor((pos - 1) / size) + 1]
	end
	return r, size, count
end

local function log10(x) return math.log(x) / math.log(10) end

--- Comparable value of a team. scores: parsed scores { ec, c, e } of the members who played.
--- size: full team size (missing members are filled in with the team average).
function T.team_value(scores, size)
	local n = #scores
	size = math.max(size or n, n)
	local ee, big = false, false
	for _, s in ipairs(scores) do
		if (s.ec or 0) > 0 then ee = true end
		if (s.e or 0) > 290 then big = true end
	end
	if ee then
		local sorted = {}
		for i, s in ipairs(scores) do sorted[i] = s end
		return { tier = 2, list = sorted, size = size }
	end
	if not big then
		local sum = 0
		for _, s in ipairs(scores) do sum = sum + (s.c or 0) * 10 ^ (s.e or 0) end
		if n < size and n > 0 then sum = sum * size / n end
		return { tier = 0, v = sum }
	end
	local logs = {}
	for _, s in ipairs(scores) do
		if (s.c or 0) > 0 then logs[#logs + 1] = log10(s.c) + (s.e or 0) end
	end
	table.sort(logs, function(a, b) return a > b end)
	local m, acc = logs[1] or -math.huge, 0
	for _, l in ipairs(logs) do acc = acc + 10 ^ (l - m) end
	local v = m + log10(acc)
	if n < size and n > 0 then v = v + log10(size / n) end
	return { tier = 1, v = v }
end

local function as_log(t)
	if t.tier == 1 then return t.v end
	if t.v <= 0 then return -math.huge end
	return log10(t.v)
end

--- 1 if a > b, -1 if a < b, 0 if equal. gt/eq compare parsed scores (only needed for "ee" tiers).
function T.compare(a, b, gt, eq)
	if a.tier == 2 or b.tier == 2 then
		if a.tier ~= b.tier then return a.tier == 2 and 1 or -1 end
		-- largest scores first; missing members filled cyclically to the team size
		local function full(t)
			local l = {}
			for i, s in ipairs(t.list) do l[i] = s end
			table.sort(l, function(x, y) return gt(x, y) end)
			local n = #l
			for i = n + 1, t.size do l[i] = l[((i - 1) % n) + 1] end
			table.sort(l, function(x, y) return gt(x, y) end)
			return l
		end
		local x, y = full(a), full(b)
		for i = 1, math.max(#x, #y) do
			local p, q = x[i], y[i]
			if p and not q then return 1 elseif q and not p then return -1 end
			if not eq(p, q) then return gt(p, q) and 1 or -1 end
		end
		return 0
	end
	if a.tier == 0 and b.tier == 0 then
		if a.v == b.v then return 0 end
		return a.v > b.v and 1 or -1
	end
	local la, lb = as_log(a), as_log(b)
	if la == lb then return 0 end
	return la > lb and 1 or -1
end

--- Losing team of a PvP blind: the single lowest team. present = { A = {scores}, B = {...}, ... }
--- (only members who took part). Teams with nobody present are skipped; nil on a tie or when
--- fewer than 2 teams took part.
function T.resolve(present, size, gt, eq)
	local teams = {}
	for _, letter in ipairs(T.LETTERS) do
		local l = present[letter]
		if l and #l > 0 then teams[#teams + 1] = { letter = letter, value = T.team_value(l, size) } end
	end
	if #teams < 2 then return nil end
	local low, tied = teams[1], 1
	for i = 2, #teams do
		local c = T.compare(teams[i].value, low.value, gt, eq)
		if c < 0 then low, tied = teams[i], 1 elseif c == 0 then tied = tied + 1 end
	end
	if tied ~= 1 then return nil end
	return low.letter
end

--- Best team(s) when every team dies at once: letters of the highest team value (ties: all).
function T.best(present, size, gt, eq)
	local teams = {}
	for _, letter in ipairs(T.LETTERS) do
		local l = present[letter]
		if l and #l > 0 then teams[#teams + 1] = { letter = letter, value = T.team_value(l, size) } end
	end
	local best = {}
	for _, t in ipairs(teams) do
		if #best == 0 then best = { t }
		else
			local c = T.compare(t.value, best[1].value, gt, eq)
			if c > 0 then best = { t } elseif c == 0 then best[#best + 1] = t end
		end
	end
	local out = {}
	for i, t in ipairs(best) do out[i] = t.letter end
	return out
end

return T
