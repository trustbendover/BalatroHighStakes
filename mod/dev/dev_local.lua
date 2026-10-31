-- Balatro High Stakes - DEV ONLY. GPL-3.0.
-- Loaded by core.lua only when mod/dev/DEV_BUILD exists AND the process has HS_DEV_LOCAL=1 (set by
-- tools/dev_local_match.ps1). mod/dev/ is never part of a release zip (tools/build_release.py refuses).
-- Swaps the Steam transport for dev/file_backend.lua and optionally runs autoplay, scenarios and captures.
--
-- Environment (all set by the launcher, per instance):
--   HS_DEV_LOCAL=1           switch on (with dev/DEV_BUILD)
--   HS_DEV_DIR               shared transport folder (all instances)
--   HS_DEV_NAME              this instance's peer id and username (dev1..dev8)
--   HS_DEV_PEERS             comma list of all peer ids
--   HS_DEV_ROLE              host | guest
--   HS_DEV_PLAYERS           host: start when this many players are in and ready
--   HS_DEV_MODE              host: gamemode key (attrition, deathmatch, duel, showdown, survival, koth, teams)
--   HS_DEV_AUTOPLAY=1        play by itself (ready, blinds, hands, shop, PvP, return to lobby)
--   HS_DEV_SCENARIO          full_match | host_leave | guest_rejoin | elimination | presets | ready_gating
--   HS_DEV_CAPTURE           folder for screenshots (F9 any time; automatic at scenario points)
--   HS_DEV_SHOT_EVERY        optional: also a screenshot every N seconds
--   HS_DEV_SPEED             game speed for bots (default 4)
local D = {}
local function env(k, d) local v = os.getenv(k); if v == nil or v == "" then return d end return v end
D.dir = env("HS_DEV_DIR")
D.name = env("HS_DEV_NAME", "dev1")
D.peers = {}
for p in env("HS_DEV_PEERS", "dev1,dev2,dev3,dev4,dev5,dev6,dev7,dev8"):gmatch("[^,%s]+") do D.peers[#D.peers + 1] = p end
D.role = env("HS_DEV_ROLE", D.name == "dev1" and "host" or "guest")
D.players = tonumber(env("HS_DEV_PLAYERS", "2")) or 2
D.mode = env("HS_DEV_MODE", "attrition")
D.autoplay = env("HS_DEV_AUTOPLAY") == "1"
D.scenario = env("HS_DEV_SCENARIO", "full_match")
D.capture = env("HS_DEV_CAPTURE")
D.shot_every = tonumber(env("HS_DEV_SHOT_EVERY", "0")) or 0
D.speed = tonumber(env("HS_DEV_SPEED", "4")) or 4
D.persona = env("HS_DEV_PERSONA")      -- aggressive | conservative | shopper | saver | random (default by name)
D.lang = env("HS_DEV_LANG")              -- e.g. nl: switch the test profile language once at start
D.seed = tonumber(env("HS_DEV_SEED", "")) -- bot decision seed (default from name+persona)

-- box only: LuaJIT on the headless box segfaults now and then (libluajit, always mid-play); HS_DEV_NOJIT=1 turns the JIT off
if env("HS_DEV_NOJIT") == "1" and jit and jit.off then jit.off(); jit.flush() end
local function log(m) if sendInfoMessage then sendInfoMessage(m, "HS-DEV") end end
D.log = log
if not D.dir then
	log("HS_DEV_LOCAL=1 but HS_DEV_DIR is not set: dev transport off")
	return nil
end
log("DEV LOCAL TEST MODE: " .. D.name .. " (" .. D.role .. ") dir=" .. D.dir .. " scenario=" .. D.scenario .. (D.autoplay and " autoplay" or ""))

local FB = MP.load_mp_file("dev/file_backend.lua")
function D.new_backend()
	if not FB then return nil, "dev/file_backend.lua failed to load" end
	local b = FB.new({ dir = D.dir, me = D.name, peers = D.peers, log = log })
	-- HS_DEV_CHAOS="lat=150,jit=100,loss=0.05,cut_every=90,cut_for=12": test-only network chaos
	local spec = os.getenv("HS_DEV_CHAOS")
	if b and spec and spec ~= "" then
		local CH = MP.load_mp_file("dev/chaos_backend.lua")
		if CH then math.randomseed(os.time() + D.index * 7919); b = CH.wrap(b, spec, { log = log }); log("DEV chaos transport: " .. spec) end
	end
	return b
end

-- username = instance name (in-memory; the test profile is separate from the real one anyway)
pcall(function() SMODS.Mods["Multiplayer"].config.username = D.name; MP.LOBBY.username = D.name end)

D.FILE_CODE = D.dir .. "/lobby_code.txt"
function D.write_code(code) local f = io.open(D.FILE_CODE, "wb"); if f then f:write(code); f:close() end end
function D.read_code() local f = io.open(D.FILE_CODE, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s and s:match("%w+") end

D.CAP = MP.load_mp_file("dev/capture.lua")
if D.CAP then D.CAP.init(D) end
function D.shot(label) if D.CAP then D.CAP.shot(label) end end
D.AP = MP.load_mp_file("dev/autoplay.lua")
D.SC = MP.load_mp_file("dev/scenarios.lua")

-- fresh test profiles: never show the first-run tutorial (Jimbo blocks the bots)
local function no_tutorial()
	if G.SETTINGS then G.SETTINGS.tutorial_complete = true; G.SETTINGS.tutorial_progress = nil end
	if G.OVERLAY_TUTORIAL then pcall(function() G.FUNCS.skip_tutorial_section() end)
		if G.OVERLAY_TUTORIAL then pcall(function() G.OVERLAY_TUTORIAL:remove() end); G.OVERLAY_TUTORIAL = nil end end
end
D.no_tutorial = no_tutorial

-- tile windows on the primary display so a region capture shows only the game
D.index = tonumber(D.name:match("(%d+)$") or "1") or 1
function D.layout(n, i)
	if n <= 2 then return 960, 540, (i - 1) * 960, 270 end
	local c = (i - 1) % 4; local r = math.floor((i - 1) / 4)
	return 480, 270, c * 480, 270 + r * 270
end
local placed = false
local function place()
	if placed or not love.window then return end
	placed = true
	local w, h, x, y = D.layout(D.players or 2, D.index)
	love.window.updateMode(w, h, { fullscreen = false, resizable = true, display = 1 })
	love.window.setPosition(x, y, 1)
	log(string.format("window %dx%d at %d,%d", w, h, x, y))
end

local t = 0
local upd = Game.update
function Game:update(dt)
	local r = upd(self, dt)
	t = t + (dt or 0)
	pcall(place)
	pcall(no_tutorial)
	if D.lang and not D.lang_done and G.SETTINGS and G.set_language and t > 1 then
		D.lang_done = true
		pcall(function() G.SETTINGS.language = D.lang; G.SETTINGS.real_language = D.lang; G:set_language(); if SMODS and SMODS.handle_loc_file then for _, m in pairs(SMODS.Mods) do if m.can_load and m.path then pcall(SMODS.handle_loc_file, m.path, m.id) end end end; if init_localization then init_localization() end; log("language " .. D.lang) end)
	end
	pcall(function()
		if D.speed and G.SETTINGS and D.autoplay then G.SETTINGS.GAMESPEED = D.speed end
		if D.SC then D.SC.tick(D, dt, t) end
		if D.autoplay and D.AP then D.AP.tick(D, dt, t) end
		if D.CAP then D.CAP.tick(D, dt, t) end
	end)
	return r
end

return D
