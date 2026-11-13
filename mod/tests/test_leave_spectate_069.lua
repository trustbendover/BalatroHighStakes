-- 0.6.9: in-game Leave holds the seat; watch while holding it; Rejoin from the spectator view.
-- run from mod/: luajit tests/test_leave_spectate_069.lua
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
	P.r = P2P.new_router({ log = os.getenv("LOG") and function(s) print("[" .. T .. " " .. name .. "] " .. s) end or nil, backend = P.b, Core = Core, json = json, now = now, version = "0.7.0", Migration = HMmod,
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
	for _, p in ipairs(ps) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.7.0" }) end
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
	p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.7.0" })
	p.send({ action = "rejoinLobby", code = code, reconnectToken = token })
	pump(8); run(2)
	p.id = old.id
	return p
end
local function newcomer(name, code, spectate)
	local p = player(name)
	all[#all + 1] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = name, modHash = "t" }); p.send({ action = "version", version = "0.7.0" })
	p.send({ action = "joinLobby", code = code, spectate = spectate }); pump(8); run(1)
	return p
end
local function ids_in(p, action)
	local r = {}
	for _, m in ipairs(p.msgs) do if m.action == action and m.playerId then r[m.playerId] = m end end
	return r
end

-- 1. Leave in a running match -> held seat (grace) -> rejoin with the same token
do
	local ps, code = setup(3, "attrition", {})
	local A = ps[3]; local t = tok(A)
	ok(t, "setup: token known")
	start(ps); clear(ps)
	A.send({ action = "leaveLobby" }); pump(8)
	local d = ps[1].last("enemyDisconnected")
	ok(d and d.playerId == A.id and d.held and d.grace, "leave: others see a held seat with a grace countdown")
	ok(not ps[1].last("playerEliminated") and not ps[1].last("playerLeft"), "leave: not eliminated / not 'left' yet")
	clear(ps)
	A.send({ action = "rejoinLobby", code = code, reconnectToken = t }); pump(8)
	ok(A.last("rejoinedLobby") and A.last("resumeGame"), "leave: rejoin with the kept token takes the seat back")
	ok(ps[1].last("enemyReconnected") and ps[1].last("enemyReconnected").playerId == A.id, "leave: others see the rejoin (banner cleared)")
end

-- 2. Leave, then watch while the seat is held: names right away, every player visible, Rejoin works
do
	local ps, code = setup(4, "attrition", {})
	local A = ps[4]; local t = tok(A)
	start(ps); clear(ps)
	A.send({ action = "leaveLobby" }); pump(8); run(5); clear(ps)
	A.send({ action = "joinLobby", code = code, spectate = true }); pump(8)
	local s = A.last("spectateStart")
	ok(s and s.reset and s.heldSeat and (s.heldSeat.token == nil or s.heldSeat.token == t) and s.heldSeat.left > 0, "watch: spectateStart carries the held seat + time left")
	local li; for _, m in ipairs(A.msgs) do if m.action == "lobbyInfo" then li = m end if m.action == "spectateStart" then break end end
	ok(li, "watch: lobbyInfo (names) arrives before spectateStart")
	local seen = ids_in(A, "enemyInfo")
	for i = 1, 3 do ok(seen[ps[i].id], "watch: sees " .. ps[i].name) end
	ok(seen[A.id] and seen[A.id].away, "watch: own held seat listed as away")
	ok(not ps[1].last("enemyReconnected"), "watch: watching does not take the seat")
	run(3)
	clear(ps)
	A.send({ action = "rejoinLobby", code = code, reconnectToken = s.heldSeat.token or t }); pump(8); run(2) -- client keeps its own token; pump(8)
	ok(A.last("rejoinedLobby") and A.last("resumeGame"), "watch: Rejoin from the spectator view")
	local li2 = ps[1].last("lobbyInfo"); local n = 0
	for _, p in ipairs(li2.players or {}) do if p.id == A.id or p.username == A.name then n = n + 1 end end
	ok(n <= 1, "watch: no duplicate entry after rejoin")
end

-- 3. Grace expires while watching: eliminated as disconnected, seat gone
do
	local ps, code = setup(3, "attrition", { rejoin_grace = "20" })
	start(ps); clear(ps)
	local A = ps[3]
	A.send({ action = "leaveLobby" }); pump(8)
	A.send({ action = "joinLobby", code = code, spectate = true }); pump(8)
	run(25)
	local e = ps[1].last("playerEliminated")
	ok(e and e.playerId == A.id and e.reason == "disconnected", "expiry: held seat eliminated after grace (client shows 'X left')")
end

-- 5. anti-abuse: absent at PvP loses a life (lowest score), can be eliminated; rejoin resumes at the match ante
do
	local ps, code = setup(4, "deathmatch", { starting_lives = "2" })
	local A = ps[4]; local t = tok(A)
	start(ps); clear(ps)
	A.send({ action = "leaveLobby" }); pump(8)
	local rest = { ps[1], ps[2], ps[3] }
	local res = blind(rest, { 10, 20, 30 })
	ok(res[ps[1]] and res[ps[1]].lost == false, "absent: the lowest connected player is spared (absent seat is lowest)")
	local info; for _, m in ipairs(ps[2].msgs) do if m.action == "enemyInfo" and m.playerId == A.id then info = m end end
	ok(info and info.lives == 1, "absent: held seat lost a life")
	for _, p in ipairs(rest) do p.send({ action = "setAnte", ante = 3 }) end; pump(4)
	res = blind(rest, { 10, 20, 30 })
	local e = ps[2].last("playerEliminated")
	ok(e and e.playerId == A.id and e.reason == "absent", "absent: eliminated at 0 lives while away")
	-- second seat: rejoin after the others moved on resumes at the match ante
	local ps2, code2 = setup(3, "attrition", {})
	local B = ps2[3]; local tb = tok(B)
	start(ps2); clear(ps2)
	B.send({ action = "leaveLobby" }); pump(8)
	for i = 1, 2 do ps2[i].send({ action = "setAnte", ante = 4 }) end; pump(4)
	clear(ps2)
	B.send({ action = "rejoinLobby", code = code2, reconnectToken = tb }); pump(8); run(2)
	local r = B.last("resumeGame")
	ok(r and r.ante >= 4, "rejoin: resumes at the match ante (" .. tostring(r and r.ante) .. "), not where it left")
end

-- 4. pure client parts
MP = MP or {}; MP.LOBBY = MP.LOBBY or {}; MP.GAME = { enemies = { old = { username = "stale" } } }
G = G or {}; G.FUNCS = G.FUNCS or {}
dofile("lib/spectator.lua")
local SP = MP.SPECTATE
SP.on_spectate_start({ reset = true, heldSeat = { left = 161, token = "x" } }, 100)
ok(next(MP.GAME.enemies) == nil, "client: stale enemies cleared on spectateStart")
ok(SP.rejoin_label(SP.state.held, 100) == "Rejoin (2:41)", "client: Rejoin (m:ss) label")
ok(SP.rejoin_label(SP.state.held, 300) == "Seat expired", "client: label after expiry")
local rows = SP.rows({ a = { id = "a", username = "A", lives = 2 }, b = { id = "b", username = "B", lives = 3 }, c = { id = "c", username = "C", lives = 1, away = true } }, {})
local f = SP.step(rows, nil, 0); local seen = { [f] = true }
for _ = 1, 3 do f = SP.step(rows, f, 1); seen[f] = true end
ok(seen.a and seen.b and seen.c, "client: Next cycles through every player")
print("PASS: leave + spectate 0.6.9")
