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
print("PASS: rejoin same peer")
