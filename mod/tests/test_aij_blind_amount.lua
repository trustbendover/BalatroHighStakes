-- luajit tests/test_aij_blind_amount.lua (run from mod/): All-in-Jest dynamic blind amounts on the blind select screen
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("ui/game/blind_hud.lua"):read("*a")
local a = src:find("function MP.UI.aij_blind_amount(", 1, true)
local fn = src:sub(a, src:find("\nend\n", a, true) + 4)
MP = { UI = {} }
local cards = {}
SMODS = { find_card = function(k) return cards[k] and { {} } or {} end }
function get_blind_amount(ante) return ante * 100 end
assert(loadstring(fn))()
ok(MP.UI.aij_blind_amount({ mult = 2 }, 3, 1) == nil, "no All-in-Jest: unchanged")
All_in_Jest = {}
ok(MP.UI.aij_blind_amount({ mult = 2 }, 3, 1) == nil, "plain blind: unchanged")
local hook = { mult = 2, aij_blind_amount_display = function(self, cfg, base, mult) return base * mult + 50 end }
ok(MP.UI.aij_blind_amount(hook, 3, 2) == 1300, "hook amount x ante scaling")
cards.j_aij_fall_of_count_chaligny = true
ok(MP.UI.aij_blind_amount(hook, 3, 1) == 350, "Chaligny: hook gets mult 1")
ok(MP.UI.aij_blind_amount({ mult = 2 }, 3, 1) == 300, "Chaligny: every blind x1")
ok(MP.UI.aij_blind_amount({ mult = 2, aij_blind_amount_display = function() error("boom") end }, 3, 1) == nil, "a broken hook never crashes the screen")
local bc = io.open("ui/game/blind_choice.lua"):read("*a")
local p1, p2 = bc:find("MP.UI.aij_blind_amount", 1, true), bc:find('blind_amt = "????"', 1, true)
ok(p1 and p2 and p1 < p2, "applied before the Nemesis ???? (PvP amounts stay hidden)")
print("PASS: All-in-Jest blind amounts")
