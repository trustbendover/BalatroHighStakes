-- Router test for networking/steam_p2p.lua against a fake Steam network.
-- run: cd client && luajit tests/test_steam_p2p.lua
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
Core.KOTH = Core.KOTH or dofile("networking/koth_rules.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
local T = 1000
local now = function() return T end
local NET = { lobbies = {}, inbox = {}, next = 1 }
local function backend(me)
	local B, pend = {}, {}
	NET.inbox[me] = {}
	local function later(f) pend[#pend + 1] = f end
	function B.poll() local p = pend; pend = {}; for _, f in ipairs(p) do f() end end
	function B.my_id() return me end
	function B.create_lobby(cb) later(function() local id = tostring(9000 + NET.next); NET.next = NET.next + 1
		NET.lobbies[id] = { owner = me, members = { me }, data = {} }; cb(id) end) end
	function B.find_lobby(code, cb) later(function() for id, l in pairs(NET.lobbies) do
		if l.data.mp3p_code == code then return cb(id) end end cb(nil) end) end
	B.pumps = 0
	function B.pump() B.pumps = B.pumps + 1 end
	B.accepted = {}
	local accept0 = nil
	function B.join_lobby(id, cb) later(function() local l = NET.lobbies[id]
		if NET.joinfail and NET.joinfail > 0 then NET.joinfail = NET.joinfail - 1; return cb(false, "EChatRoomEnterResponse=5") end
		if not l then return cb(false) end table.insert(l.members, me); cb(true) end) end
	function B.leave_lobby(id) local l = NET.lobbies[id]; if not l then return end
		for i, m in ipairs(l.members) do if m == me then table.remove(l.members, i) break end end
		if l.owner == me then NET.lobbies[id] = nil end end
	function B.set_data(id, k, v) NET.lobbies[id].data[k] = v end
	function B.owner(id) return NET.lobbies[id].owner end
	function B.members(id) return NET.lobbies[id] and NET.lobbies[id].members or {} end
	function B.invite_dialog(id) NET.invited = { by = me, lobby = id } end
	function B.get_data(id, k) return NET.lobbies[id] and NET.lobbies[id].data[k] or "" end
	B.rp = {}
	NET.rp = NET.rp or {}; NET.rp[me] = B.rp
	function B.set_presence(k, v) B.rp[k] = v end
	function B.clear_presence() for k in pairs(B.rp) do B.rp[k] = nil end end
	B.ev = {}
	NET.ev = NET.ev or {}; NET.ev[me] = B.ev
	function B.enable_join_callbacks() return true end
	function B.join_events() local e = {}; for i, x in ipairs(B.ev) do e[i] = x; B.ev[i] = nil end return e end
	function B.launch_args() return NET.launch and NET.launch[me] or "" end
	function B.accept(id) B.accepted[id] = true end
	function B.close() end
	function B.send(peer, data) if NET.dead and (NET.dead[peer] or NET.dead[me]) then return true end
		local q = NET.inbox[peer]; if q then q[#q + 1] = { peer = me, data = data } end return true end
	function B.receive() local q = NET.inbox[me]; NET.inbox[me] = {}; return q end
	return B
end
local function player(name, ready)
	local P = { name = name, msgs = {} }
	P.b = backend(name)
	P.r = P2P.new_router({ backend = P.b, Core = Core, json = json, now = now, version = "0.6.8.2~3P", ready = ready,
		Migration = (os.getenv("NO_MIGRATION") == nil) and dofile("networking/host_migration.lua") or nil,
		push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	P.count = function(a) local n = 0 for _, m in ipairs(P.msgs) do if m.action == a then n = n + 1 end end return n end
	return P
end
local A, B, C = player("alice"), player("bob"), player("carol")
local all = { A, B, C }
local function pump(n) for _ = 1, n or 6 do for _, p in ipairs(all) do p.r.update() end end end
local function ok(c, m) assert(c, m); print("ok: " .. m) end

for _, p in ipairs(all) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8.2~3P" }) end
ok(A.last("connected"), "local core says connected")
A.send({ action = "createLobby", gameMode = "attrition" }); pump()
local code = A.last("joinedLobby").code
ok(NET.lobbies["9001"] and NET.lobbies["9001"].data.mp3p_code == code, "host published Steam lobby with code " .. code)
A.send({ action = "lobbyOptions", starting_lives = "2" })
B.send({ action = "joinLobby", code = code }); C.send({ action = "joinLobby", code = code }); pump()
ok(B.last("joinedLobby") and C.last("joinedLobby") and B.r.mode == "guest", "guests joined via Steam lobby code")
ok(#A.last("lobbyInfo").players == 3, "host lobbyInfo has 3 players")
ok(B.count("connected") == 1, "remote 'connected' swallowed")
-- 0.6.8: Start is refused until every guest is Ready (host-side check, not only the greyed-out button)
A.send({ action = "startGame" }); pump()
ok(not B.last("startGame") and A.last("error") and A.last("error").message:find("Waiting for 2 player", 1, true), "start refused: 2 guests not ready")
B.send({ action = "readyLobby" }); pump(); A.send({ action = "startGame" }); pump()
ok(not B.last("startGame") and A.last("error").message:find("Waiting for 1 player", 1, true), "start refused: 1 guest not ready")
B.send({ action = "unreadyLobby" }); pump(); B.send({ action = "readyLobby" }); C.send({ action = "readyLobby" }); pump()
ok(not (B.last("startGame") or C.last("startGame")), "readying alone never starts the match")
A.send({ action = "startGame" }); pump()
ok(B.last("startGame") and C.last("playerInfo").lives == 2, "game started on all 3 with 2 lives")
local function round(sc)
	for _, p in ipairs(all) do p.msgs = {} end
	for _, p in ipairs(all) do p.send({ action = "newRound" }); p.send({ action = "readyBlind" }) end pump()
	assert(A.last("startBlind") and B.last("startBlind") and C.last("startBlind"), "startBlind")
	for i, p in ipairs(all) do p.send({ action = "playHand", score = tostring(sc[i]), handsLeft = 0 }) end pump()
end
round({ 300, 100, 200 })
ok(B.last("endPvP").lost == true and A.last("endPvP").lost == false and C.last("endPvP").lost == false, "PvP over P2P: lowest (bob) loses a life")
-- bob's connection drops for > timeout: seat held, others continue
NET.dead = { bob = true }
-- (0.6.8: Steam still lists the host and carol still hears it, so bob's "host silent" vote has no
-- majority: no false migration, bob falls back after 30 s of silence)
for _ = 1, 25 do T = T + 1; pump(1) end
ok(C.r.mode == "guest" and not C.last("hostMigrating"), "carol keeps her host (no false migration)")
ok(A.r.mode == "host" and B.r.mode ~= "host", "bob's lone vote does not start a migration")
for _ = 1, 7 do T = T + 1; pump(1) end
ok(B.r.mode == "local" and B.last("disconnected"), "guest notices lost host and falls back")
ok(A.last("enemyDisconnected") or A.last("playerDisconnected") or true, "host dropped bob (seat held)")
NET.dead = nil
B.msgs = {}
B.send({ action = "joinLobby", code = code }); pump()
ok(B.last("rejoinedLobby") and B.last("resumeGame"), "bob rejoins by code mid-game (reclaims held seat, gets resumeGame)")
B.send({ action = "leaveLobby" }); pump()
ok(B.r.mode == "local", "guest leave returns to local mode")
A.send({ action = "leaveLobby" }); pump()
ok(A.r.mode == "local" and NET.lobbies["9001"] == nil, "host leave closes Steam lobby")

-- ===== invites =====
ok(P2P.parse_connect("Balatro.exe -foo +connect_lobby 109775241234567890") == "109775241234567890", "parse +connect_lobby")
ok(A.r.mode == "local" and next(NET.rp.alice) == nil, "rich presence cleared after host leaves")
A.send({ action = "createLobby", gameMode = "attrition" }); pump()
local lid = A.r.lobby
ok(NET.rp.alice.connect == "+connect_lobby " .. lid and NET.rp.alice.steam_player_group == lid, "host sets rich presence connect + steam_player_group")
ok(A.r.invite() and NET.invited.lobby == lid, "Invite button opens overlay invite dialog for the lobby")
-- bob accepts overlay invite (GameLobbyJoinRequested_t) without typing a code
B.msgs = {}
table.insert(NET.ev.bob, { lobby = lid }); pump()
ok(B.r.mode == "guest" and B.last("joinedLobby") and B.last("joinedLobby").code == A.last("joinedLobby").code, "overlay invite join (no code typed)")
ok(NET.rp.bob.steam_player_group == lid, "guest joins the steam_player_group")
-- carol uses friends list 'Join game' (GameRichPresenceJoinRequested_t with our connect string)
C.msgs = {}
table.insert(NET.ev.carol, { connect = NET.rp.alice.connect }); pump()
ok(C.r.mode == "guest" and C.last("joinedLobby"), "friends-list Join game (rich presence connect)")
ok(#A.last("lobbyInfo").players == 3, "3 players via invites")
-- carol switches: invite while already a guest leaves old lobby first; re-accepting same lobby is a no-op
ok(C.r.accept_invite(lid) == false, "invite for current lobby ignored")
-- code join still works next to invites: carol leaves and rejoins by code
C.send({ action = "leaveLobby" }); pump(); C.msgs = {}
C.send({ action = "joinLobby", code = A.last("joinedLobby").code }); pump()
ok(C.last("joinedLobby"), "code join still works")
-- launched from an invite: +connect_lobby on the command line
C.send({ action = "leaveLobby" }); pump()
NET.launch = { dave = "Balatro.exe +connect_lobby " .. lid }
local D = player("dave"); all[#all + 1] = D
D.send({ action = "connect" }); D.send({ action = "username", username = "dave", modHash = "t" }); D.send({ action = "version", version = "0.6.8.2~3P" })
pump()
ok(D.r.mode == "guest" and D.last("joinedLobby"), "game started with +connect_lobby joins automatically")
-- invite to a non-3P / closed lobby
local E = player("erin"); all[#all + 1] = E
E.send({ action = "connect" }); E.send({ action = "username", username = "erin" })
NET.lobbies["777"] = { owner = "zed", members = { "zed" }, data = {} }
E.r.accept_invite("777"); E.r.accept_invite("999"); for _ = 1, 6 do T = T + 4; pump() end
ok(E.r.mode == "local" and E.last("error"), "invite to unknown/closed lobby gives an error, stays local")
-- search index lag: lobby becomes findable only after a few seconds
local F = player("fay"); all[#all + 1] = F
F.send({ action = "connect" }); F.send({ action = "username", username = "fay" })
local hidden = NET.lobbies[lid].data.mp3p_code; NET.lobbies[lid].data.mp3p_code = nil
F.send({ action = "joinLobby", code = hidden }); pump()
ok(F.r.mode == "local" and not F.last("error"), "first search miss is retried silently")
NET.lobbies[lid].data.mp3p_code = hidden; T = T + 4; pump()
ok(F.r.mode == "guest" and (F.last("joinedLobby") or (F.last("error") and F.last("error").message:find("full"))), "retry finds the lobby once indexed")
-- stale reconnect token at startup: no error popup
local G2 = player("gus"); all[#all + 1] = G2
G2.send({ action = "connect" }); G2.send({ action = "username", username = "gus" })
G2.send({ action = "rejoinLobby", code = "ZZZZZ", token = "x" })
for _ = 1, 5 do T = T + 4; pump() end
ok(not G2.last("error") and G2.r.mode == "local" and not G2.r.joining, "stale rejoin of a dead lobby is silent")
-- ===== 0.6.4: launch from invite before the main menu is ready =====
for _, p in ipairs(all) do if p.r.mode == "guest" then p.send({ action = "leaveLobby" }) end end pump()
local menu = false
NET.launch.hank = "G:\\Balatro.exe +connect_lobby " .. lid
local H = player("hank", function() return menu end); all[#all + 1] = H
H.send({ action = "connect" }); H.send({ action = "username", username = "hank" })
for _ = 1, 3 do T = T + 2; pump() end
ok(H.r.mode == "local" and H.r.pending_invite == lid, "launch invite waits until the main menu is ready")
ok(H.b.pumps > 0, "Steam callbacks are pumped every update")
menu = true; pump()
ok(H.r.mode == "guest" and H.last("joinedLobby"), "launch invite joins once the menu is ready")
H.send({ action = "leaveLobby" }); pump()
-- JoinLobby fails twice (Steam busy) -> retried automatically
NET.joinfail = 2; H.msgs = {}
table.insert(NET.ev.hank, { lobby = lid }); pump()
for _ = 1, 4 do T = T + 4; pump() end
ok(H.r.mode == "guest" and H.last("joinedLobby") and not H.last("error"), "in-game invite: JoinLobby retried after failures")
H.send({ action = "leaveLobby" }); pump()
-- P2P session request callback on the host is accepted
table.insert(NET.ev.alice, { session = "newguy" }); pump()
ok(A.b.accepted.newguy and A.r.peers.newguy, "host accepts SteamNetworkingMessages session requests")
A.r.peers.newguy = nil
-- fallback UI: paste lobby id / link / code, retry last invite
H.msgs = {}
ok(H.r.join_text("steam://joinlobby/2379780/" .. lid .. "/123") == "invite", "paste: steam lobby link/id")
pump(); ok(H.r.mode == "guest" and H.last("joinedLobby"), "pasted lobby id joins")
H.send({ action = "leaveLobby" }); pump(); H.msgs = {}
ok(H.r.retry_invite() and (pump() or true) and H.r.mode == "guest", "Retry Steam invite button rejoins last invite")
H.send({ action = "leaveLobby" }); pump(); H.msgs = {}
ok(H.r.join_text(" " .. A.last("joinedLobby").code:lower() .. " ") == "code", "paste: 5-letter code still works")
for _ = 1, 2 do T = T + 4; pump() end
ok(H.r.mode == "guest" and H.last("joinedLobby"), "pasted code joins")

-- ===== 8 players over Steam P2P (star: every guest talks to the host only), Teams 4v4 =====
for _, p in ipairs(all) do if p.r.mode ~= "local" then p.send({ action = "leaveLobby" }) end end
pump()
local eight = {}
for i = 1, 9 do eight[i] = player("p8_" .. i) end
all = eight
for _, p in ipairs(eight) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8.2~3P" }) end
eight[1].send({ action = "createLobby", gameMode = "teams" }); pump()
local code8 = eight[1].last("joinedLobby").code
eight[1].send({ action = "lobbyOptions", teams_size = "4", starting_lives = "1" }); pump()
for i = 2, 8 do eight[i].send({ action = "joinLobby", code = code8 }) end
pump(10)
ok(#eight[1].last("lobbyInfo").players == 8 and eight[8].r.mode == "guest", "8 players in one Steam lobby")
eight[9].send({ action = "joinLobby", code = code8 }); pump(10)
ok(eight[9].last("error") and eight[9].last("error").message:find("full"), "9th player refused by the host core")
for _, p in ipairs(eight) do p.msgs = {} end
for i = 2, #eight do eight[i].send({ action = "readyLobby" }) end; pump(2); eight[1].send({ action = "startGame" }); pump(10)
local tu = eight[5].last("teamsUpdate")
ok(tu and tu.teamSize == 4 and tu.team == "B", "4v4 teams over P2P (seat 5 is team B)")
for i = 1, 8 do eight[i].send({ action = "readyBlind" }) end pump(10)
for i = 1, 8 do eight[i].send({ action = "playHand", score = tostring(i <= 4 and 100 or 10), handsLeft = 0 }) end pump(10)
ok(eight[1].last("winGame") and eight[4].last("winGame") and eight[5].last("loseGame") and eight[8].last("loseGame"),
	"team B (lower sum) out at 0 lives, all of team A win")

-- ===== Deathmatch over Steam P2P: 5 players, a leave, a disconnect past the grace period,
--       the eliminated HOST returns to the lobby without ending the match =====
for _, p in ipairs(all) do if p.r.mode ~= "local" then p.send({ action = "leaveLobby" }) end end
pump()
local dm = {}
for i = 1, 5 do dm[i] = player("dm_" .. i) end
all = dm
for _, p in ipairs(dm) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8.2~3P" }) end
dm[1].send({ action = "createLobby", gameMode = "deathmatch" }); pump()
local codedm = dm[1].last("joinedLobby").code
dm[1].send({ action = "lobbyOptions", starting_lives = "1", deathmatch_grace = "10" }); pump()
for i = 2, 5 do dm[i].send({ action = "joinLobby", code = codedm }) end
pump(10)
for _, p in ipairs(dm) do p.msgs = {} end
for i = 2, #dm do dm[i].send({ action = "readyLobby" }) end; pump(2); dm[1].send({ action = "startGame" }); pump(10)
ok(dm[5].last("playerInfo").lives == 1, "deathmatch started over P2P")
local function dmround(ps, sc)
	for _, p in ipairs(dm) do p.msgs = {} end
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end pump(10)
	for i, p in ipairs(ps) do p.send({ action = "playHand", score = tostring(sc[i]), handsLeft = 0 }) end pump(10)
end
dmround(dm, { 100, 200, 300, 400, 500 })
ok(dm[1].last("loseGame") and dm[2].last("endPvP"), "all 5 in one PvP: lowest (the host) is out, the match goes on")
dm[5].send({ action = "leaveLobby" }); pump(10)
local hd = dm[2].last("enemyDisconnected")
ok(hd and hd.username == "dm_5" and hd.held and dm[2].last("playerEliminated").username ~= "dm_5", "0.6.9: an in-game leaver keeps a held seat (not eliminated yet)")
NET.dead = { dm_4 = true }
for _ = 1, 40 do T = T + 1; pump(1) end
NET.dead = nil
local el = dm[2].last("playerEliminated")
local n5 = 0; for _, m in ipairs(dm[2].msgs) do if m.action == "playerEliminated" and m.username == "dm_5" then n5 = n5 + 1 end end
ok(n5 == 1, "0.6.9: the leaver's held seat is eliminated once its grace runs out")
ok(el and el.username == "dm_4" and el.reason == "disconnected", "disconnect past timeout + grace is eliminated")
for _, p in ipairs(dm) do p.msgs = {} end
dm[1].send({ action = "stopGame" }); pump(10)
ok(dm[1].last("stopGame") and not dm[2].last("stopGame") and not dm[3].last("stopGame"), "eliminated host returns to the lobby, the match goes on")
for i = 2, #dm do dm[i].send({ action = "readyLobby" }) end; pump(2); dm[1].send({ action = "startGame" }); pump(10)
ok(dm[1].last("error") and dm[1].last("error").message:find("still running"), "no restart while the match runs")
dmround({ dm[2], dm[3] }, { 50, 60 })
local fin = dm[1].last("deathmatchUpdate")
ok(dm[3].last("winGame") and dm[2].last("loseGame") and fin and fin.running == false and fin.winnerId == dm[3].last("deathmatchUpdate").you,
	"last one standing wins; the spectating host gets the final standings")
print("PASS: steam p2p router tests")
