-- Gambel Time: shared table rules for 1 to 8 players.
-- Pure Lua. server/src/gambel.ts is the same rules for the reference server.
-- The host rolls; clients only display and apply the result they are sent.
local G = {}

G.KEY = "gambel_time"
G.MIN_PLAYERS = 1
G.MAX_PLAYERS = 8
G.DEFAULT_LIVES = 3
G.DEFAULT_ANTE = 6
G.TIMER = 45
G.STAKE_CAP = 50
G.POT_CASH = 8
G.TAX = 4

G.SPINS = { "double_interest", "inflation", "golden_hour", "wild_odds", "high_roller", "slim_hands" }
G.TWISTS_SOLO = { "double", "house", "allin" }
G.TWISTS = { "reverse", "double", "pot", "sabotage", "allin" }
G.WHEEL = {
	{ id = "cash", amount = 8 },
	{ id = "cash", amount = 20 },
	{ id = "tag" },
	{ id = "edition" },
	{ id = "tax", amount = 4 },
	{ id = "discard" },
	{ id = "perish" },
}

function G.is_mode(mode)
	mode = tostring(mode or "")
	return mode == G.KEY or mode == "gamemode_mp_" .. G.KEY
end

--- Stable 1-based index in 1..n from a seed, an ante, and a salt.
function G.roll(seed, ante, salt, n)
	n = math.floor(tonumber(n) or 1)
	if n < 1 then return 1 end
	local s = tostring(seed or "house") .. ":" .. tostring(math.floor(tonumber(ante) or 1)) .. ":" .. tostring(salt or "")
	local h = 2166136261
	for i = 1, #s do
		h = (h * 16777619 + s:byte(i)) % 4294967296
	end
	return (h % n) + 1
end

function G.lives(n)
	n = tonumber(n)
	if not n or n ~= n then return G.DEFAULT_LIVES end
	n = math.floor(n)
	if n < 2 then return 2 end
	if n > 5 then return 5 end
	return n
end

function G.ante_target(options)
	local n = tonumber(options and options.gambel_ante)
	if not n or n ~= n then return G.DEFAULT_ANTE end
	n = math.floor(n)
	if n < 4 then return 4 end
	if n > 12 then return 12 end
	return n
end

--- Small blind is the build-up, Big blind is the drop, Boss is the final drop.
function G.blind_phase(deck)
	deck = tostring(deck or "")
	if deck == "Boss" or deck:find("nemesis", 1, true) or deck:find("boss", 1, true) then return "final" end
	if deck == "Big" or deck:find("big", 1, true) then return "drop" end
	return "build"
end

--- Cash paid when a Big blind (the drop) starts. The boss pays through the Chaos Spin.
function G.phase_bonus(phase)
	if phase == "drop" then return 3 end
	return 0
end

--- What a wheel prize actually does. An edition or a perishable needs a real joker; otherwise it is cash.
function G.prize_plan(id, opts)
	opts = opts or {}
	if id == "edition" then
		if opts.plain_joker then return { kind = "edition" } end
		return { kind = "cash", amount = 8 }
	end
	if id == "perish" then
		if opts.mortal_joker then return { kind = "perish" } end
		return { kind = "tax", amount = 4 }
	end
	if id == "tag" then return { kind = "tag" } end
	if id == "discard" then return { kind = "discard" } end
	if id == "cash" then return { kind = "cash", amount = tonumber(opts.amount) or 0 } end
	if id == "tax" then return { kind = "tax", amount = tonumber(opts.amount) or 4 } end
	return { kind = tostring(id or "") }
end

--- How many of the lowest scores lose a life. 2-5: one. 6-8: two. Solo: none (The House).
function G.cut(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 6 then return 2 end
	if n >= 2 then return 1 end
	return 0
end

function G.table_spin(seed, ante)
	return G.SPINS[G.roll(seed, ante, "table", #G.SPINS)]
end

function G.twist(seed, ante, seq, players)
	local pool = (tonumber(players) or 1) <= 1 and G.TWISTS_SOLO or G.TWISTS
	return pool[G.roll(seed, ante, "twist:" .. tostring(seq or 1), #pool)]
end

local function played(e) return (tonumber(e.hands) or 0) >= 1 end

--- Who loses the Nemesis. better(a, b) is true when score a beats score b.
--- Reverse Stakes: the lowest score wins, and a player with no real hand cannot win.
--- A full tie (The House holds) loses nobody. Double Trouble costs 2 lives.
function G.resolve(entries, twist, better)
	entries = entries or {}
	local k = G.cut(#entries)
	local lives = twist == "double" and 2 or 1
	if k == 0 then return { losers = {}, lives = lives, hold = false } end
	local function beats(a, b)
		if a == b then return false end
		if twist == "reverse" then
			local ap, bp = played(a), played(b)
			if ap ~= bp then return ap end
			if not ap then return false end
			return better(b.score, a.score)
		end
		return better(a.score, b.score)
	end
	local hold = true
	for _, a in ipairs(entries) do
		for _, b in ipairs(entries) do
			if beats(a, b) then hold = false end
		end
	end
	if hold then return { losers = {}, lives = lives, hold = true } end
	local losers = {}
	for _, p in ipairs(entries) do
		local n = 0
		for _, q in ipairs(entries) do
			if not beats(q, p) then n = n + 1 end
		end
		if n <= k then losers[#losers + 1] = p.id end
	end
	return { losers = losers, lives = lives, hold = false }
end

--- Cash moved by Joker Pot or All-In. A joker only moves when exactly one winner
--- can take a card and a loser can give a non-eternal one. Otherwise it is cash.
function G.payout(entries, twist, losers, better)
	if twist ~= "pot" and twist ~= "allin" and twist ~= "house" then return nil end
	local lost = {}
	for _, id in ipairs(losers or {}) do lost[id] = true end
	local winners = {}
	for _, e in ipairs(entries or {}) do
		if not lost[e.id] then winners[#winners + 1] = e end
	end
	local best, tied = nil, false
	for _, e in ipairs(winners) do
		if not best then best = e
		elseif better(e.score, best.score) then best, tied = e, false
		elseif not better(best.score, e.score) then tied = true end
	end
	local to = (best and not tied) and best.id or nil
	local joker = false
	if twist == "pot" and to then
		local give = false
		for _, e in ipairs(entries) do
			if lost[e.id] and e.give then give = true end
		end
		local room = false
		for _, e in ipairs(winners) do
			if e.id == to and e.room then room = true end
		end
		joker = give and room
	end
	return {
		kind = twist == "allin" and "allin" or "pot",
		cash = G.POT_CASH,
		payout = twist == "allin" and 2 or nil,
		from = losers or {},
		to = to,
		joker = joker,
	}
end

function G.money(n)
	n = tonumber(n)
	if not n or n ~= n or n < 0 or n == math.huge then return 0 end
	return math.floor(n)
end

--- Half of the cash, at least $1, never more than the cap, and $0 when there is
--- nothing safe to bet. The result can never push the player below $0.
function G.stake(money)
	money = G.money(money)
	if money < 2 then return 0 end
	return math.min(G.STAKE_CAP, math.floor(money / 2))
end

function G.flip(seed, id, ante, money)
	local stake = G.stake(money)
	if stake < 1 then return { ok = false, reason = "low", stake = 0, delta = 0, money = G.money(money) } end
	local won = G.roll(seed, ante, "flip:" .. tostring(id), 2) == 1
	local delta = won and stake or -stake
	return { ok = true, won = won, stake = stake, delta = delta, money = G.money(money) + delta }
end

function G.wheel(seed, id, ante, money)
	local prize = G.WHEEL[G.roll(seed, ante, "wheel:" .. tostring(id), #G.WHEEL)]
	local delta = 0
	if prize.id == "cash" then delta = prize.amount or 0
	elseif prize.id == "tax" then delta = -math.min(prize.amount or G.TAX, G.money(money)) end
	return { ok = true, id = prize.id, amount = prize.amount, delta = delta, money = G.money(money) + delta }
end

--- 10 while this player is in a Gambel Time run (including a watcher). Nil in menus and other modes.
function G.music_priority(state)
	state = state or {}
	local mode = tostring(state.mode or "")
	if not mode:find(G.KEY, 1, true) then return nil end
	if state.watching or state.stage == "run" then return 10 end
	return nil
end

return G
