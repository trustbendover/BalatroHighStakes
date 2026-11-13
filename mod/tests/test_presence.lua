-- Connection status and the end-screen lines that name it. run from mod/:
-- luajit tests/test_presence.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = {}
local P = dofile("lib/presence.lua")
local Core = dofile("networking/p2p_server.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")

ok(P.kind({}) == "connected", "a seated player is connected")
ok(P.kind({ away = true }) == "held" and P.kind({ held = true, grace = 12 }) == "held", "a held seat is waiting to rejoin")
ok(P.kind({ rejoining = true, away = true }) == "rejoining", "socket back, run not restored yet")
ok(P.kind({ spectator = true }) == "watching", "a watcher is watching")
ok(P.kind({ held = true, eliminated = true }) == "gone" and P.kind({ connected = false }) == "gone", "after the grace, the seat is gone")
ok(P.label("held") == "Waiting to rejoin" and P.label("held", nil, 100) == "Waiting to rejoin 1:40", "the held label can carry the time left")

local function dict(file)
	local t = dofile(file)
	local d = t.misc and t.misc.dictionary or {}
	return function(k) return d[k] end
end
ok(P.label("rejoining", dict("localization/nl.lua")) == "Keert terug", "Dutch rejoining")
ok(P.label("watching", dict("localization/en-us.lua")) == "Watching", "English watching")
local listed = P.roster({ code = "ABCDE", players = { { id = "a", username = "Ann~2", spectator = true } },
	away = { { id = "b", username = "Bob", left = 90 } } })
ok(listed[1].kind == "watching" and listed[2].kind == "held" and listed[2].label:find("1:30", 1, true), "roster: watching and a held seat")
ok(not listed[1].code and not table.concat({ listed[1].label, listed[1].name, listed[2].label }, " "):find("ABCDE", 1, true),
	"a status never includes a lobby code")

local T = 10000
local function server() return Core.new({ now = function() return T end, log = function() end }) end
local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	c.box = msgs
	function c.last(a) for i = #msgs, 1, -1 do if msgs[i].action == a then return msgs[i] end end end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local function by_name(info, name)
	for _, row in ipairs(P.roster(info)) do if row.name == name then return row end end
end

-- Hold, rejoin, then connected again. Lives on the seat do not change.
do
	local S = server()
	local ann, bob = client(S, "Ann"), client(S, "Bob")
	S:receive(ann, { action = "createLobby", gameMode = "attrition" })
	local joined = ann.last("joinedLobby")
	S:receive(bob, { action = "joinLobby", code = joined.code })
	S:receive(bob, { action = "readyLobby" })
	S:receive(ann, { action = "startGame" })
	ok(ann.last("startGame"), "the match starts")
	local before = bob.lives
	S:disconnect(bob)
	local held = by_name(ann.last("lobbyInfo"), "Bob")
	ok(held and held.kind == "held", "disconnect holds the seat: waiting to rejoin")
	ok(bob.lives == before, "holding the seat does not change lives")
	local back = client(S, "Bob")
	S:receive(back, { action = "rejoinLobby", code = joined.code, reconnectToken = bob.reconnectToken })
	local mid = by_name(ann.last("lobbyInfo"), "Bob")
	ok(mid and mid.kind == "rejoining" and back.lives == before, "rejoin is shown while the run is restored, lives unchanged")
	S:receive(back, { action = "resumeRestarted" })
	local done = by_name(ann.last("lobbyInfo"), "Bob")
	ok(done and done.kind == "connected", "after the run is restored the status is connected")
end

-- Watching, and gone once the grace ends.
do
	local S = server()
	local ann, bob, cy = client(S, "Ann"), client(S, "Bob"), client(S, "Cy")
	S:receive(ann, { action = "createLobby", gameMode = "attrition" })
	local joined = ann.last("joinedLobby")
	S:receive(bob, { action = "joinLobby", code = joined.code })
	S:receive(cy, { action = "joinLobby", code = joined.code })
	S:receive(bob, { action = "readyLobby" })
	S:receive(cy, { action = "readyLobby" })
	S:receive(ann, { action = "startGame" })
	local watch = client(S, "Dee")
	S:receive(watch, { action = "joinLobby", code = joined.code, spectate = true })
	ok(by_name(ann.last("lobbyInfo"), "Dee").kind == "watching", "a watcher is marked watching")
	local before = bob.lives
	local cy_lives = cy.lives
	S:disconnect(bob)
	ok(by_name(ann.last("lobbyInfo"), "Bob").kind == "held" and bob.lives == before, "still held, same lives, until the grace ends")
	T = T + Core.rejoin_grace(ann.lobby.options, ann.lobby.gameMode) + 1
	S:tick()
	local gone = by_name(ann.last("lobbyInfo"), "Bob")
	ok(gone and gone.kind == "gone" and cy.lives == cy_lives, "when the grace ends the status is gone and the others keep their lives")
end

G = { FUNCS = {}, UIT = { R = 1, C = 2, T = 3 }, GAME = { skips = 0 }, SETTINGS = {},
	C = { JOKER_GREY = {}, MULT = {}, PURPLE = {}, L_BLACK = {}, UI = { TEXT_LIGHT = {} } } }
function darken(c) return c end
function localize() return "ERROR" end
MP.UI = { Disableable_Toggle = function() end }
MP.THREEP = {
	lobby_player = function() return { username = "Bob" } end,
	seat_index = function() return 2 end,
	seat_count = function() return 2 end,
}
MP.INSANE_INT = { to_string = function() return "0" end }
MP.LOBBY = {
	player_list = { { id = "a" }, { id = "b", username = "Bob" } },
	my_id = "a", is_host = true, config = {},
}
MP.GAME = {
	enemy = { lives = 4, highest_score = 0, skips = 0 },
	enemies = { b = { away = true, lives = 3, real_score = 0, skips = 1 } },
	lives = 4, highest_score = 0,
}
MP.PRESENCE = P
dofile("ui/game/lobby_info.lua")
local function row_text(node, acc)
	acc = acc or {}
	if type(node) ~= "table" then return acc end
	if node.config and type(node.config.text) == "string" then acc[#acc + 1] = node.config.text end
	if node.nodes then for _, child in ipairs(node.nodes) do row_text(child, acc) end end
	return acc
end
local row = table.concat(row_text(MP.UI.create_UIBox_player_row("guest")), "|")
ok(row:find("Waiting to rejoin", 1, true), "the player row reads the live away state, not a nil global")

print("PASS: presence")
