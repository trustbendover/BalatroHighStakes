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

local function u32(n)
	n = n % 4294967296
	if n < 0 then n = n + 4294967296 end
	return n
end

--- Low 32 bits of a product. Lua numbers are doubles, so this is split into 16-bit halves.
local function mul32(a, b)
	a, b = u32(a), u32(b)
	local a0, b0 = a % 65536, b % 65536
	local a1 = (a - a0) / 65536
	local b1 = (b - b0) / 65536
	local mid = (a1 * b0 + a0 * b1) % 65536
	return u32(a0 * b0 + mid * 65536)
end

local function bxor(a, b)
	if bit and bit.bxor then return u32(bit.bxor(a, b)) end
	local r, p = 0, 1
	a, b = u32(a), u32(b)
	for _ = 1, 32 do
		local abit, bbit = a % 2, b % 2
		if abit ~= bbit then r = r + p end
		a, b, p = (a - abit) / 2, (b - bbit) / 2, p * 2
	end
	return r
end

--- 32-bit FNV-1a. The older G.roll multiply loses bits in a double, and that
--- made one colour almost certain. This matches Math.imul on the server.
local function fnv32(s)
	local h = 2166136261
	for i = 1, #s do
		h = mul32(bxor(h, s:byte(i)), 16777619)
	end
	return h
end

local function mix(seed, ante, salt)
	local s = tostring(seed or "house") .. ":" .. tostring(math.floor(tonumber(ante) or 1)) .. ":" .. tostring(salt or "")
	return fnv32(s)
end

local ACES = { "H", "D", "S", "C" }

--- One Ace. Hearts and diamonds are red, spades and clubs are black.
--- One 32-bit mix picks the suit, so each suit is its own card and the colour
--- stays about half and half. A missing or other guess still wins on red.
--- The guess is not part of the mix, so it cannot steer the card.
function G.flip(seed, id, ante, money, choice)
	local stake = G.stake(money)
	if stake < 1 then return { ok = false, reason = "low", stake = 0, delta = 0, money = G.money(money) } end
	local suit = ACES[(mix(seed, ante, "ace:" .. tostring(id)) % 4) + 1]
	local drawn = (suit == "H" or suit == "D") and "red" or "black"
	if choice ~= "red" and choice ~= "black" then choice = nil end
	local won = choice and (choice == drawn) or (not choice and drawn == "red")
	won = won and true or false
	local delta = won and stake or -stake
	return {
		ok = true, won = won, stake = stake, delta = delta, money = G.money(money) + delta,
		drawn = drawn, suit = suit, choice = choice,
	}
end

function G.wheel(seed, id, ante, money)
	local prize = G.WHEEL[G.roll(seed, ante, "wheel:" .. tostring(id), #G.WHEEL)]
	local delta = 0
	if prize.id == "cash" then delta = prize.amount or 0
	elseif prize.id == "tax" then delta = -math.min(prize.amount or G.TAX, G.money(money)) end
	return { ok = true, id = prize.id, amount = prize.amount, delta = delta, money = G.money(money) + delta }
end

--- Which wedge a host result lands on. Cash $8 and cash $20 are different wedges.
function G.wheel_index(msg)
	msg = msg or {}
	local amount = tonumber(msg.amount)
	if amount == nil and (msg.id == "cash" or msg.id == "tax") then amount = math.abs(tonumber(msg.delta) or 0) end
	if amount == 0 then amount = nil end
	for i, prize in ipairs(G.WHEEL) do
		if prize.id == msg.id and (not prize.amount or not amount or prize.amount == amount) then return i end
	end
	return 1
end

--- Rotation that puts wedge `index` under a pointer at the top, after `turns` extra spins.
function G.wheel_rotation(index, turns)
	local n = #G.WHEEL
	index = math.floor(tonumber(index) or 1)
	if index < 1 then index = 1 end
	if index > n then index = n end
	local slice = (2 * math.pi) / n
	turns = tonumber(turns) or 4
	return -((index - 0.5) * slice) - turns * 2 * math.pi
end

--- The wedge whose centre is nearest the top pointer.
function G.wheel_under(rotation)
	local n = #G.WHEEL
	local slice = (2 * math.pi) / n
	local a = (-(tonumber(rotation) or 0)) % (2 * math.pi)
	local idx = math.floor((a / slice) + 1e-7) + 1
	if idx > n then idx = ((idx - 1) % n) + 1 end
	if idx < 1 then idx = 1 end
	return idx
end

--- A shop bet stays used until the ante changes. Reopening the shop, a booster, or a reroll does not clear it.
function G.keep_bet(bet_ante, ante, sent)
	bet_ante, ante = tonumber(bet_ante), tonumber(ante)
	if bet_ante and ante and bet_ante ~= ante then return false end
	return sent and true or false
end

--- Ease-out. 0 at the start, 1 at the landing, fast then slow.
function G.wheel_ease(t)
	t = tonumber(t) or 0
	if t < 0 then t = 0 end
	if t > 1 then t = 1 end
	local u = 1 - t
	return 1 - u * u * u
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
