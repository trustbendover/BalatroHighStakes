-- luajit tests/test_player_joined_notice.lua (run from mod/): "X joined" is a fading notice, not a blocking OK pop-up
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local src = io.open("networking/action_handlers.lua"):read("*a")
local body = src:match("local function action_player_joined%(p%)(.-)\nend")
ok(body and not body:find("overlay_message", 1, true), "no blocking overlay for a late joiner")
ok(body:find("MP.REJOIN.notify", 1, true) and body:find("k_player_joined_run", 1, true), "uses the fading notice + a translated text")
for _, f in ipairs({ "localization/en-us.lua", "localization/nl.lua" }) do
	ok(io.open(f):read("*a"):find('k_player_joined_run = "#1#', 1, true), f .. " has k_player_joined_run")
end
print("PASS: player joined notice")
