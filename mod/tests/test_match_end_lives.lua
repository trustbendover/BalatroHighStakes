-- luajit tests/test_match_end_lives.lua (run from mod/): no life loss once the match is decided; tie on the last life
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
local S = Core.new()
local function pl(id, lives, score)
	local p = { id = id, username = id, lives = lives, score = Core.parse_score(score or "0"), msgs = {} }
	p.send = function(t) p.msgs[#p.msgs + 1] = t end
	function p.got(a) for _, m in ipairs(p.msgs) do if m.action == a then return m end end end
	return p
end
local function lobby(ps)
	local L = { code = "T", players = ps, gameMode = "attrition", options = {}, slots = {}, isInGame = true }
	for _, p in ipairs(ps) do p.lobby = L end
	return L
end

-- both reach 0 in the final PvP: higher score wins, is NOT eliminated, and keeps 0 lives afterwards
local a, b = pl("a", 1, "500"), pl("b", 1, "300")
local L = lobby({ a, b })
S:lose_life(a, "round"); S:lose_life(b, "round")
ok(a.lives == 0 and b.lives == 0, "both on 0 after the last PvP")
ok(S:check_game_over(L) and not L.isInGame, "match decided")
ok(a.got("winGame") and a.got("winGame").reason == "final_score" and not a.eliminated, "higher score wins the tie, not eliminated")
ok(b.got("loseGame") and b.eliminated and L.winnerId == "a", "lower score loses")
ok(#L.elimOrder == 1 and L.elimOrder[1] == "b", "winner not in the elimination order")
a.roundLivesBlocker, a.timerLivesBlocker = false, false
S:lose_life(a, "round"); S:lose_life(a, "timer")
ok(a.lives == 0, "after the match: no further life loss (was -1)")

-- normal win: winner's lives frozen after the match
local c, d = pl("c", 2), pl("d", 1)
L = lobby({ c, d })
S:lose_life(d, "round"); S:check_game_over(L)
ok(c.got("winGame") and not L.isInGame, "last one standing wins")
local n = #c.msgs; S:lose_life(c, "timer")
ok(c.lives == 2 and #c.msgs == n, "winner loses nothing after match end, no playerInfo sent")

-- clamp + eliminated players never lose lives
local e, f = pl("e", 0), pl("f", 3)
L = lobby({ e, f }); S:lose_life(e, "round")
ok(e.lives == 0, "lives never below 0")
f.eliminated = true; S:lose_life(f, "round"); ok(f.lives == 3, "eliminated players lose nothing")

-- exact tie on score: both win (documented rule), neither eliminated
local g, h = pl("g", 1, "100"), pl("h", 1, "100")
L = lobby({ g, h }); S:lose_life(g); S:lose_life(h); S:check_game_over(L)
ok(g.got("winGame") and h.got("winGame") and not g.eliminated and not h.eliminated, "equal score on the last life: shared win")
print("PASS: match end lives")
