-- Unchanged lobby and opponent snapshots are not sent again.
-- luajit tests/test_net_quiet.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
local P2P = dofile("networking/steam_p2p.lua")
ok(P2P.TIMEOUT > 20 and P2P.TIMEOUT < 30 and P2P.HEARTBEAT >= 5, "a short stall stays connected, and the 30s fallback still runs")

local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	c.box = msgs
	function c.count(a) local n = 0 for _, m in ipairs(msgs) do if m.action == a then n = n + 1 end end return n end
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end

local S = Core.new({ now = function() return 1000 end, log = function() end })
local ann, bob = client(S, "Ann~1"), client(S, "Bob~2")
S:receive(ann, { action = "createLobby", gameMode = "attrition" })
local code = ann.last("joinedLobby").code
S:receive(bob, { action = "joinLobby", code = code })
local before = ann.count("lobbyInfo")
S:lobby_info(ann.lobby)
ok(ann.count("lobbyInfo") == before, "an unchanged roster is not sent again")
S:receive(ann, { action = "lobbyInfo" })
ok(ann.count("lobbyInfo") == before + 1, "an explicit lobby refresh is still answered")

bob.isReadyLobby = true
S:receive(ann, { action = "startGame" })
S:receive(ann, { action = "readyBlind" })
S:receive(bob, { action = "readyBlind" })
local info_before = bob.count("enemyInfo")
S:receive(ann, { action = "playHand", score = "100", handsLeft = 3 })
local once = bob.count("enemyInfo")
ok(once > info_before, "a new score is sent to the other player")
S:receive(ann, { action = "playHand", score = "100", handsLeft = 3 })
ok(bob.count("enemyInfo") == once, "the same score is not sent again")
S:receive(ann, { action = "playHand", score = "250", handsLeft = 2 })
ok(bob.count("enemyInfo") == once + 1, "a changed score is sent")

print("PASS: net quiet")
