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
print("PASS: mode descriptions fit")
