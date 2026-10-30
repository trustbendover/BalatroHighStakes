-- luajit tests/test_start_blind_out.lua (run from mod/): a player who is out ignores the lobby-wide startBlind
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("networking/action_handlers.lua"):read("*a")
ok(src:find("if MP.player_is_out and MP.player_is_out() then return end\n\tMP.UI.start_pvp_countdown(begin_pvp_blind)", 1, true), "startBlind: out players skip the PvP countdown")
local body = src:match("(function MP%.player_is_out%(%).-\nend)")
ok(body, "MP.player_is_out defined")
MP = { GAME = { lives = 2 } }
G = { STATES = { GAME_OVER = 4, SELECTING_HAND = 1 }, STATE = 1 }
assert(loadstring(body))()
ok(MP.player_is_out() == false, "alive, playing: not out")
MP.GAME.lives = 0; ok(not MP.player_is_out(), "0 lives alone is not out (deathmatch resolves at the PvP)")
MP.GAME.lives = 1; G.STATE = 4; ok(MP.player_is_out(), "game over screen: out")
G.STATE = 1; MP.SPECTATE = { watching = function() return true end }; ok(MP.player_is_out(), "spectating: out")
print("PASS: startBlind ignored when out")
