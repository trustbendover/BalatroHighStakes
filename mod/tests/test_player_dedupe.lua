-- Leave and rejoin must not list the same Steam player more than once, and a
-- ghost copy must not hold a PvP blind open.
-- run from mod/: luajit tests/test_player_dedupe.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
Core.GAMBEL = dofile("networking/gambel_rules.lua")

local function names(L)
	local t = {}
	for _, p in ipairs(L.players) do t[#t + 1] = p.username end
	return table.concat(t, ",")
end
local function count_sid(L, sid)
	local n = 0
	for _, p in ipairs(L.players) do if p.steam_id == sid then n = n + 1 end end
	return n
end

local T = 5000
local S = Core.new({ now = function() return T end, log = function() end })
local function client(name, sid)
	local box = {}
	local c = S:connect(function(m) box[#box + 1] = m end)
	c.box = box
	c.steam_id = sid
	function c.last(a) for i = #box, 1, -1 do if box[i].action == a then return box[i] end end end
	S:receive(c, { action = "username", username = name })
	return c
end

local host = client("ben dover", "steam-ben")
local lil = client("LIL COCAIN", "steam-lil")
local cronk = client("Cronkalatro", "steam-cronk")
S:receive(host, { action = "createLobby", gameMode = "attrition" })
local code = host.last("joinedLobby").code
S:receive(lil, { action = "joinLobby", code = code })
S:receive(cronk, { action = "joinLobby", code = code })
S:receive(lil, { action = "joinLobby", code = code })
S:receive(lil, { action = "joinLobby", code = code })
ok(#host.lobby.players == 3 and count_sid(host.lobby, "steam-lil") == 1, "joining again on the same socket does not duplicate (" .. names(host.lobby) .. ")")

local lil2 = client("LIL COCAIN", "steam-lil")
local lil3 = client("LIL COCAIN", "steam-lil")
S:receive(lil2, { action = "joinLobby", code = code })
S:receive(lil3, { action = "joinLobby", code = code })
ok(#host.lobby.players == 3 and count_sid(host.lobby, "steam-lil") == 1, "a new socket with the same Steam id replaces the seat")
local info = host.last("lobbyInfo")
local listed = 0
for _, p in ipairs(info.players) do if p.sid == "steam-lil" then listed = listed + 1 end end
ok(listed == 1 and #info.players == 3, "lobbyInfo and the public count stay at one row per player")
S:receive(lil3, { action = "leaveLobby" })
ok(count_sid(host.lobby, "steam-lil") == 0, "leave removes every copy of that Steam id")
S:receive(lil3, { action = "joinLobby", code = code })
ok(count_sid(host.lobby, "steam-lil") == 1, "rejoin after leave is a single seat")

-- PvP: two real players have finished. A ghost of the player waiting to rejoin
-- is still seated with a full hand. The blind must still resolve.
S:receive(host, { action = "lobbyOptions", starting_lives = "3" })
S:receive(cronk, { action = "readyLobby" })
S:receive(lil3, { action = "readyLobby" })
S:receive(host, { action = "startGame" })
for _, p in ipairs({ host, cronk, lil3 }) do S:receive(p, { action = "readyBlind" }) end
ok(host.lobby.blindActive, "the PvP blind is running")
local ghost = client("LIL COCAIN", "steam-lil")
ghost.lives, ghost.handsLeft, ghost.score = 3, 4, Core.parse_score("0")
ghost.lobby = host.lobby
host.lobby.players[#host.lobby.players + 1] = ghost
S:disconnect(lil3)
ok(count_sid(host.lobby, "steam-lil") == 0, "disconnect drops the idle ghost and holds one seat")
S:receive(host, { action = "playHand", score = "2076", handsLeft = 0 })
S:receive(cronk, { action = "playHand", score = "1300", handsLeft = 0 })
ok(host.last("endPvP") ~= nil, "the PvP resolves once the connected players are out of hands")
ok(not host.lobby.blindActive, "the blind is no longer waiting on the player who is away")

-- Teams and Gambel Time use the same resolve gate.
local function finished_pair(mode)
	local G = Core.new({ now = function() return T end, log = function() end })
	local function guy(name, sid)
		local box = {}
		local c = G:connect(function(m) box[#box + 1] = m end)
		c.box, c.steam_id = box, sid
		function c.last(a) for i = #box, 1, -1 do if box[i].action == a then return box[i] end end end
		G:receive(c, { action = "username", username = name })
		return c
	end
	local a, b = guy("Ada", "sa"), guy("Bea", "sb")
	G:receive(a, { action = "createLobby", gameMode = mode })
	local cde = a.last("joinedLobby").code
	G:receive(b, { action = "joinLobby", code = cde })
	if mode == "teams" then
		local c, d = guy("Cy", "sc"), guy("Dee", "sd")
		G:receive(c, { action = "joinLobby", code = cde })
		G:receive(d, { action = "joinLobby", code = cde })
		G:receive(b, { action = "readyLobby" })
		G:receive(c, { action = "readyLobby" })
		G:receive(d, { action = "readyLobby" })
		G:receive(a, { action = "lobbyOptions", starting_lives = "2", teams_format = "2" })
		G:receive(a, { action = "startGame" })
		for _, p in ipairs(a.lobby.players) do G:receive(p, { action = "readyBlind" }) end
		local g = guy("Bea", "sb")
		g.lobby = a.lobby
		a.lobby.players[#a.lobby.players + 1] = g
		G:disconnect(b)
		for _, p in ipairs({ a, c, d }) do G:receive(p, { action = "playHand", score = "10", handsLeft = 0 }) end
		return a.last("endPvP") ~= nil
	end
	G:receive(b, { action = "readyLobby" })
	G:receive(a, { action = "startGame" })
	for _, p in ipairs(a.lobby.players) do G:receive(p, { action = "readyBlind" }) end
	local g = guy("Bea", "sb")
	g.lobby = a.lobby
	a.lobby.players[#a.lobby.players + 1] = g
	G:disconnect(b)
	G:receive(a, { action = "playHand", score = "10", handsLeft = 0 })
	return a.last("endPvP") ~= nil
end
ok(finished_pair("gambel_time"), "Gambel Time does not wait on a ghost seat")
ok(finished_pair("teams"), "teams do not wait on a ghost seat")

-- Connected Players: name and status are separate fixed columns, and a repeated id is one row.
local function rgb() return { 1, 1, 1, 1 } end
G = { UIT = { R = 1, C = 2, T = 3, B = 4 }, C = { UI = { TEXT_LIGHT = rgb(), TEXT_INACTIVE = rgb() }, PURPLE = rgb(), ORANGE = rgb(), BLUE = rgb() }, FUNCS = {} }
MP = { UI = { UTILS = {} }, LOBBY = { seats = {}, away = {}, config = {} }, GAME = {}, FIT = nil }
MP.PRESENCE = dofile("lib/presence.lua")
dofile("lib/fit.lua")
function localize(k) return k == "k_pr_connected" and "Connected" or "ERROR" end
MP.UI.UTILS.create_text_node = function(text, cfg) cfg = cfg or {}; cfg.text = text; return { n = G.UIT.T, config = cfg } end
MP.UI.UTILS.create_row = function(cfg, nodes) return { n = G.UIT.R, config = cfg or {}, nodes = nodes } end
MP.UI.UTILS.create_column = function(cfg, nodes) return { n = G.UIT.C, config = cfg or {}, nodes = nodes } end
MP.UI.UTILS.create_blank = function(w, h) return { n = G.UIT.B, config = { w = w, h = h } } end
MP.THREEP = { seat_count = function() return 3 end }
function UIBox_button() return { n = G.UIT.C, config = {} } end
dofile("ui/lobby/players_display.lua")
local long = ("W"):rep(40)
MP.LOBBY.seats = {
	{ username = long, id = "1", sid = "s1" },
	{ username = "LIL COCAIN", id = "2", sid = "s2" },
	{ username = "LIL COCAIN", id = "2", sid = "s2" },
	{ username = "Cronkalatro", id = "3", sid = "s3" },
}
local rows = MP.UI.players_section_rows(0.45)
ok(#rows == 3, "the connected list shows one row per Steam id")
local name_col, status_col
for _, node in ipairs(rows[1].nodes) do
	if node.config and node.config.maxw == 1.85 then name_col = node end
	if node.config and node.config.maxw == 1.45 then status_col = node end
end
ok(name_col and status_col, "the name and the Connected status are separate columns")
local shown = name_col.nodes[1].config.text
ok(shown:find("%.%.$") and not shown:find(long, 1, true), "a long name is truncated inside its column")
ok(status_col.nodes[1].config.text == "Connected", "the status column reads Connected")

print("PASS: player dedupe")
