-- Each mode shows how to win before the lobby starts, in English and Dutch.
-- The words come from the current host rules, including Deathmatch's held seat.
-- run from mod/: luajit tests/test_mode_explain.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local function dict(file)
	local t = dofile(file)
	return t.misc and t.misc.dictionary or {}
end
local modes = { "duel", "teams", "teams2", "teams3", "teams4", "attrition", "showdown", "koth", "deathmatch", "survival", "gambel_time" }
local rules = { "duel", "attrition", "showdown", "koth", "deathmatch", "teams", "survival", "gambel_time" }
for _, lang in ipairs({ "en-us", "nl" }) do
	local d = dict("localization/" .. lang .. ".lua")
	ok(d.k_custom == "Custom" or d.k_custom == nil, lang .. ": Custom heading not renamed here")
	ok(d.k_standard == (lang == "nl" and "Standaard" or "Standard"), lang .. ": unrelated Standard stays")
	for _, m in ipairs(modes) do
		local win = d["k_" .. m .. "_win"]
		ok(type(win) == "string" and #win > 8, lang .. " " .. m .. " says how to win")
		local low = win:lower()
		ok(low:find("win") or low:find("winst"), lang .. " " .. m .. " win line is labeled")
	end
	for _, m in ipairs(rules) do
		ok(type(d["k_" .. m .. "_rules"]) == "string", lang .. " rules tab has " .. m)
	end
	ok(not d.k_deathmatch_rules:find("out at once", 1, true) and not d.k_deathmatch_rules:find("meteen uit", 1, true), lang .. ": Deathmatch leave is not instant elimination")
	ok(d.k_deathmatch_rules:find("60", 1, true), lang .. ": Deathmatch grace is stated")
	ok(not d.k_survival_description:lower():find("farthest") and not d.k_survival_description:lower():find("verste blind"), lang .. ": Survival does not claim a furthest-blind win")
end
local card = io.open("ui/main_menu/play_button/gamemode_selection.lua"):read("*a")
ok(card:find('local win_key = "k_" .. entry .. "_win"', 1, true), "the mode card shows the win line before Create Lobby")
print("PASS: mode explanations")
