-- Balatro High Stakes: in-process lobby/game server (Lua port of the TypeScript
-- server: server/src/Lobby.ts + actionHandlers.ts). 2 to 8 players.
-- Used by Steam P2P mode, where the lobby host runs this inside their game.
-- Pure Lua (no LOVE / Balatro dependencies) so it can be unit-tested.
-- GPL-3.0, based on Balatro-Multiplayer/BalatroMultiplayerAPI-Server.

local Core = {}
-- Balatro High Stakes: 2 to 8 players. 1v1 Duel is exactly 2, Teams needs 4-8 (even split).
Core.MAX_PLAYERS = 8
Core.MIN_PLAYERS = 2
function Core.max_players(mode) return mode == "duel" and 2 or Core.MAX_PLAYERS end
--- nil when the lobby can start, else the reason (sent to the host as an error).
--- guests (not the host, players[1]) that are not Ready in the lobby; spectators are never waited for
function Core.unready_count(players)
	local n = 0
	for i = 2, #(players or {}) do
		local p = players[i]
		if not (p.isReadyLobby or p.spectator) then n = n + 1 end
	end
	return n
end

function Core.start_error(mode, n, options)
	if n < Core.MIN_PLAYERS then return "Need at least 2 players to start." end
	if n > Core.max_players(mode) then return "Too many players for this mode." end
	if mode == "duel" and n ~= 2 then return "1v1 Duel needs exactly 2 players." end
	if mode == "teams" then
		local size, why = Core.TEAMS and Core.TEAMS.plan(n, options)
		if not size then return "Teams " .. tostring(why or "unavailable") .. " (4, 6 or 8 players)." end
	end
	return nil
end
Core.SERVER_VERSION = "0.6.8"
Core.STARTING_LIVES = { attrition = 4, showdown = 2, survival = 1, koth = 3, teams = 4, duel = 4, deathmatch = 4 }
-- Deathmatch: seconds a disconnected player may rejoin before counting as eliminated
Core.DEATHMATCH_GRACE = 60
function Core.deathmatch_grace(options)
	local g = tonumber((options or {}).deathmatch_grace)
	if g and g >= 1 and g <= 300 then return g end
	return Core.DEATHMATCH_GRACE
end
-- 0.6.8: a player who drops keeps their seat this long (status "disconnected", PvP goes on without
-- them); rejoining within it restores their run. After it they are eliminated as before.
-- Lobby option rejoin_grace (10-900 s) overrides; Deathmatch keeps its own deathmatch_grace (60 s).
Core.REJOIN_GRACE = 180
function Core.rejoin_grace(options, mode)
	local g = tonumber((options or {}).rejoin_grace)
	if g and g == g and g > 0 then return math.max(10, math.min(900, math.floor(g))) end -- 0 / unset = mode default
	if mode == "deathmatch" then return Core.deathmatch_grace(options) end
	return Core.REJOIN_GRACE
end
-- 0.6.8: spectators (joined while a match runs and could not late join, or asked to watch).
-- They never count as players: not alive, no PvP, no win, no seat. Max this many per lobby.
Core.MAX_SPECTATORS = 8
-- what a spectator may send (everything else is ignored: spectators cannot affect the game)
Core.SPECTATOR_OK = { username = true, version = true, leaveLobby = true, lobbyInfo = true, keepAlive = true,
	keepAliveAck = true, stopGame = true, syncClient = true }
-- relays an eliminated player may still send (end-of-game screens)
Core.END_GAME_RELAYS = { getEndGameJokers = true, receiveEndGameJokers = true, getNemesisDeck = true,
	receiveNemesisDeck = true, endGameStatsRequested = true, nemesisEndGameStats = true }
--- Modes without late join (teams are fixed; Deathmatch guarantees everyone fights every PvP)
function Core.no_late_join(mode) return mode == "teams" or mode == "deathmatch" end
-- free-for-all life-loss rule for 2-8 players (networking/pvp_rules.lua), injected by the loader / tests
Core.PVP = Core.PVP or nil
-- Teams rules module (networking/teams_rules.lua), injected by the loader / tests
Core.TEAMS = Core.TEAMS or nil
-- King of the Hill rules module (networking/koth_rules.lua), injected by the loader / tests
Core.KOTH = Core.KOTH or nil
Core.EMPTY_LOBBY_TTL = 10 * 60
-- Host migration (Steam P2P): seconds the new host waits for everyone to reconnect before
-- the missing players count as disconnected (blinds don't start / resolve meanwhile)
Core.MIGRATION_HOLD = 15

---------------------------------------------------------------- scores
-- Score strings like "1234", "1.5e20", "ee1.2e5" (same format as InsaneInt)
local function parse_score(str)
	str = tostring(str or "0")
	local ec = 0
	while str:sub(1, 1) == "e" do
		ec = ec + 1
		str = str:sub(2)
	end
	local hash = str:find("#", 1, true)
	if hash then
		ec = ec + (tonumber(str:sub(hash + 1)) or 0)
		str = str:sub(1, hash - 1)
	end
	local c, e = str:match("^([^e]*)e(.*)$")
	if c then return { ec = ec, c = tonumber(c) or 0, e = tonumber(e) or 0, raw = str } end
	return { ec = ec, c = tonumber(str) or 0, e = 0 }
end
local function s_eq(a, b) return a.ec == b.ec and a.e == b.e and a.c == b.c end
local function s_gt(a, b)
	if a.ec ~= b.ec then return a.ec > b.ec end
	if a.e ~= b.e then return a.e > b.e end
	return a.c > b.c
end
local function s_lt(a, b) return not s_eq(a, b) and not s_gt(a, b) end
local ZERO = function() return { ec = 0, c = 0, e = 0, str = "0" } end
Core.parse_score, Core.score_gt, Core.score_eq = parse_score, s_gt, s_eq

---------------------------------------------------------------- helpers
local function filter(t, f)
	local r = {}
	for _, v in ipairs(t) do if f(v) then r[#r + 1] = v end end
	return r
end
local function find(t, f)
	for i, v in ipairs(t) do if f(v) then return v, i end end
end
local function every(t, f)
	for _, v in ipairs(t) do if not f(v) then return false end end
	return true
end
local function remove_value(t, x)
	for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end
end
local function copy(t, extra)
	local r = {}
	for k, v in pairs(t or {}) do r[k] = v end
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end
local function rand_str(chars, n)
	local s = {}
	for i = 1, n do
		local k = math.random(1, #chars)
		s[i] = chars:sub(k, k)
	end
	return table.concat(s)
end
local function base_name(u)
	local s = (tostring(u or ""):match("^([^~]*)") or ""):lower()
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s
end
Core.base_name = base_name

---------------------------------------------------------------- server
local Server = {}
Server.__index = Server

function Core.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Server)
	self.lobbies = {}
	self.now = opts.now or os.time
	self.log = opts.log or function() end
	self.next_id = 0
	return self
end

--- A new connection. send(tbl) delivers an action table to that client;
--- close() drops the transport (optional).
function Server:connect(send, close)
	self.next_id = self.next_id + 1
	local c = {
		id = string.format("p%d-%s", self.next_id, rand_str("abcdef0123456789", 6)),
		send = send,
		close = close or function() end,
		reconnectToken = rand_str("abcdef0123456789", 32),
		username = "Guest", modHash = "NULL", lobby = nil,
		isReadyLobby = false, isReady = false, firstReady = false,
		lives = 5, score = ZERO(), handsLeft = 4, playedThisBlind = false,
		ante = 1, skips = 0, furthestBlind = 0,
		roundLivesBlocker = false, timerLivesBlocker = false,
		eliminated = false, pvpDone = false, pvpTimerFailed = false,
		inPvp = false, blindSeq = 0, sitOut = false, team = nil,
		location = "loc_selecting", isCached = true,
	}
	c.send({ action = "connected" })
	c.send({ action = "version" })
	return c
end

local function sendA(c, t) if c and c.send then c.send(t) end end

---------------------------------------------------------------- client-ish
function Server:reset_blocker(c) c.roundLivesBlocker = false; c.timerLivesBlocker = false end

function Server:set_location(c, loc)
	c.location = loc
	if c.lobby then
		for _, p in ipairs(c.lobby.players) do
			if p ~= c then sendA(p, { action = "enemyLocation", location = loc, playerId = c.id }) end
		end
	end
end

function Server:lose_life(c, cause)
	cause = cause or "round"
	if cause == "timer" then
		if c.timerLivesBlocker then return end
		c.timerLivesBlocker = true
	else
		if c.roundLivesBlocker then return end
		c.roundLivesBlocker = true
	end
	c.lives = c.lives - 1
	local b = c.lobby and self.book_entry and self:book_entry(c.lobby, c)
	if b then b.livesLost = (b.livesLost or 0) + 1 end
	sendA(c, { action = "playerInfo", lives = c.lives })
	if c.lobby then
		local info = self:enemy_info(c, true)
		for _, p in ipairs(c.lobby.players) do if p ~= c then sendA(p, info) end end
	end
end

---------------------------------------------------------------- lobby
function Server:new_lobby(host, gameMode)
	local code
	repeat code = rand_str("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 5) until not self.lobbies[code]
	local L = {
		code = code, players = { host }, gameMode = gameMode or "attrition", options = {},
		firstReadyAt = nil, slots = {}, isInGame = false, seed = nil,
		blindActive = false, blindSeq = 0, emptySince = nil,
	}
	self.lobbies[code] = L
	host.lobby = L
	host.isReadyLobby = false
	sendA(host, { action = "joinedLobby", code = code, type = L.gameMode, reconnectToken = host.reconnectToken })
	return L
end

function Server:alive(L) return filter(L.players, function(p) return not p.eliminated end) end
function Server:away_alive(L) return filter(L.slots, function(s) return not s.old.eliminated and s.old.lives > 0 end) end
function Server:spectators(L) return filter(L.players, function(p) return p.spectator end) end
function Server:seated(L) return filter(L.players, function(p) return not p.spectator end) end
function Server:participants(L) return filter(self:alive(L), function(p) return not p.sitOut end) end

function Server:broadcast(L, t) for _, p in ipairs(L.players) do sendA(p, t) end end
--- Teams: same team (never true outside a running teams game).
function Server:is_teammate(a, b)
	return a ~= b and a.team ~= nil and a.team == b.team and a.lobby ~= nil and a.lobby.gameMode == "teams"
end
--- Nemesis-style relays. In Teams they only reach the other teams.
function Server:to_opponents(c, t)
	if not c.lobby then return end
	for _, p in ipairs(c.lobby.players) do if p ~= c and not self:is_teammate(c, p) then sendA(p, t) end end
end
function Server:to_others(c, t)
	if not c.lobby then return end
	for _, p in ipairs(c.lobby.players) do if p ~= c then sendA(p, t) end end
end

function Server:enemy_info(p, with_score)
	return {
		action = "enemyInfo", playerId = p.id, username = p.username, handsLeft = p.handsLeft,
		score = with_score and (p.score.str or "0") or nil, noScore = (not with_score) or nil,
		skips = p.skips, lives = p.lives, eliminated = p.eliminated, ante = p.ante,
		away = (p.lobby == nil) or nil, spectator = p.spectator or nil,
	}
end

function Server:lobby_info(L)
	local host = L.players[1]
	if not host then return end
	local players = {}
	local preview = nil
	if L.gameMode == "teams" and Core.TEAMS then
		local ids = {}
		for i, p in ipairs(L.players) do ids[i] = p.id end
		preview = Core.TEAMS.assign(ids, L.options)
	end
	for i, p in ipairs(L.players) do
		players[i] = { id = p.id, username = p.username, hash = p.modHash, cached = p.isCached, ready = p.isReadyLobby,
			isHost = i == 1, lives = p.lives, eliminated = p.eliminated, team = preview and (p.team or preview[p.id]) or nil,
			spectator = p.spectator or nil }
	end
	local away = {}
	local now, grace = self.now(), Core.rejoin_grace(L.options, L.gameMode)
	for i, s in ipairs(L.slots) do
		away[i] = { id = s.old.id, username = s.old.username, lives = s.old.lives, eliminated = s.old.eliminated or nil,
			left = (L.isInGame and s.since and not s.old.eliminated) and math.max(0, math.floor(grace - (now - s.since))) or nil }
	end
	for _, p in ipairs(L.players) do
		local a = { action = "lobbyInfo", host = host.username, hostHash = host.modHash, isHost = p == host,
			hostCached = host.isCached, players = players, you = p.id, maxPlayers = Core.max_players(L.gameMode), away = away, inGame = L.isInGame }
		local g = L.players[2]
		if g then
			a.guest, a.guestHash, a.guestCached = g.username, g.modHash, g.isCached
			a.guestReady = every(L.players, function(o) return o == host or o.isReadyLobby end)
		end
		sendA(p, a)
	end
	self:broadcast(L, { action = "handyMPExtensionLobbyEnabled", enabled = false })
end

function Server:reset_players(L)
	L.isInGame = false
	for _, p in ipairs(L.players) do
		p.isReady, p.firstReady = false, false
		self:reset_blocker(p)
		self:set_location(p, "Blind Select")
		p.furthestBlind, p.skips, p.score, p.handsLeft = 0, 0, ZERO(), 4
		p.pvpDone, p.pvpTimerFailed, p.playedThisBlind, p.inPvp, p.sitOut, p.ante = false, false, false, false, false, 1
		p.team = nil
		p.runState = nil
	end
	self:promote_spectators(L)
	L.firstReadyAt, L.blindActive, L.slots = nil, false, {}
	L.teamLives = nil
	L.elimOrder, L.winnerId = nil, nil
end

--- Spectators become normal lobby members for the next match while there are free seats.
function Server:promote_spectators(L)
	local seated = #self:seated(L)
	for _, p in ipairs(L.players) do
		if p.spectator and seated < Core.max_players(L.gameMode) then
			p.spectator, p.eliminated, p.sitOut = nil, false, false
			seated = seated + 1
		end
	end
end

--- 0.6.8: spectators learn when the match is over (they get no winGame / loseGame).
local function notify_match_over(self, L)
	if self.stats_finish then self:stats_finish(L) end
	for _, p in ipairs(L.players) do
		if p.spectator then sendA(p, { action = "matchOver", winnerId = L.winnerId }) end
	end
end

function Server:destroy(L)
	L.slots = {}
	self.lobbies[L.code] = nil
end

function Server:check_game_over(L)
	if not L.isInGame then return true end
	local over = self:check_game_over_inner(L)
	if not L.isInGame then notify_match_over(self, L) end
	return over
end

function Server:check_game_over_inner(L)
	-- Deathmatch: a player at 0 lives during a PvP blind dies when that PvP resolves, so players
	-- who die in the same PvP die together (simultaneous final deaths -> highest score wins).
	if L.gameMode == "deathmatch" and L.blindActive then return false end
	local dying = {}
	for _, p in ipairs(L.players) do
		if not p.eliminated and p.lives <= 0 then dying[#dying + 1] = p end
	end
	local survivors = #filter(L.players, function(p) return not p.eliminated and p.lives > 0 end) + #self:away_alive(L)
	local spared = {}
	if survivors == 0 and #dying > 0 and not self:teams_active(L) then
		-- nobody left standing: the highest score among those dying now wins (ties: all of them)
		local best = nil
		for _, p in ipairs(dying) do if best == nil or s_gt(p.score, best) then best = p.score end end
		for _, p in ipairs(dying) do if s_eq(p.score, best) then spared[p] = true end end
	end
	for _, p in ipairs(dying) do
		p.eliminated = true
		if not spared[p] then sendA(p, { action = "loseGame" }) end
		for _, o in ipairs(L.players) do
			if o ~= p then sendA(o, { action = "playerEliminated", playerId = p.id, username = p.username }) end
		end
		L.elimOrder = L.elimOrder or {}
		L.elimOrder[#L.elimOrder + 1] = p.id
	end
	if next(spared) then
		for p in pairs(spared) do sendA(p, { action = "winGame", reason = "final_score" }); L.winnerId = L.winnerId or p.id end
		L.isInGame, L.blindActive, L.slots = false, false, {}
		self:deathmatch_broadcast(L)
		return true
	end
	if #dying > 0 or L.gameMode == "deathmatch" then self:deathmatch_broadcast(L) end
	local alive = self:alive(L)
	if self:teams_active(L) then
		-- Teams: the game ends when only one team has anyone left (connected or seat held)
		local left, n = {}, 0
		for _, p in ipairs(alive) do if p.team and not left[p.team] then left[p.team] = true; n = n + 1 end end
		for _, sl in ipairs(self:away_alive(L)) do
			if sl.old.team and not left[sl.old.team] then left[sl.old.team] = true; n = n + 1 end
		end
		if n <= 1 then
			for _, p in ipairs(alive) do sendA(p, { action = "winGame", reason = "teams" }) end
			L.isInGame, L.blindActive, L.slots = false, false, {}
			return true
		end
		return false
	end
	if #alive + #self:away_alive(L) <= 1 then
		if alive[1] then sendA(alive[1], { action = "winGame" }) end
		L.isInGame, L.blindActive, L.slots = false, false, {}
		L.winnerId = alive[1] and alive[1].id or nil
		self:deathmatch_broadcast(L)
		return true
	end
	return false
end

--- Deathmatch standings for everyone in the lobby (also eliminated players who spectate).
function Server:deathmatch_broadcast(L)
	if L.gameMode ~= "deathmatch" then return end
	local alive, out = {}, {}
	for _, p in ipairs(L.players) do
		if not p.eliminated then alive[#alive + 1] = { id = p.id, username = p.username, lives = p.lives } end
	end
	for _, sl in ipairs(L.slots) do
		if not sl.old.eliminated then alive[#alive + 1] = { id = sl.old.id, username = sl.old.username, lives = sl.old.lives, away = true } end
	end
	for i, id in ipairs(L.elimOrder or {}) do out[#out + 1] = { id = id, place = #alive + (#(L.elimOrder) - i) + 1 } end
	for _, p in ipairs(L.players) do
		sendA(p, { action = "deathmatchUpdate", you = p.id, alive = alive, out = out,
			running = L.isInGame and true or false, winnerId = (not L.isInGame) and L.winnerId or nil })
	end
end

--- A held seat whose grace ran out counts as eliminated (all modes since 0.6.8; the seat stays,
--- so a late reconnect comes back as a spectator of its own seat).
function Server:expire_slot(L, slot)
	local o = slot.old
	if o.eliminated then return end
	self.log("Player " .. tostring(o.username) .. " did not rejoin in time: eliminated")
	o.eliminated, o.lives = true, 0
	L.elimOrder = L.elimOrder or {}
	L.elimOrder[#L.elimOrder + 1] = o.id
	for _, p in ipairs(L.players) do
		sendA(p, { action = "playerEliminated", playerId = o.id, username = o.username, reason = "disconnected" })
		sendA(p, self:enemy_info(o, true))
	end
	self:deathmatch_broadcast(L)
	self:teams_broadcast(L)
	if self:check_game_over(L) then return end
	self:try_start_blind(L)
	self:try_resolve_pvp(L)
	self:lobby_info(L)
end
Server.deathmatch_expire = Server.expire_slot

function Server:try_start_blind(L)
	if not L.isInGame or L.blindActive or L.migration then return false end
	local alive = self:alive(L)
	if #alive == 0 or not every(alive, function(p) return p.isReady end) then return false end
	L.blindSeq = L.blindSeq + 1
	for _, p in ipairs(alive) do
		p.sitOut, p.inPvp, p.blindSeq = false, true, L.blindSeq
		p.isReady, p.score, p.handsLeft, p.playedThisBlind, p.pvpDone = false, ZERO(), 4, false, false
		self:reset_blocker(p)
	end
	local first = find(alive, function(p) return p.firstReady end)
	L.firstReadyAt, L.blindActive = nil, true
	self:broadcast(L, { action = "startBlind", firstPlayer = first and (first == L.players[1] and "host" or "guest") or nil,
		firstPlayerId = first and first.id or nil })
	return true
end

function Server:try_resolve_pvp(L)
	if not L.isInGame or not L.blindActive or L.migration then return end
	local alive = self:participants(L)
	if #alive == 0 then return end
	if not every(alive, function(p) return p.pvpDone or p.handsLeft < 1 end) then return end
	L.blindActive = false
	for _, p in ipairs(L.players) do p.inPvp = false end
	if #alive == 1 then
		local p = alive[1]
		p.firstReady, p.pvpDone, p.pvpTimerFailed = false, false, false
		sendA(p, { action = "endPvP", lost = false, loserIds = {}, opponentsAway = true })
		return
	end
	if self:teams_active(L) then return self:resolve_teams_pvp(L, alive) end
	local timerLosers = filter(alive, function(p) return p.pvpTimerFailed end)
	local roundLosers = {}
	if #timerLosers == 0 then
		-- 2-5 players: the single lowest score; 6-8: the bottom two (networking/pvp_rules.lua)
		local entries = {}
		for i, p in ipairs(alive) do entries[i] = { id = p.id, score = p.score } end
		local ids = Core.PVP and Core.PVP.losers(entries, function(a, b) return not s_gt(a, b) end) or {}
		local lose = {}
		for _, id in ipairs(ids) do lose[id] = true end
		roundLosers = filter(alive, function(p) return lose[p.id] end)
	end
	local koth_ev = self:koth_resolve(L, alive, roundLosers)
	if koth_ev and koth_ev.shieldedId then
		roundLosers = filter(roundLosers, function(p) return p.id ~= koth_ev.shieldedId end)
	end
	for _, p in ipairs(roundLosers) do self:lose_life(p, "round") end
	do
		local lost = {}
		for _, p in ipairs(roundLosers) do lost[p] = true end
		for _, p in ipairs(timerLosers) do lost[p] = true end
		self:stats_pvp(L, alive, lost)
	end
	for _, p in ipairs(alive) do p.firstReady, p.pvpDone, p.pvpTimerFailed = false, false, false end
	-- everyone (also eliminated players and spectators) sees the new scores and lives
	for _, p in ipairs(L.players) do
		for _, o in ipairs(L.players) do if o ~= p and not o.spectator then sendA(p, self:enemy_info(o, true)) end end
	end
	if koth_ev then
		self:koth_broadcast(L, koth_ev)
		if koth_ev.winnerId and self:koth_hill_win(L, koth_ev.winnerId) then return end
	end
	if self:check_game_over(L) then return end
	local losers, ids = {}, {}
	for _, p in ipairs(roundLosers) do losers[p] = true; ids[#ids + 1] = p.id end
	for _, p in ipairs(timerLosers) do losers[p] = true; ids[#ids + 1] = p.id end
	for _, p in ipairs(alive) do
		sendA(p, { action = "endPvP", lost = losers[p] or false, pvpTimerLost = (#timerLosers > 0) or nil, loserIds = ids })
	end
end

---------------------------------------------------------------- 0.6.8 match stats
-- The host keeps a stats book per player (L.book, keyed by player id) for the whole match:
-- damage (your score in every PvP blind = the chips you threw at your opponents, all modes),
-- PvPs played / won and lives lost come from the host itself; best hand, jokers, money earned
-- and highest ante are reported by each player's game ("statsReport", sanitised, only ever go
-- up). The book is part of the host snapshot, so it survives host migration and rejoin.
-- At match end the host builds one table + awards and sends the same "matchStats" to everyone
-- in the lobby (spectators too).
Core.STATS_MAX_LINEUP = 8
local function score_num(s)
	if type(s) ~= "table" then s = parse_score(s) end
	if (s.ec or 0) > 0 then return 1e308 end
	local v = (tonumber(s.c) or 0) * 10 ^ (tonumber(s.e) or 0)
	if v ~= v then return 0 end
	return math.min(v, 1e308)
end
Core.score_num = score_num

local function stat_num(v, max)
	v = tonumber(v)
	if not v or v ~= v or v < 0 then return nil end
	return math.floor(math.min(v, max or 1e9))
end

function Server:book_entry(L, p)
	if not (L.book and p and p.id) then return nil end
	local b = L.book[p.id]
	if not b then
		b = { id = p.id, name = p.username, dealt = 0, pvps = 0, pvpWon = 0, livesLost = 0, best = "0",
			jokers = 0, seen = 0, money = 0, ante = 1 }
		L.book[p.id] = b
	end
	b.name = p.username or b.name
	b.team = p.team or b.team
	return b
end

function Server:stats_start(L)
	L.book, L.teamBook, L.lastStats = {}, {}, nil
	for _, p in ipairs(self:seated(L)) do self:book_entry(L, p) end
end

--- One PvP blind resolved: everyone who took part dealt their score; losers = set of players.
function Server:stats_pvp(L, alive, losers)
	if not L.book then return end
	for _, p in ipairs(alive) do
		local b = self:book_entry(L, p)
		if b then
			b.dealt = math.min(1e308, (b.dealt or 0) + score_num(p.score))
			b.pvps = (b.pvps or 0) + 1
			if not losers[p] then b.pvpWon = (b.pvpWon or 0) + 1 end
		end
	end
end

local HAND_OK = "^[%w%s%-'&%.]+$"
local KEY_OK = "^[%w_%-]+$"
--- A player's own numbers (sanitised; values only go up, so a rejoin can't lower them).
function Server:stats_report(L, c, a)
	local b = self:book_entry(L, c)
	if not b then return end
	local best = tostring(a.best or "")
	if #best > 0 and #best <= 40 and best:match("^[%deE%.%+%-#]+$") then
		local s = parse_score(best)
		if s_gt(s, parse_score(b.best or "0")) then
			b.best = best
			local h = tostring(a.bestHand or "")
			b.bestHand = (#h <= 24 and h:match(HAND_OK)) and h or nil
		end
	end
	local j = stat_num(a.jokers, 999)
	if j then b.jokers = j end
	if type(a.lineup) == "table" then
		local l = {}
		for i = 1, math.min(#a.lineup, Core.STATS_MAX_LINEUP) do
			local k = tostring(a.lineup[i] or "")
			if #k <= 40 and k:match(KEY_OK) then l[#l + 1] = k end
		end
		b.lineup = l
	end
	for _, f in ipairs({ "seen", "money", "ante" }) do
		local v = stat_num(a[f])
		if v and v > (b[f] or 0) then b[f] = v end
	end
end

--- Pure: final table rows (best place first), team totals and awards from a stats book.
--- out[id] = true for players who are out; order = elimination order (first out first).
function Core.match_table(book, out, order, teams_mode)
	local rows, place_of = {}, {}
	local n = 0
	for _ in pairs(book or {}) do n = n + 1 end
	-- winners: everyone still in; then the reverse elimination order
	local p = 1
	local alive = {}
	for id in pairs(book or {}) do if not out[id] then alive[#alive + 1] = id end end
	table.sort(alive)
	for _, id in ipairs(alive) do place_of[id] = 1 end
	if #alive > 0 then p = 2 end
	local seen = {}
	for i = #(order or {}), 1, -1 do
		local id = order[i]
		if book[id] and not place_of[id] and not seen[id] then seen[id] = true; place_of[id] = p; p = p + 1 end
	end
	for id in pairs(book or {}) do if not place_of[id] then place_of[id] = p end end
	for id, b in pairs(book or {}) do
		local r = {}
		for k, v in pairs(b) do r[k] = v end
		r.place, r.out = place_of[id], out[id] and true or false
		rows[#rows + 1] = r
	end
	table.sort(rows, function(a, b)
		if a.place ~= b.place then return a.place < b.place end
		if (a.dealt or 0) ~= (b.dealt or 0) then return (a.dealt or 0) > (b.dealt or 0) end
		return tostring(a.name) < tostring(b.name)
	end)
	-- awards: the first row (best place) wins ties
	local function best_by(f, better)
		local w
		for _, r in ipairs(rows) do if w == nil or better(f(r), f(w)) then w = r end end
		return w and w.id or nil
	end
	local gt = function(x, y) return x > y end
	local awards = {}
	if #rows > 0 then
		awards.damage = best_by(function(r) return r.dealt or 0 end, gt)
		awards.best = best_by(function(r) return parse_score(r.best or "0") end, s_gt)
		awards.jokers = best_by(function(r) return math.max(r.seen or 0, r.jokers or 0) end, gt)
		awards.lives = best_by(function(r) return -(r.livesLost or 0) end, gt)
		awards.pvp = best_by(function(r) return r.pvpWon or 0 end, gt)
		awards.money = best_by(function(r) return r.money or 0 end, gt)
		awards.ante = best_by(function(r) return r.ante or 0 end, gt)
	end
	local teams = nil
	if teams_mode then
		local by = {}
		teams = {}
		for _, r in ipairs(rows) do
			if r.team then
				local t = by[r.team]
				if not t then
					t = { team = r.team, dealt = 0, pvpWon = 0, livesLost = 0, money = 0, best = "0", members = {}, place = r.place }
					by[r.team] = t
					teams[#teams + 1] = t
				end
				t.dealt = math.min(1e308, t.dealt + (r.dealt or 0))
				t.pvpWon = t.pvpWon + (r.pvpWon or 0)
				t.money = t.money + (r.money or 0)
				t.place = math.min(t.place, r.place)
				if s_gt(parse_score(r.best or "0"), parse_score(t.best)) then t.best = r.best end
				t.members[#t.members + 1] = r.id
			end
		end
		table.sort(teams, function(a, b) if a.place ~= b.place then return a.place < b.place end return a.team < b.team end)
	end
	return rows, teams, awards
end

--- Match over: build the final table once and send it to everyone in the lobby.
function Server:stats_finish(L)
	if not L.book or L.lastStats then return end
	local out = {}
	local function mark(p) if p.eliminated then out[p.id] = true end end
	for _, p in ipairs(L.players) do mark(p) end
	for _, sl in ipairs(L.slots or {}) do mark(sl.old) end
	for id in pairs(L.book) do
		local here = find(L.players, function(p) return p.id == id end)
		if not here then out[id] = true end -- left the match
	end
	if L.winnerId then out[L.winnerId] = nil end
	local teams_mode = L.gameMode == "teams" and L.teamLives ~= nil
	local rows, teams, awards = Core.match_table(L.book, out, L.elimOrder, teams_mode)
	if teams then
		for _, t in ipairs(teams) do
			t.livesLost = (L.teamBook and L.teamBook[t.team]) or 0
			t.lives = L.teamLives and L.teamLives[t.team]
		end
	end
	L.lastStats = { action = "matchStats", gameMode = L.gameMode, winnerId = L.winnerId, rows = rows, teams = teams, awards = awards }
	for _, p in ipairs(L.players) do sendA(p, L.lastStats) end
end

---------------------------------------------------------------- Teams (2v2 ... 4v4, 2v2v2, 2v2v2v2)
function Server:teams_active(L) return L.gameMode == "teams" and L.teamLives ~= nil and Core.TEAMS ~= nil end

--- Fix the teams at game start (exactly 4 players).
function Server:teams_start(L, lives)
	if L.gameMode ~= "teams" or not Core.TEAMS then return end
	local ids = {}
	for i, p in ipairs(L.players) do ids[i] = p.id end
	local t, size, count = Core.TEAMS.assign(ids, L.options)
	if not t then return end
	for _, p in ipairs(L.players) do p.team = t[p.id] end
	L.teamSize, L.teamLives = size, {}
	for i = 1, count do L.teamLives[Core.TEAMS.LETTERS[i]] = lives end
	self:teams_broadcast(L)
end

--- Everyone on a team: connected players and held (away) seats.
function Server:team_members(L, team)
	local r = {}
	for _, p in ipairs(L.players) do if p.team == team then r[#r + 1] = p end end
	for _, sl in ipairs(L.slots) do if sl.old.team == team then r[#r + 1] = sl.old end end
	return r
end

--- Set a team's shared lives and sync them to everyone.
function Server:set_team_lives(L, team, lives)
	if not L.teamLives then return end
	local before = L.teamLives[team]
	if L.teamBook and before and lives < before then L.teamBook[team] = (L.teamBook[team] or 0) + (before - lives) end
	L.teamLives[team] = lives
	for _, m in ipairs(self:team_members(L, team)) do m.lives = lives end
	for _, p in ipairs(L.players) do
		if p.team == team then
			sendA(p, { action = "playerInfo", lives = lives })
			local info = self:enemy_info(p, true)
			for _, o in ipairs(L.players) do if o ~= p then sendA(o, info) end end
		end
	end
end

--- Life loss outside the PvP resolution (timers, failed rounds). In Teams the whole team loses
--- one life, once per cause per round (the teammates' blockers are set too).
function Server:lose_life_for(c, cause)
	local L = c.lobby
	if not L or not self:teams_active(L) or not c.team then return self:lose_life(c, cause) end
	local blocked = (cause == "timer") and c.timerLivesBlocker or (cause ~= "timer" and c.roundLivesBlocker)
	if blocked then return end
	for _, m in ipairs(self:team_members(L, c.team)) do
		if cause == "timer" then m.timerLivesBlocker = true else m.roundLivesBlocker = true end
	end
	self:set_team_lives(L, c.team, math.max(0, (L.teamLives[c.team] or c.lives) - 1))
end

--- Tell everyone the teams, team lives and (optionally) which team lost the last PvP.
function Server:teams_broadcast(L, lastLoser, has_last)
	if not self:teams_active(L) then return end
	local teams = {}
	for letter, lives in pairs(L.teamLives) do teams[letter] = { members = {}, lives = lives } end
	local function add(p) if p.team and teams[p.team] then local m = teams[p.team].members; m[#m + 1] = { id = p.id, username = p.username } end end
	for _, p in ipairs(L.players) do add(p) end
	for _, sl in ipairs(L.slots) do add(sl.old) end
	for _, p in ipairs(L.players) do
		local msg = { action = "teamsUpdate", you = p.id, team = p.team, teamSize = L.teamSize, teams = teams }
		if has_last then msg.lastLoser = lastLoser or "none" end
		sendA(p, msg)
	end
end

--- Teams PvP resolution: the single lowest team sum loses a team life (tie: nobody).
function Server:resolve_teams_pvp(L, alive)
	local present, n_teams = {}, 0
	for _, p in ipairs(alive) do
		if p.team then
			if not present[p.team] then present[p.team] = {}; n_teams = n_teams + 1 end
			local list = present[p.team]
			list[#list + 1] = p.score
		end
	end
	local timerLosers = filter(alive, function(p) return p.pvpTimerFailed end)
	local loser = nil
	if #timerLosers == 0 and n_teams >= 2 then
		loser = Core.TEAMS.resolve(present, L.teamSize, s_gt, s_eq)
		if loser then self:set_team_lives(L, loser, math.max(0, L.teamLives[loser] - 1)) end
	end
	do
		local lost = {}
		for _, p in ipairs(alive) do if (loser and p.team == loser) or p.pvpTimerFailed then lost[p] = true end end
		self:stats_pvp(L, alive, lost)
	end
	for _, p in ipairs(alive) do p.firstReady, p.pvpDone, p.pvpTimerFailed = false, false, false end
	for _, p in ipairs(alive) do
		for _, o in ipairs(L.players) do if o ~= p then sendA(p, self:enemy_info(o, true)) end end
	end
	self:teams_broadcast(L, loser, true)
	if self:check_game_over(L) then return end
	local timer_teams = {}
	for _, p in ipairs(timerLosers) do if p.team then timer_teams[p.team] = true end end
	local ids, seen = {}, {}
	local function add(p) if not seen[p.id] then seen[p.id] = true; ids[#ids + 1] = p.id end end
	if loser then for _, m in ipairs(self:team_members(L, loser)) do add(m) end end
	for _, p in ipairs(L.players) do if p.team and timer_teams[p.team] then add(p) end end
	for _, p in ipairs(alive) do
		sendA(p, { action = "endPvP", lost = (loser ~= nil and p.team == loser) or (p.team ~= nil and timer_teams[p.team] == true),
			pvpTimerLost = (#timerLosers > 0) or nil, opponentsAway = (n_teams < 2) or nil, loserIds = ids, loserTeam = loser })
	end
end

---------------------------------------------------------------- King of the Hill
function Server:koth_active(L) return L.gameMode == "koth" and Core.KOTH ~= nil end

function Server:koth_resolve(L, alive, roundLosers)
	if not self:koth_active(L) then return nil end
	local K = Core.KOTH
	L.koth = L.koth or K.new_state()
	local cfg = K.config(L.options, L.startPlayers)
	local entries = {}
	for _, p in ipairs(alive) do entries[#entries + 1] = { id = p.id, name = p.username, score = p.score } end
	local loser_ids = {}
	for i, p in ipairs(roundLosers) do loser_ids[i] = p.id end
	local ev = K.resolve(L.koth, entries, loser_ids, s_gt, s_eq, cfg)
	if ev.lifeBonus and ev.claimedBy then
		local p = find(alive, function(x) return x.id == ev.claimedBy end)
		if p and p.lives < cfg.starting_lives then
			p.lives = p.lives + 1
			sendA(p, { action = "playerInfo", lives = p.lives })
		else
			ev.lifeBonus = false
		end
	end
	return ev
end

--- Send the King state to everyone (personalised with "you" = their own id).
function Server:koth_broadcast(L, ev)
	if not self:koth_active(L) then return end
	if not ev then
		L.koth = L.koth or Core.KOTH.new_state()
		local names = {}
		for _, p in ipairs(L.players) do names[p.id] = p.username end
		ev = Core.KOTH.snapshot(L.koth, names, Core.KOTH.config(L.options, L.startPlayers))
	end
	for _, p in ipairs(L.players) do sendA(p, copy(ev, { action = "kothUpdate", you = p.id })) end
end

--- The King held the hill long enough: everyone else is out.
function Server:koth_hill_win(L, winnerId)
	local winner = find(L.players, function(p) return p.id == winnerId end)
	if not winner then return false end
	for _, p in ipairs(L.players) do
		if p ~= winner and not p.eliminated then
			p.eliminated = true
			sendA(p, { action = "loseGame", reason = "koth_hill" })
			for _, o in ipairs(L.players) do
				if o ~= p then sendA(o, { action = "playerEliminated", playerId = p.id, username = p.username }) end
			end
		end
	end
	sendA(winner, { action = "winGame", reason = "koth_hill" })
	L.isInGame, L.blindActive, L.slots = false, false, {}
	L.winnerId = winner.id
	notify_match_over(self, L)
	return true
end

function Server:leave(c)
	local L = c.lobby
	if not L then return end
	local was = find(L.players, function(p) return p == c end)
	remove_value(L.players, c)
	local was_eliminated = c.eliminated
	c.lobby, c.eliminated = nil, false
	if not was then return end
	if #L.players == 0 then self:destroy(L); return end
	if c.spectator then
		c.spectator = nil
		self:broadcast(L, { action = "spectatorLeft", playerId = c.id, username = c.username })
		self:lobby_info(L)
		return
	end
	c.eliminated = was_eliminated -- (for the checks below; reset after)
	if L.isInGame then
		self:broadcast(L, { action = "playerLeft", playerId = c.id, username = c.username })
		if L.gameMode == "deathmatch" and not c.eliminated then
			-- a leaver counts as eliminated
			L.elimOrder = L.elimOrder or {}
			L.elimOrder[#L.elimOrder + 1] = c.id
			self:broadcast(L, { action = "playerEliminated", playerId = c.id, username = c.username, reason = "left" })
		end
		c.team = nil
		self:teams_broadcast(L)
		c.eliminated = false
		self:deathmatch_broadcast(L)
		self:check_game_over(L)
		if L.isInGame then self:try_start_blind(L); self:try_resolve_pvp(L) end
	else
		c.eliminated = false
		self:broadcast(L, { action = "stopGame" })
		self:reset_players(L)
	end
	self:lobby_info(L)
end

--- Transport lost for this connection.
function Server:disconnect(c)
	local L = c.lobby
	if not L then return end
	local _, idx = find(L.players, function(p) return p == c end)
	if not idx then return end
	if not L.isInGame or c.spectator then self:leave(c); return end
	local grace = Core.rejoin_grace(L.options, L.gameMode)
	self.log("Player " .. c.username .. " disconnected from " .. L.code .. "; seat held for " .. grace .. " s")
	L.slots[#L.slots + 1] = { reconnectToken = c.reconnectToken, index = idx, old = c, since = self.now() }
	table.remove(L.players, idx)
	c.lobby = nil
	for _, p in ipairs(L.players) do
		sendA(p, { action = "enemyDisconnected", timeout = 0, playerId = c.id, username = c.username, held = true,
			grace = (not c.eliminated) and grace or nil })
	end
	if #L.players == 0 then L.emptySince = self.now(); return end
	self:try_start_blind(L)
	self:try_resolve_pvp(L)
	self:lobby_info(L)
end

local SLOT_FIELDS = { "team", "lives", "score", "handsLeft", "ante", "skips", "furthestBlind", "isReady", "firstReady",
	"isReadyLobby", "roundLivesBlocker", "timerLivesBlocker", "location", "eliminated", "pvpDone",
	"pvpTimerFailed", "playedThisBlind", "blindSeq", "inPvp", "sitOut", "modHash", "isCached", "spectator", "runState" }

function Server:send_resume(L, c, late)
	sendA(c, { action = "resumeGame", seed = L.seed, ante = math.max(1, c.ante), lives = c.lives, lateJoin = late,
		eliminated = c.eliminated, blindActive = L.blindActive, runState = c.runState,
		stats = L.book and L.book[c.id] or nil,
		inCurrentBlind = (c.inPvp and L.blindActive and c.blindSeq == L.blindSeq) or false })
	sendA(c, { action = "playerInfo", lives = c.lives })
	for _, o in ipairs(L.players) do if o ~= c and not o.spectator then sendA(c, self:enemy_info(o, true)) end end
	for _, s in ipairs(L.slots) do if not s.old.spectator then sendA(c, self:enemy_info(s.old, true)) end end
end

function Server:reclaim(L, c, slot)
	remove_value(L.slots, slot)
	L.emptySince = nil
	local o = slot.old
	for _, f in ipairs(SLOT_FIELDS) do c[f] = o[f] end
	if not c.username or c.username == "Guest" then c.username = o.username end
	if slot.keep_id then
		-- host migration: the seat keeps its player id and token, so every client's view stays valid
		c.id, c.reconnectToken, c.seat = o.id, o.reconnectToken or c.reconnectToken, o.seat
		local pos = 1
		for i, p in ipairs(L.players) do if (p.seat or 500) <= (c.seat or 500) then pos = i + 1 end end
		table.insert(L.players, pos, c)
	else
		-- 0.6.8: a rejoining player keeps its player id, so everyone's HUD / standings / spectator
		-- panel keep pointing at the same seat (no stale "disconnected" ghost entry)
		c.id = o.id or c.id
		table.insert(L.players, math.min(slot.index, #L.players + 1), c)
	end
	c.lobby = L
	if slot.migration then return self:migration_reclaimed(L, c) end
	local missed = c.inPvp and (not L.blindActive or c.blindSeq ~= L.blindSeq)
	if missed then c.inPvp, c.pvpDone, c.isReady = false, false, false end
	sendA(c, { action = "rejoinedLobby", code = L.code, type = L.gameMode, reconnectToken = c.reconnectToken })
	sendA(c, copy(copy({ gamemode = L.gameMode }, L.options), { action = "lobbyOptions" }))
	self:send_resume(L, c, false)
	self:koth_broadcast(L)
	self:teams_broadcast(L)
	if missed then sendA(c, { action = "endPvP", lost = false, loserIds = {} }) end
	for _, p in ipairs(L.players) do
		if p ~= c then
			sendA(p, { action = "enemyReconnected", playerId = c.id, username = c.username })
			sendA(p, self:enemy_info(c, true))
		end
	end
	self:lobby_info(L)
end

function Server:take_over(L, stale)
	self:disconnect(stale)
	pcall(stale.close)
	return find(L.slots, function(s) return s.old == stale end)
end

function Server:rejoin(L, c, token)
	local slot = find(L.slots, function(s) return s.reconnectToken == token end)
	if not slot and L.isInGame then
		local stale = find(L.players, function(p) return p.reconnectToken == token and p ~= c end)
		if stale then slot = self:take_over(L, stale) end
	end
	if not slot then return false end
	self:reclaim(L, c, slot)
	return true
end

function Server:late_join(L, c)
	local all = {}
	for _, p in ipairs(self:alive(L)) do all[#all + 1] = p end
	local conn = #all
	for _, s in ipairs(self:away_alive(L)) do all[#all + 1] = s.old end
	local minl, mina = math.huge, math.huge
	for i, p in ipairs(all) do
		minl = math.min(minl, p.lives)
		if i <= conn or conn == 0 then mina = math.min(mina, p.ante or 1) end
	end
	c.lives = math.max(1, minl == math.huge and 1 or minl)
	c.ante = math.max(1, mina == math.huge and 1 or mina)
	c.eliminated, c.isReady, c.firstReady, c.score, c.handsLeft, c.skips = false, false, false, ZERO(), 4, 0
	c.inPvp, c.pvpDone, c.sitOut = false, false, L.blindActive
	self:reset_blocker(c)
	L.players[#L.players + 1] = c
	c.lobby, c.isReadyLobby = L, true
	sendA(c, { action = "joinedLobby", code = L.code, type = L.gameMode, reconnectToken = c.reconnectToken })
	sendA(c, copy(copy({ gamemode = L.gameMode }, L.options), { action = "lobbyOptions" }))
	self:send_resume(L, c, true)
	self:koth_broadcast(L)
	for _, p in ipairs(L.players) do
		if p ~= c then
			sendA(p, { action = "playerJoined", playerId = c.id, username = c.username })
			sendA(p, self:enemy_info(c, true))
		end
	end
	self:lobby_info(L)
end

--- 0.6.8: watch a running match. Spectators get the same live info as eliminated players
--- (scores, lives, location, standings) but every game action they send is ignored.
function Server:spectate(L, c)
	if #self:spectators(L) >= Core.MAX_SPECTATORS then
		return sendA(c, { action = "error", message = "Too many spectators in this lobby." })
	end
	c.spectator, c.eliminated, c.lives, c.isReady, c.sitOut, c.inPvp = true, true, 0, false, true, false
	c.isReadyLobby, c.lobby = true, L
	L.players[#L.players + 1] = c
	sendA(c, { action = "joinedLobby", code = L.code, type = L.gameMode, reconnectToken = c.reconnectToken, spectator = true })
	sendA(c, copy(copy({ gamemode = L.gameMode }, L.options), { action = "lobbyOptions" }))
	sendA(c, { action = "spectateStart", code = L.code, gameMode = L.gameMode, blindActive = L.blindActive })
	for _, o in ipairs(L.players) do if o ~= c and not o.spectator then sendA(c, self:enemy_info(o, true)) end end
	for _, s in ipairs(L.slots) do if not s.old.spectator then sendA(c, self:enemy_info(s.old, true)) end end
	self:koth_broadcast(L)
	self:teams_broadcast(L)
	self:deathmatch_broadcast(L)
	for _, p in ipairs(L.players) do
		if p ~= c then sendA(p, { action = "spectatorJoined", playerId = c.id, username = c.username }) end
	end
	self:lobby_info(L)
end

function Server:join(L, c, want_spectate)
	if L.isInGame then
		local name = base_name(c.username)
		local slot = find(L.slots, function(s) return base_name(s.old.username) == name end)
		if slot then return self:reclaim(L, c, slot) end
		local stale = find(L.players, function(p) return base_name(p.username) == name and p ~= c end)
		if stale then
			local s2 = self:take_over(L, stale)
			if s2 then return self:reclaim(L, c, s2) end
		end
		-- late join if there's a free seat (not in Teams / Deathmatch); otherwise (or when asked) watch
		if not want_spectate and not Core.no_late_join(L.gameMode)
			and #self:seated(L) + #L.slots < Core.max_players(L.gameMode) then return self:late_join(L, c) end
		return self:spectate(L, c)
	end
	if #self:seated(L) >= Core.max_players(L.gameMode) then
		return sendA(c, { action = "error", message = "Lobby is full or does not exist." })
	end
	L.players[#L.players + 1] = c
	c.eliminated, c.lobby, c.isReadyLobby = false, L, false
	sendA(c, { action = "joinedLobby", code = L.code, type = L.gameMode, reconnectToken = c.reconnectToken })
	sendA(c, copy(copy({ gamemode = L.gameMode }, L.options), { action = "lobbyOptions" }))
	self:lobby_info(L)
end

---------------------------------------------------------------- host migration (Steam P2P)
-- The Steam host replicates its lobby state to every guest (Server:snapshot). When the host is
-- gone, the elected successor rebuilds the lobby from the last snapshot (Core.restore): every
-- player starts as a held seat that keeps its id and token, and is reclaimed when that player's
-- client reconnects to the new host. Until everyone is back (or Core.MIGRATION_HOLD runs out)
-- no blind starts or resolves, so a PvP that was running simply continues.
local SNAP_FIELDS = { "id", "username", "reconnectToken", "seat" }
for _, f in ipairs(SLOT_FIELDS) do SNAP_FIELDS[#SNAP_FIELDS + 1] = f end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local function snap_player(p)
	local d = {}
	for _, f in ipairs(SNAP_FIELDS) do
		local v = p[f]
		if f == "score" then
			v = v or ZERO()
			v = { ec = finite(v.ec) and v.ec or 0, c = finite(v.c) and v.c or 0, e = finite(v.e) and v.e or 0, raw = v.raw, str = v.str }
		elseif type(v) == "number" and not finite(v) then
			v = 0
		end
		d[f] = v
	end
	return d
end
local function plain(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do
		if type(v) ~= "function" then r[k] = (type(v) == "table") and plain(v) or ((type(v) == "number" and not finite(v)) and 0 or v) end
	end
	return r
end

--- JSON-safe copy of a lobby's authoritative state (nil if the lobby doesn't exist).
function Server:snapshot(code, hostId)
	local L = self.lobbies[code or ""]
	if not L then return nil end
	local now = self.now()
	local s = {
		v = 1, code = L.code, gameMode = L.gameMode, options = plain(L.options), isInGame = L.isInGame and true or false,
		seed = L.seed, blindActive = L.blindActive and true or false, blindSeq = L.blindSeq or 0, startPlayers = L.startPlayers,
		teamSize = L.teamSize, teamLives = plain(L.teamLives), koth = plain(L.koth), elimOrder = plain(L.elimOrder),
		book = plain(L.book), teamBook = plain(L.teamBook), lastStats = plain(L.lastStats),
		winnerId = L.winnerId, firstReadyAge = L.firstReadyAt and (now - L.firstReadyAt) or nil,
		next_id = self.next_id, hostId = hostId, players = {}, slots = {},
	}
	for i, p in ipairs(L.players) do s.players[i] = snap_player(p) end
	for i, sl in ipairs(L.slots) do
		s.slots[i] = { token = sl.reconnectToken, index = sl.index, age = sl.since and (now - sl.since) or nil,
			mig = sl.migration or nil, oldHost = sl.oldHost or nil, old = snap_player(sl.old) }
	end
	return s
end

--- Rebuild a server from a snapshot on the new host.
--- opts: now, log, oldHostId, newHostId, reason ("left" | "disconnected"), hold (seconds)
function Core.restore(snap, opts)
	opts = opts or {}
	local S = Core.new(opts)
	S.next_id = (tonumber(snap.next_id) or 0) + 100
	local now = S.now()
	local L = {
		code = snap.code, gameMode = snap.gameMode or "attrition", options = snap.options or {},
		isInGame = snap.isInGame and true or false, seed = snap.seed, blindActive = snap.blindActive and true or false,
		blindSeq = tonumber(snap.blindSeq) or 0, startPlayers = snap.startPlayers, teamSize = snap.teamSize,
		teamLives = snap.teamLives, koth = snap.koth, elimOrder = snap.elimOrder, winnerId = snap.winnerId,
		book = snap.book, teamBook = snap.teamBook, lastStats = snap.lastStats,
		firstReadyAt = snap.firstReadyAge and (now - snap.firstReadyAge) or nil,
		players = {}, slots = {}, emptySince = nil,
	}
	if L.teamLives and next(L.teamLives) == nil and L.gameMode ~= "teams" then L.teamLives = nil end
	local noop = function() end
	local function mk(d)
		local o = copy(d)
		o.send, o.close, o.lobby = noop, noop, nil
		o.score = d.score or ZERO()
		return o
	end
	local oldName
	for i, d in ipairs(snap.players or {}) do
		local o = mk(d)
		local is_old = d.id == opts.oldHostId
		o.seat = (d.id == opts.newHostId and 0) or (is_old and 1000) or i
		if is_old then oldName = d.username end
		L.slots[#L.slots + 1] = { reconnectToken = d.reconnectToken, index = i, old = o, since = now, keep_id = true,
			migration = (not is_old) or nil, oldHost = is_old or nil }
	end
	for i, sd in ipairs(snap.slots or {}) do
		local o = mk(sd.old or {})
		o.seat = o.seat or (200 + i)
		L.slots[#L.slots + 1] = { reconnectToken = sd.token, index = sd.index or 99, old = o,
			since = sd.age and (now - sd.age) or now, keep_id = true, migration = sd.mig or nil, oldHost = sd.oldHost or nil }
	end
	L.migration = { untilT = now + (opts.hold or Core.MIGRATION_HOLD), oldHostId = opts.oldHostId, oldHostName = oldName,
		newHostId = opts.newHostId, reason = opts.reason or "disconnected" }
	S.lobbies[L.code] = L
	return S, L
end

--- A player reconnected to the new host after a migration.
function Server:migration_reclaimed(L, c)
	local m = L.migration or {}
	local host = L.players[1]
	sendA(c, { action = "hostMigrated", code = L.code, type = L.gameMode, reconnectToken = c.reconnectToken, you = c.id,
		hostId = host and host.id, hostName = host and host.username, oldHostName = m.oldHostName, inGame = L.isInGame })
	sendA(c, copy(copy({ gamemode = L.gameMode }, L.options), { action = "lobbyOptions" }))
	if L.isInGame then
		sendA(c, { action = "playerInfo", lives = c.lives })
		for _, o in ipairs(L.players) do if o ~= c and not o.spectator then sendA(c, self:enemy_info(o, true)) end end
		for _, s in ipairs(L.slots) do if not s.old.spectator then sendA(c, self:enemy_info(s.old, true)) end end
		if self:koth_active(L) and L.koth then self:koth_broadcast(L) end
		self:teams_broadcast(L)
		self:deathmatch_broadcast(L)
	end
	self:lobby_info(L)
	if not find(L.slots, function(s) return s.migration end) then self:end_migration(L) end
end

--- A held seat that will not come back (the old host who left on purpose).
function Server:slot_left(L, o)
	if not L.isInGame then return end
	self:broadcast(L, { action = "playerLeft", playerId = o.id, username = o.username })
	if L.gameMode == "deathmatch" and not o.eliminated then
		L.elimOrder = L.elimOrder or {}
		L.elimOrder[#L.elimOrder + 1] = o.id
		self:broadcast(L, { action = "playerEliminated", playerId = o.id, username = o.username, reason = "left" })
	end
	o.team = nil
end

--- Everyone is back (or the hold ran out): apply the old host's leave and continue the game.
function Server:end_migration(L)
	local m = L.migration
	if not m then return end
	L.migration = nil
	local missing = {}
	for i = #L.slots, 1, -1 do
		local sl = L.slots[i]
		if sl.migration then
			sl.migration = nil
			if L.isInGame and not sl.old.spectator then missing[#missing + 1] = sl.old else table.remove(L.slots, i) end
		elseif sl.oldHost then
			sl.oldHost = nil
			if not L.isInGame then
				table.remove(L.slots, i)
			elseif m.reason == "left" then
				table.remove(L.slots, i)
				self:slot_left(L, sl.old)
			else
				missing[#missing + 1] = sl.old
			end
		end
	end
	for _, o in ipairs(missing) do
		for _, p in ipairs(L.players) do sendA(p, { action = "enemyDisconnected", timeout = 0, playerId = o.id, held = true }) end
	end
	if #L.players == 0 then L.emptySince = self.now() end
	if L.isInGame then
		self:teams_broadcast(L)
		self:deathmatch_broadcast(L)
		if not self:check_game_over(L) then
			self:try_start_blind(L)
			self:try_resolve_pvp(L)
		end
	end
	self:lobby_info(L)
end

---------------------------------------------------------------- actions
local RELAYS = {
	sendPhantom = true, removePhantom = true, asteroid = true, letsGoGamblingNemesis = true, eatPizza = true,
	soldJoker = true, spentLastShop = true, magnet = true, magnetResponse = true, getEndGameJokers = true,
	receiveEndGameJokers = true, getNemesisDeck = true, receiveNemesisDeck = true,
	endGameStatsRequested = true, nemesisEndGameStats = true, startAnteTimer = true, pauseAnteTimer = true,
	dataSync = true,
}

local H = {}

function H.username(S, c, a)
	c.username = a.username or c.username
	c.modHash = a.modHash or c.modHash
	if c.lobby then S:lobby_info(c.lobby) end
end
function H.version(S, c, a)
	local maj, min, pat = tostring(a.version or ""):match("^(%d+)%.(%d+)%.(%d+)")
	local smaj, smin, spat = Core.SERVER_VERSION:match("^(%d+)%.(%d+)%.(%d+)")
	if maj then
		maj, min, pat, smaj, smin, spat = tonumber(maj), tonumber(min), tonumber(pat), tonumber(smaj), tonumber(smin), tonumber(spat)
		if maj < smaj or (maj == smaj and min < smin) or (maj == smaj and min == smin and pat < spat) then
			sendA(c, { action = "error", message = "[WARN] Server expecting version " .. Core.SERVER_VERSION })
		end
	end
end
function H.createLobby(S, c, a) S:new_lobby(c, a.gameMode) end
function H.joinLobby(S, c, a)
	local L = S.lobbies[a.code or ""]
	if not L then return sendA(c, { action = "error", message = "Lobby does not exist." }) end
	S:join(L, c, a.spectate and true or false)
end
function H.rejoinLobby(S, c, a)
	local L = S.lobbies[a.code or ""]
	if not L then return sendA(c, { action = "rejoinFailed", message = "Lobby no longer exists." }) end
	if not S:rejoin(L, c, a.reconnectToken) then
		if L.isInGame and find(L.slots, function(s) return base_name(s.old.username) == base_name(c.username) end) then
			return S:join(L, c)
		end
		sendA(c, { action = "rejoinFailed", message = "Could not rejoin lobby. Token invalid or slot expired." })
	end
end
function H.lobbyInfo(S, c) if c.lobby then S:lobby_info(c.lobby) end end
function H.leaveLobby(S, c) S:leave(c) end
function H.readyLobby(S, c) c.isReadyLobby = true; if c.lobby then S:lobby_info(c.lobby) end end
function H.unreadyLobby(S, c) c.isReadyLobby = false; if c.lobby then S:lobby_info(c.lobby) end end
function H.keepAlive(S, c) sendA(c, { action = "keepAliveAck" }) end
function H.keepAliveAck() end
function H.startGame(S, c)
	local L = c.lobby
	if not L or L.players[1] ~= c then return end
	if L.migration then return sendA(c, { action = "error", message = "Host migration in progress, try again in a moment." }) end
	if L.isInGame then return sendA(c, { action = "error", message = "A match is still running." }) end
	local why = Core.start_error(L.gameMode, #S:seated(L), L.options)
	if why then return sendA(c, { action = "error", message = why }) end
	-- 0.6.8: every guest must be Ready (spectators and returning players count as ready); the host's Start button
	-- is greyed out until then, this guards against an old/modified client
	local waiting = Core.unready_count(L.players)
	if waiting > 0 then return sendA(c, { action = "error", message = "Waiting for " .. waiting .. " player(s) to ready up." }) end
	S:promote_spectators(L)
	L.startPlayers = #S:seated(L)
	L.lastStats = nil
	local lives = tonumber(L.options.starting_lives) or Core.STARTING_LIVES[L.gameMode] or 4
	local seed = nil
	if not L.options.different_seeds then seed = rand_str("ABCDEFGHIJKLMNPQRSTUVWXYZ123456789", 8) end
	L.seed = seed
	S:reset_players(L)
	L.isInGame = true
	local seated = S:seated(L)
	for _, p in ipairs(seated) do sendA(p, { action = "startGame", deck = "c_multiplayer_1", seed = seed, playerCount = #seated }) end
	for _, p in ipairs(seated) do p.lives, p.eliminated = lives, false end
	for _, p in ipairs(seated) do sendA(p, { action = "playerInfo", lives = lives }) end
	for _, p in ipairs(S:spectators(L)) do
		p.lives, p.eliminated = 0, true
		sendA(p, { action = "spectateStart", code = L.code, gameMode = L.gameMode })
	end
	L.koth = nil
	S:koth_broadcast(L)
	S:teams_start(L, lives)
	S:stats_start(L)
	for i = 2, #L.players do L.players[i].isReadyLobby = false end
	for _, p in ipairs(L.players) do
		for _, o in ipairs(seated) do if o ~= p then sendA(p, S:enemy_info(o, true)) end end
	end
end
function H.readyBlind(S, c)
	local L = c.lobby
	if not L or c.eliminated then return end
	c.isReady = true
	local other = find(S:alive(L), function(p) return p ~= c and (p.isReady or p.firstReady) end)
	if not c.firstReady and not other then
		c.firstReady = true
		L.firstReadyAt = S.now()
		sendA(c, { action = "speedrun" })
	elseif L.firstReadyAt and S.now() - L.firstReadyAt <= 30 and not c.firstReady then
		sendA(c, { action = "speedrun" })
	end
	S:try_start_blind(L)
end
function H.unreadyBlind(S, c) c.isReady = false end
function H.playHand(S, c, a)
	local L = c.lobby
	if not L or not L.isInGame or c.eliminated then return end
	c.score = parse_score(a.score)
	c.score.str = tostring(a.score or "0")
	c.handsLeft = math.floor(tonumber(a.handsLeft) or 0)
	local hide = L.options.hide_score_until_played and true or false
	if s_gt(c.score, ZERO()) then c.playedThisBlind = true end
	if c.handsLeft < 1 then c.pvpDone = true end
	local ranking = {}
	for _, p in ipairs(S:alive(L)) do ranking[#ranking + 1] = p end
	table.sort(ranking, function(x, y)
		if s_eq(x.score, y.score) then return (x.firstReady and 1 or 0) > (y.firstReady and 1 or 0) end
		return s_gt(x.score, y.score)
	end)
	local order = {}
	for i, p in ipairs(ranking) do order[i] = p.id end
	for _, o in ipairs(L.players) do
		if o ~= c then
			sendA(o, copy(S:enemy_info(c, not hide or o.playedThisBlind), { pvpTimerOrder = order[1] == c.id and "guest" or "host", pvpOrder = order }))
			sendA(c, copy(S:enemy_info(o, not hide or c.playedThisBlind), { pvpTimerOrder = order[1] == c.id and "host" or "guest", pvpOrder = order }))
		end
	end
	S:try_resolve_pvp(L)
end
function H.failPvPTimer(S, c)
	local L = c.lobby
	if c.eliminated then return end
	S:lose_life_for(c, "timer")
	if not L then return end
	c.pvpDone, c.pvpTimerFailed = true, true
	if S:check_game_over(L) then return end
	S:try_resolve_pvp(L)
end
function H.stopGame(S, c)
	if not c.lobby then return end
	-- An eliminated player (or spectator) going back to the lobby must not end the match for the others
	if c.lobby.isInGame and c.eliminated then return sendA(c, { action = "stopGame" }) end
	S:broadcast(c.lobby, { action = "stopGame" })
	S:reset_players(c.lobby)
end
function H.lobbyOptions(S, c, a)
	local L = c.lobby
	if not L then return end
	local opts = {}
	local teams_before = tostring(L.options.teams_order or "") .. "|" .. tostring(L.options.teams_size or "")
	for k, v in pairs(a) do
		if k ~= "action" then
			if v == "true" then v = true elseif v == "false" then v = false end
			L.options[k] = v
			opts[k] = a[k]
		end
	end
	for i = 2, #L.players do sendA(L.players[i], copy(copy({ gamemode = L.gameMode }, opts), { action = "lobbyOptions" })) end
	-- re-broadcast the team preview only on a real change (the host re-sends all options after each lobbyInfo)
	local teams_after = tostring(L.options.teams_order or "") .. "|" .. tostring(L.options.teams_size or "")
	if L.gameMode == "teams" and not L.isInGame and teams_after ~= teams_before then S:lobby_info(L) end
end
function H.failRound(S, c)
	local L = c.lobby
	if not L or c.eliminated then return end
	if L.options.death_on_round_loss then S:lose_life_for(c, "round") end
	S:check_game_over(L)
end
function H.failTimer(S, c)
	local L = c.lobby
	if c.eliminated then return end
	S:lose_life_for(c, "timer")
	if L then S:check_game_over(L) end
end
function H.setAnte(S, c, a) c.ante = tonumber(a.ante) or c.ante end
function H.setLocation(S, c, a) S:set_location(c, a.location) end
function H.newRound(S, c) S:reset_blocker(c) end
function H.setFurthestBlind(S, c, a) c.furthestBlind = tonumber(a.furthestBlind) or c.furthestBlind end
function H.skip(S, c, a)
	c.skips = tonumber(a.skips) or c.skips
	if c.lobby then S:to_others(c, S:enemy_info(c, true)) end -- teammates see skips too
end
--- 0.6.8: the player's last known run state (sent at every checkpoint: shop / blind select).
--- The host keeps it with the seat (also through host migration) and sends it back on rejoin.
--- 0.6.8: a player's own match stats (best hand, jokers, money earned, highest ante)
function H.statsReport(S, c, a)
	local L = c.lobby
	if not L or not L.isInGame or c.spectator then return end
	S:stats_report(L, c, a)
end
local RUN_FIELDS = { "ante", "round", "dollars", "jokers", "deck", "hands", "discards", "ckpt" }
function H.runState(S, c, a)
	if c.spectator or c.eliminated or not (c.lobby and c.lobby.isInGame) then return end
	local st = {}
	for _, f in ipairs(RUN_FIELDS) do
		local v = tonumber(a[f])
		if v and v == v and v > -1e9 and v < 1e12 then st[f] = math.floor(v) end
	end
	c.runState = st
	if st.ante and st.ante >= 1 then c.ante = st.ante end
end
function H.syncClient(S, c, a) c.isCached = a.isCached and true or false end
function H.resumeRestarted(S, c)
	local L = c.lobby
	if not L then return end
	if L.blindActive then
		c.sitOut, c.inPvp = true, false
		S:try_resolve_pvp(L)
	end
	c.isReady = false
end
function H.moddedAction(S, c, a)
	local L = c.lobby
	if not L then return end
	local msg = copy(a, { action = "moddedAction", from = L.players[1] == c and "host" or "guest" })
	msg.target = nil
	if (a.target or "nemesis") == "all" then S:broadcast(L, msg) else S:to_opponents(c, msg) end
end
function H.submitLogHashes() end
function H.streamLogLines() end
function H.gameInfo() end
function H.handyMPExtensionEnable() end
function H.handyMPExtensionDisable() end
function H.tcgServerVersion() end

--- Handle one action table from connection c.
function Server:receive(c, a)
	if type(a) ~= "table" or type(a.action) ~= "string" then return end
	-- 0.6.8: spectators cannot affect the game; eliminated players only finish their end screen
	if c.spectator and c.lobby and c.lobby.isInGame and not Core.SPECTATOR_OK[a.action] then return end
	if c.eliminated and c.lobby and c.lobby.isInGame and RELAYS[a.action] and not Core.END_GAME_RELAYS[a.action] then return end
	local h = H[a.action]
	if h then
		local ok, err = pcall(h, self, c, a)
		if not ok then self.log("p2p server error in " .. a.action .. ": " .. tostring(err)) end
	elseif RELAYS[a.action] and c.lobby then
		local msg = copy(a, { playerId = c.id })
		local tid = msg.targetId
		msg.targetId = nil
		-- 3P: end-game requests/responses can target one player (the nemesis / the requester)
		local target = tid and find(c.lobby.players, function(p) return p ~= c and p.id == tid end)
		if target then sendA(target, msg) else self:to_opponents(c, msg) end
	end
end

--- Periodic housekeeping (call ~once per second).
function Server:tick()
	local now = self.now()
	for code, L in pairs(self.lobbies) do
		if L.migration and now >= L.migration.untilT then self:end_migration(L) end
		if L.isInGame and not L.migration then
			local grace = Core.rejoin_grace(L.options, L.gameMode)
			for _, sl in ipairs(L.slots) do
				if L.isInGame and not sl.old.eliminated and not sl.old.spectator and sl.since and not sl.migration
					and now - sl.since >= grace then self:expire_slot(L, sl) end
			end
		end
		if #L.players == 0 and L.emptySince and now - L.emptySince > Core.EMPTY_LOBBY_TTL then
			self:destroy(L)
		end
	end
end

return Core
