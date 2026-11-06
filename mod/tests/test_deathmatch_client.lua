-- luajit tests/test_deathmatch_client.lua (run from mod root): Deathmatch client texts, standings,
-- spectator state, and the event jokers reacting to a leave / disconnect elimination.
MP = { LOBBY = { code = "ABCDE", config = { gamemode = "gamemode_mp_deathmatch", multiplayer_jokers = true }, names_by_id = { b = "Bob", c = "Carol", d = "Dan" }, player_count = 4 },
	GAME = { lives = 4, enemy = {}, enemies = {} }, UTILS = {} }
G = { STAGE = 1, STAGES = { RUN = 1 }, UIT = { R = 1, T = 2 }, C = { UI = {}, WHITE = {} }, jokers = {}, hand = { size = 8, change_size = function(self, n) self.size = self.size + n end } }
local warned = {}
function sendWarnMessage(m) warned[#warned + 1] = m end
local dollars = 0
function ease_dollars(n) dollars = dollars + n end
function localize() return "ERROR" end -- force English fallbacks
function card_eval_status_text() end
MP.UTILS.add_nemesis_info = function() end
MP.is_pvp_boss = function() return false end
local defs = {}
SMODS = { Atlas = function() end, Joker = function(t) defs[t.key] = t end }
dofile("lib/presence.lua"); dofile("lib/modes.lua"); dofile("lib/teams.lua"); dofile("lib/jokers_3p.lua"); dofile("lib/deathmatch.lua")
for _, k in ipairs({ "vulture", "laughing_third", "bounty_hunter" }) do dofile("objects/jokers/threep/" .. k .. ".lua") end
local D, J = MP.DEATHMATCH, MP.J3P
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local function deep(t) local r = {} for k, v in pairs(t) do r[k] = type(v) == "table" and deep(v) or v end return r end
local function card(key) local d = defs[key]; return { ability = { extra = deep(d.config.extra) }, area = G.jokers, def = d } end

ok(D.is_active(), "gamemode detected")
ok(MP.MODES.limits("gamemode_mp_deathmatch").min == 2 and MP.MODES.limits("deathmatch").max == 8 and MP.MODES.default_lives("deathmatch") == 4, "2-8 players, 4 lives")
ok(MP.MODES.start_problem(1, "deathmatch") ~= nil and MP.MODES.start_problem(8, "deathmatch") == nil and MP.MODES.start_problem(9, "deathmatch") ~= nil, "start limits")

-- standings + messages
local s1 = { you = "a", running = true, alive = { { id = "a", lives = 4 }, { id = "b", lives = 3 }, { id = "c", lives = 2, away = true }, { id = "d", lives = 1 } }, out = {} }
ok(D.standings_text(s1) == "Deathmatch: 4 left  |  You 4  Bob 3  Carol 2 Waiting to rejoin  Dan 1", D.standings_text(s1))
local s2 = { you = "a", running = true, alive = { { id = "a", lives = 4 }, { id = "b", lives = 3 }, { id = "c", lives = 2 } }, out = { { id = "d", place = 4 } } }
local m = D.messages(s1, s2)
ok(#m == 1 and m[1] == "Dan eliminated - 3 left", "elimination message: " .. tostring(m[1]))
local s3 = { you = "a", running = true, alive = { { id = "b", lives = 3 }, { id = "c", lives = 2 } }, out = { { id = "d", place = 4 }, { id = "a", place = 3 } } }
m = D.messages(s2, s3)
ok(m[1] == "You are out (place 3). Watch the standings or return to the lobby.", "own elimination: spectate hint: " .. tostring(m[1]))
local s4 = { you = "a", running = false, winnerId = "b", alive = { { id = "b", lives = 1 } }, out = { { id = "d", place = 4 }, { id = "a", place = 3 }, { id = "c", place = 2 } } }
m = D.messages(s3, s4)
ok(m[#m] == "Deathmatch over: Bob wins", "spectator sees the winner")
ok(D.place(s4, "b") == 1 and D.place(s4, "a") == 3 and D.place(s1, "a") == nil, "places")
ok(D.standings_text({ you = "a", running = false, winnerId = "a" }) == "Deathmatch over: you are the last one standing!", "winner text")

-- on_update keeps HUD lives in sync and works for a spectator outside the run
G.STAGE = 2
MP.GAME.enemies = { b = { id = "b", username = "Bob", lives = 4 }, c = { id = "c", username = "Carol", lives = 4 }, d = { id = "d", username = "Dan", lives = 4 } }
MP.THREEP = { refresh_hud = function() end }
D.on_update(s1)
ok(MP.GAME.enemies.b.lives == 3 and MP.GAME.deathmatch_text:find("4 left", 1, true), "enemy lives synced from standings")
D.on_update(s2)
ok(warned[#warned] == "Dan eliminated - 3 left", "spectator / menu gets a warn message")
ok(D.spectate_row() ~= nil, "spectate standings row available")
G.STAGE = 1

-- jokers: a rival who LEAVES with 3 lives (client marks him eliminated, lives 0 -- action_player_left)
MP.GAME.lives = 3
MP.GAME.enemies = { b = { id = "b", lives = 3 }, c = { id = "c", lives = 2 }, d = { id = "d", lives = 2 } }
local v, l, h = card("vulture"), card("laughing_third"), card("bounty_hunter")
for _, x in ipairs({ v, l, h }) do x.def.add_to_deck(nil, x, false); x.def.update(nil, x, 0) end
local d0 = dollars
MP.GAME.enemies.b.eliminated = true; MP.GAME.enemies.b.lives = 0 -- left mid-match
for _, x in ipairs({ v, l, h }) do x.def.update(nil, x, 0) end
ok(dollars > d0 and v.ability.extra.hands == 1, "Vulture reacts to a leaver's elimination")
local g = J.SCALE.laughing_gain(J.rival_count())
ok(math.abs(l.ability.extra.x_mult - (1 + g)) < 1e-9, "Laughing Third: a leaver counts as one life, not three (X" .. l.ability.extra.x_mult .. ")")
-- and a disconnect past the grace period (server: playerEliminated reason disconnected)
local d1 = dollars
MP.GAME.enemies.c.eliminated = true; MP.GAME.enemies.c.lives = 0
for _, x in ipairs({ v, l, h }) do x.def.update(nil, x, 0) end
ok(dollars > d1 and v.ability.extra.hands == 2 and math.abs(l.ability.extra.x_mult - (1 + 2 * g)) < 1e-9, "Vulture + Laughing Third react to a grace-timeout elimination")
-- 0.6.8: a dropped seat (crash) shows its last known name, never "?"
local pa = { running = true, you = "me", alive = { { id = "me", username = "Me", lives = 2 }, { id = "zz", username = "Zed", lives = 1 } }, out = {} }
local pb = { running = true, you = "me", alive = { { id = "me", username = "Me", lives = 2 } }, out = { { id = "zz", place = 2 } } }
local mz = D.messages(pa, pb)
ok(mz[1] and mz[1]:find("Zed", 1, true) and not mz[1]:find("?", 1, true), "dropped player keeps the last known name (" .. tostring(mz[1]) .. ")")
-- host side: out entries carry the name
local Core = dofile("networking/p2p_server.lua"); local Sx = Core.new()
local got = {}
local a = { id = "a", username = "Ann", lives = 1, send = function(t) got[#got + 1] = t end }
local Lx = { gameMode = "deathmatch", players = { a }, slots = { { old = { id = "b", username = "Bob", eliminated = true } } }, elimOrder = { "b" }, isInGame = true }
Sx:deathmatch_broadcast(Lx)
ok(got[1].out[1].username == "Bob", "host: eliminated seat sent with its name")
print("PASS: deathmatch client")
