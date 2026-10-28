-- luajit tests/test_host_migration_ui.lua (run from mod root): host migration texts
MP = { LOBBY = { names_by_id = { b = "Bob~2" } }, UI = { UTILS = {} } }
G = { STAGE = 2, STAGES = { RUN = 1 }, C = {} }
function localize() return "ERROR" end
local shown = {}
function sendWarnMessage(m) shown[#shown + 1] = m end
MP.UI.UTILS.overlay_message = function(m) shown[#shown + 1] = "overlay:" .. m end
dofile("lib/host_migration_ui.lua")
local M = MP.HOST_MIGRATION
local function ok(c, m) assert(c, m); print("ok: " .. m) end
ok(M.migrated_text({ hostId = "b", you = "a", hostName = "Bob~2" }) == "Host left - Bob is now host", "new host named (blind colour suffix stripped)")
ok(M.migrated_text({ hostId = "a", you = "a" }) == "Host left - you are now host", "you are host")
ok(M.migrating_text({ reason = "left" }) == "Host left - switching to a new host...", "migrating text")
ok(M.migrating_text({ reason = "cut_off" }):find("rejoining"), "cut-off text")
ok(M.migrating_text({ reason = "frozen" }):find("not responding"), "frozen-host text")
ok(M.failed_text({}):find("nobody could take over") and M.failed_text({ lost = true }):find("Lost connection"), "fallback texts")
M.on_migrated({ hostId = "b", you = "a" })
ok(shown[1] == "Host left - Bob is now host" and shown[2] == "overlay:Host left - Bob is now host", "outside a run: warn + overlay")
print("PASS: host migration ui")
