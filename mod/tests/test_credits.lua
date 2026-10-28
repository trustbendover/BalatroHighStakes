-- luajit tests/test_credits.lua (run from mod/): the in-game credits tab + GPL credit files
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local loc = {}
function localize(k) return loc[k] or "ERROR" end
G = { UIT = { ROOT = 0, R = 1, C = 2, T = 3, B = 4, O = 5 }, C = { BLACK = "black", GOLD = "gold", RED = "red", MULT = "mult", CHIPS = "chips",
	UI = { TEXT_LIGHT = "w", TEXT_INACTIVE = "grey" } }, FUNCS = {} }
function UIBox_button(t) return { button = t } end
local opened
love = { system = { openURL = function(u) opened = u end } }
MP = { UI = {}, BRAND = { author = "Trust Ben Dover", repo = "trustbendover/BalatroMultiplayer3P" } }
dofile("ui/smods_menu/credits_tab.lua")
local function collect(t, acc, seen)
	acc, seen = acc or { texts = {}, buttons = {} }, seen or {}
	if type(t) ~= "table" or seen[t] then return acc end
	seen[t] = true
	if t.n == G.UIT.T then acc.texts[#acc.texts + 1] = t.config.text end
	if type(t.button) == "table" then acc.buttons[t.button.button] = t.button.label[1] end
	for _, v in pairs(t) do collect(v, acc, seen) end
	return acc
end
local function check(lang, made_by, based)
	local ui = collect(MP.UI.create_credits_tab())
	local all = table.concat(ui.texts, "\n")
	ok(all:find(made_by, 1, true) and all:find("Trust Ben Dover", 1, true), lang .. ": made by Trust Ben Dover")
	ok(all:find(based, 1, true) and all:find("CREDITS.md", 1, true), lang .. ": one small line about the original mod + CREDITS.md")
	for _, name in ipairs({ "Virtualized", "TGMM", "Senfinbrare", "CUexter", "Brawmario", "Divvy", "Andy", "Steph", "SleepyG11" }) do
		assert(not all:find(name, 1, true), lang .. ": no individual original names on the screen (" .. name .. ")")
	end
	ok(true, lang .. ": no individual names of the original authors on the screen")
	ok(ui.buttons.open_kofi and ui.buttons.bmp_github and ui.buttons.bmp_original_github and not ui.buttons.bmp_discord,
		lang .. ": Ko-fi, GitHub and 'Original mod' buttons")
	return ui
end
check("EN (fallback)", "A mod by", "Based on Balatro Multiplayer by the Balatro Multiplayer team (GPL-3.0)")
-- Dutch strings come from localization/nl.lua
local nl = dofile("localization/nl.lua")
local d = nl.misc.dictionary
for k, v in pairs(d) do if k:match("^[kb]_hs_") then loc[k] = v end end
check("NL", "Een mod van", "Gebaseerd op Balatro Multiplayer")
local en = dofile("localization/en-us.lua").misc.dictionary
for k in pairs(MP.UI.CREDITS.FALLBACK) do
	assert(en[k] == MP.UI.CREDITS.FALLBACK[k], "en-us.lua has " .. k)
	assert(d[k], "nl.lua has " .. k)
end
ok(true, "every credits text in EN and NL")
G.FUNCS.bmp_original_github()
ok(opened == "https://github.com/Balatro-Multiplayer/BalatroMultiplayer", "'Original mod' opens the original repo")
-- GPL: the original authors stay credited in the files
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end
local credits = read("CREDITS.md")
for _, name in ipairs({ "Virtualized", "TGMM", "Senfinbrare", "CUexter", "Brawmario", "Divvy", "Andy", "Steph", "SleepyG11", "GPL" }) do
	assert(credits:find(name, 1, true), "CREDITS.md credits " .. name)
end
ok(true, "CREDITS.md keeps every original author")
ok(read("LICENSE.md"):find("GNU GENERAL PUBLIC LICENSE", 1, true) and read("FORK_NOTICE.md"):find("Virtualized", 1, true), "LICENSE.md and FORK_NOTICE.md kept")
local mj = read("Multiplayer.json")
ok(mj:find('"author": %[%s*"Trust Ben Dover"%s*%]') and mj:find("Based on Balatro Multiplayer", 1, true), "mods list: author Trust Ben Dover, description says based on Balatro Multiplayer")
local kofi = read("ui/game/functions.lua")
ok(kofi:find("ko-fi.com/trustbendover", 1, true), "Ko-fi points to trustbendover")
print("PASS: credits")
