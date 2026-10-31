-- Network chaos (latency, jitter, loss, link cuts) over the simulated Steam network, many seeded iterations. luajit tests/test_chaos.lua [iterations]
-- + p2p_server core). run from mod/: luajit tests/test_host_migration.lua
-- The fake Steam behaves like the real one where it matters: when the lobby owner leaves, Steam
-- makes another member the owner; SetLobbyOwner only works for the current owner; a player who
-- quits Balatro drops out of the member list and stops answering P2P.
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
local CH = dofile("dev/chaos_backend.lua")
--- one PvP for the given players under chaos (time passes so delayed frames arrive)
local function blind(ps, scores)
	clear(ps)
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
	for _ = 1, 20 do run(1); local all_ = true; for _, p in ipairs(ps) do if not p.last("startBlind") then all_ = false end end if all_ then break end end
	for _, p in ipairs(ps) do assert(p.last("startBlind"), p.name .. " startBlind") end
	for i, p in ipairs(ps) do p.send({ action = "playHand", score = tostring(scores[i]), handsLeft = 0 }) end
	local res = {}
	for _ = 1, 20 do run(1); local all_ = true
		for _, p in ipairs(ps) do res[p] = p.last("winGame") or p.last("loseGame") or p.last("endPvP"); if not res[p] then all_ = false end end
		if all_ then break end end
	return res
end
local ITER = tonumber(arg and arg[1]) or tonumber(os.getenv("CHAOS_ITER")) or 60
-- wrap every new player's backend in chaos (the router keeps a reference to P.b)
local base_player = player
player = function(name)
	local real_backend = backend
	backend = function(me) return CH.wrap(real_backend(me), CHAOS, { clock = now, random = math.random }) end
	local P = base_player(name)
	backend = real_backend
	return P
end
local function hosts(ps) local n = 0 for _, p in ipairs(ps) do if p.alive and not p.gone and p.r.mode == "host" then n = n + 1 end end return n end
local function settle(ps, limit)
	for s = 1, limit do run(1); if hosts(ps) == 1 then local h = host_of(ps); local okall = true
		for _, p in ipairs(live(ps)) do if p ~= h and not (p.r.mode == "guest" and p.r.host == h.name) then okall = false end end
		if okall then return s end end end
	return nil
end
local results = { pass = 0, fail = 0, fails = {} }
local SCEN = { "host_quit", "two_hosts_in_a_row", "guest_freeze_rejoin", "host_freeze" }
for it = tonumber(os.getenv("CHAOS_FROM")) or 1, ITER do
	math.randomseed(1000 + it)
	CHAOS = {} -- clean link while the lobby is set up and the match starts
	local sc = SCEN[(it - 1) % #SCEN + 1]
	local n = 3 + (it % 3)
	local okk, err = pcall(function()
		local ps = setup(n, ({ "attrition", "koth", "deathmatch" })[it % 3 + 1])
		start(ps); run(3)
		CHAOS.lat, CHAOS.jit, CHAOS.loss = 50 + (it % 4) * 100, 300, (it % 3) * 0.05
		if it % 2 == 0 then CHAOS.cut_every, CHAOS.cut_for = 40, 6 end -- sudden short link cuts
		if sc == "host_quit" then
			quit(ps[1]); assert(settle(ps, 60), "one host after the host quit")
		elseif sc == "two_hosts_in_a_row" then
			quit(ps[1]); assert(settle(ps, 60), "first migration"); run(5)
			local h = host_of(ps); quit(h); assert(settle(ps, 60), "second migration")
		elseif sc == "guest_freeze_rejoin" then
			ps[n].alive = false; run(30); ps[n].alive = true
			assert(settle(ps, 40), "one host"); run(10)
			assert(ps[n].last("rejoinedLobby") or not (ps[1].r.dropped or {})[ps[n].name], "frozen guest re-attached")
		elseif sc == "host_freeze" then
			ps[1].alive = false; run(35); ps[1].alive = true
			assert(settle(ps, 60), "one host after the frozen host woke up")
			for _ = 1, 20 do if ps[1].last("rejoinedLobby") then break end run(1) end
			assert(ps[1].last("rejoinedLobby"), "woken old host got its seat back")
		end
		-- the match still works: everyone still in it gets a PvP result
		local rest = live(ps)
		local sc2 = {}; for i = 1, #rest do sc2[i] = 1000 - 37 * i end
		local res = blind(rest, sc2)
		for _, p in ipairs(rest) do assert(res[p], p.name .. " got the next PvP result") end
	end)
	if okk then results.pass = results.pass + 1 else results.fail = results.fail + 1; results.fails[#results.fails + 1] = it .. " " .. sc .. " " .. n .. "p: " .. tostring(err) end
end
for _, f in ipairs(results.fails) do print("FAIL " .. f) end
print(string.format("chaos: %d iterations, %d passed, %d failed (%.1f%%)", ITER, results.pass, results.fail, 100 * results.pass / ITER))
assert(results.fail == 0, "chaos failures")
print("PASS: chaos")
