-- luajit tests/test_mode_desc_fit.lua (run from mod/): gamemode info texts never overlap the blind chips graphic
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { UTILS = {} }
dofile("lib/string_utils.lua")
local function lines(t) local _, n = t:gsub("\n", ""); return n + 1 end
local modes = { "attrition", "duel", "showdown", "koth", "teams", "deathmatch", "survival" }
for _, lang in ipairs({ "en-us", "nl" }) do
	local src = io.open("localization/" .. lang .. ".lua"):read("*a")
	for _, m in ipairs(modes) do
		local d = src:match('k_' .. m .. '_description = "(.-)",\n')
		ok(d and lines(MP.UTILS.wrapText(d, 70)) <= MP.UTILS.MODE_DESC_LINES, lang .. " " .. m .. " fits in " .. MP.UTILS.MODE_DESC_LINES .. " lines")
	end
end
localize = function() return string.rep("word ", 120) end
local t, s = MP.UTILS.mode_desc("k_x")
ok(lines(t) <= MP.UTILS.MODE_DESC_LINES + 1 and s < 0.6, "too long text: wider + smaller instead of overlapping")
localize = function() return "short text" end
t, s = MP.UTILS.mode_desc("k_x"); ok(s == 0.6 and lines(t) == 1, "short text unchanged")
for _, m in ipairs(modes) do ok(io.open("gamemodes/" .. m .. ".lua"):read("*a"):find('MP.UTILS.mode_desc("k_' .. m .. '_description")', 1, true), m .. " uses the guarded text") end
-- The orange win line is its own row. A wrapped explanation must be one row per line,
-- and every line must fit the mode card, or the win line sits on the last white word.
MP.FIT = {}
dofile("lib/fit.lua")
local function dict(file) return dofile(file).misc.dictionary end
local function balanced(s)
	local n = 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "{" then n = n + 1 elseif c == "}" then n = n - 1 end
		if n < 0 then return false end
	end
	return n == 0
end
local card_modes = { "duel", "teams", "teams2", "teams3", "teams4", "attrition", "showdown", "koth", "deathmatch", "survival", "gambel_time" }
for _, lang in ipairs({ "en-us", "nl" }) do
	local d = dict("localization/" .. lang .. ".lua")
	for _, m in ipairs(card_modes) do
		for _, suf in ipairs({ "_short", "_win", "_rules", "_description" }) do
			local s = d["k_" .. m .. suf]
			if type(s) == "string" then
				ok(balanced(s) and not s:find("%a%{[CX]:", 1), lang .. " " .. m .. suf .. " braces are closed and a colour tag does not sit on the previous letter")
				local scale = suf == "_win" and 0.38 or (suf == "_rules" and 0.4 or 0.45)
				local max_lines = suf == "_rules" and 10 or (suf == "_description" and 8 or 3)
				local lines, sc = MP.UTILS.fit_lines(s, scale, 10.2, max_lines)
				ok(#lines <= max_lines, lang .. " " .. m .. suf .. " fits its rows")
				for _, line in ipairs(lines) do
					ok(MP.FIT.width(line, sc) <= 10.21, lang .. " " .. m .. suf .. " line fits the card: " .. line)
				end
			end
		end
	end
	local short = MP.UTILS.fit_lines(d.k_gambel_time_short, 0.45, 10.2, 3)
	ok(#short >= 2, lang .. ": Gambel Time explanation is more than one row, so the orange line starts underneath it")
end
local card = io.open("ui/main_menu/play_button/gamemode_selection.lua"):read("*a")
ok(card:find("fit_lines", 1, true) and card:find("for _, line in ipairs(lines)", 1, true), "each wrapped line is its own row")
print("PASS: mode descriptions fit")
