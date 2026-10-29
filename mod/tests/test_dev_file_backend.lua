-- luajit tests/test_dev_file_backend.lua (run from mod/): DEV-ONLY local transport (dev/file_backend.lua).
-- Real files in a temp folder, real router + host core: 4 "instances" form a lobby by code, ready up, play a
-- PvP blind, the host quits (host migration), a guest restarts with a new session and rejoins.
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
Core.KOTH = dofile("networking/koth_rules.lua"); Core.TEAMS = dofile("networking/teams_rules.lua"); Core.PVP = dofile("networking/pvp_rules.lua")
local FB = dofile("dev/file_backend.lua")
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local DIR = os.tmpname(); os.remove(DIR); os.execute('mkdir -p "' .. DIR .. '"')
local T, CLK = 1000, 0
local now = function() return T end
local PEERS = { "dev1", "dev2", "dev3", "dev4" }
local function inst(name, session)
	local P = { name = name, msgs = {}, alive = true }
	P.b = FB.new({ dir = DIR, me = name, peers = PEERS, now = now, clock = function() return CLK end, session = session })
	P.r = P2P.new_router({ backend = P.b, Core = Core, json = json, now = now, version = "0.6.8", ready = function() return true end,
		Migration = dofile("networking/host_migration.lua"), push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	P.send({ action = "connect" }); P.send({ action = "username", username = name, modHash = "t" }); P.send({ action = "version", version = "0.6.8" })
	return P
end
local ps = { inst("dev1"), inst("dev2"), inst("dev3"), inst("dev4") }
local function pump(n) for _ = 1, n or 8 do CLK = CLK + 0.06; for _, p in ipairs(ps) do if p.alive then p.r.update() end end end end
local function run(s) for _ = 1, s do T = T + 1; pump(4) end end

ps[1].send({ action = "createLobby", gameMode = "attrition" }); pump()
local code = ps[1].last("joinedLobby") and ps[1].last("joinedLobby").code
ok(code and ps[1].r.mode == "host", "dev1 hosts lobby " .. tostring(code) .. " over the file transport")
for i = 2, 4 do ps[i].send({ action = "joinLobby", code = code }) end
run(15)
ok(ps[2].last("joinedLobby") and ps[4].last("joinedLobby") and #ps[1].last("lobbyInfo").players == 4, "3 guests found the lobby by code and joined (4 players)")
ps[1].send({ action = "startGame" }); pump()
ok(ps[1].last("error") and ps[1].last("error").message:find("Waiting for 3", 1, true), "ready gating works over the file transport")
for i = 2, 4 do ps[i].send({ action = "readyLobby" }) end; pump()
ps[1].send({ action = "startGame" }); run(2)
ok(ps[2].last("startGame") and ps[4].last("startGame"), "match started on every instance")
local dirlist = io.popen('ls "' .. DIR .. '/tmp" | wc -l'):read("*a")
ok(tonumber(dirlist) == 0, "no leftover tmp files (atomic rename)")

-- host quits Balatro: stops heartbeating, files stay (like a crash); after STALE seconds the others migrate
ps[1].alive = false
run(FB.STALE + 30)
local newhost
for i = 2, 4 do if ps[i].r.mode == "host" then newhost = ps[i] end end
ok(newhost ~= nil, "host gone -> host migration to " .. tostring(newhost and newhost.name))
ok(ps[2].b.owner(ps[2].r.lobby) == newhost.name, "lobby owner follows (Steam-like: longest-standing member)")

-- a guest restarts (new session token, seq numbers from 1 again) and its messages still arrive
local g
for i = 2, 4 do if ps[i] ~= newhost then g = i break end end
ps[g].b = nil
local before = #newhost.msgs
local fresh = FB.new({ dir = DIR, me = ps[g].name, peers = PEERS, now = now, clock = function() return CLK end, session = "restart2" })
ok(fresh.send(newhost.name, '{"action":"keepAlive"}') and fresh.send(newhost.name, '{"action":"keepAlive"}'), "restarted instance can send")
CLK = CLK + 1
local got = newhost.b.receive()
local n = 0 for _, m in ipairs(got) do if m.peer == ps[g].name then n = n + 1 end end
ok(n == 2, "new session is picked up, messages read in order from seq 1")
-- Windows replace (remove+rename) or an AV scan can hide a state file for a moment: not a departure
do
	local lid = "Lgrace"; local a = FB.new({ dir = DIR, me = "dev1", peers = PEERS, now = now, session = "ga" })
	local b = FB.new({ dir = DIR, me = "dev2", peers = PEERS, now = now, session = "gb" })
	local done; a.create_lobby(function(id) lid = id end); a.poll()
	b.join_lobby(lid, function(x) done = x end); b.poll()
	ok(done and #a.members(lid) == 2 and a.owner(lid) == "dev1", "grace: both members listed")
	os.remove(DIR .. "/lobby/" .. lid .. "__m__dev2"); os.remove(DIR .. "/lobby/" .. lid .. "__owner")
	ok(#a.members(lid) == 2 and a.owner(lid) == "dev1", "grace: a briefly missing member/owner file is bridged")
	T = T + 7
	ok(#a.members(lid) == 1, "grace: a file that stays missing counts as gone")
	b.leave_lobby(lid); ok(#a.members(lid) == 1, "grace: explicit leave")
end
os.execute('rm -rf "' .. DIR .. '"')
print("PASS: dev file backend")
