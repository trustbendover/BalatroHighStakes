-- The Custom-group ruleset button (k_blitz) is labeled High Stakes Multiplayer.
-- Other Standard strings, and the Custom heading, stay as they are.
-- run from mod/: luajit tests/test_blitz_menu_label.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end

local function dict(file)
	local t = dofile(file)
	return t.misc and t.misc.dictionary or {}
end

local en = dict("localization/en-us.lua")
local nl = dict("localization/nl.lua")
local LABEL = "High Stakes Multiplayer"

ok(en.k_blitz == LABEL, "English Custom-group entry is High Stakes Multiplayer")
ok(nl.k_blitz == LABEL, "Dutch uses the same High Stakes Multiplayer label")
ok(en.k_custom == "Custom", "Custom heading is unchanged")
ok(nl.k_custom == nil, "Dutch does not replace the Custom heading")
ok(en.k_standard == "Standard", "unrelated English Standard stays")
ok(nl.k_standard == "Standaard", "unrelated Dutch Standaard stays")
ok(en.k_standard_ranked == "Standard Ranked", "Standard Ranked stays")
ok(en.k_experimental_standard == "Experimental (Standard)", "Experimental (Standard) stays")
ok(en.k_vanilla == "Vanilla" and en.k_traditional == "Traditional", "the other Custom-group buttons stay")

local menu = io.open("ui/main_menu/play_button/ruleset_selection.lua"):read("*a")
local custom = menu:match('name = "k_custom",%s*buttons = %{%s*{ button_id = "blitz_ruleset_button", button_localize_key = "k_blitz" }')
ok(custom, "the button under Custom still selects the blitz ruleset via k_blitz")
ok(menu:find('{ button_id = "standard_ranked_ruleset_button", button_localize_key = "k_standard_ranked" }', 1, true), "Standard Ranked keeps its own key")
ok(not menu:find('blitz_ruleset_button", button_localize_key = "k_standard"', 1, true), "the multiplayer entry is not keyed as k_standard")

local options = io.open("ui/lobby/_lobby_options/main_options.lua"):read("*a")
local minw = tonumber(options:match("UIBox_button%(%{.-minw = (%d+)"))
local scale = tonumber(options:match("UIBox_button%(%{.-scale = ([%d%.]+)"))
ok(minw == 4 and scale == 0.4, "ruleset buttons still use minw 4 and scale 0.4")
MP = {}
dofile("lib/fit.lua")
local w = MP.FIT.width(LABEL, scale)
ok(w <= minw, string.format("High Stakes Multiplayer fits the button (%.2f <= %d)", w, minw))
local header = MP.FIT.width(LABEL .. " King of the Hill", 0.6)
ok(header <= 10, string.format("lobby header with the longest mode still fits the settings box (%.2f <= 10)", header))

print("PASS: blitz menu label")
