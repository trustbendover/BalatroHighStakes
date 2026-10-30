-- luajit tests/test_end_of_round_context.lua (run from mod/): our end-of-round override passes a context
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("ui/game/game_state.lua"):read("*a")
ok(not src:find("get_end_of_round_effect()", 1, true), "never called without a context")
ok(src:find("get_end_of_round_effect({ cardarea = G.hand, end_of_round = true", 1, true), "Steamodded-style end_of_round context")
print("PASS: end of round context")
