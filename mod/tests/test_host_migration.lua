-- Host migration over a simulated Steam network (networking/host_migration.lua + steam_p2p router
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
local function check_migrated(ps, newhost, label)
	for _, p in ipairs(ps) do
		assert(p.last("hostMigrated"), label .. ": " .. p.name .. " got hostMigrated")
		assert(not p.last("disconnected") and not p.last("hostMigrationFailed"), label .. ": " .. p.name .. " stayed connected")
		assert(not p.last("resumeGame"), label .. ": " .. p.name .. " kept its run (no resume/restart)")
		if p == newhost then assert(p.r.mode == "host", label .. ": new host mode")
		else assert(p.r.mode == "guest" and p.r.host == newhost.name, label .. ": " .. p.name .. " follows " .. newhost.name .. " (has " .. tostring(p.r.host) .. ")") end
	end
	assert(newhost.last("hostMigrated").hostId == newhost.id, label .. ": hostMigrated names the new host")
	-- player ids survive the migration (HUD, jokers, eliminations keep pointing at the same players)
	for _, p in ipairs(ps) do
		assert(p.last("hostMigrated").you == p.id, label .. ": " .. p.name .. " keeps its player id")
	end
	SNAPMAX = math.max(SNAPMAX or 0, #(newhost.r.migration.last_snap or ""))
end

local MODES = { attrition = {}, showdown = {}, koth = { starting_lives = "3" }, deathmatch = {}, teams = {}, duel = {} }

-- ===== 1. host quits in the lobby (2, 3, 5, 8 players, every mode)
for _, n in ipairs({ 2, 3, 5, 8 }) do
	for _, mode in ipairs({ "attrition", "showdown", "koth", "teams", "deathmatch", "duel", "survival" }) do
		if not (mode == "duel" and n > 2) and not (mode == "teams" and n % 2 == 1) then
			local ps = setup(n, mode, MODES[mode])
			clear(ps)
			quit(ps[1])
			run(3)
			local rest = live(ps)
			check_migrated(rest, ps[2], mode .. " lobby " .. n .. "p")
			local li = ps[2].last("lobbyInfo")
			assert(li.isHost and #li.players == n - 1, mode .. " " .. n .. "p: lobby has " .. (n - 1) .. " players, P2 is host")
			assert(NET.lobbies[ps[2].r.lobby].owner == ps[2].name, "Steam lobby owner moved to the new host")
			if n >= 3 and mode ~= "teams" then
				for _, p in ipairs(rest) do if p ~= ps[2] then p.send({ action = "readyLobby" }) end end; pump(2); clear(rest); ps[2].send({ action = "startGame" }); pump(6)
				assert(ps[3].last("startGame"), mode .. " " .. n .. "p: the new host can start the game")
			end
		end
	end
	print("ok: lobby: host quits -> seat 2 is host, everyone stays in the lobby (" .. n .. " players, all modes)")
end

-- ===== 2. host quits mid-shop (between PvPs) and mid-PvP, every PvP mode, 2/3/5/8 players
local function lives_of(p) local pi = p.last("playerInfo"); return pi and pi.lives end
for _, n in ipairs({ 2, 3, 5, 8 }) do
	for _, mode in ipairs({ "attrition", "showdown", "koth", "teams", "deathmatch", "duel" }) do
		if not (mode == "duel" and n > 2) and not (mode == "teams" and (n % 2 == 1 or n < 4)) then
			-- mid-shop
			local ps = setup(n, mode, MODES[mode])
			start(ps)
			local sc = {}
			for i = 1, n do sc[i] = i * 100 end
			sc[n] = 1 -- the last seat loses this PvP
			blind(ps, sc)
			local before = {}
			for _, p in ipairs(ps) do p.send({ action = "setLocation", location = "loc_shop" }) end
			pump(4); run(1)
			clear(ps)
			quit(ps[1])
			run(3)
			local rest = live(ps)
			check_migrated(rest, ps[2], mode .. " mid-shop " .. n .. "p")
			run(Core.MIGRATION_HOLD + 1)
			if n > 2 then
				local s2 = {}
				for i, p in ipairs(rest) do s2[i] = 1000 - i end
				local res = blind(rest, s2)
				for _, p in ipairs(rest) do assert(res[p], mode .. " " .. n .. "p mid-shop: " .. p.name .. " finished the next PvP") end
			else
				assert(ps[2].last("winGame") or ps[2].count("enemyDisconnected") >= 0, "duel 2p: alone")
			end
			-- mid-PvP: the host quits after some players finished, with one final hand never processed
			ps = setup(n, mode, MODES[mode])
			start(ps)
			clear(ps)
			for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
			pump(8)
			assert(ps[n].last("startBlind"), "blind started")
			for i = 2, n - 1 do ps[i].send({ action = "playHand", score = tostring(500 + i), handsLeft = 0 }) end
			pump(6)
			if n >= 3 then ps[n].send({ action = "playHand", score = "9999", handsLeft = 0 }) end -- sent, host never reads it
			quit(ps[1])
			run(3)
			rest = live(ps)
			check_migrated(rest, ps[2], mode .. " mid-PvP " .. n .. "p")
			-- seat 2 (new host) plays its last hand only now
			if n == 2 then ps[2].send({ action = "playHand", score = "10", handsLeft = 0 }) end
			pump(6)
			run(Core.MIGRATION_HOLD + 1)
			pump(6)
			for _, p in ipairs(rest) do
				local m = p.last("endPvP") or p.last("winGame") or p.last("loseGame")
				assert(m, mode .. " " .. n .. "p mid-PvP: " .. p.name .. " got the PvP result after the migration")
			end
			if n >= 3 and mode ~= "teams" then
				local e = ps[n].last("endPvP") or ps[n].last("winGame")
				assert(e and (e.action == "winGame" or e.lost == false), mode .. " " .. n .. "p: the replayed top score (never seen by the old host) counted")
			end
		end
	end
	print("ok: in game: host quits mid-shop and mid-PvP, the match goes on (" .. n .. " players, all PvP modes)")
end

-- ===== 3. Deathmatch: a host who LEAVES is eliminated; a host who drops can rejoin within grace
do
	local ps = setup(5, "deathmatch", { deathmatch_grace = "60" })
	start(ps)
	clear(ps)
	ps[1].send({ action = "leaveLobby" }); pump(6)
	run(2)
	local rest = live(ps); for i = #rest, 1, -1 do if rest[i] == ps[1] then table.remove(rest, i) end end
	ps[1].gone = true
	check_migrated(rest, ps[2], "deathmatch host leaves")
	pump(6)
	local el = ps[3].last("playerEliminated")
	ok(el and el.playerId == ps[1].id and el.reason == "left", "deathmatch: the host who left is eliminated once everyone is back")
	local du = ps[4].last("deathmatchUpdate")
	ok(du and #du.alive == 4 and du.running, "deathmatch: standings show 4 left")
	local res = blind(rest, { 100, 200, 300, 400 })
	ok(res[ps[2]].lost == true and res[ps[5]].lost == false, "deathmatch: next PvP over the new host, lowest loses a life")
end
do
	local ps = setup(3, "deathmatch", { deathmatch_grace = "60" })
	start(ps)
	blind(ps, { 300, 200, 100 })
	local lives1 = 2 -- top score: no life lost
	-- host's connection drops (Steam kicks it from the lobby), Balatro keeps running
	NET.dead[ps[1].name] = true
	for id in pairs(NET.lobbies) do steam_leave(id, nil, ps[1].name) end
	clear(ps)
	run(3)
	check_migrated({ ps[2], ps[3] }, ps[2], "deathmatch host drops")
	NET.dead[ps[1].name] = nil -- connection back
	run(25) -- the old host notices it was cut off and rejoins as a guest
	ok(ps[1].r.mode == "guest" and ps[1].r.host == ps[2].name, "old host rejoined the new host as a guest (mode " .. ps[1].r.mode .. ", host " .. tostring(ps[1].r.host) .. ", owner " .. tostring(NET.lobbies[ps[2].r.lobby].owner) .. ")")
	ok(ps[1].last("rejoinedLobby") and lives_of(ps[1]) == lives1, "old host keeps its seat and lives (within grace)")
	ok(not ps[1].last("error"), "no error popups while the old host retries")
	ok(not ps[2].last("playerEliminated"), "nobody eliminated")
	local res = blind(ps, { 50, 60, 70 })
	ok(res[ps[1]] and res[ps[1]].action, "old host plays the next PvP as a guest")
end

-- host LEAVES (Leave lobby button) mid-PvP in every PvP mode: counts as a leave, the PvP finishes
for _, mode in ipairs({ "attrition", "showdown", "koth", "teams", "deathmatch" }) do
	local n = mode == "teams" and 4 or 3
	local ps = setup(n, mode, MODES[mode])
	start(ps)
	clear(ps)
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
	pump(8)
	ps[2].send({ action = "playHand", score = "700", handsLeft = 0 }); pump(4)
	ps[1].send({ action = "leaveLobby" }); ps[1].gone = true; pump(4)
	run(2)
	local rest = live(ps); table.remove(rest, 1)
	check_migrated(rest, ps[2], mode .. " host leaves mid-PvP")
	for i = 3, n do ps[i].send({ action = "playHand", score = tostring(100 * i), handsLeft = 0 }) end
	pump(8)
	ok(ps[3].last("playerLeft") and (ps[3].last("endPvP") or ps[3].last("winGame") or ps[3].last("loseGame")),
		mode .. ": host left mid-PvP -> playerLeft, the PvP still resolves among the others")
end

-- ===== 4. the successor leaves right after taking over; two players drop at once
for _, n in ipairs({ 3, 5, 8 }) do
	local ps = setup(n, "attrition")
	start(ps)
	clear(ps)
	quit(ps[1]); run(2)
	ps[2].send({ action = "leaveLobby" }); ps[2].gone = true; pump(4)
	run(3)
	local rest = live(ps)
	check_migrated(rest, ps[3], "successor leaves " .. n .. "p")
	run(Core.MIGRATION_HOLD + 1)
	if #rest >= 2 then
		local sc = {}
		for i = 1, #rest do sc[i] = i * 10 end
		local res = blind(rest, sc)
		assert(res[rest[1]] and (res[rest[1]].lost or res[rest[1]].lost == false), "successor leaves " .. n .. "p: game continues (0.6.9: held seats count as lowest)")
		local nl = 0; for _, p in ipairs(rest) do if res[p] and res[p].lost then nl = nl + 1 end end
		assert(nl <= 1, "successor leaves " .. n .. "p: absent seats take losing places first")
	end
	print("ok: host quits, the new host leaves right after -> seat 3 takes over (" .. n .. " players)")

	ps = setup(n, "koth", { starting_lives = "3" })
	start(ps)
	clear(ps)
	quit(ps[1]); quit(ps[2])
	run(3)
	rest = live(ps)
	check_migrated(rest, ps[3], "host + successor quit at once " .. n .. "p")
	print("ok: host and seat 2 quit at the same moment -> seat 3 takes over (" .. n .. " players)")

	-- seat 2 is cut off but still listed in the Steam lobby: the others wait, then seat 3 takes over
	ps = setup(n, "attrition")
	start(ps)
	clear(ps)
	quit(ps[1]); NET.dead[ps[2].name] = true; ps[2].alive = false
	run(HMmod.WAIT + 3)
	rest = live(ps)
	check_migrated(rest, ps[3], "silent successor " .. n .. "p")
	print("ok: seat 2 silent (still in the Steam lobby) -> after " .. HMmod.WAIT .. " s seat 3 takes over (" .. n .. " players)")
end

-- ===== 5. no successor possible -> clean fallback
do
	local ps = setup(2, "attrition")
	start(ps)
	clear(ps)
	ps[2].r.snap = nil -- e.g. a guest that never got a snapshot
	quit(ps[1]); run(25)
	ok(ps[2].last("hostMigrationFailed") and ps[2].last("disconnected") and ps[2].r.mode == "local", "without a snapshot: back to the menu with a message")
end

-- ===== 6. split brain: two players both promote; the better-ranked one wins
do
	local ps = setup(4, "attrition")
	start(ps)
	clear(ps)
	-- seat 3 can't see seat 2 for a moment and promotes itself as well
	quit(ps[1])
	local real_members = ps[3].b.members
	ps[3].b.members = function(id) local m = real_members(id); remove(m, ps[2].name); return m end
	run(2)
	ps[3].b.members = real_members
	run(6)
	local hosts = 0
	for _, p in ipairs(live(ps)) do if p.r.mode == "host" then hosts = hosts + 1 end end
	ok(hosts == 1 and ps[2].r.mode == "host" and ps[3].r.mode == "guest" and ps[4].r.host == ps[2].name, "split brain resolved: one host (seat 2)")
	run(Core.MIGRATION_HOLD + 1)
	local res = blind({ ps[2], ps[3], ps[4] }, { 10, 20, 30 })
	ok(res[ps[2]] and res[ps[2]].lost == false, "game continues after the split brain (0.6.9: the crashed host's held seat is lowest)")
end

-- ===== 7. a later guest join reaches the new host
do
	local ps = setup(3, "attrition")
	clear(ps)
	quit(ps[1]); run(3)
	local x = player("late_x"); all[#all + 1] = x
	x.send({ action = "connect" }); x.send({ action = "username", username = "late_x", modHash = "t" })
	x.send({ action = "joinLobby", code = ps[2].r.code }); pump(6); run(2)
	ok(x.last("joinedLobby") and x.r.host == ps[2].name, "a new player joins the migrated lobby by code (Steam owner = new host)")
end
-- ===== 8. frozen host: Balatro hangs but stays in the Steam lobby (no quit, no Steam drop)
local function freeze(p) p.alive = false end -- stops running; Steam keeps it listed, messages queue up
local function until_migrated(rest, limit)
	local t0 = T
	while T - t0 < limit do
		run(1)
		local all_in = true
		for _, p in ipairs(rest) do if not p.last("hostMigrated") then all_in = false end end
		if all_in then break end
	end
	return T - t0
end
local FROZEN = {}
for _, n in ipairs({ 2, 3, 5, 8 }) do
	for _, phase in ipairs({ "shop", "pvp" }) do
		local mode = (phase == "pvp" and n >= 3) and "deathmatch" or "attrition"
		local ps = setup(n, mode, { deathmatch_grace = "120" })
		start(ps)
		if phase == "shop" and n > 2 then
			local sc = {}; for i = 1, n do sc[i] = 100 * i end
			blind(ps, sc)
		end
		clear(ps)
		if phase == "pvp" then
			for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
			pump(8)
			for i = 2, n do ps[i].send({ action = "playHand", score = tostring(300 + i), handsLeft = 0 }) end
		end
		freeze(ps[1])
		local rest = {}; for i = 2, n do rest[#rest + 1] = ps[i] end
		local took = until_migrated(rest, 31)
		check_migrated(rest, ps[2], "frozen host " .. phase .. " " .. n .. "p")
		assert(ps[2].last("hostMigrating") and ps[2].last("hostMigrating").reason == "frozen", "migration reason is 'frozen'")
		assert(took <= 20, "frozen host " .. n .. "p replaced within 20 s (took " .. took .. " s)")
		FROZEN[n] = math.max(FROZEN[n] or 0, took)
		assert(NET.lobbies[ps[2].r.lobby].members[1] == ps[1].name, "the frozen host is still listed by Steam")
		-- a newcomer joining by code finds the new host although the frozen one still owns the Steam lobby
		if n == 3 and phase == "shop" then
			local x = player("late_f"); all[#all + 1] = x
			x.send({ action = "connect" }); x.send({ action = "username", username = "late_f", modHash = "t" })
			x.send({ action = "joinLobby", code = ps[2].r.code }); pump(6); run(1)
			ok(x.r.host == ps[2].name, "frozen owner: a join by code reaches the new host (member data)")
			x.send({ action = "leaveLobby" }); pump(4); x.alive = false; remove(all, x)
		end
		run(Core.MIGRATION_HOLD + 1); pump(6)
		if phase == "pvp" then
			for _, p in ipairs(rest) do assert(p.last("endPvP") or p.last("winGame") or p.last("loseGame"), "frozen mid-PvP " .. n .. "p: " .. p.name .. " got the PvP result") end
		elseif n > 2 then
			local sc = {}; for i = 1, #rest do sc[i] = 1000 - 50 * i end
			local res = blind(rest, sc)
			for _, p in ipairs(rest) do assert(res[p], "frozen " .. n .. "p: " .. p.name .. " finished the next PvP") end
		end
		-- the old host wakes up: it sees the higher epoch, steps down and rejoins as a guest
		ps[1].alive = true
		run(4)
		local hosts = 0
		for _, p in ipairs(ps) do if p.r.mode == "host" then hosts = hosts + 1 end end
		assert(hosts == 1 and ps[2].r.mode == "host", "unfreeze " .. n .. "p: still exactly one host")
		assert(ps[1].r.mode == "guest" and ps[1].r.host == ps[2].name, "unfreeze " .. n .. "p: old host follows the new host (mode " .. ps[1].r.mode .. ")")
		assert(ps[1].last("rejoinedLobby"), "unfreeze " .. n .. "p: old host got its seat back")
		assert(NET.lobbies[ps[2].r.lobby].owner == ps[2].name, "unfreeze " .. n .. "p: old host handed Steam ownership to the new host")
		if n >= 3 and phase == "shop" then
			local sc = {}; for i = 1, n do sc[i] = 1000 - i end
			local gone = {} -- 0.6.9: seats that lost their last life while away (absent = lowest)
			for _, q in ipairs(ps) do for _, m in ipairs(q.msgs) do if m.action == "playerEliminated" and m.reason == "absent" then gone[m.playerId] = true end end end
			local res = blind(ps, sc)
			if os.getenv("DBG") then for _, p in ipairs(ps) do local acts = {} for _, m in ipairs(p.msgs) do acts[#acts+1] = m.action end print(p.name, p.r.mode, table.concat(acts, ",")) end end
			for _, p in ipairs(ps) do
				-- 0.6.9: a seat that was away at PvPs may have lost its last life meanwhile (absent = lowest)
				assert(res[p] or gone[p.id], "unfreeze " .. n .. "p: " .. p.name .. " (incl. old host) plays the next PvP")
			end
		end
	end
	print("ok: frozen host (still in Steam) replaced in <= " .. FROZEN[n] .. " s, in the shop and mid-PvP; it steps down after unfreezing (" .. n .. " players)")
end

-- host AND seat 2 freeze together (5 players): the majority still agrees, seat 3 takes over
do
	local ps = setup(5, "attrition")
	start(ps); clear(ps)
	freeze(ps[1]); freeze(ps[2])
	local rest = { ps[3], ps[4], ps[5] }
	local took = until_migrated(rest, 31)
	check_migrated(rest, ps[3], "host + seat 2 frozen 5p")
	ok(took <= 20, "host and seat 2 frozen at once (5 players): seat 3 takes over after " .. took .. " s")
	-- both stay frozen for a long time (90 s), then wake up: both step down and rejoin
	run(90)
	ps[1].alive, ps[2].alive = true, true
	run(5)
	ok(ps[1].r.mode == "guest" and ps[2].r.mode == "guest" and ps[1].r.host == ps[3].name and ps[2].r.host == ps[3].name
		and ps[1].last("rejoinedLobby") and ps[2].last("rejoinedLobby"),
		"after a 90 s freeze the old host and seat 2 step down and rejoin seat 3")
end

-- ===== 9. false alarm: ONE guest's connection breaks, the host is fine
for _, n in ipairs({ 3, 5, 8 }) do
	local ps = setup(n, "attrition")
	start(ps)
	clear(ps)
	local bad = ps[n == 3 and 2 or 3] -- also the successor case (seat 2) for 3 players
	NET.dead[bad.name] = true -- P2P gone, Steam still lists everybody
	run(25)
	for _, p in ipairs(ps) do
		assert(not (p ~= bad and p.last("hostMigrating")), "false alarm " .. n .. "p: " .. p.name .. " did not migrate")
	end
	assert(ps[1].r.mode == "host" and bad.r.mode == "guest", "false alarm " .. n .. "p: no takeover by the bad guest")
	run(6)
	ok(bad.r.mode == "local" and bad.last("hostMigrationFailed") and bad.last("hostMigrationFailed").lost,
		"false alarm " .. n .. "p: the bad guest falls back after 30 s (not 60), nobody else migrates")
	NET.dead[bad.name] = nil
	bad.msgs = {}
	bad.send({ action = "joinLobby", code = ps[1].r.code }); pump(6); run(1)
	ok(bad.last("rejoinedLobby") and bad.r.host == ps[1].name, "false alarm " .. n .. "p: it rejoins the same host by code")
end
-- 2 players: the lone guest can't tell "host frozen" from "my connection broke". It takes over
-- after 13 s; when the connection is back the old host sees the higher epoch and joins it.
do
	local ps = setup(2, "attrition")
	start(ps); clear(ps)
	NET.dead[ps[2].name] = true
	local took = until_migrated({ ps[2] }, 31)
	ok(ps[2].r.mode == "host" and took <= 15, "2p: lone guest takes over after " .. took .. " s of silence")
	NET.dead[ps[2].name] = nil
	run(6)
	ok(ps[1].r.mode == "guest" and ps[1].r.host == ps[2].name and ps[1].last("rejoinedLobby"), "2p: the old host steps down and joins the guest once the link is back")
end

-- 0.6.8 final (B1): the frozen host also drops out of the member list while frozen (dev transport /
-- Steam timing), stays frozen past the old watch window, then comes back: it must step down
do
	local ps = setup(4, "attrition")
	start(ps); clear(ps)
	local l = ps[1].r.lobby
	freeze(ps[1]); remove(NET.lobbies[l].members, ps[1].name)
	local rest = { ps[2], ps[3], ps[4] }
	until_migrated(rest, 40)
	local nh = host_of(rest)
	ok(nh and nh ~= ps[1], "B1: a guest took over from the frozen host")
	run(60)
	table.insert(NET.lobbies[l].members, ps[1].name); ps[1].alive = true
	run(8)
	local hosts = 0
	for _, p in ipairs(ps) do if p.r.mode == "host" then hosts = hosts + 1 end end
	ok(hosts == 1 and ps[1].r.mode == "guest" and ps[1].r.host == nh.name, "B1: old host back after 60 s steps down (no split brain)")
end

-- 0.6.8 final (B2): a guest freezes past the P2P timeout (host holds its seat), then wakes up and
-- keeps playing: the host asks it to rejoin with its token, it gets its seat back
do
	local ps = setup(3, "attrition")
	start(ps); clear(ps)
	freeze(ps[3]); run(28)
	ok(ps[1].r.dropped and ps[1].r.dropped[ps[3].name], "B2: host timed the frozen guest out (seat held)")
	ps[3].alive = true
	ps[3].send({ action = "setLocation", location = "loc_shop" })
	run(6)
	ok(ps[3].last("rejoinedLobby") and ps[3].r.mode == "guest" and ps[3].r.host == ps[1].name, "B2: woken guest re-attached by token")
	ok(not (ps[1].r.dropped or {})[ps[3].name], "B2: host no longer treats it as dropped")
end

-- 0.6.8 final (B3): the whole machine/every game hitches at once for 40 s (2 and 3 players):
-- nobody may drop anybody, no migration, no "Lost connection" on wake-up
for _, n in ipairs({ 2, 3 }) do
	local ps = setup(n, "attrition")
	start(ps); clear(ps)
	T = T + 40 -- nobody ran for 40 s
	run(10)
	local hosts = 0
	for _, p in ipairs(ps) do if p.r.mode == "host" then hosts = hosts + 1 end end
	ok(hosts == 1 and ps[1].r.mode == "host" and not ps[2].last("hostMigrationFailed") and not ps[2].last("hostMigrating")
		and not (ps[1].r.dropped or {})[ps[2].name], "B3: everyone frozen 40 s at once (" .. n .. "p): no drop, no migration")
end

print(string.format("info: largest snapshot after a migration %.1f KB", (SNAPMAX or 0) / 1024))
print("PASS: host migration tests")
