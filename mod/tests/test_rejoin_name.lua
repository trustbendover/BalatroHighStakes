-- luajit tests/test_rejoin_name.lua (run from mod/): "X rejoined" never shows "?" when the message has a name
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { LOBBY = { names_by_id = {} }, GAME = {} }
G = {}
function sendWarnMessage() end
local msgs = {}
dofile("lib/rejoin.lua")
local RJ = MP.REJOIN
RJ.notify = function(m) msgs[#msgs + 1] = m end
RJ.show_bar = function() end
RJ.on_away({ playerId = "p1" }) -- no name known yet
RJ.on_back({ playerId = "p1", username = "dev1~1" })
ok(msgs[1] and msgs[1]:find("dev1", 1, true) and not msgs[1]:find("?", 1, true), "rejoined notice uses the message name (" .. tostring(msgs[1]) .. ")")
RJ.on_away({ playerId = "p2" })
RJ.on_expired({ playerId = "p2", username = "dev2~3" })
ok(msgs[2] and msgs[2]:find("dev2 did not", 1, true), "expired notice uses the message name, no '?' or ~suffix (" .. tostring(msgs[2]) .. ")")
local src = io.open("networking/action_handlers.lua"):read("*a")
ok(src:find('name = tostring(name):gsub("~.*$", "")', 1, true), "eliminated message strips the ~suffix")
print("PASS: rejoin name")
