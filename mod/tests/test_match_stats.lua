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
	P.r = P2P.new_router({ log = os.getenv("LOG") and function(s) print("[" .. T .. " " .. name .. "] " .. s) end or nil, backend = P.b, Core = Core, json = json, now = now, version = "0.6.9", Migration = HMmod,
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
	for _, p in ipairs(ps) do p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.9" }) end
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
	for i = 2, #ps do ps[i].send({ action = "readyLobby" }) end; pump(2); ps[1].send({ action = "startGame" }); pump(6)
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
	p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" }); p.send({ action = "version", version = "0.6.9" })
	p.send({ action = "rejoinLobby", code = code, reconnectToken = token })
	pump(8); run(2)
	p.id = old.id
	return p
end
local function newcomer(name, code, spectate)
	local p = player(name)
	all[#all + 1] = p
	p.send({ action = "connect" }); p.send({ action = "username", username = name, modHash = "t" }); p.send({ action = "version", version = "0.6.9" })
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
	local solo_view = MS.view({ winnerId = "a", rows = { { id = "a", name = "Ada", place = 1, dealt = 0, best = "100", ante = 6, livesLost = 2 } }, awards = {} }, "a")
	ok(#solo_view.awards == 0 and #solo_view.rows == 1 and solo_view.winner == "Ada wins!", "one player has a row and no awards")
	_G.G = { STATES = { GAME_OVER = 1, MENU = 0 }, STATE = 1, GAME = { round_resets = { ante = 6 }, round_scores = {} }, jokers = { cards = {} } }
	MP.GAME.lives = 0
	MP.GAME.won = false
	MP.LOBBY.my_id = "ada"
	local summary = MS.local_summary()
	local shown = MS.view(summary, "ada")
	ok(#summary.rows == 1 and summary.rows[1].ante == 6 and #shown.awards == 0 and #shown.rows == 1, "a finished solo run can build a one-player table locally")
	MS.last = nil
	G.STATE = G.STATES.MENU
	MP.GAME.lives = 3
	MP.GAME.won = false
	MP.GAME.match_finished = false
	local warned
	_G.attention_text = function(t) warned = t end
	G.OVERLAY_MENU = { id = "game_end" }
	MS.open()
	ok(not MS.last and warned and warned.major == G.OVERLAY_MENU, "mid-match the notice sits on the overlay, not behind it")
	MS.last = nil
	G.STATE = G.STATES.GAME_OVER
	MP.GAME.lives = 0
	MP.GAME.won = false
	MP.GAME.match_finished = false
	MP.LOBBY.player_list = { { id = "ada" }, { id = "bob" } }
	MP.LOBBY.player_count = 2
	warned = nil
	MS.open()
	ok(not MS.last and warned, "an eliminated player in a live multiplayer match does not see a solo 1st-place table")
	MP.GAME.match_finished = true
	MS.last = nil
	MS.open()
	ok(MS.last and MS.last.rows[1].place == 1, "once the match is finished the local table can fill in")
	MP.LOBBY.player_list = nil
	MP.LOBBY.player_count = nil
	MP.GAME.match_finished = false
	MP.GAME.lives = 3
	G.STATE = G.STATES.MENU
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
	local function side(n, bigger, lives_a)
		local rows, members_a, members_b = {}, {}, {}
		for i = 1, n do
			local team = i <= bigger and "A" or "B"
			rows[#rows + 1] = { id = "p" .. i, name = "P" .. i, place = team == "A" and 1 or 2, team = team,
				lives = team == "A" and lives_a or 0, out = team ~= "A", dealt = 100 * i, best = tostring(100 * i), ante = 4,
				livesLost = team == "A" and 1 or 4, pvpWon = 1, pvps = 2, money = 0, jokers = 1, seen = 1 }
			if team == "A" then members_a[#members_a + 1] = "p" .. i else members_b[#members_b + 1] = "p" .. i end
		end
		return MS.result_lines({ winnerId = "p1", gameMode = "teams", rows = rows, teams = {
			{ team = "A", place = 1, dealt = 300, pvpWon = 2, livesLost = 1, lives = lives_a, members = members_a },
			{ team = "B", place = 2, dealt = 200, pvpWon = 0, livesLost = 4, lives = 0, members = members_b },
		}, code = "ABCDE" })
	end
	for _, spec in ipairs({ { 5, 3, "3v2" }, { 7, 4, "4v3" }, { 4, 2, "2v2" } }) do
		local lines = side(spec[1], spec[2], 2)
		local blob = table.concat(lines, "\n")
		ok(lines[1] == "Team A wins!", spec[3] .. " names the winning team")
		ok(blob:find("2 lives", 1, true) and blob:find("Out", 1, true) and blob:find("ante 4", 1, true), spec[3] .. " shows lives, outs and ante")
		ok(blob:find("P1 %[A%]") and blob:find("P" .. spec[1] .. " %[B%]"), spec[3] .. " lists every player on a team")
		ok(not blob:find("ABCDE", 1, true), spec[3] .. " does not print a lobby code")
	end
	local endsrc = io.open("ui/game/game_end.lua"):read("*a")
	ok(endsrc:find("rematch_button", 1, true) and endsrc:find("end_block", 1, true), "the end screen still offers Rematch and shows the results")
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
-- ===== 8. layout (Balatro building blocks, stubbed): tabs, award cards, paged player panels
do
	local function rgb(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 } end
	_G.G = { STAGES = { RUN = 2 }, STAGE = 1, CARD_W = 2.4, CARD_H = 3.2,
		UIT = { ROOT = 0, R = 1, C = 2, T = 3, O = 4 },
		C = { RED = rgb("FE5F55"), MULT = rgb("FE5F55"), CHIPS = rgb("009dff"), BLUE = rgb("009dff"), MONEY = rgb("f3b958"), FILTER = rgb("ff9a00"),
			GREEN = rgb("4BC292"), PURPLE = rgb("8867a5"), GOLD = rgb("eac058"), WHITE = rgb("ffffff"), BLACK = rgb("374244"), L_BLACK = rgb("4f6367"),
			JOKER_GREY = rgb("bfc7d5"), BOOSTER = rgb("646eb7"), CLEAR = { 0, 0, 0, 0 }, SECONDARY_SET = { Planet = rgb("13afce") },
			UI = { TEXT_LIGHT = rgb("ffffff"), TEXT_INACTIVE = rgb("888888") } },
		P_CENTERS = { j_joker = { key = "j_joker" }, j_blueprint = { key = "j_blueprint" } } }
	_G.darken = function(c, a) return { c[1] * (1 - a), c[2] * (1 - a), c[3] * (1 - a), c[4] } end
	_G.DynaText = function(a) return { dyna = true, text = a.string[1], colour = a.colours[1], scale = a.scale } end
	local emplaced = {}
	_G.CardArea = function() return { emplace = function(_, c) emplaced[#emplaced + 1] = c end } end
	_G.Card = function(_, _, _, _, _, c) return { center = c } end
	local cycles, tabs_args, generic = {}, nil, nil
	_G.create_option_cycle = function(a) cycles[#cycles + 1] = a; return { n = 1, cycle = a } end
	_G.create_tabs = function(a) tabs_args = a; return { n = 1, tabs = a } end
	_G.create_UIBox_generic_options = function(a) generic = a; return { n = 0, nodes = a.contents } end
	_G.UIBox_button = function(a) return { n = 1, button = a.button } end
	_G.localize = function(k) if k == "b_back" then return "Back" end return "ERROR" end
	MS.last = nil
	G.STATES = G.STATES or {}
	G.STATES.GAME_OVER = 1
	G.STATE = 1
	G.GAME = { round_resets = { ante = 4 }, round_scores = {} }
	G.jokers = { cards = {} }
	G.FUNCS = G.FUNCS or {}
	local opened
	G.FUNCS.overlay_menu = function(args) opened = args end
	MP.GAME.lives = 0
	MP.GAME.won = true
	MP.LOBBY.my_id = "ada"
	MS.open()
	ok(opened and opened.definition and MS.last and MS.last.winnerId == "ada" and #MS.last.rows == 1, "Match stats opens a one-player screen when the host table has not arrived")
	local function find_all(node, pred, out)
		out = out or {}
		if type(node) ~= "table" then return out end
		if pred(node) then out[#out + 1] = node end
		for _, c in ipairs(node.nodes or {}) do find_all(c, pred, out) end
		if node.config and node.config.object and type(node.config.object) == "table" then find_all(node.config.object, pred, out) end
		return out
	end
	local rows8, book = {}, {}
	for i = 1, 8 do book["m" .. i] = { id = "m" .. i, name = "Mock" .. i, dealt = 1000 * (9 - i), best = tostring(100 * i), bestHand = "Pair",
		livesLost = i - 1, pvpWon = 8 - i, pvps = 8, money = 10 * i, ante = 3, seen = i, jokers = 2, lineup = { "j_joker", "j_blueprint" } } end
	local out, order = {}, {}
	for i = 8, 2, -1 do out["m" .. i] = true; order[#order + 1] = "m" .. i end
	local rows, _, aw = Core.match_table(book, out, order, false)
	MS.last = { winnerId = "m1", rows = rows, awards = aw }
	MS.tab, MS.page = "awards", 1
	local root = MS.ui(MS.last)
	ok(generic.back_func == "mp_ms_close" and generic.back_label == "Back" and not generic.no_back, "Balatro generic panel with the orange Back button")
	ok(root.nodes[1].nodes[1].config.object.dyna and root.nodes[1].nodes[1].config.object.colour == G.C.GOLD, "title is a gold DynaText (like You Win)")
	ok(#tabs_args.tabs == 2 and tabs_args.tabs[1].label == "Awards" and tabs_args.tabs[2].label == "Players" and tabs_args.tabs[1].chosen, "tabs: Awards / Players")
	local v = MS.view(MS.last, "m3")
	local at = MS.awards_tab(v)
	local strips = find_all(at, function(n) return n.config and n.config.minw == 0.14 end)
	ok(#strips == 7, "7 award cards with a colour strip")
	ok(#at.nodes[1].nodes == 2 and #at.nodes[1].nodes[1].nodes == 4 and #at.nodes[1].nodes[2].nodes == 3, "award cards in two columns (4 + 3)")
	ok(#emplaced == 2 and emplaced[1].center.key == "j_joker", "the winner's final jokers are real cards in a CardArea")
	local pt = MS.players_tab(v)
	local panels = find_all(pt, function(n) return n.config and n.config.minw == MS.PANEL_W end)
	ok(#panels == 4 and #cycles == 1 and #cycles[1].options == 2 and cycles[1].opt_callback == "mp_ms_page", "8 players: 4 panels per page + a Balatro page cycle")
	MS.page = 2
	local pt2 = MS.players_tab(v)
	local texts = find_all(pt2, function(n) return n.config and n.config.text == "Mock8" end)
	ok(#texts == 1, "page 2 shows the last players")
	MS.page = 1
	local winner_boxes = find_all(MS.players_tab(MS.view(MS.last)), function(n) return n.config and n.config.minh == 0.45 and n.config.colour ~= G.C.BLACK end)
	ok(#winner_boxes >= 1, "category winners get a coloured value box")
	local pages = select(2, MS.page_of({ 1, 2, 3, 4, 5 }, 9, 4))
	ok(pages == 2 and #MS.page_of({ 1, 2, 3, 4, 5 }, 9, 4) == 1 and #MS.page_of({}, 1, 4) == 0, "paging clamps")
	local tv = MS.view({ rows = rows, awards = aw, teams = { { team = "A", place = 1, dealt = 5000, pvpWon = 3, livesLost = 1, members = { "m1", "m2" } },
		{ team = "B", place = 2, dealt = 10, pvpWon = 0, livesLost = 2, members = { "m3" } } } })
	ok(#MS.tab_list(tv) == 3 and MS.tab_list(tv)[3].label == "Teams" and tv.team_panels[1].members == "Mock1, Mock2", "Teams tab with team panels")
	ok(#find_all(MS.teams_tab(tv), function(n) return n.config and n.config.minw == MS.PANEL_W end) == 2, "a panel per team")

	-- worst case widths (Balatro T nodes have no maxw: texts are fitted up front): 32-char names, huge numbers, EN + NL
	dofile("lib/fit.lua")
	local UM = dofile("tests/ui_measure.lua")
	local long = ("W"):rep(32)
	local wbook = {}
	for i = 1, 8 do wbook["m" .. i] = { id = "m" .. i, name = long .. i, dealt = 1.234e15 * (9 - i), best = "123456789012345", bestHand = "Flush Five",
		livesLost = i - 1, pvpWon = 8 - i, pvps = 8, money = 123456 * i, ante = 38, seen = 150, jokers = 150, lineup = { "j_joker" } } end
	local wrows, _, waw = Core.match_table(wbook, out, order, false)
	for _, lang in ipairs({ "en-us", "nl" }) do
		_G.localize = UM.localizer("localization/" .. lang .. ".lua")
		local wv = MS.view({ winnerId = "m1", rows = wrows, awards = waw, teams = {
			{ team = "A", place = 1, dealt = 9e15, pvpWon = 30, livesLost = 1, members = { "m1", "m2", "m3", "m4" } },
			{ team = "B", place = 2, dealt = 8e15, pvpWon = 2, livesLost = 2, members = { "m5", "m6", "m7", "m8" } } } }, "m3")
		for page = 1, 2 do
			MS.page = page
			for _, p in ipairs(find_all(MS.players_tab(wv), function(n) return n.config and n.config.minw == MS.PANEL_W end)) do
				local w, issues = UM.measure(p)
				assert(#issues == 0 and w <= MS.PANEL_W + 0.2, lang .. " player panel " .. string.format("%.2f", w) .. " " .. tostring(issues[1]))
			end
		end
		ok(true, lang .. ": 8 players with 32-char names and huge numbers fit their panels (" .. MS.PANEL_W .. ")")
		for _, p in ipairs(find_all(MS.teams_tab(wv), function(n) return n.config and n.config.minw == MS.PANEL_W end)) do
			local w, issues = UM.measure(p)
			assert(#issues == 0 and w <= MS.PANEL_W + 0.2, lang .. " team panel " .. string.format("%.2f", w) .. " " .. tostring(issues[1]))
		end
		ok(true, lang .. ": team panels with 4 long member names fit")
		local _, aissues = UM.measure(MS.awards_tab(wv))
		ok(#aissues == 0, lang .. ": award cards fit" .. (aissues[1] and (" - " .. aissues[1]) or ""))
	end
	MS.page = 1
	_G.localize = function(k) if k == "b_back" then return "Back" end return "ERROR" end
end
print("PASS: match stats")
