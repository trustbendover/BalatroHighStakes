-- luajit tests/test_aij_blind_drawn.lua (run from mod/): All in Jest "Blind Drawn" hides the nemesis score/hands
-- (AiJ's own lovely patches target the old ui/game.lua / ui/hud.lua layout and no longer apply)
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("ui/game/blind_hud.lua"):read("*a")
local a = src:find("function MP.UI.aij_blind_drawn()", 1, true)
local fn = src:sub(a, src:find("\nend", a, true) + 4)
local b = src:find("G.FUNCS.multiplayer_blind_chip_UI_scale = function(e)", 1, true)
local scale = src:sub(b, src:find("\nend\n", b, true) + 4)
local j = src:find("function MP.UI.juice_up_pvp_hud()", 1, true)
local juice = src:sub(j, src:find("\nend\n", j, true) + 4)
local owned = false
SMODS = { find_card = function(k) if owned and k == "j_aij_mp_blind_drawn" then return { {} } end return {} end }
G = { FUNCS = {}, GAME = { blind = {}, current_round = { hands_played = 1 } }, E_SWITCH_POINT = 1e11 }
local juiced = 0
G.HUD_blind = { get_UIE_by_ID = function() return { juice_up = function() juiced = juiced + 1 end } end }
MP = { UI = {}, LOBBY = { config = {} }, GAME = { enemy = { hands = 3, score = { coeffiocient = 500 } } },
	is_pvp_boss = function() return true end,
	INSANE_INT = { to_string = function() return "500" end, greater_than = function() return false end, create = function() end } }
function scale_number() return 0.5 end
assert(loadstring(fn .. "\n" .. scale .. "\n" .. juice))()
local e = { config = {} }
G.FUNCS.multiplayer_blind_chip_UI_scale(e)
ok(MP.GAME.enemy.score_text == "500" and MP.GAME.enemy.hands_text == "3", "without the joker: real score and hands")
MP.UI.juice_up_pvp_hud(); ok(juiced == 2, "without the joker: HUD juices up")
owned = true
G.FUNCS.multiplayer_blind_chip_UI_scale(e)
ok(MP.GAME.enemy.score_text == "???" and MP.GAME.enemy.hands_text == "?", "Blind Drawn: score ??? and hands ?")
MP.UI.juice_up_pvp_hud(); ok(juiced == 2, "Blind Drawn: no juice-up that would reveal a score change")
ok(io.open("ui/game/lobby_info.lua"):read("*a"):find("MP.UI.aij_blind_drawn()", 1, true), "lobby info hides the opponent's highest score too")
print("PASS: All in Jest Blind Drawn")
