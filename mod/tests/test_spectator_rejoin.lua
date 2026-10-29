-- Spectator mode + rejoin after a disconnect (0.6.8) over the simulated Steam network.
-- run from mod/: luajit tests/test_spectator_rejoin.lua
-- Server side: networking/p2p_server.lua through the steam_p2p router (same fake Steam as
-- tests/test_host_migration.lua). Client side: the pure parts of lib/spectator.lua and
-- lib/rejoin.lua, plus the checkpoint with a stubbed Balatro (save.jkr must never be written).
package.path = "tests/?.lua;" .. package.path
local json = os.getenv("JSON_LIB") and dofile(os.getenv("JSON_LIB")) or require("dkjson")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
local HMmod = dofile("networking/host_migration.lua")
Core.KOTH = dofile("networking/koth_rules.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
local T = 5000
local now = function() return T end
local NET

local function remove(t, x) for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end end
local function steam_leave(l, id, me)
	local L = NET.lobbies[l]; if not L then return end
	remove(L.members, me)
	if L.owner == me then
		if #L.members == 0 then NET.lobbies[l] = nil else L.owner = L.members[1] end
	end
end
local function backend(me)
	local B, pend = {}, {}
	NET.inbox[me] = {}
	local function later(f) pend[#pend + 1] = f end
	function B.poll() local p = pend; pend = {}; for _, f in ipairs(p) do f() end end
	function B.my_id() return me end
	function B.create_lobby(cb) later(function() local id = tostring(7000 + NET.next); NET.next = NET.next + 1
		NET.lobbies[id] = { owner = me, members = { me }, data = {} }; cb(id) end) end
	function B.find_lobby(code, cb) later(function() for id, l in pairs(NET.lobbies) do
		if l.data.mp3p_code == code then return cb(id) end end cb(nil) end) end
	function B.join_lobby(id, cb) later(function() local l = NET.lobbies[id]
		if not l or NET.dead[me] then return cb(false) end
		remove(l.members, me); table.insert(l.members, me); cb(true) end) end
	function B.leave_lobby(id) steam_leave(id, nil, me) end
	function B.set_data(id, k, v) if NET.lobbies[id] and NET.lobbies[id].owner == me then NET.lobbies[id].data[k] = v end end
	function B.get_data(id, k) return NET.lobbies[id] and NET.lobbies[id].data[k] or "" end
	function B.owner(id) return NET.lobbies[id] and NET.lobbies[id].owner or "0" end
	function B.set_member_data(id, k, v) local l = NET.lobbies[id]
		if l then l.md = l.md or {}; l.md[me] = l.md[me] or {}; l.md[me][k] = v end end
	function B.get_member_data(id, who, k) local l = NET.lobbies[id]
		for _, m in ipairs(l and l.members or {}) do if m == who then return (l.md and l.md[who] and l.md[who][k]) or "" end end
		return "" end
	function B.set_owner(id, new) local l = NET.lobbies[id]
		if l and l.owner == me then for _, m in ipairs(l.members) do if m == new then l.owner = new; return true end end end
		return false end
	function B.members(id) local l = NET.lobbies[id]; local r = {}; for i, m in ipairs(l and l.members or {}) do r[i] = m end return r end
	function B.invite_dialog() end
	function B.accept() end
	function B.close() end
	function B.send(peer, data)
		if NET.dead[peer] or NET.dead[me] then return true end
		local q = NET.inbox[peer]; if q then q[#q + 1] = { peer = me, data = data } end return true end
	function B.receive() local q = NET.inbox[me]; NET.inbox[me] = {}; return q end
	return B
end

local all
local function player(name)
	local P = { name = name, msgs = {}, alive = true }
	P.b = backend(name)
	P.r = P2P.new_router({ log = os.getenv("LOG") and function(s) print("[" .. T .. " " .. name .. "] " .. s) end or nil, backend = P.b, Core = Core, json = json, now = now, version = "0.6.8~3P", Migration = HMmod,
		push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	P.count = function(a) local n = 0 for _, m in ipairs(P.msgs) do if m.action == a then n = n + 1 end end return n end
	return P
end
local function pump(n) for _ = 1, n or 6 do for _, p in ipairs(all) do if p.alive then p.r.update() end end end end
local function run(secs) for _ = 1, secs do T = T + 1; pump(3) end end
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local function live(ps) local r = {} for _, p in ipairs(ps) do if p.alive and not p.gone then r[#r + 1] = p end end return r end

--- n players in a lobby of the given mode; returns the players (host first) and the code
local function setup(n, mode, opts)
	NET = { lobbies = {}, inbox = {}, next = 1, dead = {} }
	local ps = {}
	for i = 1, n do ps[i] = player(mode:sub(1, 3) .. n .. "_" .. i) end
	all = ps
	for _, p in ipairs(ps) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" }) end
	ps[1].send({ action = "createLobby", gameMode = mode }); pump()
	local code = ps[1].last("joinedLobby").code
	local o = { starting_lives = "2" }
	for k, v in pairs(opts or {}) do o[k] = v end
	o.action = "lobbyOptions"
	ps[1].send(o); pump()
	for i = 2, n do ps[i].send({ action = "joinLobby", code = code }); pump(4) end
	pump(6)
	for _, p in ipairs(ps) do p.id = (p.last("lobbyInfo") or {}).you end
	assert(#ps[1].last("lobbyInfo").players == n, "lobby filled")
	run(1)
	return ps, code
end
local function start(ps)
	for i = 2, #ps do ps[i].send({ action = "readyLobby" }) end; pump(2); ps[1].send({ action = "startGame" }); pump(6)
	run(1)
end
local function clear(ps) for _, p in ipairs(ps) do p.msgs = {} end end
local function quit(p) -- Balatro closed: gone from the Steam lobby, no more P2P
	p.alive = false
	NET.dead[p.name] = true
	for id in pairs(NET.lobbies) do steam_leave(id, nil, p.name) end
end
local function host_of(ps) for _, p in ipairs(live(ps)) do if p.r.mode == "host" then return p end end end
--- one PvP blind for the given players with scores by position; returns results per player
local function blind(ps, scores)
	clear(ps)
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
	pump(8)
	for _, p in ipairs(ps) do assert(p.last("startBlind"), p.name .. " startBlind") end
	for i, p in ipairs(ps) do p.send({ action = "playHand", score = tostring(scores[i]), handsLeft = 0 }) end
	pump(8)
	local res = {}
	for _, p in ipairs(ps) do res[p] = p.last("winGame") or p.last("loseGame") or p.last("endPvP") end
	return res
end

do -- keep the pump list separate from the seat list (newcomers / restarted processes join it)
	local setup0 = setup
	setup = function(...)
		local ps, code = setup0(...)
		local c = {}
		for i, p in ipairs(ps) do c[i] = p end
		all = c
		return ps, code
	end
end
local function tok(p) local j = p.last("joinedLobby") or p.last("rejoinedLobby"); return j and j.reconnectToken end
--- Balatro crashed and was started again: a fresh process with the same Steam id that rejoins
local function restart(ps, i, code, token)
	local old = ps[i]
	NET.dead[old.name] = nil
	local p = player(old.name)
	all[#all + 1] = p
	ps[i] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" })
	p.send({ action = "rejoinLobby", code = code, reconnectToken = token })
	pump(8); run(2)
	p.id = old.id
	return p
end
local function newcomer(name, code, spectate)
	local p = player(name)
	all[#all + 1] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" })
	p.send({ action = "joinLobby", code = code, spectate = spectate }); pump(8); run(1)
	return p
end
local function ids_in(p, action)
	local r = {}
	for _, m in ipairs(p.msgs) do if m.action == action and m.playerId then r[m.playerId] = m end end
	return r
end

-- ===== 1. somebody joins a running Deathmatch / Teams match: they spectate, they can't play
for _, mode in ipairs({ "deathmatch", "teams" }) do
	for _, n in ipairs({ 2, 4, 8 }) do
		if not (mode == "teams" and n < 4) then
			local ps, code = setup(n, mode, {})
			start(ps)
			clear(ps)
			local X = newcomer("watcher_" .. mode .. n, code)
			local j = X.last("joinedLobby")
			assert(j and j.spectator == true, mode .. " " .. n .. "p: joinedLobby as spectator")
			assert(X.last("spectateStart"), mode .. " " .. n .. "p: spectateStart")
			assert(not X.last("startGame") and not X.last("resumeGame"), mode .. " " .. n .. "p: no run for the spectator")
			local seen = ids_in(X, "enemyInfo")
			for _, p in ipairs(ps) do assert(seen[p.id], mode .. " " .. n .. "p: spectator sees " .. p.name) end
			assert(ps[2].last("spectatorJoined"), mode .. " " .. n .. "p: players are told someone watches")
			local li = ps[1].last("lobbyInfo")
			local nspec = 0
			for _, pl in ipairs(li.players) do if pl.spectator then nspec = nspec + 1 end end
			assert(nspec == 1, mode .. " " .. n .. "p: lobbyInfo marks the spectator")
			-- the spectator tries to play: everything is ignored
			clear(ps)
			X.send({ action = "readyBlind" }); X.send({ action = "playHand", score = "999999", handsLeft = 0 })
			X.send({ action = "failRound" }); X.send({ action = "sendPhantom", key = "j_joker" }); X.send({ action = "startGame" })
			pump(6)
			for _, p in ipairs(ps) do
				assert(not p.last("sendPhantom") and not p.last("startBlind") and not p.last("enemyInfo"),
					mode .. " " .. n .. "p: spectator actions never reach " .. p.name)
			end
			-- a PvP blind starts and resolves without waiting for the spectator
			local sc = {}
			for i = 1, n do sc[i] = 100 * i end
			local res = blind(ps, sc)
			for _, p in ipairs(ps) do assert(res[p], mode .. " " .. n .. "p: " .. p.name .. " finished the PvP without the spectator") end
			assert(X.last("enemyInfo"), mode .. " " .. n .. "p: spectator gets live scores")
		end
	end
end
print("ok: joining a running Deathmatch/Teams match -> spectator (2/4/8 players), can't play, gets live info")

-- ===== 2. Attrition: late join still takes a free seat; spectate=true just watches; max spectators
do
	local ps, code = setup(3, "attrition", {})
	start(ps)
	local A = newcomer("late_one", code)
	ok(A.last("joinedLobby") and not A.last("joinedLobby").spectator and A.last("resumeGame"), "attrition: late join takes a free seat (as before)")
	local B = newcomer("only_watch", code, true)
	ok(B.last("joinedLobby").spectator and B.last("spectateStart"), "attrition: spectate=true watches instead")
	local Ws = {}
	for i = 1, Core.MAX_SPECTATORS do Ws[i] = newcomer("w" .. i, code, true) end
	ok(Ws[Core.MAX_SPECTATORS].last("error") and not Ws[Core.MAX_SPECTATORS].last("spectateStart"),
		"attrition: at most " .. Core.MAX_SPECTATORS .. " spectators")
	-- spectators don't count for the win: the 4 players play down to one winner
	local players = { ps[1], ps[2], ps[3], A }
	for round = 1, 6 do
		local alive = {}
		for _, p in ipairs(players) do if not p.last("loseGame") then alive[#alive + 1] = p end end
		if #alive <= 1 then break end
		local sc = {}
		for i = 1, #alive do sc[i] = 100 * i end
		blind(alive, sc)
	end
	local winners = 0
	for _, p in ipairs(players) do if p.last("winGame") then winners = winners + 1 end end
	ok(winners == 1 and not B.last("winGame") and not B.last("loseGame"), "attrition: exactly one winner, spectators get no win/lose")
	ok(B.last("matchOver"), "attrition: spectators are told the match is over")
	-- next match: spectators become players while there are free seats
	for i = 2, #ps do ps[i].send({ action = "readyLobby" }) end; pump(2); ps[1].send({ action = "startGame" }); pump(8)
	ok(B.last("startGame"), "next match: a spectator gets a seat")
end

-- ===== 3. eliminated players keep getting live info; their game actions are ignored
do
	local ps = setup(4, "deathmatch", { starting_lives = "1" })
	start(ps)
	blind(ps, { 400, 300, 200, 100 })
	ok(ps[4].last("loseGame"), "deathmatch: lowest is out")
	clear(ps)
	ps[4].send({ action = "sendPhantom", key = "j_joker" }); ps[4].send({ action = "failRound" })
	pump(4)
	ok(not ps[1].last("sendPhantom") and not ps[1].last("enemyInfo"), "eliminated player's game actions are ignored")
	local res = blind({ ps[1], ps[2], ps[3] }, { 300, 200, 100 })
	local seen = ids_in(ps[4], "enemyInfo")
	ok(seen[ps[1].id] and seen[ps[2].id] and seen[ps[3].id], "eliminated player sees every remaining player's score after a PvP")
end

-- ===== 4. disconnect -> status + grace -> rejoin with the last known run state (2..8 players)
for _, n in ipairs({ 2, 3, 5, 8 }) do
	local ps, code = setup(n, "attrition", {})
	start(ps)
	local sc = {}
	for i = 1, n do sc[i] = 100 * i end
	blind(ps, sc)
	local i = n -- the last seat (top score, keeps both lives) drops
	local token = tok(ps[i])
	ps[i].send({ action = "runState", ante = 2, round = 3, dollars = 17, jokers = 3, deck = 52, hands = 4, discards = 3, ckpt = 4, junk = "x" })
	ps[i].send({ action = "runState", ante = "2", dollars = "1e999", ckpt = 5 })
	pump(4)
	ps[i].send({ action = "runState", ante = 2, round = 3, dollars = 17, jokers = 3, deck = 52, hands = 4, discards = 3, ckpt = 6 })
	pump(4)
	clear(ps)
	local id = ps[i].id
	quit(ps[i])
	run(P2P.TIMEOUT + 2) -- Steam P2P notices the dead peer
	local d = ps[1].last("enemyDisconnected")
	assert(d and d.held and d.playerId == id and d.grace == Core.REJOIN_GRACE, n .. "p: enemyDisconnected with the grace window")
	local li = ps[1].last("lobbyInfo")
	assert(li.away and li.away[1] and li.away[1].left and li.away[1].left > 0, n .. "p: lobbyInfo shows the seconds left")
	run(60)
	assert(not ps[1].last("playerEliminated"), n .. "p: not eliminated within the grace window")
	local p = restart(ps, i, code, token)
	local r = p.last("resumeGame")
	assert(r and not r.eliminated and r.runState and r.runState.dollars == 17 and r.runState.ckpt == 6
		and r.runState.jokers == 3 and r.runState.junk == nil and r.ante == 2, n .. "p: resumeGame carries the last run state")
	assert(p.last("playerInfo").lives == 2, n .. "p: lives kept")
	local back = ps[1].last("enemyReconnected")
	assert(back and back.playerId == id and back.username, n .. "p: others are told who rejoined")
	if n > 2 then
		local alive = {}
		for _, q in ipairs(ps) do if not q.last("loseGame") then alive[#alive + 1] = q end end
		local s2 = {}
		for k = 1, #alive do s2[k] = 1000 + k end
		local res = blind(alive, s2)
		assert(res[p], n .. "p: the rejoined player plays the next PvP")
	end
end
print("ok: disconnect -> 'waiting to rejoin' + grace -> rejoin restores lives and the last run state (2/3/5/8 players)")

-- ===== 5. grace runs out -> eliminated as "disconnected"; rejoining later only watches
do
	local ps, code = setup(3, "attrition", { rejoin_grace = "30" })
	start(ps)
	local token = tok(ps[3])
	local id = ps[3].id
	clear(ps)
	quit(ps[3])
	run(P2P.TIMEOUT + 2)
	ok(ps[1].last("enemyDisconnected").grace == 30, "rejoin_grace option is used (30 s)")
	run(31)
	local e = ps[1].last("playerEliminated")
	ok(e and e.playerId == id and e.reason == "disconnected", "after the grace window the player is eliminated")
	local res = blind({ ps[1], ps[2] }, { 200, 100 })
	ok(res[ps[1]] and res[ps[2]], "the match goes on without them")
	-- 2 players left; 3rd rejoins as out
	local p = restart(ps, 3, code, token)
	local r = p.last("resumeGame")
	ok(r and r.eliminated, "rejoining after the window: you are out (and can watch)")
	clear(ps)
	p.send({ action = "playHand", score = "1", handsLeft = 0 }); pump(4)
	ok(not ps[1].last("enemyInfo"), "...and can't play")
end
do
	local ps = setup(3, "deathmatch", { deathmatch_grace = "60" })
	start(ps)
	quit(ps[3]); run(P2P.TIMEOUT + 2)
	ok(ps[1].last("enemyDisconnected").grace == 60, "deathmatch keeps its own grace option")
	ok(Core.rejoin_grace({}, "attrition") == 180 and Core.rejoin_grace({ rejoin_grace = "5" }, "koth") == 10
		and Core.rejoin_grace({ rejoin_grace = "9999" }, "koth") == 900, "rejoin_grace: default 180 s, clamped 10..900")
end

-- ===== 6. host migration: the host's Balatro crashes, a guest takes over, the old host rejoins
for _, n in ipairs({ 3, 5, 8 }) do
	local ps, code = setup(n, "attrition", {})
	start(ps)
	ps[1].send({ action = "runState", ante = 3, dollars = 42, jokers = 5, ckpt = 9 }); pump(4)
	local X = newcomer("watch_hm" .. n, code, true)
	local token = tok(ps[1])
	clear(ps)
	quit(ps[1])
	run(3)
	local nh = host_of(ps)
	assert(nh == ps[2], n .. "p: seat 2 (a player, not the spectator) is the new host")
	run(Core.MIGRATION_HOLD + 2)
	assert(X.last("hostMigrated") and X.r.host == ps[2].name, n .. "p: the spectator follows the new host")
	assert(ps[2].last("enemyDisconnected") or ps[3].last("enemyDisconnected"), n .. "p: the old host shows as disconnected")
	assert(not ps[3].last("playerEliminated"), n .. "p: the old host is not eliminated")
	local p = restart(ps, 1, code, token)
	local r = p.last("resumeGame")
	assert(p.r.mode == "guest" and p.r.host == ps[2].name, n .. "p: old host rejoins as a guest")
	assert(r and r.runState and r.runState.dollars == 42 and r.runState.ckpt == 9, n .. "p: its run state survived the migration")
	assert(ps[3].last("enemyReconnected"), n .. "p: others see it rejoined")
end
print("ok: host crashes -> migration -> the old host rejoins as a guest with its run state (3/5/8 players)")

-- ===== 7. a spectator can take over as host, but only after every seated player
do
	local ps, code = setup(2, "attrition", {})
	start(ps)
	local X = newcomer("spec_host", code, true)
	clear(ps)
	quit(ps[1]); run(3)
	ok(host_of({ ps[2], X }) == ps[2], "2p + spectator: the remaining player hosts, not the spectator")
	quit(ps[2]); run(4)
	ok(X.r.mode == "host" and not X.last("hostMigrationFailed"), "the spectator takes over when all players are gone (mode " .. tostring(X.r.mode) .. ")")
end

-- ===== 8. client: pure spectator + rejoin helpers
_G.MP = { LOBBY = { code = "ABCD" }, GAME = {} }
_G.localize = function(k) return "ERROR" end
dofile("lib/spectator.lua")
dofile("lib/rejoin.lua")
local SP, RJ = MP.SPECTATE, MP.REJOIN
do
	local enemies = {
		a = { id = "a", username = "Ann~1", lives = 2, raw_score = "500", hands = 1, ante = 3, location = "Shop" },
		b = { id = "b", username = "Bob", lives = 3, raw_score = "100", hands = 4 },
		c = { id = "c", username = "Cid", lives = 0, raw_score = "900", eliminated = true },
		d = { id = "d", username = "Dee", lives = 2, raw_score = "800", away = true },
	}
	local rows = SP.rows(enemies)
	ok(rows[1].id == "b" and rows[2].id == "d" and rows[3].id == "a" and rows[4].id == "c", "spectator list: most lives, then score; out last")
	ok(rows[3].name == "Ann", "names drop the ~tag")
	ok(SP.leader(rows).id == "b", "leader = first alive")
	ok(SP.step(rows, "b", 1) == "d" and SP.step(rows, "a", 1) == "b" and SP.step(rows, "b", -1) == "a", "follow next/prev wraps and skips players who are out")
	ok(SP.step(rows, "zzz", 1) == "b", "unknown follow -> leader")
	local v = SP.lines(rows, "a")
	ok(v.follow == "Following: Ann" and v.detail:find("Lives: 2") and v.detail:find("Hands left: 1") and v.detail:find("Ante 3")
		and v.where == "Now: Shop", "panel shows lives, score, hands, ante and location")
	ok(v.rows[1]:find("ahead") and v.rows[2]:find("disconnected") and v.rows[4]:find("out") and v.rows[3]:sub(1, 2) == "> ",
		"list marks who is ahead, away, out and who you follow")
	ok(#v.rows == SP.MAX_ROWS and v.rows[8] == "", "always " .. SP.MAX_ROWS .. " rows")
	ok(SP.step({}, nil, 1) == nil and SP.lines({}, nil).follow == "Nobody left to watch", "nobody left")
	_G.localize = function(a) if type(a) == "table" and a.key == "k_sp_following" then return "Je volgt: " .. a.vars[1] end return "ERROR" end
	ok(SP.lines(rows, "a").follow == "Je volgt: Ann", "texts come from the game language (localize) when present")
	_G.localize = function() return "ERROR" end
end
do
	ok(RJ.countdown(161) == "2:41" and RJ.countdown(-3) == "0:00", "countdown m:ss")
	local s = RJ.summary({ dollars = 12, round = 5, round_resets = { ante = 2, hands = 4, discards = 3 } }, 4, 50, 7)
	ok(s.ante == 2 and s.dollars == 12 and s.jokers == 4 and s.deck == 50 and s.ckpt == 7, "run summary is just numbers")
	local meta = { code = "ABCD", server_seed = "SEED", ckpt = 5, time = 1000 }
	ok(RJ.usable(meta, { seed = "SEED", runState = { ckpt = 5 } }, 1100), "checkpoint usable: same lobby, seed, not older than the host's")
	ok(not RJ.usable(meta, { seed = "OTHER" }, 1100), "other seed -> not used")
	ok(not RJ.usable(meta, { seed = "SEED", runState = { ckpt = 6 } }, 1100), "older than the host's last checkpoint -> not used")
	ok(not RJ.usable(meta, { seed = "SEED" }, 1000 + RJ.MAX_AGE + 1), "too old -> not used")
	MP.LOBBY.code = "ZZZZ"
	ok(not RJ.usable(meta, { seed = "SEED" }, 1100), "other lobby -> not used")
	MP.LOBBY.code = "ABCD"
	local bar = RJ.bar_text({ x = { name = "Ann", end_time = 100 } }, 0)
	ok(bar == "Ann disconnected - waiting to rejoin 1:40", "status bar text")
end
do -- checkpoint with a stubbed Balatro: captures the run, never queues a save.jkr write
	local files = {}
	_G.G = { STAGES = { RUN = 2, MAIN_MENU = 1 }, STATES = { SHOP = 5, BLIND_SELECT = 7, SELECTING_HAND = 1 }, STAGE = 2, STATE = 5,
		F_NO_SAVING = true, ARGS = {}, GAME = { dollars = 9, round = 4, round_resets = { ante = 2 } }, jokers = { cards = { 1, 2 } }, playing_cards = { 1, 2, 3 } }
	MP.GAME.lives = 2
	MP.STEAM_P2P = {}
	local sent = {}
	_G.Client = { send = function(t) sent[#sent + 1] = t end }
	_G.compress_and_save = function(f, d) files[f] = d end
	local vanilla_calls = 0
	local function vanilla_save_run()
		vanilla_calls = vanilla_calls + 1
		assert(not G.F_NO_SAVING, "save_run runs with saving enabled while capturing")
		G.ARGS.save_run = { GAME = { dollars = G.GAME.dollars }, STATE = G.STATE }
		G.FILE_HANDLER = G.FILE_HANDLER or {}
		G.FILE_HANDLER.run, G.FILE_HANDLER.update_queued = true, true
	end
	RJ.on_start({ seed = "SEED" })
	RJ.on_save_run(vanilla_save_run)
	local f = files[RJ.FILE]
	ok(f and f.run.GAME.dollars == 9 and f.meta.code == "ABCD" and f.meta.server_seed == "SEED" and f.meta.ckpt == 1,
		"checkpoint written to its own file with lobby, seed and counter")
	ok(not G.FILE_HANDLER.run and not G.FILE_HANDLER.update_queued and G.F_NO_SAVING == true and G.ARGS.save_run == nil,
		"save.jkr write cancelled, saving stays off")
	ok(sent[1] and sent[1].action == "runState" and sent[1].dollars == 9 and sent[1].jokers == 2 and sent[1].ckpt == 1,
		"host gets the numeric summary")
	G.STATE = G.STATES.SELECTING_HAND
	RJ.on_save_run(vanilla_save_run)
	ok(vanilla_calls == 1 and #sent == 1, "no checkpoint mid-round")
	G.STATE = G.STATES.BLIND_SELECT
	MP.GAME.lives = 0
	RJ.on_save_run(vanilla_save_run)
	ok(vanilla_calls == 1, "no checkpoint once you are out")
	RJ.on_save_run(function() error("boom") end)
	ok(G.F_NO_SAVING == true, "a failing save_run is contained")
end
print("PASS: spectator + rejoin")
