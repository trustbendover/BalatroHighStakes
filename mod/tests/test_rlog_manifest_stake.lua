-- luajit tests/test_rlog_manifest_stake.lua (run from mod/): the replay manifest always has a stake
-- (Steam P2P startGame has none, which logged "RLOG: manifest missing required key 'stake'" every match).
local src = io.open("networking/action_handlers.lua"):read("*a")
local line = src:match("MP%.RLOG%.begin_run%(%{.-\n%s*stake = ([^\n]+)")
assert(line and line:find("MP.LOBBY.config.stake", 1, true) and line:find("or 1", 1, true), "manifest stake falls back to the lobby stake")
print("ok: manifest stake falls back to the lobby stake")
print("PASS: rlog manifest stake")
