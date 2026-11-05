-- Host match settings win over the other player's local copy, both directions.
-- run from mod/: luajit tests/test_match_settings.lua
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local Core = dofile("networking/p2p_server.lua")
local M = Core.MATCH or dofile("networking/match_settings.lua")
Core.MATCH = M

local function ok(c, m) assert(c, m); print("ok: " .. m) end

local KEYS = {
	"normal_bosses", "death_on_round_loss", "starting_lives", "pvp_start_round", "timer",
	"hide_score_until_played", "multiplayer_jokers", "gold_on_life_loss", "no_gold_on_round_loss",
	"different_seeds", "the_order", "preview_disabled",
}

local function with(base, overrides)
	local c = {}
	for k, v in pairs(base) do c[k] = v end
	for k, v in pairs(overrides or {}) do c[k] = v end
	return c
end

local host_off = with(M.fresh(), {
	normal_bosses = false, death_on_round_loss = false, starting_lives = 2, pvp_start_round = 3,
	timer = false, hide_score_until_played = true, multiplayer_jokers = false, gold_on_life_loss = false,
	no_gold_on_round_loss = true, different_seeds = true, the_order = false, preview_disabled = true,
})
local guest = with(M.fresh(), {
	normal_bosses = true, death_on_round_loss = true, starting_lives = 9, pvp_start_round = 1,
	timer = true, hide_score_until_played = false, multiplayer_jokers = true, gold_on_life_loss = true,
	no_gold_on_round_loss = false, different_seeds = false, the_order = true, preview_disabled = false,
	weekly = "seen-week", misprint_display = true,
})
local smods = { timersfx = 2, misprint_display = true, integrations = { Preview = false } }
local wire = M.wire(host_off)
ok(wire.match_settings == 1 and wire.normal_bosses == false, "wire publishes PvP boss effects OFF")
ok(wire.weekly == nil and wire.misprint_display == nil and wire.timersfx == nil, "personal keys are not on the wire")
local round = json.decode(json.encode(wire))
ok(round.normal_bosses == false and round.death_on_round_loss == false and round.timer == false
	and round.gold_on_life_loss == false and round.multiplayer_jokers == false, "JSON keeps explicit false")
M.apply(guest, round)
for _, k in ipairs(KEYS) do
	ok(guest[k] == host_off[k], "guest follows host OFF-direction: " .. k .. " = " .. tostring(host_off[k]))
end
ok(guest.weekly == "seen-week" and guest.misprint_display == true, "local weekly / misprint display stay")
ok(smods.timersfx == 2 and smods.integrations.Preview == false, "audio and accessibility config is not written")
local boss, effects = M.pvp_boss(3, guest)
ok(boss == "bl_mp_nemesis" and effects == false, "effects OFF: both players get Nemesis, no boss debuff")
boss, effects = M.pvp_boss(2, guest)
ok(boss == nil and not effects, "before the host's PvP ante there is no PvP boss")

local host_on = with(M.fresh(), {
	normal_bosses = true, death_on_round_loss = true, starting_lives = 6, pvp_start_round = 1,
	timer = true, hide_score_until_played = false, multiplayer_jokers = true, gold_on_life_loss = true,
	no_gold_on_round_loss = false, different_seeds = false, the_order = true, preview_disabled = false,
})
local guest_on = with(M.fresh(), {
	normal_bosses = false, death_on_round_loss = false, starting_lives = 1, pvp_start_round = 8,
	timer = false, hide_score_until_played = true, multiplayer_jokers = false, gold_on_life_loss = false,
	no_gold_on_round_loss = true, different_seeds = true, the_order = false, preview_disabled = true,
})
M.apply(guest_on, json.decode(json.encode(M.wire(host_on))))
for _, k in ipairs(KEYS) do
	ok(guest_on[k] == host_on[k], "guest follows host ON-direction: " .. k .. " = " .. tostring(host_on[k]))
end
boss, effects = M.pvp_boss(1, guest_on)
ok(boss == nil and effects == true, "effects ON: vanilla boss debuff, round is still PvP")

local leftover = { normal_bosses = true, starting_lives = 4, weekly = "keep" }
M.apply_patch(leftover, { starting_lives = "3" })
ok(leftover.normal_bosses == false and leftover.starting_lives == 3 and leftover.weekly == "keep",
	"a message that omits PvP effects means OFF, not the guest's old ON")

-- Server: join, ignored guest write, start, leave-keeps-seat, rejoin, watch.
local S = Core.new({ log = function() end, now = function() return 1000 end })
local function client(name)
	local p = { name = name, msgs = {} }
	p.c = S:connect(function(t) p.msgs[#p.msgs + 1] = t end)
	function p.last(a)
		for i = #p.msgs, 1, -1 do if p.msgs[i].action == a then return p.msgs[i] end end
	end
	function p.count(a)
		local n = 0
		for _, m in ipairs(p.msgs) do if m.action == a then n = n + 1 end end
		return n
	end
	S:receive(p.c, { action = "username", username = name, modHash = "t" })
	return p
end

local A, B = client("host"), client("guest")
S:receive(A.c, { action = "createLobby", gameMode = "duel" })
local code = A.last("joinedLobby").code
-- Old-style partial: the host never mentions PvP effects. Stored value must still be OFF,
-- and a failed round must not start costing a life just because the default is on.
S:receive(A.c, { action = "lobbyOptions", starting_lives = "2" })
ok(A.c.lobby.options.normal_bosses == false, "omitted PvP effects are stored as OFF")
ok(A.c.lobby.options.death_on_round_loss == nil, "a partial update does not invent server-side round-loss")
S:receive(B.c, { action = "joinLobby", code = code })
local joined = B.last("lobbyOptions")
ok(joined and joined.match_settings == 1 and joined.normal_bosses == false and joined.starting_lives == 2
	and joined.gamemode == "gamemode_mp_duel", "join publishes the host snapshot for this mode")
local local_on = with(M.fresh(), { normal_bosses = true, starting_lives = 9, weekly = "mine" })
M.apply(local_on, joined)
ok(local_on.normal_bosses == false and local_on.starting_lives == 2 and local_on.weekly == "mine",
	"join apply: guest ON becomes host OFF")
boss, effects = M.pvp_boss(local_on.pvp_start_round, local_on)
ok(boss == "bl_mp_nemesis" and not effects, "after join both players play Nemesis")

local broadcasts = B.count("lobbyOptions")
S:receive(B.c, { action = "lobbyOptions", match_settings = 1, normal_bosses = true, starting_lives = 9,
	death_on_round_loss = true, timer = false })
ok(A.c.lobby.options.normal_bosses == false and A.c.lobby.options.starting_lives == 2, "guest cannot override the host")
ok(B.count("lobbyOptions") == broadcasts, "rejected guest settings are not sent back")

S:receive(A.c, { action = "lobbyOptions", match_settings = 1, normal_bosses = true, starting_lives = 5,
	death_on_round_loss = true, pvp_start_round = 1, timer = true, hide_score_until_played = false,
	multiplayer_jokers = false, gold_on_life_loss = false, no_gold_on_round_loss = true })
B.c.isReadyLobby = true
S:receive(A.c, { action = "startGame" })
local started = B.last("startGame")
ok(started and started.config and started.config.normal_bosses == true and started.config.starting_lives == 5
	and started.config.pvp_start_round == 1 and started.config.multiplayer_jokers == false
	and started.config.gold_on_life_loss == false and started.config.no_gold_on_round_loss == true
	and started.config.death_on_round_loss == true, "start carries the host snapshot, not the guest's")
local dirty = with(M.fresh(), { normal_bosses = false, starting_lives = 1, pvp_start_round = 9,
	multiplayer_jokers = true, gold_on_life_loss = true, death_on_round_loss = false, timer = false })
M.apply(dirty, started.config)
ok(dirty.normal_bosses == true and dirty.starting_lives == 5 and dirty.multiplayer_jokers == false
	and dirty.gold_on_life_loss == false and dirty.timer == true, "start apply overwrites the opposite local copy")
boss, effects = M.pvp_boss(1, dirty)
ok(effects == true and boss == nil, "after start, boss effects are on for everyone")
ok(A.c.lobby.options.death_on_round_loss == true, "server enforces the host's round-loss flag from the snapshot")

-- Alt+F4: seat held, immediate rejoin sees the host copy even if the host changed it while they were gone.
local token = B.c.reconnectToken
local lives = nil
for _, m in ipairs(B.msgs) do if m.action == "playerInfo" then lives = m.lives end end
S:disconnect(B.c)
S:receive(A.c, { action = "lobbyOptions", match_settings = 1, normal_bosses = false, starting_lives = 5,
	death_on_round_loss = false, pvp_start_round = 2, timer = false, hide_score_until_played = true })
local B2 = client("guest")
S:receive(B2.c, { action = "rejoinLobby", code = code, reconnectToken = token })
local resumed = B2.last("resumeGame")
local again = B2.last("lobbyOptions")
ok(B2.last("rejoinedLobby") and resumed and resumed.config and resumed.config.normal_bosses == false
	and resumed.config.death_on_round_loss == false and resumed.config.timer == false
	and resumed.config.hide_score_until_played == true and resumed.config.pvp_start_round == 2,
	"rejoin resume carries the host snapshot")
ok(again and again.normal_bosses == false and again.starting_lives == 5, "rejoin lobbyOptions matches resume")
ok(resumed.lives == lives, "rejoin keeps the seat's lives")
local memory = with(M.fresh(), { normal_bosses = true, timer = true, hide_score_until_played = false, death_on_round_loss = true })
M.apply(memory, resumed.config)
ok(memory.normal_bosses == false and memory.timer == false and memory.hide_score_until_played == true
	and memory.death_on_round_loss == false, "rejoin apply: local ON does not survive")
boss, effects = M.pvp_boss(2, memory)
ok(boss == "bl_mp_nemesis" and not effects, "after rejoin both players are back to Nemesis")

-- Leave keeps the seat; Watch still receives the host snapshot.
S:receive(B2.c, { action = "leaveLobby" })
local held = false
for _, sl in ipairs(A.c.lobby.slots) do if sl.reconnectToken == B2.c.reconnectToken then held = true end end
ok(held and A.c.lobby.isInGame, "Leave during a match keeps the seat")
local watch = client("watch")
S:receive(watch.c, { action = "joinLobby", code = code, spectate = true })
ok(watch.last("spectateStart") and watch.last("lobbyOptions") and watch.last("lobbyOptions").normal_bosses == false
	and watch.last("lobbyOptions").starting_lives == 5, "Watch match still gets the host snapshot")
S:receive(B2.c, { action = "rejoinLobby", code = code, reconnectToken = B2.c.reconnectToken })
ok(B2.last("rejoinedLobby") and B2.last("resumeGame") and B2.last("resumeGame").config.normal_bosses == false,
	"Rejoin from the held seat still applies the host snapshot")

print("PASS: host match settings")
