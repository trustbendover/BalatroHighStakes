-- Post-match rematch: host only, after the match is actually over, same group and settings.
-- Guests must ready again. Per-match lives, scores and elimination do not carry over.
-- run from mod/: luajit tests/test_rematch.lua
package.path = "tests/?.lua;" .. package.path
local Core = dofile("networking/p2p_server.lua")
Core.KOTH = dofile("networking/koth_rules.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
assert(Core.MATCH and Core.MATCH.store, "match settings loaded with the server")

local function ok(c, m) assert(c, m); print("ok: " .. m) end
local S

local function client(name)
	local p = { name = name, msgs = {} }
	p.c = S:connect(function(t) p.msgs[#p.msgs + 1] = t end)
	function p.last(a)
		for i = #p.msgs, 1, -1 do if p.msgs[i].action == a then return p.msgs[i] end end
	end
	function p.clear() p.msgs = {} end
	S:receive(p.c, { action = "username", username = name, modHash = "t" })
	return p
end

local function fresh()
	S = Core.new({ log = function() end, now = function() return 8000 end })
end

local function lobby(mode, n, opts)
	fresh()
	local ps = {}
	for i = 1, n do ps[i] = client(mode .. i) end
	S:receive(ps[1].c, { action = "createLobby", gameMode = mode })
	local code = ps[1].last("joinedLobby").code
	local msg = { action = "lobbyOptions", match_settings = 1, starting_lives = 1, normal_bosses = true, pvp_start_round = 4 }
	for k, v in pairs(opts or {}) do msg[k] = v end
	S:receive(ps[1].c, msg)
	for i = 2, n do
		S:receive(ps[i].c, { action = "joinLobby", code = code })
		ps[i].c.isReadyLobby = true
	end
	for _, p in ipairs(ps) do p.id = p.last("lobbyInfo").you end
	return ps, code
end

local function start(ps)
	for _, p in ipairs(ps) do p.clear() end
	S:receive(ps[1].c, { action = "startGame" })
	ok(ps[2].last("startGame"), "match started")
end

local function pvp(players, score_of)
	for _, p in ipairs(players) do
		if not p.c.eliminated and not p.c.spectator then S:receive(p.c, { action = "readyBlind" }) end
	end
	for _, p in ipairs(players) do
		if not p.c.eliminated and not p.c.spectator then
			S:receive(p.c, { action = "playHand", score = tostring(score_of(p)), handsLeft = 0 })
		end
	end
end

local function teams_of(ps)
	local t = {}
	for _, p in ipairs(ps) do t[p.id] = p.c.team end
	return t
end

-- 1v1: guest cannot rematch or start the next one; host can, only after it is over;
-- settings stay; ready is required; the new run does not keep the old lives.
do
	local ps, code = lobby("duel", 2, { starting_lives = 2 })
	start(ps)
	local seed1 = ps[2].last("startGame").seed
	pvp(ps, function(p) return p == ps[1] and 10 or 80 end)
	ok(ps[1].c.lives == 1 and ps[1].c.lobby.isInGame, "1v1 still running after one life")
	ps[1].clear()
	S:receive(ps[1].c, { action = "rematch" })
	ok(ps[1].last("error") and ps[1].last("error").message:find("still running", 1, true), "no rematch while the 1v1 is running")
	ok(ps[1].c.lobby.isInGame and not ps[2].last("rematch"), "a refused rematch does not reset the match")
	pvp(ps, function(p) return p == ps[1] and 10 or 80 end)
	ok(ps[1].c.lives == 0 and not ps[1].c.lobby.isInGame, "1v1 is over when the host is out")
	ok(ps[1].last("loseGame") and ps[1].last("loseGame").finished == true, "the host's loss is the end of the match")
	ps[2].clear(); ps[1].clear()
	S:receive(ps[2].c, { action = "rematch" })
	ok(ps[2].last("error") and ps[2].last("error").message:find("host", 1, true), "guest cannot force a rematch")
	ok(not ps[1].last("rematch") and not ps[1].c.lobby.isInGame, "guest rematch does not start anything")
	ps[2].c.isReadyLobby = true
	S:receive(ps[1].c, { action = "rematch" })
	local rm = ps[2].last("rematch")
	ok(rm and rm.config and rm.config.normal_bosses == true and rm.config.pvp_start_round == 4, "rematch sends the same host settings")
	ok(ps[1].c.lobby.options.normal_bosses == true and ps[1].c.lobby.code == code, "lobby and settings stay")
	ok(not ps[2].c.isReadyLobby, "guests must ready again")
	ok(ps[1].c.lives == 0 and ps[2].c.lives == 0 and ps[2].c.eliminated == false, "old lives and elimination are cleared")
	ok(ps[2].c.ante == 1 and tostring(ps[2].c.score.str or "0") == "0", "ante and score reset")
	ok(#ps[1].c.lobby.slots == 0 and not ps[1].c.lobby.blindActive and not ps[1].c.lobby.koth, "no held seat, blind or king carried over")
	ps[1].clear()
	S:receive(ps[1].c, { action = "startGame" })
	ok(ps[1].last("error") and ps[1].last("error").message:find("Waiting", 1, true) and not ps[1].c.lobby.isInGame, "start waits until the guest is ready")
	S:receive(ps[2].c, { action = "startGame" })
	ok(not ps[1].c.lobby.isInGame, "guest cannot start the rematch")
	S:receive(ps[2].c, { action = "readyLobby" })
	ps[2].clear()
	S:receive(ps[1].c, { action = "startGame" })
	local seed2 = ps[2].last("startGame").seed
	ok(seed2 and seed2 ~= seed1, "the new match gets its own seed")
	ok(ps[1].c.lives == 2 and ps[2].c.lives == 2 and not ps[1].c.eliminated and not ps[2].c.eliminated, "both start on the lobby's lives, not the old score")
	ok(ps[2].last("startGame").config.normal_bosses == true, "the new match still uses the host's PvP effects")
	local token = ps[2].c.reconnectToken
	S:disconnect(ps[2].c)
	local back = client("duel2b")
	S:receive(back.c, { action = "rejoinLobby", code = code, reconnectToken = token })
	ok(back.last("rejoinedLobby") and back.last("resumeGame") and back.last("resumeGame").lives == 2, "Alt+F4 during the rematch restores this match's lives")
	print("ok: 1v1 rematch")
end

-- Teams: the host's team order survives the reset and the next start.
do
	local ps = lobby("teams", 4, { starting_lives = 1, teams_size = 2, teams_format = 2, teams_order = "1,2,3,4" })
	start(ps)
	local before = teams_of(ps)
	ok(before[ps[1].id] == "A" and before[ps[3].id] == "B", "teams assigned from the host order")
	pvp(ps, function(p) return (p == ps[1] or p == ps[2]) and 90 or 10 end)
	ok(not ps[1].c.lobby.isInGame, "teams match over after one shared life")
	S:receive(ps[3].c, { action = "rematch" })
	ok(ps[3].c.lobby.isInGame == false and ps[1].c.lobby.options.teams_order == "1,2,3,4", "guest rematch leaves the team order alone")
	S:receive(ps[1].c, { action = "rematch" })
	ok(ps[1].c.lobby.options.teams_order == "1,2,3,4" and ps[1].c.lobby.options.normal_bosses == true, "rematch keeps teams and settings")
	local info = ps[2].last("lobbyInfo")
	local by_id = {}
	for _, pl in ipairs(info.players) do by_id[pl.id] = pl.team end
	ok(by_id[ps[1].id] == "A" and by_id[ps[3].id] == "B", "lobby preview still has the same teams")
	for i = 2, 4 do S:receive(ps[i].c, { action = "readyLobby" }) end
	start(ps)
	local after = teams_of(ps)
	ok(after[ps[1].id] == before[ps[1].id] and after[ps[4].id] == before[ps[4].id], "next match uses the same teams")
	ok(ps[3].c.lives == 1 and not ps[3].c.eliminated, "a knocked-out teammate is back in for the rematch")
	print("ok: teams rematch")
end

-- Deathmatch: rematch is refused while someone is still playing, then allowed when it is over.
do
	local ps = lobby("deathmatch", 3, { starting_lives = 1 })
	start(ps)
	pvp(ps, function(p) return p == ps[1] and 300 or (p == ps[2] and 200 or 50) end)
	ok(ps[3].c.eliminated and ps[1].c.lobby.isInGame, "deathmatch continues after the first elimination")
	ps[1].clear()
	S:receive(ps[1].c, { action = "rematch" })
	ok(ps[1].last("error") and ps[1].last("error").message:find("still running", 1, true), "host cannot rematch a deathmatch that is still going")
	ok(ps[1].c.lobby.isInGame and ps[1].c.lives == 1, "refused rematch does not touch lives")
	local rest = { ps[1], ps[2] }
	pvp(rest, function(p) return p == ps[1] and 300 or 40 end)
	ok(not ps[1].c.lobby.isInGame, "deathmatch over when one player remains")
	S:receive(ps[1].c, { action = "rematch" })
	ok(ps[2].last("rematch") and not ps[3].c.eliminated and ps[3].c.lives == 0, "eliminated player is cleared for the rematch")
	ok(ps[1].c.lobby.options.normal_bosses == true, "deathmatch settings unchanged")
	for i = 2, 3 do ok(not ps[i].c.isReadyLobby, "deathmatch guests are not still ready") end
	for i = 2, 3 do S:receive(ps[i].c, { action = "readyLobby" }) end
	start(ps)
	ok(ps[1].c.lives == 1 and ps[2].c.lives == 1 and ps[3].c.lives == 1, "everyone starts the next deathmatch clean")
	ok(not ps[1].c.eliminated and not ps[3].c.eliminated and ps[1].c.lobby.elimOrder == nil, "no stale elimination order")
	print("ok: deathmatch rematch")
end

print("PASS: rematch")
