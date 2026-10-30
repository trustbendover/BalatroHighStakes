-- luajit tests/test_elim_unblocks_pvp.lua (run from mod/): a player eliminated by a failed normal round
-- must not leave the others (already Ready at the PvP blind) waiting forever (seen in a 3p deathmatch).
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
local S = Core.new()
local function pl(id)
	local p = { id = id, username = id, lives = 1, score = Core.parse_score("0"), msgs = {} }
	p.send = function(t) p.msgs[#p.msgs + 1] = t end
	function p.got(a) for _, m in ipairs(p.msgs) do if m.action == a then return m end end end
	return p
end
for _, mode in ipairs({ "deathmatch", "attrition" }) do
	for _, how in ipairs({ "failRound", "failTimer" }) do
		local a, b, c = pl("a"), pl("b"), pl("c")
		local L = { code = "T", players = { a, b, c }, gameMode = mode, options = { death_on_round_loss = true }, slots = {}, isInGame = true, blindSeq = 0 }
		for _, p in ipairs(L.players) do p.lobby = L end
		a.lives, b.lives = 3, 3
		S:receive(a, { action = "readyBlind" }); S:receive(b, { action = "readyBlind" })
		ok(not a.got("startBlind"), mode .. "/" .. how .. ": PvP waits while c is still playing")
		S.log = function(m) print("  server: " .. m) end; S:receive(c, { action = how })
		ok(c.eliminated and a.got("startBlind") and b.got("startBlind"), mode .. "/" .. how .. ": c out -> PvP starts for a and b")
	end
end
print("PASS: elimination unblocks the PvP blind")
