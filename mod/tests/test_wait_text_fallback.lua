-- luajit tests/test_wait_text_fallback.lua (run from mod/): the lobby Start button never gets a plain string
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { UI = {}, LOBBY = { player_list = { 1 } } }
function localize() return "ERROR" end
dofile("ui/lobby/start_ready_button.lua")
local t = MP.UI.start_wait_text()
ok(type(t) == "table" and t[1] == "WAITING FOR", "missing translation -> list of lines, not 'ERROR' (lobby crash)")
print("PASS: wait text fallback")
