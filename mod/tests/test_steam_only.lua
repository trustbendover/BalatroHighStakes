-- luajit tests/test_steam_only.lua (run from mod root)
-- 0.6.8: Balatro High Stakes is Steam peer-to-peer only. No TCP client, no server address, no mode choice.
local n = 0
local function ok(c, m) assert(c, m); n = n + 1 end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

-- the TCP client is gone and nothing loads it
ok(read("networking/socket.lua") == nil, "networking/socket.lua removed")
local core = assert(read("core.lua"))
ok(not core:find("socket.lua", 1, true) and not core:find("NETWORKING_THREAD", 1, true) and not core:find("START_TCP", 1, true), "core.lua starts no TCP thread")
ok(not core:find("server_url", 1, true) or core:find("server_url/server_port are ignored", 1, true), "core.lua only mentions server_url to say it is ignored")
ok(core:find('MP.ENV.mode = "steam"', 1, true), "core.lua forces mode=steam")
ok(core:find('MP.ENV.mode ~= nil and MP.ENV.mode ~= "steam"', 1, true) and core:find("is no longer supported", 1, true), "other mode -> log line")
ok(not core:find('if MP.ENV.mode == "steam"', 1, true), "P2P no longer depends on mode=steam")
ok(core:find("function MP.START_P2P()", 1, true), "MP.START_P2P exists (Reconnect retries Steam)")
ok(read("scripts/release.sh") == nil, "upstream release script (prod server address) removed")
local cfg = assert(read("config.lua"))
ok(not cfg:find("server_url", 1, true) and not cfg:find("server_port", 1, true), "config.lua has no server address")
local ex = assert(read(".env.example"))
ok(ex:find("\nmode=steam", 1, true) and not ex:find("\nserver_url", 1, true), ".env.example: mode=steam, no server_url")
local lobby = assert(read("ui/lobby/lobby.lua"))
ok(lobby:find("MP.START_P2P()", 1, true), "Reconnect button restarts Steam P2P")

-- no in-game UI for a server / IP / address
for _, f in ipairs({ "localization/en-us.lua", "localization/nl.lua" }) do
	local s = assert(read(f)):lower()
	ok(not s:find("playit", 1, true) and not s:find("tailscale", 1, true) and not s:find("server address", 1, true)
		and not s:find("serveradres", 1, true) and not s:find("ip address", 1, true), f .. ": no server/address texts")
end

-- Client.send: without Steam P2P nothing goes to the old TCP channel
local ah = assert(read("networking/action_handlers.lua"))
local body = ah:match("(function Client%.send%(msg%).-\nend\n)")
ok(body and not body:find("uiToNetwork", 1, true), "Client.send has no TCP fallback")
local pushed, sent, traced = 0, {}, 0
local env = setmetatable({
	Client = {}, MP = { STEAM_P2P = nil }, no_log_actions = { keepAlive = true },
	love = { thread = { getChannel = function() return { push = function() pushed = pushed + 1 end } end } },
	json = { encode = function() return "{}" end },
	sendTraceMessage = function() traced = traced + 1 end, sendWarnMessage = function() end,
}, { __index = _G })
local fn = assert(loadstring("local no_log_actions = no_log_actions\n" .. body))
setfenv(fn, env); fn()
env.Client.send({ action = "connect" })
ok(pushed == 0 and traced == 1, "no Steam: message dropped with a log line, not pushed to TCP")
env.MP.STEAM_P2P = { send = function(m) sent[#sent + 1] = m end }
env.Client.send({ action = "createLobby" })
ok(#sent == 1 and sent[1].action == "createLobby" and pushed == 0, "Steam: message goes to the P2P router")
env.MP.SAFE_MODE = true
env.Client.send({ action = "x" })
ok(#sent == 1, "safe mode: nothing sent")

-- installer: no mode prompt, no host address, no connection test
local inst = assert(read("../installer/install.ps1"))
ok(not inst:find("How do you want to play", 1, true) and not inst:find("Choice [1]", 1, true), "installer: no mode choice")
ok(not inst:find("Host address", 1, true) and not inst:find("TcpClient", 1, true), "installer: no host address / TCP test")
ok(inst:find("Convert-EnvToSteam", 1, true) and inst:find("settings__.env", 1, true), "installer: converts old .env to Steam with a backup")
for _, f in ipairs({ "../installer/README.txt", "../installer/LEES_MIJ.txt" }) do
	local s = assert(read(f))
	ok(not s:find("option 2", 1, true) and not s:find("keuze 2", 1, true) and not s:lower():find("servermod", 1, true)
		and not s:find("SERVER MODE", 1, true), f .. ": no server mode")
end

-- user-facing strings say High Stakes, not 3P
local sp = assert(read("networking/steam_p2p.lua"))
ok(not sp:find("Multiplayer 3P lobby", 1, true) and not sp:find("not a 3P lobby", 1, true), "Steam presence/errors say Balatro High Stakes")
ok(not assert(read("lib/updater.lua")):find('"MP3P updater"', 1, true), "updater window title says Balatro High Stakes")

-- patch notes mention it
local pn = assert(read("patchnotes/0.6.8.lua"))
ok(pn:find("Steam only", 1, true) and pn:find("Alleen Steam", 1, true), "patch notes 0.6.8: Steam only (EN + NL)")

print("PASS: steam only (" .. n .. " checks)")
