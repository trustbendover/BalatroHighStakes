-- The lobby lives control goes to 16. A pick above 5 must start the match at that number.
-- luajit tests/test_starting_lives.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")

local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end

local function start(mode, lives, guest)
	local S = Core.new({ now = function() return 1000 end, log = function() end })
	local host = client(S, "Ann~1")
	S:receive(host, { action = "createLobby", gameMode = mode })
	local other
	if guest then
		other = client(S, "Bob~2")
		S:receive(other, { action = "joinLobby", code = host.last("joinedLobby").code })
		S:receive(other, { action = "readyLobby" })
	end
	S:receive(host, { action = "lobbyOptions", match_settings = 1, starting_lives = lives })
	S:receive(host, { action = "startGame" })
	return S, host, other
end

local _, host, bob = start("attrition", 8, true)
ok(host.lives == 8 and bob.lives == 8, "attrition starts both players at 8 lives")
ok(host.last("playerInfo").lives == 8 and bob.last("enemyInfo").lives == 8, "the HUD message and the other player's row say 8")

local S, again, pal = start("attrition", 99, true)
ok(again.lives == 16 and pal.lives == 16, "a pick above the menu max starts at 16")
S:receive(again, { action = "stopGame" })
S:receive(pal, { action = "readyLobby" })
S:receive(again, { action = "startGame" })
ok(again.lives == 16 and pal.lives == 16 and again.last("playerInfo").lives == 16, "a rematch keeps the host's 16 lives")

local _, house = start("gambel_time", 9, false)
ok(house.lives == 9 and house.last("playerInfo").lives == 9, "Gambel Time keeps 9 lives instead of stopping at 5")
local _, low = start("gambel_time", 1, false)
ok(low.lives == 2, "Gambel Time still refuses a 1-life start")

print("PASS: starting lives")
