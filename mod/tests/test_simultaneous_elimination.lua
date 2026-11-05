-- Forced simultaneous elimination over the simulated Steam network (0.6.8 final). luajit tests/test_simultaneous_elimination.lua
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
	P.r = P2P.new_router({ log = os.getenv("LOG") and function(s) print("[" .. T .. " " .. name .. "] " .. s) end or nil, backend = P.b, Core = Core, json = json, now = now, version = "0.6.9", Migration = HMmod,
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
	for _, p in ipairs(ps) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.9" }) end
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
--- everyone ready, the PvP blind starts; `plays` = { [i] = {score=, timer=true|nil} }
local function pvp(ps, plays)
	clear(ps)
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
	pump(8)
	for _, p in ipairs(ps) do assert(p.last("startBlind"), p.name .. " startBlind") end
	-- everything below is sent in ONE pump: the host sees these on the same tick
	for i, p in ipairs(ps) do
		local pl = plays[i]
		p.send({ action = "playHand", score = tostring(pl.score), handsLeft = pl.timer and 1 or 0 })
		if pl.timer then p.send({ action = "failPvPTimer" }) end
	end
	pump(10)
end
local function verdict(p) return (p.last("winGame") and "win") or (p.last("loseGame") and "lose") or "none" end
local function same_on_all(ps, label)
	-- every peer saw the same eliminations (ids, order-independent) and the same match winner
	local ref
	for _, p in ipairs(ps) do
		local ids = {}
		for _, m in ipairs(p.msgs) do if m.action == "playerEliminated" then ids[#ids + 1] = m.playerId end end
		if p.last("loseGame") then ids[#ids + 1] = p.id end
		table.sort(ids); local k = table.concat(ids, ",")
		if ref == nil then ref = k else assert(ref == k, label .. ": " .. p.name .. " saw eliminations " .. k .. " vs " .. ref) end
	end
	return ref
end

local CASES = {
	{ mode = "duel", n = 2, opts = { starting_lives = "1" }, plays = { { score = 900, timer = true }, { score = 400, timer = true } }, win = { 1 } },
	{ mode = "duel", n = 2, opts = { starting_lives = "1" }, plays = { { score = 100, timer = true }, { score = 400, timer = true } }, win = { 2 } },
	{ mode = "attrition", n = 3, opts = { starting_lives = "1" }, plays = { { score = 500 }, { score = 300, timer = true }, { score = 800, timer = true } }, win = { 1 } },
	{ mode = "deathmatch", n = 3, opts = { starting_lives = "1" }, plays = { { score = 200, timer = true }, { score = 700, timer = true }, { score = 50, timer = true } }, win = { 2 } },
	{ mode = "koth", n = 3, opts = { starting_lives = "1" }, plays = { { score = 300, timer = true }, { score = 600, timer = true }, { score = 900 } }, win = { 3 } },
	{ mode = "teams", n = 4, opts = { starting_lives = "1", teams_format = "2" }, plays = { { score = 900, timer = true }, { score = 100, timer = true }, { score = 500, timer = true }, { score = 200, timer = true } }, teamwin = true },
}
for ci, c in ipairs(CASES) do
	for order = 1, 2 do -- same tick, both message orders: the result may not depend on who was first
		local ps = setup(c.n, c.mode, c.opts)
		start(ps)
		local plays = c.plays
		if order == 2 then -- reverse the send order but keep each player's play
			local rp, rpl = {}, {}
			for i = #ps, 1, -1 do rp[#rp + 1] = ps[i]; rpl[#rpl + 1] = plays[i] end
			pvp(rp, rpl)
		else pvp(ps, plays) end
		local label = c.mode .. " case " .. ci .. " order " .. order
		if c.teamwin then
			-- teams: the team with the higher summed value wins; both members get the same verdict
			local t1 = ps[1].last("lobbyInfo")
			local v = {}
			for _, p in ipairs(ps) do v[#v + 1] = verdict(p) end
			local wins = 0; for _, x in ipairs(v) do if x == "win" then wins = wins + 1 end end
			assert(wins == 2, label .. ": exactly one team (2 players) wins, got " .. table.concat(v, ","))
		else
			local want = {}; for _, i in ipairs(c.win) do want[i] = true end
			for i, p in ipairs(ps) do
				local v = verdict(p)
				assert((want[i] and v == "win") or (not want[i] and (v == "lose" or (c.plays[i].timer == nil and v ~= "win"))),
					label .. ": " .. p.name .. " verdict " .. v)
			end
		end
		same_on_all(ps, label)
		print("ok: " .. label)
	end
end
print("PASS: simultaneous elimination")
