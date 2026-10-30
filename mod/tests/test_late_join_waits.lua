-- luajit tests/test_late_join_waits.lua (run from mod/): a late join waits for the lobby screen (like a rejoin)
-- and never restores an old checkpoint; before, the lobby-enter hook sent the fresh run back to the menu.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("networking/action_handlers.lua"):read("*a")
ok(src:find("if MP.REJOIN then return MP.REJOIN.queue(p) end", 1, true) and not src:find("if MP.REJOIN and not p.lateJoin then", 1, true), "resumeGame: late join is queued too")
local rj = io.open("lib/rejoin.lua"):read("*a")
local a = rj:find("function RJ.restore(p)", 1, true)
local b = select(2, rj:find('return "restarted"\n\tend', a, true))
ok(a and b, "RJ.restore found")
local restarted = 0
RJ = { load = function() return { meta = { code = "X" }, run = "R" } end, usable = function() return true end }
MP = { GAME = {}, THREEP = { restart_at_ante = function() restarted = restarted + 1 end } }
local restore = assert(loadstring("local RJ = RJ\n" .. rj:sub(a, b) .. "\nend\nreturn RJ.restore"))()
ok(restore and restore({ lateJoin = true, lives = 2 }) == "restarted" and restarted == 1, "late join: fresh run at the ante, checkpoint ignored")
print("PASS: late join waits")
