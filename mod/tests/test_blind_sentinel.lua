-- luajit tests/test_blind_sentinel.lua (run from mod/): the -1 "prevent losing" blind sentinel is never shown
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local LOC = { k_mp_blind_failed = "Failed", k_mp_blind_out = "Out" }
function localize(k) return LOC[k] or k end
local base_called = 0
G = { FUNCS = { blind_chip_UI_scale = function(e) base_called = base_called + 1; G.GAME.blind.chip_text = tostring(G.GAME.blind.chips) end }, GAME = {} }
MP = { UI = {}, GAME = { lives = 2 }, is_mp_or_ghost = function() return true end }
-- load only the sentinel part of blind_hud.lua (the rest needs the full game)
local src = io.open("ui/game/blind_hud.lua"):read("*a")
local s0 = src:find("%-%- The \"prevent losing\" path", 1); local part = src:sub(s0)
assert(load(part))()
local e = { config = { scale = 0.7 } }
G.GAME.blind = { chips = 300 }; G.FUNCS.blind_chip_UI_scale(e)
ok(G.GAME.blind.chip_text == "300" and base_called == 1, "normal blind untouched, base func still runs")
G.GAME.blind = { chips = -1 }; G.FUNCS.blind_chip_UI_scale(e)
ok(G.GAME.blind.chip_text == "Failed", "sentinel shows Failed, not -1")
MP.GAME.lives = 0; G.FUNCS.blind_chip_UI_scale(e)
ok(G.GAME.blind.chip_text == "Out", "eliminated player shows Out")
MP.is_mp_or_ghost = function() return false end
G.GAME.blind = { chips = -1 }; G.FUNCS.blind_chip_UI_scale(e)
ok(G.GAME.blind.chip_text == "-1", "singleplayer untouched")
ok(MP.UI.blind_sentinel_text(0, 1) == nil and MP.UI.blind_sentinel_text(nil, 1) == nil, "0 / nil not a sentinel")
-- localization keys exist in EN and NL
for _, f in ipairs({ "localization/en-us.lua", "localization/nl.lua" }) do
	local s = io.open(f):read("*a")
	ok(s:find("k_mp_blind_failed", 1, true) and s:find("k_mp_blind_out", 1, true), f .. " has both keys")
end
print("all ok")
