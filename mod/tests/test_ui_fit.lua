-- luajit tests/test_ui_fit.lua (run from mod/): worst-case widths of the 0.6.8 panels (spectator list,
-- rejoin bar, blind HUD re-fit): longest names, team tags, huge scores, every status, 8 players, EN + NL.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local function rgb(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 } end
_G.G = { UIT = { ROOT = 0, R = 1, C = 2, T = 3, O = 4 },
	C = { GOLD = rgb("eac058"), GREEN = rgb("4BC292"), ORANGE = rgb("fda200"), RED = rgb("FE5F55"), BLACK = rgb("374244"),
		CLEAR = { 0, 0, 0, 0 }, UI = { TEXT_LIGHT = rgb("ffffff"), TEXT_INACTIVE = rgb("888888") } } }
_G.MP = { LOBBY = { code = "ABCD" }, GAME = {} }
_G.localize = function() return "ERROR" end
dofile("lib/fit.lua")
dofile("lib/spectator.lua")
dofile("lib/rejoin.lua")
local UM = dofile("tests/ui_measure.lua")
local F, SP, RJ = MP.FIT, MP.SPECTATE, MP.REJOIN

-- ===== 1. fitting helpers (m6x11 metrics)
ok(math.abs(F.width("W", 1) - 0.5625) < 1e-9 and math.abs(F.width("il", 2) - 0.75) < 1e-9 and F.width("", 1) == 0, "m6x11 widths")
local e = F.ellipsize(("W"):rep(40), 0.35, 3)
ok(F.width(e, 0.35) <= 3 and e:sub(-2) == ".." and F.ellipsize("Ann", 0.35, 3) == "Ann", "ellipsize with '..' (m6x11 has no ellipsis glyph)")
ok(F.number("123,456,789,012,345", 0.35, 1.8) == "1.235e14" or F.width(F.number("123,456,789,012,345", 0.35, 1.8), 0.35) <= 1.8, "huge scores become compact")
ok(F.number("48,200", 0.35, 1.8) == "48,200", "normal scores untouched")
ok(F.join({ "aaaa", "bbbb" }, 1, 100) == "aaaa   bbbb" and F.width(F.join({ ("x"):rep(30), ("y"):rep(30) }, 1, 20), 1) <= 20, "join drops spacing, then ellipsizes")
local dst = { 0, 0, 0, 0 }; F.set_colour(dst, G.C.GOLD)
ok(dst[1] == G.C.GOLD[1] and dst ~= G.C.GOLD, "colour copied into the T node's own table")

-- ===== 2. spectator panel, worst case: 8 players, 32-char names, team tags, huge scores, every status
local long = ("W"):rep(32)
local function enemies()
	local t = {}
	for i = 1, 8 do
		t["p" .. i] = { id = "p" .. i, username = (i % 2 == 0) and long or ("Wildcard" .. ("M"):rep(20)), lives = 9 - i % 3,
			raw_score = (i == 1) and "123,456,789,012,345,678" or (i == 2) and "1.234e45" or tostring(13150 * i), hands = 4, ante = 12,
			location = "Playing a PvP blind (Nemesis)", away = (i == 3 or i == 5), eliminated = (i >= 7) }
	end
	return t
end
MP.TEAMS = { is_active = function() return true end, team_of = function(id) return ({ "A", "B", "C", "D" })[(tonumber(id:sub(2)) - 1) % 4 + 1] end }
local function stub_ui()
	_G.create_UIBox_generic_options = function(a) return { n = G.UIT.ROOT, config = {}, nodes = a.contents } end
	_G.UIBox_button = function(a) return { n = G.UIT.C, config = { minw = a.minw, button = a.button }, nodes = {} } end
end
stub_ui()
for _, lang in ipairs({ "en-us", "nl" }) do
	_G.localize = UM.localizer("localization/" .. lang .. ".lua")
	MP.GAME = { enemies = enemies(), lives = 0 }
	MP.LOBBY.names_by_id = nil
	SP.state.follow = "p2"
	local rows = SP.refresh()
	ok(#rows == 8 and rows[1].team ~= "", lang .. ": 8 players with team tags")
	local v = SP.lines(rows, "p2")
	for i = 1, 8 do
		local c = v.cells[i]
		for _, k in ipairs({ "name", "lives", "score", "status" }) do
			assert(F.width(c[k], SP.ROW_SCALE) <= SP.COL[k] - 2 * SP.CELL_PAD + 1e-6, lang .. " row " .. i .. " " .. k .. " too wide: " .. c[k])
		end
	end
	ok(true, lang .. ": every cell fits its column (name, lives, score, status)")
	local kinds = {}
	for i = 1, 8 do kinds[v.cells[i].kind] = true end
	ok(kinds.ahead and kinds.away and kinds.out, lang .. ": ahead, disconnected and out all present")
	ok(v.cells[1].name:find("%.%.$") and v.cells[1].name:find("^1%. %[") , lang .. ": long names shortened with '..', team tag kept")
	for _, k in ipairs({ "follow", "detail", "where" }) do
		local sc = k == "follow" and 0.5 or 0.4
		assert(F.width(v[k], sc) <= SP.TEXT_W + 1e-6, lang .. " " .. k .. " too wide: " .. v[k])
	end
	ok(true, lang .. ": follow / detail / where lines fit " .. SP.TEXT_W)
	local ui = SP.ui()
	local box = UM.find(ui, function(n) return n.config and n.config.colour == G.C.BLACK and n.config.minw == SP.BOX_W end)[1]
	ok(box and #box.nodes == 8, lang .. ": black list box with 8 rows")
	local w, issues = UM.measure(box)
	ok(#issues == 0 and math.abs(w - SP.BOX_W) < 1e-6, lang .. ": list box keeps its fixed width " .. SP.BOX_W .. " (measured " .. string.format("%.2f", w) .. ")"
		.. (#issues > 0 and (" " .. issues[1]) or ""))
	local _, all = UM.measure(ui)
	ok(#all == 0, lang .. ": nothing in the panel is wider than its box" .. (#all > 0 and (" - " .. all[1]) or ""))
	-- status colours follow the row: ahead green, away orange, out grey; followed name gold
	local ahead, away, out_
	for i = 1, 8 do
		local k = v.cells[i].kind
		if k == "ahead" then ahead = i elseif k == "away" then away = away or i elseif k == "out" then out_ = i end
	end
	ok(SP.colours[ahead].status[1] == G.C.GREEN[1] and SP.colours[away].status[1] == G.C.ORANGE[1]
		and SP.colours[out_].name[1] == G.C.UI.TEXT_INACTIVE[1], lang .. ": status colours (ahead green, away orange, out grey)")
end
MP.TEAMS = nil
_G.localize = function() return "ERROR" end
dofile("lib/presence.lua")
for _, lang in ipairs({ "en-us", "nl" }) do
	_G.localize = UM.localizer("localization/" .. lang .. ".lua")
	MP.GAME.enemies = enemies()
	local v = SP.lines(SP.rows(MP.GAME.enemies), "p2")
	for i = 1, 8 do
		local c = v.cells[i]
		assert(F.width(c.status, SP.ROW_SCALE) <= SP.COL.status - 2 * SP.CELL_PAD + 1e-6, lang .. " presence status fits: " .. c.status)
	end
	local saw = false
	for i = 1, 8 do if v.cells[i].kind == "away" and v.cells[i].status ~= "" then saw = true end end
	ok(saw, lang .. ": a held seat shows a connection status")
end
_G.localize = function() return "ERROR" end

-- ===== 3. rejoin bar: up to 7 players away, long names, EN + NL
for _, lang in ipairs({ "en-us", "nl" }) do
	_G.localize = UM.localizer("localization/" .. lang .. ".lua")
	for n = 1, 7 do
		local away = {}
		for i = 1, n do away["x" .. i] = { name = "[B] " .. long, end_time = 100 + i * 10 } end
		local bar = RJ.bar_text(away, 0)
		assert(F.width(bar, RJ.BAR_SCALE) <= RJ.BAR_W + 1e-6, lang .. " " .. n .. " away: bar too wide: " .. bar)
		if n > 1 then assert(bar:find("+" .. (n - (bar:find("|.*|") and 2 or 1)), 1, true), lang .. ": +N for the rest: " .. bar) end
	end
	ok(true, lang .. ": rejoin bar fits " .. RJ.BAR_W .. " with 1-7 players away (long names, +N)")
end
_G.localize = function() return "ERROR" end
ok(RJ.bar_text({ x = { name = "Ann", end_time = 100 } }, 0) == "Ann disconnected - waiting to rejoin 1:40", "short bar unchanged")
local two = RJ.bar_text({ x = { name = "Ann", end_time = 100 }, y = { name = "Bob", end_time = 50 } }, 0)
ok(two == "Bob disconnected - waiting to rejoin 0:50  |  +1 more", "two away: the soonest deadline by name, the rest as +N")

-- ===== 4. blind HUD (team totals + opponents): DynaText re-fit when the line changes
do
	local obj = { config = { maxw = 4.5, scale = 0.6, mp_maxw = true }, scale = 0.6 }
	local text = ("Team A (jij) 123,456,789 4L | "):rep(4)
	function obj:update_text() self.config.W = F.width(text, self.scale) end
	F.refit_dynatext(obj)
	ok(math.abs(obj.config.W - 4.5) < 1e-6 and obj.scale < 0.6, "long HUD line shrinks to the blind box (4.5)")
	text = "Team A 100 4L"
	F.refit_dynatext(obj)
	ok(obj.scale == 0.6, "short line grows back to the normal size")
end
print("PASS: ui fit")
