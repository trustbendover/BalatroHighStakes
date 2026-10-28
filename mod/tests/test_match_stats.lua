-- Match stats screen (0.6.8) over the simulated Steam network (same fake Steam as
-- tests/test_host_migration.lua). run from mod/: luajit tests/test_match_stats.lua
-- Server: networking/p2p_server.lua stats book + final table. Client: the pure parts of
-- lib/match_stats.lua (view, number format, report from a stubbed game).
package.path = "tests/?.lua;" .. package.path
local json = os.getenv("JSON_LIB") and dofile(os.getenv("JSON_LIB")) or require("dkjson")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
local HMmod = dofile("networking/host_migration.lua")
Core.KOTH = dofile("networking/koth_rules.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
local T = 5000
local now = function() return T end
local NET

local function remove(t, x) for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end end
local function steam_leave(l, id, me)
	local L = NET.lobbies[l]; if not L then return end
	remove(L.members, me)
	if L.owner == me then
		if #L.members == 0 then NET.lobbies[l] = nil else L.owner = L.members[1] end
	end
end
local function backend(me)
	local B, pend = {}, {}
	NET.inbox[me] = {}
	local function later(f) pend[#pend + 1] = f end
	function B.poll() local p = pend; pend = {}; for _, f in ipairs(p) do f() end end
	function B.my_id() return me end
	function B.create_lobby(cb) later(function() local id = tostring(7000 + NET.next); NET.next = NET.next + 1
		NET.lobbies[id] = { owner = me, members = { me }, data = {} }; cb(id) end) end
	function B.find_lobby(code, cb) later(function() for id, l in pairs(NET.lobbies) do
		if l.data.mp3p_code == code then return cb(id) end end cb(nil) end) end
	function B.join_lobby(id, cb) later(function() local l = NET.lobbies[id]
		if not l or NET.dead[me] then return cb(false) end
		remove(l.members, me); table.insert(l.members, me); cb(true) end) end
	function B.leave_lobby(id) steam_leave(id, nil, me) end
	function B.set_data(id, k, v) if NET.lobbies[id] and NET.lobbies[id].owner == me then NET.lobbies[id].data[k] = v end end
	function B.get_data(id, k) return NET.lobbies[id] and NET.lobbies[id].data[k] or "" end
	function B.owner(id) return NET.lobbies[id] and NET.lobbies[id].owner or "0" end
	function B.set_member_data(id, k, v) local l = NET.lobbies[id]
		if l then l.md = l.md or {}; l.md[me] = l.md[me] or {}; l.md[me][k] = v end end
	function B.get_member_data(id, who, k) local l = NET.lobbies[id]
		for _, m in ipairs(l and l.members or {}) do if m == who then return (l.md and l.md[who] and l.md[who][k]) or "" end end
		return "" end
	function B.set_owner(id, new) local l = NET.lobbies[id]
		if l and l.owner == me then for _, m in ipairs(l.members) do if m == new then l.owner = new; return true end end end
		return false end
	function B.members(id) local l = NET.lobbies[id]; local r = {}; for i, m in ipairs(l and l.members or {}) do r[i] = m end return r end
	function B.invite_dialog() end
	function B.accept() end
	function B.close() end
	function B.send(peer, data)
		if NET.dead[peer] or NET.dead[me] then return true end
		local q = NET.inbox[peer]; if q then q[#q + 1] = { peer = me, data = data } end return true end
	function B.receive() local q = NET.inbox[me]; NET.inbox[me] = {}; return q end
	return B
end

local all
local function player(name)
	local P = { name = name, msgs = {}, alive = true }
	P.b = backend(name)
	P.r = P2P.new_router({ log = os.getenv("LOG") and function(s) print("[" .. T .. " " .. name .. "] " .. s) end or nil, backend = P.b, Core = Core, json = json, now = now, version = "0.6.8~3P", Migration = HMmod,
		push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	P.count = function(a) local n = 0 for _, m in ipairs(P.msgs) do if m.action == a then n = n + 1 end end return n end
	return P
end
local function pump(n) for _ = 1, n or 6 do for _, p in ipairs(all) do if p.alive then p.r.update() end end end end
local function run(secs) for _ = 1, secs do T = T + 1; pump(3) end end
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local function live(ps) local r = {} for _, p in ipairs(ps) do if p.alive and not p.gone then r[#r + 1] = p end end return r end

--- n players in a lobby of the given mode; returns the players (host first) and the code
local function setup(n, mode, opts)
	NET = { lobbies = {}, inbox = {}, next = 1, dead = {} }
	local ps = {}
	for i = 1, n do ps[i] = player(mode:sub(1, 3) .. n .. "_" .. i) end
	all = ps
	for _, p in ipairs(ps) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" }) end
	ps[1].send({ action = "createLobby", gameMode = mode }); pump()
	local code = ps[1].last("joinedLobby").code
	local o = { starting_lives = "2" }
	for k, v in pairs(opts or {}) do o[k] = v end
	o.action = "lobbyOptions"
	ps[1].send(o); pump()
	for i = 2, n do ps[i].send({ action = "joinLobby", code = code }); pump(4) end
	pump(6)
	for _, p in ipairs(ps) do p.id = (p.last("lobbyInfo") or {}).you end
	assert(#ps[1].last("lobbyInfo").players == n, "lobby filled")
	run(1)
	return ps, code
end
local function start(ps)
	ps[1].send({ action = "startGame" }); pump(6)
	run(1)
end
local function clear(ps) for _, p in ipairs(ps) do p.msgs = {} end end
local function quit(p) -- Balatro closed: gone from the Steam lobby, no more P2P
	p.alive = false
	NET.dead[p.name] = true
	for id in pairs(NET.lobbies) do steam_leave(id, nil, p.name) end
end
local function host_of(ps) for _, p in ipairs(live(ps)) do if p.r.mode == "host" then return p end end end
--- one PvP blind for the given players with scores by position; returns results per player
local function blind(ps, scores)
	clear(ps)
	for _, p in ipairs(ps) do p.send({ action = "readyBlind" }) end
	pump(8)
	for _, p in ipairs(ps) do assert(p.last("startBlind"), p.name .. " startBlind") end
	for i, p in ipairs(ps) do p.send({ action = "playHand", score = tostring(scores[i]), handsLeft = 0 }) end
	pump(8)
	local res = {}
	for _, p in ipairs(ps) do res[p] = p.last("winGame") or p.last("loseGame") or p.last("endPvP") end
	return res
end
do -- keep the pump list separate from the seat list (newcomers / restarted processes join it)
	local setup0 = setup
	setup = function(...)
		local ps, code = setup0(...)
		local c = {}
		for i, p in ipairs(ps) do c[i] = p end
		all = c
		return ps, code
	end
end
local function tok(p) local j = p.last("joinedLobby") or p.last("rejoinedLobby"); return j and j.reconnectToken end
--- Balatro crashed and was started again: a fresh process with the same Steam id that rejoins
local function restart(ps, i, code, token)
	local old = ps[i]
	NET.dead[old.name] = nil
	local p = player(old.name)
	all[#all + 1] = p
	ps[i] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" })
	p.send({ action = "rejoinLobby", code = code, reconnectToken = token })
	pump(8); run(2)
	p.id = old.id
	return p
end
local function newcomer(name, code, spectate)
	local p = player(name)
	all[#all + 1] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = name, modHash = "t" }); p.send({ action = "version", version = "0.6.8~3P" })
	p.send({ action = "joinLobby", code = code, spectate = spectate }); pump(8); run(1)
	return p
end
local function done(p) return p.last("loseGame") or p.last("winGame") end
--- play PvP blinds until the match is over; scores(alive, round) -> list
local function play_out(ps, scores, max)
	for round = 1, max or 40 do
		local alive = {}
		for _, p in ipairs(ps) do if p.alive and not done(p) then alive[#alive + 1] = p end end
		if #alive <= 1 or (ps[1].last("matchStats") and true) then break end
		local sc = scores(alive, round)
		blind(alive, sc)
		for _, p in ipairs(alive) do if not p.last("startBlind") then return end end
	end
end
local function report(p, t) t.action = "statsReport"; p.send(t); pump(4) end
local function same_table(ps, label)
	local ref = nil
	for _, p in ipairs(ps) do
		local m = p.last("matchStats")
		assert(m, label .. ": " .. p.name .. " got matchStats")
		local sig = {}
		for i, r in ipairs(m.rows) do sig[i] = table.concat({ r.id, r.place, r.dealt, r.best, r.livesLost, r.pvpWon, r.money, r.ante }, ":") end
		local aw = {}
		for k, v in pairs(m.awards or {}) do aw[#aw + 1] = k .. "=" .. tostring(v) end
		table.sort(aw)
		sig = table.concat(sig, "|") .. "#" .. table.concat(aw, ",")
		if ref == nil then ref = sig else assert(sig == ref, label .. ": everyone sees the same table (" .. p.name .. ")") end
	end
	return ps[1].last("matchStats")
end
local function row_of(m, id) for _, r in ipairs(m.rows) do if r.id == id then return r end end end

-- ===== 1. 2, 4 and 8 players (Attrition): one final table for everyone, spectators included
for _, n in ipairs({ 2, 4, 8 }) do
	local ps, code = setup(n, "attrition", {})
	start(ps)
	local X = newcomer("spec" .. n, code, true)
	for i, p in ipairs(ps) do
		report(p, { best = tostring(1000 * i), bestHand = (i == 2) and "Flush" or "Pair", jokers = i % 5, lineup = { "j_joker", "j_blueprint" },
			seen = i, money = 10 * i, ante = 1 + (i % 3) })
	end
	local total = {}
	play_out(ps, function(alive)
		local sc = {}
		for k, p in ipairs(alive) do
			local idx = 0
			for i, q in ipairs(ps) do if q == p then idx = i end end
			sc[k] = 100 * idx
			total[p] = (total[p] or 0) + sc[k]
		end
		return sc
	end)
	local all_seen = { X }
	for _, p in ipairs(ps) do all_seen[#all_seen + 1] = p end
	local m = same_table(all_seen, n .. "p")
	assert(#m.rows == n, n .. "p: a row per player")
	local winner = nil
	for _, p in ipairs(ps) do if p.last("winGame") then winner = p end end
	assert(winner and m.rows[1].id == winner.id and m.rows[1].place == 1 and m.winnerId == winner.id, n .. "p: the winner is first")
	for _, p in ipairs(ps) do
		local r = row_of(m, p.id)
		assert(r.dealt == (total[p] or 0), n .. "p: damage = the PvP scores of " .. p.name .. " (" .. tostring(r.dealt) .. " vs " .. tostring(total[p]) .. ")")
		assert((p == winner and r.livesLost < 2) or (p ~= winner and r.livesLost == 2), n .. "p: lives lost of " .. p.name .. " = " .. tostring(r.livesLost))
		assert(r.money and r.ante and r.best and r.lineup and #r.lineup == 2, n .. "p: reported stats are in the table")
	end
	assert(m.awards.damage == winner.id and m.awards.best == ps[n].id, n .. "p: awards go to the most damage / best hand")
	if n > 2 then assert(row_of(m, ps[2].id).bestHand == "Flush", n .. "p: hand type kept") end
	assert(not X.last("winGame") and X.last("matchOver"), n .. "p: spectator saw the stats and the end")
	-- rounds 2..: places by elimination order (last out = 2nd)
	local places = {}
	for _, r in ipairs(m.rows) do places[#places + 1] = r.place end
	for i = 2, #places do assert(places[i] >= places[i - 1], n .. "p: rows sorted by place") end
end
print("ok: 2/4/8 players: one table for everyone (also spectators), winner first, damage, lives, awards")

-- ===== 2. Teams: team totals
do
	local ps = setup(4, "teams", {})
	start(ps)
	for i, p in ipairs(ps) do report(p, { best = tostring(500 * i), money = 5 * i, ante = 2 }) end
	local team = {}
	for _, p in ipairs(ps) do team[p] = p.last("teamsUpdate").team end
	play_out(ps, function(alive)
		local sc = {}
		for k, p in ipairs(alive) do sc[k] = (team[p] == "A") and 1000 or 10 end
		return sc
	end)
	local m = same_table(ps, "teams")
	ok(m.teams and #m.teams == 2 and m.teams[1].team == "A" and m.teams[1].place == 1, "teams: team totals, winning team first")
	local a_dealt = 0
	for _, r in ipairs(m.rows) do if r.team == "A" then a_dealt = a_dealt + r.dealt end end
	ok(m.teams[1].dealt == a_dealt and m.teams[2].livesLost == 2 and m.teams[1].livesLost == 0, "teams: team damage = sum, team lives lost")
end

-- ===== 3. host migration mid-match: the stats book travels with the snapshot
for _, n in ipairs({ 4, 8 }) do
	local ps = setup(n, "attrition", {})
	start(ps)
	report(ps[1], { best = "987654", bestHand = "Straight Flush", money = 77, ante = 4, lineup = { "j_joker" }, seen = 3, jokers = 1 })
	report(ps[2], { best = "5", money = 1 })
	local sc = {}
	for i = 1, n do sc[i] = 100 * i end
	sc[1] = 5000
	blind(ps, sc)
	local h1 = ps[1].id
	quit(ps[1])
	run(3)
	run(Core.MIGRATION_HOLD + 2)
	local rest = live(ps)
	assert(host_of(ps) == ps[2], n .. "p: seat 2 hosts")
	play_out(rest, function(alive) local s = {} for k = 1, #alive do s[k] = 100 * k end return s end)
	-- the old host's seat is held for the rejoin window; once that runs out the match can end
	run(Core.REJOIN_GRACE + 2)
	local m = same_table(rest, n .. "p migration")
	local r = row_of(m, h1)
	assert(r and r.best == "987654" and r.bestHand == "Straight Flush" and r.money == 77 and r.dealt == 5000 and r.pvps == 1,
		n .. "p migration: the old host's stats survived (" .. json.encode(r or {}) .. ")")
	assert(m.awards.best == h1, n .. "p migration: its best hand still wins the award")
	assert(r.out and r.place > 1, n .. "p migration: the host who never came back is ranked as out")
end
print("ok: host migration mid-match (4/8 players): stats from before the migration are in the final table")

-- ===== 4. rejoin: the stats come back with resumeGame and stay in the book
do
	local ps, code = setup(3, "attrition", {})
	start(ps)
	report(ps[3], { best = "4242", bestHand = "Full House", money = 50, ante = 3, seen = 6 })
	local token = tok(ps[3])
	quit(ps[3]); run(P2P.TIMEOUT + 2)
	local p = restart(ps, 3, code, token)
	local rs = p.last("resumeGame")
	ok(rs.stats and rs.stats.money == 50 and rs.stats.best == "4242", "rejoin: resumeGame carries your stats")
	report(p, { best = "10", money = 5, ante = 1, seen = 1 }) -- a restarted run reports lower numbers
	play_out(ps, function(alive) local s = {} for k, q in ipairs(alive) do s[k] = (q == p) and 9000 or 100 * k end return s end)
	local m = same_table(ps, "rejoin")
	local r = row_of(m, p.id)
	ok(r and r.best == "4242" and r.money == 50 and r.ante == 3 and r.seen == 6 and r.bestHand == "Full House", "rejoin: numbers only go up (a restart can't lower them)")
	ok(m.rows[1].id == p.id, "rejoin: the rejoined player can still win")
end

-- ===== 5. bad reports are cleaned; spectators can't report
do
	local ps, code = setup(2, "attrition", {})
	start(ps)
	local X = newcomer("bad_spec", code, true)
	report(ps[1], { best = "1e10", bestHand = "Pair<script>", lineup = { "j_joker", "os.execute('x')", string.rep("a", 80), "j_ok_2" }, jokers = -4, money = "lots", ante = 1e30 })
	report(X, { best = "1e300", money = 999 })
	play_out(ps, function(alive) local s = {} for k = 1, #alive do s[k] = 100 * k end return s end)
	local m = ps[1].last("matchStats")
	local r = row_of(m, ps[1].id)
	ok(r.best == "1e10" and r.bestHand == nil and #r.lineup == 2 and r.lineup[2] == "j_ok_2" and r.jokers == 0 and r.money == 0 and r.ante == 1e9,
		"bad values are dropped or capped")
	ok(not row_of(m, X.id) and #m.rows == 2, "spectators are not in the table and can't report")
	ok(X.last("matchStats"), "...but they see it")
end

-- ===== 6. pure: table, places, awards
do
	local book = {
		a = { id = "a", name = "Ann", dealt = 500, best = "1e5", livesLost = 1, pvpWon = 3, money = 40, ante = 5, seen = 7, team = "A" },
		b = { id = "b", name = "Bob", dealt = 900, best = "200", livesLost = 2, pvpWon = 1, money = 90, ante = 4, seen = 2, team = "B" },
		c = { id = "c", name = "Cid", dealt = 100, best = "ee2", livesLost = 2, pvpWon = 0, money = 10, ante = 6, seen = 1, team = "A" },
	}
	local rows, teams, aw = Core.match_table(book, { b = true, c = true }, { "c", "b" }, true)
	ok(rows[1].id == "a" and rows[2].id == "b" and rows[3].id == "c" and rows[2].place == 2 and rows[3].place == 3, "places: winner, then last out first")
	ok(aw.damage == "b" and aw.best == "c" and aw.jokers == "a" and aw.lives == "a" and aw.pvp == "a" and aw.money == "b" and aw.ante == "c", "awards per category")
	ok(teams[1].team == "A" and teams[1].dealt == 600 and teams[2].team == "B", "team totals")
	local r2 = Core.match_table({ x = { id = "x", name = "X", dealt = 0 } }, {}, {}, false)
	ok(#r2 == 1 and r2[1].place == 1, "single player table")
end

-- ===== 7. client: view + format + report from a stubbed game
_G.MP = { LOBBY = { code = "ABCD" }, GAME = { lives = 2 } }
_G.localize = function() return "ERROR" end
dofile("lib/spectator.lua")
dofile("lib/match_stats.lua")
local MS = MP.MATCH_STATS
do
	ok(MS.short(950) == "950" and MS.short(12345) == "12.3K" and MS.short(4500000) == "4.5M" and MS.short(2e9) == "2B"
		and MS.short("3.4e15") == "3.40e15" and MS.short("ee5") == "ee5", "numbers: 950, 12.3K, 4.5M, 2B, 3.40e15")
	local st = {
		winnerId = "a",
		rows = {
			{ id = "a", name = "Ann~x", place = 1, dealt = 12345, best = "54000", bestHand = "Flush", jokers = 5, seen = 9, livesLost = 1, pvpWon = 4, pvps = 6, money = 120, ante = 8, lineup = { "j_joker", "j_blue_joker" } },
			{ id = "b", name = "Bob", place = 2, dealt = 99999, best = "1000", jokers = 3, seen = 3, livesLost = 4, pvpWon = 2, pvps = 6, money = 200, ante = 6 },
		},
		awards = { damage = "b", best = "a", jokers = "a", lives = "a", pvp = "a", money = "b", ante = "a" },
	}
	local v = MS.view(st, "b")
	ok(v.winner == "Ann wins!" and v.title == "Match stats", "winner line")
	ok(#v.awards == 7 and v.awards[1].label == "Most damage" and v.awards[1].name == "Bob" and v.awards[1].value == "100K"
		and v.awards[1].colour == "red" and v.awards[1].you, "award lines: label, colour, name, value, you")
	ok(v.awards[2].value == "54K (Flush)" and v.awards[5].value == "4/6" and v.awards[6].value == "$200", "award values")
	ok(v.rows[1].cells[2] == "Ann" and v.rows[1].hl[4] == "chips" and v.rows[2].hl[3] == "red" and v.rows[2].you, "table cells highlight category winners")
	ok(v.lineup == "Ann's final jokers: Joker, Blue joker", "winner's final joker lineup")
	_G.localize = function(a) if type(a) == "table" and a.key == "k_ms_wins" then return a.vars[1] .. " wint!" end return "ERROR" end
	ok(MS.view(st).winner == "Ann wint!", "texts follow the game language")
	_G.localize = function() return "ERROR" end
	ok(#MS.view({ rows = { st.rows[1] }, awards = st.awards }).awards == 0, "one player: no awards")
	local tv = MS.view({ rows = st.rows, awards = {}, teams = { { team = "A", place = 1, dealt = 5000, pvpWon = 3, livesLost = 1 } } })
	ok(tv.winner == "Team A wins!" and tv.teams[1] == "Team A: damage 5K, PvPs won 3, lives lost 1", "teams lines")
	-- report from a stubbed game: best hand, lineup, jokers used, money earned, ante
	_G.G = { STAGES = { RUN = 2 }, STAGE = 2, GAME = { round_scores = { hand = { amt = 1234 } }, last_hand_played = "Two Pair", round_resets = { ante = 3 } } }
	MS.on_start()
	MS.on_dollars(5); MS.on_dollars(-3); MS.on_dollars(4)
	local jk = { { config = { center = { key = "j_joker" } } }, { config = { center = { key = "j_egg" } } } }
	local r = MS.collect(G.GAME, jk)
	ok(r.action == "statsReport" and r.best == "1234" and r.bestHand == "Two Pair" and r.jokers == 2 and r.seen == 2 and r.money == 9 and r.ante == 3,
		"report: best hand, jokers, money earned (only gains), ante")
	G.GAME.last_hand_played = "High Card"
	r = MS.collect(G.GAME, { jk[1], { config = { center = { key = "j_dna" } } } })
	ok(r.bestHand == "Two Pair" and r.seen == 3 and r.jokers == 2, "the best hand type only changes with a new best; jokers used counts every joker seen")
	MS.on_resume({ stats = { money = 50, seen = 8 } })
	r = MS.collect(G.GAME, jk)
	ok(r.money == 50 and r.seen == 8, "after a rejoin the counters continue from the host's numbers")
end
print("PASS: match stats")
