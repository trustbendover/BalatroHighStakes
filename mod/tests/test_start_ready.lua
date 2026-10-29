-- luajit tests/test_start_ready.lua (run from mod/): host Start waits for every guest's Ready
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Core = dofile("networking/p2p_server.lua")
local function P(r, s) return { isReadyLobby = r, spectator = s } end
ok(Core.unready_count({ P(false) }) == 0, "solo host: nobody to wait for (the 2-player minimum blocks the start)")
ok(Core.unready_count({ P(false), P(false), P(true) }) == 1, "host's own ready state does not count; 1 guest not ready")
ok(Core.unready_count({ P(false), P(false, true), P(true) }) == 0, "spectators are never waited for")
ok(Core.unready_count({ P(true), P(false), P(false), P(false) }) == 3, "after a host migration the new seat 1 is the host; 3 guests to wait for")

-- client text: button + warning line, EN + NL
local UM = dofile("tests/ui_measure.lua")
_G.G = { C = { UI = { TEXT_LIGHT = {} } } }
_G.SMODS = { Gradients = {} }
for _, lang in ipairs({ "en-us", "nl" }) do
	local base = UM.localizer("localization/" .. lang .. ".lua")
	local dict = dofile("localization/" .. lang .. ".lua").misc.dictionary
	_G.localize = function(a) if type(a) == "string" and type(dict[a]) == "table" then return dict[a] end return base(a) end
	_G.MP = { UI = {}, LOBBY = { is_host = true, ready_to_start = false, unready_count = 3, player_list = { 1, 2, 3, 4 }, guest = { username = "b" } },
		MODES = { start_problem = function() return nil end } }
	dofile("lib/fit.lua")
	local src = io.open("ui/lobby/start_ready_button.lua"):read("*a")
	local a = src:find("function MP.UI.start_wait_text", 1, true); local b = src:find("\nend\n", a, true)
	assert(loadstring(src:sub(a, b + 4)))()
	local t = MP.UI.start_wait_text()
	local head = dict.b_wait_for_players[1]
	ok(t[1] == head and t[2]:find("3", 1, true), lang .. " button: " .. t[1] .. " / " .. t[2])
	ok(MP.FIT.width(t[2], 0.9) <= MP.FIT.width(head, 0.9), lang .. ": count line not wider than the existing first line (no extra shrink)")
	MP.LOBBY.unready_count = 1
	ok(MP.UI.start_wait_text()[2] ~= t[2] and not MP.UI.start_wait_text()[2]:find("S$"), lang .. ": singular for 1 player")
	for _, k in ipairs({ "k_wait_ready", "k_wait_ready_one" }) do
		local s = localize({ type = "variable", key = k, vars = { 7 } })
		ok(s ~= "ERROR" and MP.FIT.width(s, 0.3) < 6, lang .. " hint fits the lobby status area: " .. s)
	end
	MP.MODES.start_problem = function() return "Need 4/6/8" end; MP.LOBBY.unready_count = 2
	-- (nl has no b_wait_for_guest_ready of its own; in the game Steamodded falls back to English)
	local old = MP.UI.start_wait_text()
	ok(old ~= nil and not (type(old) == "table" and old[2] and old[2]:find("2", 1, true)), lang .. ": a player-count problem keeps the old text, no count")
end
print("PASS: start waits for ready")
