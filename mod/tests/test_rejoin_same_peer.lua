-- luajit tests/test_rejoin_same_peer.lua (run from mod/): a restarted game on the same peer rejoins its own seat
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
local S = Core.new(); S.log = function() end
local function pl(id)
	local p = { id = id, username = id, lives = 3, ante = 2, score = Core.parse_score("0"), msgs = {}, reconnectToken = "tok" .. id }
	p.send = function(t) p.msgs[#p.msgs + 1] = t end
	function p.got(a) for _, m in ipairs(p.msgs) do if m.action == a then return m end end end
	return p
end
local a, b, c = pl("a"), pl("b"), pl("c")
local L = { code = "T", players = { a, b, c }, gameMode = "attrition", options = {}, slots = {}, isInGame = true, blindSeq = 0, seed = "S" }
for _, p in ipairs(L.players) do p.lobby = L end
S.lobbies = S.lobbies or {}; S.lobbies.T = L
b.lives = 2
S:receive(b, { action = "rejoinLobby", code = "T", reconnectToken = "tokb" })
ok(not b.got("rejoinFailed"), "no 'Token invalid' for the same peer")
ok(b.got("rejoinedLobby") and b.got("resumeGame") and b.got("resumeGame").lives == 2, "seat given back with its lives")
local n = 0; for _, p in ipairs(L.players) do if p == b then n = n + 1 end end
ok(#L.players == 3 and n == 1 and #L.slots == 0, "no duplicate seat, no held slot left")
S:receive(c, { action = "rejoinLobby", code = "T", reconnectToken = "wrong" })
ok(c.got("rejoinFailed"), "a wrong token still fails")

-- os.time() granularity: one integer step is not a full second of a 1s grace.
ok(Core.grace_spent(0, true) == 0 and Core.grace_spent(1, true) == 0, "coarse clock: the next whole second is not a full second")
ok(Core.grace_spent(2, true) == 1, "coarse clock: two ticks cover a 1s grace")
ok(Core.grace_spent(1, false) == 1 and Core.grace_spent(0.2, false) == 0.2, "fractional clock counts the time that actually passed")

local function grace_lobby(coarse)
	local T = 9000
	local G = Core.new({ now = function() return T end, log = function() end })
	G.coarse_clock = coarse
	local function client(name)
		local box = {}
		local p = G:connect(function(m) box[#box + 1] = m end)
		G:receive(p, { action = "username", username = name })
		function p.last(act) for i = #box, 1, -1 do if box[i].action == act then return box[i] end end end
		return p
	end
	local host, drop = client("Host"), client("Drop")
	G:receive(host, { action = "createLobby", gameMode = "deathmatch" })
	local code = host.last("joinedLobby").code
	G:receive(host, { action = "lobbyOptions", starting_lives = "2", deathmatch_grace = "1" })
	G:receive(drop, { action = "joinLobby", code = code })
	G:receive(drop, { action = "readyLobby" })
	G:receive(host, { action = "startGame" })
	return G, function(t) T = t end, host, drop, code
end

do -- a 1s os.time() grace survives the first integer tick, then eliminates
	local G, setT, host, drop = grace_lobby(true)
	G:disconnect(drop)
	local since = host.lobby.slots[1].since
	setT(since + 1); G:tick()
	ok(not host.last("playerEliminated"), "1s grace is not over on the first os.time() tick")
	setT(since + 2); G:tick()
	ok(host.last("playerEliminated") and host.last("playerEliminated").reason == "disconnected", "1s grace ends on the second os.time() tick")
end

do -- rejoin clears the timestamp; a later tick must not eliminate the seat
	local G, setT, host, drop, code = grace_lobby(true)
	local token = drop.reconnectToken
	G:disconnect(drop)
	local since = host.lobby.slots[1].since
	setT(since + 1); G:tick()
	local back = G:connect(function() end)
	G:receive(back, { action = "username", username = "Drop" })
	G:receive(back, { action = "rejoinLobby", code = code, reconnectToken = token })
	ok(back.lobby and not back.eliminated and (back.lives or 0) > 0, "rejoin within a coarse 1s grace restores the live seat")
	ok(#host.lobby.slots == 0, "rejoin drops the held seat and its grace timestamp")
	setT(since + 5); G:tick()
	ok(not host.last("playerEliminated"), "after rejoin, the old grace does not eliminate the seat")
end

do -- a fractional clock expires a 1s grace at exactly one second
	local G, setT, host, drop = grace_lobby(false)
	G:disconnect(drop)
	local since = host.lobby.slots[1].since
	setT(since + 0.9); G:tick()
	ok(not host.last("playerEliminated"), "0.9s on a fractional clock is still inside a 1s grace")
	setT(since + 1); G:tick()
	ok(host.last("playerEliminated") and host.last("playerEliminated").playerId == drop.id, "1.0s on a fractional clock eliminates")
end

print("PASS: rejoin same peer")
