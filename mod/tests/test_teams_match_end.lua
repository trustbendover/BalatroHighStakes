-- luajit tests/test_teams_match_end.lua (run from mod/): Teams life loss after the match / all teams out at once
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
local S = Core.new()
local function pl(id, score)
	local p = { id = id, username = id, lives = 2, score = Core.parse_score(score or "0"), msgs = {} }
	p.send = function(t) p.msgs[#p.msgs + 1] = t end
	function p.got(a) for _, m in ipairs(p.msgs) do if m.action == a then return m end end end
	function p.count(a, k, v) local n = 0; for _, m in ipairs(p.msgs) do if m.action == a and (k == nil or m[k] == v) then n = n + 1 end end return n end
	return p
end
local function lobby(ps)
	local L = { code = "T", players = ps, gameMode = "teams", options = {}, slots = {}, isInGame = true }
	for _, p in ipairs(ps) do p.lobby = L end
	S:teams_start(L, 1)
	for _, p in ipairs(ps) do p.lives = 1 end
	return L
end

-- the observed run: team B dies first, team A wins; A's own failed round right after must not cost lives
local a, b, c, d = pl("a", "500"), pl("b", "500"), pl("c", "500"), pl("d", "500")
local L = lobby({ a, b, c, d })
ok(a.team == b.team and c.team == d.team and a.team ~= c.team, "two teams of two")
S:lose_life_for(c, "round"); S:check_game_over(L)
ok(not L.isInGame and a.got("winGame") and c.got("loseGame"), "team of c out first, team of a wins")
local before = a.count("playerInfo")
S:lose_life_for(a, "round")
ok(a.count("playerInfo") == before and L.teamLives[a.team] == 1, "winner team loses no life after the match (was 0)")

-- every team out in the same check: the higher team value wins (final-score rule), not nobody
a, b, c, d = pl("a", "900"), pl("b", "700"), pl("c", "500"), pl("d", "400")
L = lobby({ a, b, c, d })
L.teamLives[a.team], L.teamLives[c.team] = 0, 0
for _, p in ipairs(L.players) do p.lives = 0 end
S:check_game_over(L)
ok(a.got("winGame") and b.got("winGame") and a.got("winGame").reason == "final_score", "best team wins when all teams die at once")
ok(c.got("loseGame") and d.got("loseGame") and not a.eliminated, "other team loses, winners not eliminated")

-- exact tie: both teams spared (a draw, everyone gets winGame)
a, b, c, d = pl("a", "500"), pl("b", "500"), pl("c", "500"), pl("d", "500")
L = lobby({ a, b, c, d }); for _, p in ipairs(L.players) do p.lives = 0 end
L.teamLives[a.team], L.teamLives[c.team] = 0, 0
S:check_game_over(L)
ok(a.got("winGame") and c.got("winGame") and not L.isInGame, "tied teams both spared, match ends")
print("all ok")
