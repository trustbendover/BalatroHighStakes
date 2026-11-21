-- A saved match is not joined from the main menu, and money does not touch a missing HUD.
-- luajit tests/test_hud_rejoin.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end

MP = {}
dofile("lib/smods_compat.lua")
G = { STAGES = { MAIN_MENU = 1, RUN = 2 }, STAGE = 1 }
ok(not MP.UTILS.in_active_run(), "the main menu is not a run")
G.STAGE = 2
G.HUD = {}
ok(not MP.UTILS.in_active_run(), "a run without a dollar HUD is not ready")
G.HUD.get_UIE_by_ID = function() end
ok(MP.UTILS.in_active_run(), "a run with a HUD may take money")
G.STAGE = 1
ok(not MP.UTILS.in_active_run(), "leaving the run drops the HUD guard")

MP = { UTILS = MP.UTILS, LOBBY = {}, GAME = {}, THREEP = {} }
local cleared, sent = 0, {}
MP.THREEP.clear_reconnect_info = function() cleared = cleared + 1 end
Client = { send = function(m) sent[#sent + 1] = m end }
G = { STAGES = { MAIN_MENU = 1, RUN = 2 }, STAGE = 1, FUNCS = {}, C = {} }
function sendWarnMessage() end
dofile("lib/rejoin.lua")
local RJ = MP.REJOIN

RJ.note_saved("ABCDE", "tok")
ok(RJ.offer and RJ.offer.code == "ABCDE" and #sent == 0, "a saved match is remembered and not joined")
local taken = RJ.accept_saved()
ok(taken and taken.code == "ABCDE" and taken.token == "tok" and RJ.resume_allowed(), "Rejoin may restore the run")
RJ.note_saved("ABCDE", "tok")
RJ.accept_saved()
RJ.drop_saved()
ok(RJ.offer == nil and RJ.blocked and not RJ.resume_allowed(), "New lobby ignores an in-flight rejoin")
ok(cleared == 1 and sent[1].action == "leaveLobby", "New lobby clears the saved match and leaves it")
RJ.pending = { p = { seed = "s" } }
RJ.allow_match()
ok(not RJ.blocked and not RJ.resume_allowed() and RJ.pending, "the stale resume after the new lobby is the one that is dropped")
ok(RJ.resume_allowed(), "a later resume, such as a late join, is allowed")

local src = io.open("networking/action_handlers.lua"):read("*a")
ok(src:find("MP.REJOIN.note_saved", 1, true), "connect offers the saved match instead of joining it")
ok(src:find("RUN_ACTIONS", 1, true) and src:find("letsGoGamblingNemesis = true", 1, true), "match actions wait for a run")
ok(src:find("MP.UTILS.in_active_run", 1, true), "those actions check the HUD")
ok(src:find("MP.REJOIN.drop_saved", 1, true), "create and join clear the saved match")
local dollars = io.open("overrides/game.lua"):read("*a")
ok(dollars:find("function ease_dollars(mod, ...)", 1, true) and dollars:find("ease_dollars_ref(mod, ...)", 1, true), "ease_dollars still forwards its arguments")
ok(dollars:find("in_active_run", 1, true), "ease_dollars does not queue a HUD update off the run")

print("PASS: hud rejoin")
