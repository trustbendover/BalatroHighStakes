-- Public lobby browser: discovery rules, Join/Watch, stale public->private, and the menu UI.
-- run from mod/: luajit tests/test_lobby_browser.lua
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local Browser = dofile("networking/lobby_browser.lua")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
local Match = dofile("networking/match_settings.lua")
local HMmod = dofile("networking/host_migration.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
Core.KOTH = dofile("networking/koth_rules.lua")

local function ok(c, m) assert(c, m); print("ok: " .. m) end

local logic = io.open("networking/lobby_browser.lua"):read("*a")
local router = io.open("networking/steam_p2p.lua"):read("*a")
ok(not logic:find("loadstring", 1, true) and not logic:find("os.execute", 1, true) and not logic:find("dofile", 1, true), "listing rules do not run lobby text")
ok(router:find("AddRequestLobbyListStringFilter", 1, true) and router:find("AddRequestLobbyListResultCountFilter", 1, true)
	and router:find("RequestLobbyData", 1, true) and router:find("RequestLobbyList", 1, true), "browser uses the Steam lobby-list calls")
ok(P2P.BROWSER and P2P.BROWSER.MOD == "hs" and type(P2P.BROWSER.accept) == "function", "router loads the listing rules")

-- rules, no Steam
ok(Browser.sanitize_name("Ann") == "Ann", "plain host name kept")
ok(Browser.sanitize_name("J\195\188rgen") == "J\195\188rgen", "utf-8 host name kept")
local nasty = Browser.sanitize_name("os.execute('rm')\n<script>%s")
ok(type(nasty) == "string" and not nasty:find("\n", 1, true) and not nasty:find("<", 1, true) and not nasty:find("%%", 1, true)
	and nasty ~= "os.execute('rm')\n<script>%s", "control characters are stripped and the name stays plain text")
ok(#Browser.sanitize_name(("W"):rep(80)) == Browser.NAME_MAX, "host name is capped")
ok(Browser.sanitize_name("") == nil and Browser.sanitize_name(nil) == nil, "empty name is not a string we invent here")

local ver = "0.6.9"
local filters = Browser.filters(ver)
ok(filters[1].key == "mp3p_discover" and filters[1].value == "1" and filters[2].value == "hs" and filters[3].value == ver, "Steam filters are discover + this mod + this version")
ok(Browser.version("0.6.8.2~3P") == "0.6.8.2~3P" and Browser.version("bad version") == "", "version filter is a single token")

local function sample(over)
	local d = {
		mp3p_discover = "1", mp3p_mod = "hs", mp3p_version = ver, mp3p_name = "Ann",
		mp3p_mode = "attrition", mp3p_fmt = "", mp3p_players = "1", mp3p_max = "8",
		mp3p_state = "wait", mp3p_watch = "0", mp3p_code = "ABCDE",
	}
	for k, v in pairs(over or {}) do d[k] = v end
	return d
end
local function hidden(over, why)
	ok(Browser.accept(sample(over), { version = ver }) == nil, why)
end
hidden({ mp3p_discover = "0" }, "discover 0 is hidden")
hidden({ mp3p_discover = "" }, "missing discover is hidden")
hidden({ mp3p_mod = "other" }, "another mod is hidden")
hidden({ mp3p_version = "0.1.0" }, "another version is hidden")
hidden({ mp3p_mode = "return loadstring('x')" }, "unknown mode is hidden")
hidden({ mp3p_state = "hack" }, "unknown state is hidden")
hidden({ mp3p_players = "nope" }, "non-numeric player count is hidden")
hidden({ mp3p_watch = "yes" }, "watch flag must be 0 or 1")
local evil = Browser.accept(sample({ mp3p_name = "os.execute('rm') Ann" }), { version = ver })
ok(evil and type(evil.name) == "string" and not evil.name:find("(", 1, true) and not evil.name:find(")", 1, true) and evil.code == nil, "a listed name is plain text and the card has no code")
do
	local blob = {}
	for k, v in pairs(evil) do blob[#blob + 1] = tostring(k) .. "=" .. tostring(v) end
	ok(not table.concat(blob, " "):find("ABCDE", 1, true), "the lobby code is not copied onto the card")
end
local teams = Browser.accept(sample({ mp3p_mode = "teams", mp3p_fmt = "2", mp3p_max = "4" }), { version = ver })
ok(teams and teams.mode_key == "k_teams2", "2v2 uses the teams format name")
local wait = Browser.accept(sample(), { version = ver })
ok(Browser.action(wait) == "join", "a waiting lobby with room can be joined")
local full = Browser.accept(sample({ mp3p_players = "8" }), { version = ver })
local fact, why = Browser.action(full)
ok(fact == nil and why == "full", "a full waiting lobby is shown but not joinable")
local play = Browser.accept(sample({ mp3p_state = "play", mp3p_watch = "1", mp3p_players = "2" }), { version = ver })
ok(Browser.action(play) == "watch", "a running match with room for spectators can be watched")
local blind = Browser.accept(sample({ mp3p_state = "play", mp3p_watch = "0" }), { version = ver })
fact, why = Browser.action(blind)
ok(fact == nil and why == "playing", "a running match that is not accepting spectators has no Watch")
local rows = {}
for i = 1, 8 do rows[i] = { id = tostring(1000 + i), name = "P" .. i, state = (i % 2 == 0) and "play" or "wait" } end
Browser.sort(rows)
ok(rows[1].state == "wait" and rows[#rows].state == "play", "waiting lobbies sort before matches in progress")
local p1, page, pages = Browser.slice(rows, 1, 6)
local p2 = Browser.slice(rows, 2, 6)
ok(#p1 == 6 and page == 1 and pages == 2 and #p2 == 2, "the list is paged, 6 then the remainder")
ok(Browser.page_count(0, 6) == 1 and #Browser.slice({}, 3, 6) == 0, "an empty list is one empty page")

local function pub(L, flag)
	return Browser.publish(L, { public = flag, version = ver, max_players = Core.max_players, max_spectators = 8 })
end
local cleared = pub({ gameMode = "attrition", players = { { username = "Ann" } } }, false)
ok(cleared.mp3p_discover == "0" and cleared.mp3p_mod == "" and cleared.mp3p_name == "", "private clears the listing keys")
local listed = pub({ gameMode = "duel", players = { { username = "Ann" } }, options = {} }, true)
ok(listed.mp3p_discover == "1" and listed.mp3p_mod == "hs" and listed.mp3p_mode == "duel" and listed.mp3p_max == "2" and listed.mp3p_state == "wait" and listed.mp3p_watch == "0", "a public duel publishes mode, seats and waiting")
ok(not listed.mp3p_code, "publishing does not add a code field")

-- simulated Steam + the real router and host core
local T = 1000
local now = function() return T end
local NET
local function remove(t, x) for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end end
local function steam_leave(l, me)
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
	function B.create_lobby(cb, typ) later(function()
		local id = tostring(8000 + NET.next); NET.next = NET.next + 1
		NET.lobbies[id] = { owner = me, members = { me }, data = {}, typ = typ }
		cb(id)
	end) end
	function B.find_lobby(code, cb) later(function()
		for id, l in pairs(NET.lobbies) do if l.data.mp3p_code == code then return cb(id) end end
		cb(nil)
	end) end
	function B.join_lobby(id, cb) later(function()
		NET.read_snap = nil
		local l = NET.lobbies[id]
		if not l or (NET.dead and NET.dead[me]) then return cb(false, "gone") end
		NET.joins = (NET.joins or 0) + 1
		remove(l.members, me); l.members[#l.members + 1] = me
		cb(true)
	end) end
	function B.leave_lobby(id) steam_leave(id, me) end
	function B.set_data(id, k, v)
		local l = NET.lobbies[id]
		if l and l.owner == me then l.data[k] = tostring(v) end
	end
	function B.get_data(id, k)
		if NET.read_snap then return NET.read_snap[k] or "" end
		local l = NET.lobbies[id]
		return (l and l.data[k]) or ""
	end
	function B.set_lobby_type(id, t)
		local l = NET.lobbies[id]
		if not l or l.owner ~= me then return false end
		l.typ = t
		return true
	end
	function B.owner(id) local l = NET.lobbies[id]; return l and l.owner or nil end
	function B.members(id) local l = NET.lobbies[id]; local r = {}; for i, m in ipairs(l and l.members or {}) do r[i] = m end return r end
	function B.set_member_data() end
	function B.get_member_data() return "" end
	function B.invite_dialog(id) NET.invited = id end
	function B.set_presence() end
	function B.clear_presence() end
	function B.accept() end
	function B.close() end
	function B.send(peer, data)
		if NET.dead and (NET.dead[peer] or NET.dead[me]) then return true end
		local q = NET.inbox[peer]; if q then q[#q + 1] = { peer = me, data = data } end
		return true
	end
	function B.receive() local q = NET.inbox[me]; NET.inbox[me] = {}; return q or {} end
	function B.list_public(filters, keys, cap, cb)
		later(function()
			NET.last_filters, NET.last_cap = filters, cap
			if NET.list_fail then return cb(nil, "failed") end
			local rows = {}
			for id, l in pairs(NET.lobbies) do
				local data = {}
				for _, k in ipairs(keys) do data[k] = l.data[k] or "" end
				rows[#rows + 1] = { id = id, data = data }
			end
			for _, extra in ipairs(NET.extra or {}) do rows[#rows + 1] = extra end
			cb(rows)
		end)
	end
	function B.refresh_lobby(id, cb)
		later(function()
			if NET.refresh_hang then return end
			if NET.refresh_fail then return cb(false) end
			cb(NET.lobbies[id] ~= nil)
		end)
		return true
	end
	return B
end

local all = {}
local function player(name)
	local P = { name = name, msgs = {} }
	P.b = backend(name)
	P.r = P2P.new_router({ backend = P.b, Core = Core, json = json, now = now, version = ver, Migration = HMmod,
		push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	all[#all + 1] = P
	return P
end
local function pump(n)
	for _ = 1, n or 6 do for _, p in ipairs(all) do if not (NET.dead and NET.dead[p.name]) then p.r.update() end end end
end
local function boot()
	NET = { lobbies = {}, inbox = {}, next = 1, dead = {}, extra = {} }
	all = {}
end
local function ready_player(p)
	p.send({ action = "connect" })
	p.send({ action = "username", username = p.name, modHash = "t" })
	p.send({ action = "version", version = ver })
end
local function browse(p)
	local got
	p.r.browse(function(err, rows) got = { err = err, rows = rows or {} } end)
	pump(3)
	return got
end
local function ids_of(got)
	local s = {}
	for _, row in ipairs(got.rows) do s[row.id] = row end
	return s
end
local function card_blob(row)
	local parts = {}
	for k, v in pairs(row) do
		if type(v) == "function" then error("a browser row has a function") end
		parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
	end
	return table.concat(parts, " ")
end

boot()
local A, B, C = player("Ann"), player("Ben"), player("Cleo")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "attrition" }); pump()
local code = A.last("joinedLobby").code
local lob = NET.lobbies[A.r.lobby]
ok(lob.data.mp3p_discover == "0" and lob.data.mp3p_mod == "", "a new lobby is not listed")
B.send({ action = "joinLobby", code = code }); pump(6)
ok(B.r.mode == "guest" and B.last("joinedLobby"), "code join still reaches a private lobby")
local before = NET.joins
local listed_before = browse(C)
ok(listed_before.err == nil and #listed_before.rows == 0, "private lobby is absent from the list")
ok(NET.last_filters[1].value == "1" and NET.last_filters[2].value == "hs" and NET.last_filters[3].value == ver and NET.last_cap == 48, "the list request asks Steam for this mod, this version, public, capped")

A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, normal_bosses = true, death_on_round_loss = false }); pump()
lob = NET.lobbies[A.r.lobby]
ok(lob.typ == P2P.STEAM_LOBBY_PUBLIC and lob.data.mp3p_discover == "1" and lob.data.mp3p_mod == "hs", "public sets the Steam type and the discover flag")
ok(lob.data.mp3p_name == "Ann" and lob.data.mp3p_mode == "attrition" and lob.data.mp3p_players == "2" and lob.data.mp3p_state == "wait", "the listing shows the host, the mode and the current seats")
ok(lob.data.mp3p_boss == "1" and lob.data.mp3p_code ~= nil, "a host who turned boss effects on publishes that, and the code stays off the card later")
local guest_on = { normal_bosses = false, death_on_round_loss = true, weekly = "keep-me" }
Match.apply(guest_on, B.last("lobbyOptions"))
ok(guest_on.normal_bosses == true and guest_on.death_on_round_loss == false and guest_on.weekly == "keep-me", "join applies the host's modifiers both ways and leaves a personal setting")

-- pollution: the fake index returns every lobby, including ones Steam filters would drop
NET.extra[#NET.extra + 1] = { id = "900001", data = sample({ mp3p_mod = "other", mp3p_name = "OtherMod" }) }
NET.extra[#NET.extra + 1] = { id = "900002", data = sample({ mp3p_version = "9.9.9", mp3p_name = "OldBuild" }) }
NET.extra[#NET.extra + 1] = { id = "900003", data = sample({ mp3p_discover = "0", mp3p_name = "Hidden" }) }
NET.extra[#NET.extra + 1] = { id = "not-a-number", data = sample({ mp3p_name = "BadId" }) }
NET.extra[#NET.extra + 1] = { id = "900004", data = sample({ mp3p_name = "os.execute('rm -rf /')\n<script>", mp3p_players = "1", mp3p_max = "8" }) }
local found = browse(C)
local by = ids_of(found)
ok(by[A.r.lobby] and not by["900001"] and not by["900002"] and not by["900003"] and not by["not-a-number"], "other mods, versions, private rows and a bad id are dropped")
local hostile = by["900004"]
ok(hostile and type(hostile.name) == "string" and not hostile.name:find("<", 1, true) and not hostile.name:find("\n", 1, true)
	and not card_blob(hostile):find("ABCDE", 1, true), "a hostile name is shown as plain text, with no code and no execution")
ok(by[A.r.lobby].action == "join" and by[A.r.lobby].name == "Ann" and by[A.r.lobby].mode_key == "k_attrition", "the real public lobby is waiting and joinable")
local own = browse(A)
ok(ids_of(own)[A.r.lobby] == nil, "the host's own lobby is not offered back to the host")

-- public -> private before the click: do not join
local saved = A.r.lobby
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = false }); pump()
ok(NET.lobbies[saved].data.mp3p_discover == "0" and NET.lobbies[saved].data.mp3p_mod == "" and NET.lobbies[saved].data.mp3p_boss == "" and NET.lobbies[saved].typ == P2P.STEAM_LOBBY_PRIVATE, "switching to private clears the listing, including boss effects")
local gone = browse(C)
ok(ids_of(gone)[saved] == nil, "a lobby that went private disappears on refresh")
local joins = NET.joins
local res
C.r.join_browser(saved, "join", function(okj, whyj) res = { okj, whyj } end)
pump(4)
ok(res and res[1] == false and res[2] == "private" and NET.joins == joins and C.r.mode == "local", "a stale Join does not enter a lobby that is now private")
ok(not C.last("joinedLobby"), "the game join is not sent for that stale row")

-- refresh still looks public, the lobby is private by the time Steam accepts
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, normal_bosses = false }); pump()
local snap = {}
for k, v in pairs(NET.lobbies[saved].data) do snap[k] = v end
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = false }); pump()
NET.read_snap = snap
C.msgs = {}
res = nil
joins = NET.joins
C.r.join_browser(saved, "join", function(okj, whyj) res = { okj, whyj } end)
pump(6)
ok(res and res[1] == false and res[2] == "private", "a list that is still public in the snapshot is checked again after JoinLobby")
ok(C.r.mode == "local" and not C.last("joinedLobby"), "the game join is not sent when the lobby went private during the join")
local members = NET.lobbies[saved].members
local still = false
for _, m in ipairs(members) do if m == "Cleo" then still = true end end
ok(not still, "the client leaves the Steam lobby again")
NET.read_snap = nil

-- host explicit off wins over a guest that had the modifier on; code join still works
B.send({ action = "leaveLobby" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, normal_bosses = false, death_on_round_loss = false }); pump()
local again = browse(C)
local row = ids_of(again)[saved]
ok(row and row.action == "join", "the lobby is listed again once the host turns public back on")
res = nil
C.r.join_browser(saved, "join", function(okj, whyj) res = { okj, whyj } end)
pump(8)
ok(res and res[1] == true and C.last("joinedLobby"), "Join from the list enters the lobby")
local guest_off = { normal_bosses = true, death_on_round_loss = true, weekly = "local" }
Match.apply(guest_off, C.last("lobbyOptions"))
ok(guest_off.normal_bosses == false and guest_off.death_on_round_loss == false and guest_off.weekly == "local", "listed join uses the host's off modifiers, not the guest's")
C.send({ action = "leaveLobby" }); pump()

-- full waiting duel: shown, no Join, click does not enter
boot()
A, B, C = player("Ann"), player("Ben"), player("Cleo")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "duel" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true }); pump()
B.send({ action = "joinLobby", code = A.last("joinedLobby").code }); pump(6)
local duel = browse(C)
row = ids_of(duel)[A.r.lobby]
ok(row and row.players == 2 and row.max == 2 and row.action == nil and row.reason == "full", "a full duel is listed as full")
joins = NET.joins
res = nil
C.r.join_browser(A.r.lobby, "join", function(okj, whyj) res = { okj, whyj } end)
pump(4)
ok(res and res[1] == false and res[2] == "full" and NET.joins == joins, "Join on a full lobby does not call JoinLobby")

-- deathmatch in progress: Watch, not Join. Teams name is covered by a waiting 2v2 below.
boot()
local D
A, B, C, D = player("Ann"), player("Ben"), player("Cleo"), player("Dee")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "deathmatch" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, starting_lives = 1 }); pump()
B.send({ action = "joinLobby", code = A.last("joinedLobby").code }); pump(6)
B.send({ action = "readyLobby" }); pump()
A.send({ action = "startGame" }); pump(4)
ok(A.last("startGame") and B.last("startGame"), "deathmatch started")
local running = browse(C)
row = ids_of(running)[A.r.lobby]
ok(row and row.state == "play" and row.action == "watch" and row.mode_key == "k_deathmatch", "a running deathmatch offers Watch")
res = nil
C.r.join_browser(A.r.lobby, "join", function(okj, whyj) res = { okj, whyj } end)
pump(3)
ok(res and res[1] == false and res[2] == "playing" and C.r.mode == "local", "Join is refused once the match is in progress")
res = nil
C.r.join_browser(A.r.lobby, "watch", function(okj, whyj) res = { okj, whyj } end)
pump(8)
ok(res and res[1] == true and (C.last("spectateStart") or (C.last("joinedLobby") and C.last("joinedLobby").spectator)), "Watch sits down as a spectator")
ok(C.r.mode == "guest", "the spectator is in the Steam lobby")

-- list failure is not an empty list; a hung confirm does not join
NET.list_fail = true
local failed = browse(D)
ok(failed.err == "failed" and #failed.rows == 0, "a failed Steam request is an error, not zero lobbies")
NET.list_fail = false
local empty = browse(D)
ok(empty.err == nil, "a successful request with only our own in-progress lobby still returns the other public rows to a bystander")
NET.refresh_hang = true
res = nil
local hanger = player("Eve")
ready_player(hanger)
hanger.r.join_browser(A.r.lobby, "watch", function(okj, whyj) res = { okj, whyj } end)
T = T + 9
pump(2)
ok(res and res[1] == false and res[2] == "unconfirmed" and hanger.r.mode == "local", "if Steam never confirms the lobby, Watch does not join")
NET.refresh_hang = nil

-- teams waiting name, then rematch keeps a public duel listed as waiting
boot()
A, B = player("Ann"), player("Ben")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "teams" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, teams_format = 2, teams_size = 2, normal_bosses = true }); pump()
C = player("Cleo"); ready_player(C)
local teamrow = ids_of(browse(C))[A.r.lobby]
ok(teamrow and teamrow.mode_key == "k_teams2" and teamrow.action == "join", "a public 2v2 is listed under its mode name")

boot()
A, B, C = player("Ann"), player("Ben"), player("Cleo")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "duel" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, starting_lives = 1, normal_bosses = true }); pump()
local duel_code = A.last("joinedLobby").code
B.send({ action = "joinLobby", code = duel_code }); pump(6)
B.send({ action = "readyLobby" }); pump()
A.send({ action = "startGame" }); pump(4)
ok(B.last("startGame"), "duel started for the rematch listing")
A.send({ action = "readyBlind" }); B.send({ action = "readyBlind" }); pump(4)
A.send({ action = "playHand", score = "10", handsLeft = 0 })
B.send({ action = "playHand", score = "80", handsLeft = 0 })
pump(8)
ok(not A.r.core.lobbies[duel_code].isInGame, "the duel is over")
A.send({ action = "rematch" }); pump(4)
ok(B.last("rematch") and B.last("rematch").config.lobby_public == true and B.last("rematch").config.normal_bosses == true, "rematch keeps the public lobby and the host modifiers")
ok(not B.last("lobbyInfo").players[2].ready, "the guest is not still ready after rematch")
local after = NET.lobbies[A.r.lobby]
ok(after.data.mp3p_discover == "1" and after.data.mp3p_state == "wait" and after.typ == P2P.STEAM_LOBBY_PUBLIC, "after rematch the lobby stays public and is waiting again")
local relisted = ids_of(browse(C))[A.r.lobby]
ok(relisted and relisted.state == "wait" and relisted.reason == "full" and relisted.players == 2, "after rematch the duel is listed as waiting and full")
A.msgs = {}
A.send({ action = "startGame" }); pump()
ok(A.last("error") and not A.r.core.lobbies[duel_code].isInGame, "start waits until the guest readies")
B.send({ action = "startGame" }); pump()
ok(not A.r.core.lobbies[duel_code].isInGame, "the guest cannot start the rematch")
B.send({ action = "readyLobby" }); pump()
A.send({ action = "startGame" }); pump()
ok(A.r.core.lobbies[duel_code].isInGame and B.last("startGame"), "the host can start once the guest is ready")

-- migration keeps the public listing and the new host's name
boot()
A, B, C = player("Ann"), player("Ben"), player("Cleo")
for _, p in ipairs(all) do ready_player(p) end
A.send({ action = "createLobby", gameMode = "attrition" }); pump()
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, normal_bosses = true }); pump()
local mig_code = A.last("joinedLobby").code
B.send({ action = "joinLobby", code = mig_code }); pump(8)
T = T + 2; pump(3)
A.alive = false
NET.dead[A.name] = true
steam_leave(A.r.lobby, A.name)
T = T + 4; pump(6)
ok(B.r.mode == "host", "guest became host")
local moved = NET.lobbies[B.r.lobby]
ok(moved and moved.data.mp3p_discover == "1" and moved.data.mp3p_name == "Ben" and moved.typ == P2P.STEAM_LOBBY_PUBLIC, "public listing follows the new host")
local mig_row = ids_of(browse(C))[B.r.lobby]
ok(mig_row and mig_row.name == "Ben" and mig_row.action == "join", "the browser shows the new host")

-- UI
local function rgb(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 } end
_G.G = { FUNCS = {}, UIDEF = {}, UIT = { ROOT = 0, R = 1, C = 2, T = 3, O = 4 },
	C = { BLUE = rgb("009dff"), RED = rgb("FE5F55"), GREEN = rgb("4BC292"), BLACK = rgb("374244"),
		UI = { TEXT_LIGHT = rgb("ffffff"), TEXT_INACTIVE = rgb("88888888") } },
	SETTINGS = { tutorial_complete = true } }
_G.MP = { BROWSER = nil, LOBBY = { connected = true, config = {} }, STEAM_P2P = { browser = Browser }, FIT = nil, SAFE_MODE = nil }
dofile("lib/fit.lua")
local UM = dofile("tests/ui_measure.lua")
_G.create_UIBox_generic_options = function(a)
	return { n = G.UIT.ROOT, config = { back = a.back_func }, nodes = a.contents }
end
_G.UIBox_button = function(a)
	return { n = G.UIT.C, config = { minw = a.minw, button = a.button, ref_table = a.ref_table, colour = a.colour },
		nodes = { { n = G.UIT.T, config = { text = a.label and a.label[1] or "", scale = a.scale or 0.4, colour = G.C.UI.TEXT_LIGHT, maxw = a.minw } } } }
end
dofile("ui/main_menu/play_button/lobby_browser.lua")
dofile("ui/main_menu/play_button/play_button.lua")

local function buttons(node)
	return UM.find(node, function(n) return n.config and n.config.button end)
end
local function texts(node)
	local acc = {}
	for _, n in ipairs(UM.find(node, function(x) return x.n == G.UIT.T end)) do acc[#acc + 1] = n.config.text end
	return table.concat(acc, " | ")
end

for _, lang in ipairs({ "en-us", "nl" }) do
	_G.localize = UM.localizer("localization/" .. lang .. ".lua")
	MP.BROWSER.phase = "loading"
	MP.BROWSER.rows = {}
	MP.BROWSER.note_key = nil
	MP.BROWSER.page = 1
	local loading = G.UIDEF.mp_lobby_browser()
	local lt = texts(loading)
	ok(lt:find(localize("k_browser_loading"), 1, true) and #buttons(loading) == 2, lang .. ": loading, with Back and Refresh only")
	MP.BROWSER.phase = "empty"
	local empty_ui = texts(G.UIDEF.mp_lobby_browser())
	ok(empty_ui:find(localize("k_browser_empty"), 1, true), lang .. ": empty list says there are no public lobbies")
	MP.BROWSER.phase = "error"
	MP.BROWSER.note_key = "failed"
	ok(texts(G.UIDEF.mp_lobby_browser()):find(localize("k_browser_failed"), 1, true), lang .. ": a failed load is not the empty state")
	MP.BROWSER.phase = "ready"
	MP.BROWSER.note_key = nil
	local many = {}
	for i = 1, 8 do
		local action, reason = "join", nil
		if i == 3 then action, reason = nil, "full" end
		if i == 4 then action = "watch" end
		many[i] = {
			id = tostring(5000 + i), name = (i == 1) and ("W"):rep(24) or ("Host " .. i),
			mode = i == 2 and "koth" or "attrition", mode_key = i == 2 and "k_koth" or "k_attrition",
			players = i == 3 and 8 or 1, max = 8, state = i == 4 and "play" or "wait",
			watch = i == 4, action = action, reason = reason,
		}
	end
	many[5] = { id = "5005", name = "InProgress", mode = "deathmatch", mode_key = "k_deathmatch", players = 3, max = 8, state = "play", watch = false, action = nil, reason = "playing" }
	MP.BROWSER.rows = many
	local page1 = G.UIDEF.mp_lobby_browser()
	local t1 = texts(page1)
	ok(t1:find(localize("k_browser_title"), 1, true) and t1:find(localize("k_attrition"), 1, true) and t1:find(localize("k_koth"), 1, true), lang .. ": title and mode names")
	ok(t1:find("1/8", 1, true) and t1:find(localize("k_browser_full"), 1, true), lang .. ": player count and full")
	ok(t1:find(localize("b_browser_join"), 1, true) and t1:find(localize("b_browser_watch"), 1, true), lang .. ": Join and Watch")
	ok(t1:find(localize("k_browser_no_watch"), 1, true), lang .. ": in progress without spectators")
	ok(not t1:find("ABCDE", 1, true), lang .. ": the lobby code is not on the screen")
	local joins_bt = 0
	for _, b in ipairs(buttons(page1)) do if tostring(b.config.button):find("^mp_browser_join_") then joins_bt = joins_bt + 1 end end
	ok(joins_bt >= 1, lang .. ": Join is a button")
	local _, issues = UM.measure(page1)
	ok(#issues == 0, lang .. ": page 1 fits" .. (#issues > 0 and (" " .. issues[1]) or ""))
	G.FUNCS.mp_browser_next()
	local page2 = G.UIDEF.mp_lobby_browser()
	local t2 = texts(page2)
	ok(t2:find(localize("k_browser_page"):gsub("#1#", "2"):gsub("#2#", "2"), 1, true) or t2:find("2/2", 1, true), lang .. ": second page")
	local _, issues2 = UM.measure(page2)
	ok(#issues2 == 0, lang .. ": page 2 fits" .. (#issues2 > 0 and (" " .. issues2[1]) or ""))
end

_G.localize = UM.localizer("localization/en-us.lua")
MP.LOBBY.connected = true
local menu = G.UIDEF.override_main_menu_play_button()
local menu_buttons = {}
for _, b in ipairs(buttons(menu)) do menu_buttons[b.config.button] = true end
ok(menu_buttons.mp_open_browser and menu_buttons.join_lobby and menu_buttons.create_lobby, "the multiplayer menu has Public lobbies next to Create and Join")
MP.LOBBY.connected = false
local offline = G.UIDEF.override_main_menu_play_button()
local off_b = {}
for _, b in ipairs(buttons(offline)) do off_b[b.config.button] = true end
ok(not off_b.mp_open_browser, "Public lobbies is hidden until multiplayer is connected")
local en = io.open("localization/en-us.lua"):read("*a")
local nl = io.open("localization/nl.lua"):read("*a")
ok(en:find("the public lobby list can show this lobby", 1, true) and nl:find("de openbare lobbyljst kan deze lobby tonen", 1, true), "the public toggle explains the list that exists now")
ok(not en:find("future lobby browser", 1, true), "the toggle no longer says the list is future work")

print("PASS: lobby browser")
