-- Balatro High Stakes 0.6.8: match stats screen. GPL-3.0.
-- Every player's game reports its own numbers to the host ("statsReport": best single hand and its
-- type, joker lineup / jokers used, money earned, highest ante). The host adds what only it knows
-- (damage = your score in every PvP blind, PvPs won, lives lost), keeps it all in its replicated
-- state (survives host migration and rejoin) and at match end sends one final table to everyone,
-- spectators included (networking/p2p_server.lua: stats_finish). This file shows that table:
-- automatically a few seconds after the match ends, and from the "Match stats" button on the
-- game-over / win screen. Category winners get a coloured badge, like the patch notes.
MP.MATCH_STATS = MP.MATCH_STATS or {}
local MS = MP.MATCH_STATS

MS.AUTO_DELAY = 4
MS.PER_PAGE = 4 -- player panels per page on the Players tab
MS.REPORT_EVERY = 3
MS.MAX_ROWS = 8
-- award key, Balatro colour name, text key, fallback
MS.AWARDS = {
	{ "damage", "red", "k_ms_damage", "Most damage" },
	{ "best", "chips", "k_ms_best", "Best hand" },
	{ "jokers", "purple", "k_ms_jokers", "Most jokers" },
	{ "lives", "green", "k_ms_lives", "Fewest lives lost" },
	{ "pvp", "planet", "k_ms_pvp", "Most PvPs won" },
	{ "money", "money", "k_ms_money", "Most money earned" },
	{ "ante", "filter", "k_ms_ante", "Highest ante" },
}
-- table columns: field, header text key, fallback, award that highlights it
MS.COLUMNS = {
	{ "place", "k_ms_col_place", "#" },
	{ "name", "k_ms_col_name", "Player" },
	{ "dealt", "k_ms_col_damage", "Damage", "damage" },
	{ "best", "k_ms_col_best", "Best hand", "best" },
	{ "jokers", "k_ms_col_jokers", "Jokers", "jokers" },
	{ "livesLost", "k_ms_col_lives", "Lives lost", "lives" },
	{ "pvpWon", "k_ms_col_pvp", "PvP won", "pvp" },
	{ "money", "k_ms_col_money", "Money", "money" },
	{ "ante", "k_ms_col_ante", "Ante", "ante" },
}

local function L(key, fallback, vars)
	if MP.SPECTATE and MP.SPECTATE.L then return MP.SPECTATE.L(key, fallback, vars) end
	if vars then for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", (tostring(v):gsub("%%", "%%%%"))) end end
	return fallback
end
local function clean(n) return (tostring(n or "?"):gsub("~.*$", "")) end
local function now() return (love and love.timer and love.timer.getTime()) or os.clock() end

--- Pure: short number: 950, 12.3K, 4.5M, 1.2B, 3.40e15
function MS.short(v)
	if type(v) == "string" then
		local n = tonumber(v)
		if not n then return v end
		v = n
	end
	v = tonumber(v) or 0
	local a = math.abs(v)
	if a < 1000 then return tostring(math.floor(v + 0.5)) end
	local function f(x, s)
		local t = string.format("%.1f", x)
		t = t:gsub("%.0$", "")
		return t .. s
	end
	if a < 1e6 then return f(v / 1e3, "K") end
	if a < 1e9 then return f(v / 1e6, "M") end
	if a < 1e12 then return f(v / 1e9, "B") end
	return string.format("%.2e", v):gsub("e%+", "e")
end

local function joker_name(key)
	local ok, s = pcall(localize, { type = "name_text", set = "Joker", key = key })
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= "" then return s end
	local n = tostring(key):gsub("^j_", ""):gsub("^mp_", ""):gsub("_", " ")
	return (n:gsub("^%l", string.upper))
end
MS.joker_name = joker_name

--- Pure: everything the screen shows, as plain strings (also used by the preview renderer).
function MS.view(st, me)
	st = st or {}
	local rows = st.rows or {}
	local by_id = {}
	for _, r in ipairs(rows) do by_id[r.id] = r end
	local v = { title = L("k_ms_title", "Match stats"), awards = {}, header = {}, rows = {}, teams = {} }
	local w = st.winnerId and by_id[st.winnerId]
	if st.teams and st.teams[1] and st.teams[1].place == 1 then
		v.winner = L("k_ms_team_wins", "Team #1# wins!", { st.teams[1].team })
	elseif w then
		v.winner = L("k_ms_wins", "#1# wins!", { clean(w.name) })
	elseif rows[1] and rows[1].place == 1 then
		v.winner = L("k_ms_wins", "#1# wins!", { clean(rows[1].name) })
	else
		v.winner = ""
	end
	local function value(award, r)
		if award == "damage" then return MS.short(r.dealt or 0) end
		if award == "best" then
			local s = MS.short(r.best or "0")
			return r.bestHand and (s .. " (" .. r.bestHand .. ")") or s
		end
		if award == "jokers" then return tostring(math.max(r.seen or 0, r.jokers or 0)) end
		if award == "lives" then return tostring(r.livesLost or 0) end
		if award == "pvp" then return tostring(r.pvpWon or 0) .. "/" .. tostring(r.pvps or 0) end
		if award == "money" then return "$" .. tostring(r.money or 0) end
		if award == "ante" then return tostring(r.ante or 1) end
		return ""
	end
	for _, a in ipairs(MS.AWARDS) do
		local id = st.awards and st.awards[a[1]]
		local r = id and by_id[id]
		if r and #rows > 1 then
			v.awards[#v.awards + 1] = { key = a[1], colour = a[2], label = L(a[3], a[4]), name = clean(r.name),
				value = value(a[1], r), you = (me ~= nil and r.id == me) }
		end
	end
	for i, c in ipairs(MS.COLUMNS) do v.header[i] = L(c[2], c[3]) end
	for i = 1, math.min(#rows, MS.MAX_ROWS) do
		local r = rows[i]
		local cells, hl = {}, {}
		for j, c in ipairs(MS.COLUMNS) do
			local f = c[1]
			if f == "place" then cells[j] = tostring(r.place or i)
			elseif f == "name" then cells[j] = clean(r.name) .. (r.team and (" [" .. r.team .. "]") or "")
			elseif f == "dealt" then cells[j] = MS.short(r.dealt or 0)
			elseif f == "best" then cells[j] = MS.short(r.best or "0") .. (r.bestHand and (" " .. r.bestHand) or "")
			elseif f == "jokers" then cells[j] = tostring(math.max(r.seen or 0, r.jokers or 0))
			elseif f == "livesLost" then cells[j] = tostring(r.livesLost or 0)
			elseif f == "pvpWon" then cells[j] = tostring(r.pvpWon or 0)
			elseif f == "money" then cells[j] = "$" .. tostring(r.money or 0)
			elseif f == "ante" then cells[j] = tostring(r.ante or 1) end
			if c[4] and st.awards and st.awards[c[4]] == r.id and #rows > 1 then
				for _, a in ipairs(MS.AWARDS) do if a[1] == c[4] then hl[j] = a[2] end end
			end
		end
		v.rows[i] = { cells = cells, hl = hl, you = (me ~= nil and r.id == me), out = r.out }
	end
	-- Players tab: one Balatro panel per player, stats as small label + coloured value boxes
	v.players = {}
	local STAT_COLOUR = { dealt = "red", best = "chips", jokers = "purple", livesLost = "mult", pvpWon = "planet", money = "money", ante = "filter" }
	for i = 1, #rows do
		local r = rows[i]
		local stats = {}
		local cells = v.rows[i] and v.rows[i].cells or {}
		for j, c in ipairs(MS.COLUMNS) do
			if c[4] then
				local val, sub = cells[j], nil
				if c[1] == "best" then val, sub = MS.short(r.best or "0"), r.bestHand end
				local award_colour
				for _, a in ipairs(MS.AWARDS) do if a[1] == c[4] then award_colour = a[2] end end
				stats[#stats + 1] = { key = c[1], label = L(c[2], c[3]), value = val or "", sub = sub, colour = STAT_COLOUR[c[1]],
					award_colour = award_colour, winner = (st.awards and st.awards[c[4]] == r.id and #rows > 1) or false }
			end
		end
		local lives_text = ""
		if r.out or r.eliminated then lives_text = L("k_ms_out", "Out")
		elseif r.lives ~= nil then lives_text = L("k_ms_lives_left", "#1# lives", { r.lives }) end
		v.players[i] = { place = r.place or i, name = clean(r.name), team = r.team, you = (me ~= nil and r.id == me),
			out = r.out and true or false, lives_text = lives_text, ante = tonumber(r.ante), best = r.best, stats = stats }
	end
	v.lineup_keys = (w or rows[1]) and (w or rows[1]).lineup or nil
	v.lineup_owner = (w or rows[1]) and clean((w or rows[1]).name) or nil
	for i, t in ipairs(st.teams or {}) do
		v.teams[i] = L("k_ms_team_line", "Team #1#: damage #2#, PvPs won #3#, lives lost #4#",
			{ t.team, MS.short(t.dealt or 0), t.pvpWon or 0, t.livesLost or 0 })
	end
	v.team_panels = {}
	for i, t in ipairs(st.teams or {}) do
		local members = {}
		for k, id in ipairs(t.members or {}) do members[k] = by_id[id] and clean(by_id[id].name) or "?" end
		v.team_panels[i] = { team = t.team, place = t.place, winner = (t.place == 1), lives = t.lives,
			members = table.concat(members, ", "),
			stats = {
				{ key = "dealt", label = L("k_ms_col_damage", "Damage"), value = MS.short(t.dealt or 0), colour = "red" },
				{ key = "pvpWon", label = L("k_ms_col_pvp", "PvP won"), value = tostring(t.pvpWon or 0), colour = "planet" },
				{ key = "livesLost", label = L("k_ms_col_lives", "Lives lost"), value = tostring(t.livesLost or 0), colour = "mult" },
			} }
	end
	local lw = w or rows[1]
	if lw and lw.lineup and #lw.lineup > 0 then
		local names = {}
		for i, k in ipairs(lw.lineup) do names[i] = joker_name(k) end
		v.lineup = L("k_ms_lineup", "#1#'s final jokers: #2#", { clean(lw.name), table.concat(names, ", ") })
	end
	return v
end

--- Compact lines for the game-over screen: winner, each team, then every player the host tracked.
function MS.result_lines(st)
	local v = MS.view(st)
	local lines = {}
	if v.winner ~= "" then lines[#lines + 1] = v.winner end
	for i, t in ipairs(v.team_panels or {}) do
		local line = v.teams[i] or L("k_ms_team", "Team #1#", { t.team })
		if t.lives ~= nil then line = line .. " | " .. L("k_ms_lives_left", "#1# lives", { t.lives }) end
		lines[#lines + 1] = line
		if t.members and t.members ~= "" then lines[#lines + 1] = t.members end
	end
	for _, p in ipairs(v.players or {}) do
		local s = tostring(p.place) .. ". " .. p.name
		if p.team then s = s .. " [" .. p.team .. "]" end
		if p.lives_text and p.lives_text ~= "" then s = s .. "  " .. p.lives_text end
		if p.ante then s = s .. "  " .. L("k_ms_ante_short", "ante #1#", { p.ante }) end
		if p.best and tostring(p.best) ~= "0" then s = s .. "  " .. MS.short(p.best) end
		lines[#lines + 1] = s
	end
	return lines
end

---------------------------------------------------------------------------------------------
-- tracking (own run) + reports to the host
MS.t = MS.t or { money = 0, seen = {}, nseen = 0 }
function MS.on_start()
	MS.t = { money = 0, seen = {}, nseen = 0 }
	MS.last, MS.show_at, MS.sig = nil, nil, nil
end

local function in_mp_run()
	return MP.LOBBY and MP.LOBBY.code and G and G.STAGE == G.STAGES.RUN and G.GAME
		and not (MP.GHOST and MP.GHOST.is_active and MP.GHOST.is_active())
end

function MS.on_dollars(mod)
	mod = tonumber(mod)
	if mod and mod > 0 and in_mp_run() and (MP.GAME.lives or 0) > 0 then MS.t.money = MS.t.money + math.floor(mod) end
end

function MS.on_resume(p)
	local s = p and p.stats
	if type(s) ~= "table" then return end
	MS.t.money = math.max(MS.t.money or 0, tonumber(s.money) or 0)
	MS.t.base_seen = math.max(MS.t.base_seen or 0, tonumber(s.seen) or 0)
end

local function score_str(x)
	if x == nil then return nil end
	local s = tostring(x)
	if type(to_big) == "function" then
		local ok, b = pcall(function() return tostring(to_big(x)) end)
		if ok then s = b end
	end
	if not s:match("[eE]") and s:match("%.") then s = s:gsub("%..*$", "") end
	s = s:gsub(",", "")
	return s
end

--- Pure-ish: the report from the current game state (G passed in for tests).
function MS.collect(g, jokers)
	local t = MS.t
	local lineup = {}
	for _, c in ipairs(jokers or {}) do
		local k = c and c.config and c.config.center and c.config.center.key
		if k then
			lineup[#lineup + 1] = k
			if not t.seen[k] then t.seen[k] = true; t.nseen = t.nseen + 1 end
		end
	end
	local rs = g.round_scores and g.round_scores.hand
	local best = rs and score_str(rs.amt)
	if best and best ~= t.best then
		t.best = best
		t.bestHand = g.last_hand_played or t.bestHand
	end
	local ante = g.round_resets and tonumber(g.round_resets.ante) or 1
	t.ante = math.max(t.ante or 1, ante)
	local hand = t.bestHand
	if hand and localize then
		local ok, s = pcall(localize, hand, "poker_hands")
		if ok and type(s) == "string" and s ~= "ERROR" then hand = s end
	end
	return { action = "statsReport", best = t.best or "0", bestHand = hand, jokers = #lineup, lineup = lineup,
		seen = math.max(t.nseen, t.base_seen or 0), money = t.money, ante = t.ante }
end

function MS.report()
	if not (MP.STEAM_P2P and Client and Client.send and in_mp_run()) then return end
	local ok, r = pcall(MS.collect, G.GAME, G.jokers and G.jokers.cards)
	if not ok or not r then return end
	local sig = table.concat({ r.best, tostring(r.bestHand), r.jokers, table.concat(r.lineup, ","), r.seen, r.money, r.ante }, "|")
	if sig == MS.sig then return end
	MS.sig = sig
	pcall(Client.send, r)
end

---------------------------------------------------------------------------------------------
-- screen
local function colour(name)
	local C = G.C or {}
	local SS = C.SECONDARY_SET or {}
	local map = { red = C.MULT or C.RED, mult = C.RED, chips = C.CHIPS or C.BLUE, purple = C.PURPLE, green = C.GREEN,
		planet = SS.Planet or C.BLUE, money = C.MONEY or C.GOLD, filter = C.FILTER or C.ORANGE, gold = C.GOLD }
	return map[name] or C.WHITE
end
MS.colour = colour

--- Pure: page `page` (1-based) of a list, `per` items each; returns the slice and the page count.
function MS.page_of(list, page, per)
	per = per or MS.PER_PAGE
	local pages = math.max(1, math.ceil(#(list or {}) / per))
	page = math.max(1, math.min(pages, tonumber(page) or 1))
	local out = {}
	for i = (page - 1) * per + 1, math.min(#(list or {}), page * per) do out[#out + 1] = list[i] end
	return out, pages, page
end

-- building blocks in the style of the game-over "round scores" rows
-- G.UIT.T has no maxw in Balatro (only containers / DynaText): fit the text here instead.
-- Shrink to at most 70 % of the scale, then shorten with "..".
local function T(text, scale, col, maxw)
	text = tostring(text or "")
	if maxw and MP.FIT then
		local sc = MP.FIT.scale(text, scale, maxw)
		if sc < scale * 0.7 then
			sc = scale * 0.7
			text = MP.FIT.ellipsize(text, sc, maxw)
		end
		scale = sc
	end
	return { n = G.UIT.T, config = { text = text, scale = scale, colour = col or G.C.UI.TEXT_LIGHT, shadow = true, maxw = maxw } }
end
local function dyn(text, scale, col, extra)
	local ok, d = pcall(DynaText, { string = { text }, colours = { col or G.C.WHITE }, shadow = true, float = true,
		scale = scale, pop_in = extra and extra.pop_in, bump = extra and extra.bump, rotate = extra and extra.rotate,
		spacing = extra and extra.spacing, maxw = extra and extra.maxw })
	if ok and d then return { n = G.UIT.O, config = { object = d } } end
	return T(text, scale, col)
end
local PANEL = function() return darken and darken(G.C.JOKER_GREY, 0.1) or G.C.L_BLACK end

--- small grey label over a black value box (the box takes the award colour for the category winner)
local function stat_box(s, w)
	local box_col = s.winner and colour(s.award_colour or s.colour) or G.C.BLACK
	local val_col = s.winner and G.C.WHITE or colour(s.colour)
	-- box padding 0.04 around / between the texts: value (+ hand type) gets the rest of the width
	local room = (w or 1.35) - (s.sub and 0.12 or 0.08)
	local inner = { T(s.value, 0.36, val_col, s.sub and room * 0.42 or room) }
	if s.sub then inner[#inner + 1] = T(" " .. s.sub, 0.3, s.winner and G.C.WHITE or G.C.UI.TEXT_LIGHT, room * 0.58) end
	return { n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { T(s.label, 0.28, G.C.UI.TEXT_LIGHT, w or 1.35) } },
		{ n = G.UIT.R, config = { align = "cm", minw = w or 1.35, maxw = w or 1.35, minh = 0.45, r = 0.1, colour = box_col, emboss = 0.05, padding = 0.04 },
			nodes = inner },
	} }
end

local function award_card(a)
	return { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.1, colour = PANEL(), emboss = 0.05 }, nodes = {
		{ n = G.UIT.C, config = { align = "cm", minw = 0.14, minh = 0.9, r = 0.1, colour = colour(a.colour) }, nodes = {} },
		{ n = G.UIT.C, config = { align = "cm", padding = 0.02, minw = 2.5, maxw = 2.5 }, nodes = { T(a.label, 0.4, G.C.UI.TEXT_LIGHT, 2.4) } },
		{ n = G.UIT.C, config = { align = "cm", minw = 2.7, minh = 0.9, r = 0.1, colour = G.C.BLACK, emboss = 0.05, padding = 0.05 }, nodes = {
			{ n = G.UIT.R, config = { align = "cm" }, nodes = { dyn(a.value, 0.45, colour(a.colour), { maxw = 2.6 }) } },
			{ n = G.UIT.R, config = { align = "cm" }, nodes = { T(a.name, 0.32, a.you and G.C.GOLD or G.C.WHITE, 2.5) } },
		} },
	} }
end

local function lineup_node(v)
	local keys = v.lineup_keys
	if not (keys and #keys > 0) then return nil end
	local ok, area = pcall(function()
		local s = 0.6
		local ar = CardArea(0, 0, G.CARD_W * s * math.min(#keys, 5) * 1.1, G.CARD_H * s,
			{ card_limit = #keys, type = "title", highlight_limit = 0 })
		for _, k in ipairs(keys) do
			local c = G.P_CENTERS and G.P_CENTERS[k]
			if c then
				ar:emplace(Card(0, 0, G.CARD_W * s, G.CARD_H * s, nil, c, { bypass_discovery_center = true, bypass_discovery_ui = true }))
			end
		end
		return ar
	end)
	local label = { n = G.UIT.R, config = { align = "cm" }, nodes = { T(L("k_ms_lineup_title", "#1#'s final jokers", { v.lineup_owner }), 0.32, G.C.UI.TEXT_LIGHT) } }
	if ok and area then
		return { n = G.UIT.R, config = { align = "cm", padding = 0.05, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
			label, { n = G.UIT.R, config = { align = "cm" }, nodes = { { n = G.UIT.O, config = { object = area } } } } } }
	end
	return v.lineup and { n = G.UIT.R, config = { align = "cm" }, nodes = { T(v.lineup, 0.3, G.C.UI.TEXT_LIGHT) } } or nil
end

function MS.awards_tab(v)
	local left, right = {}, {}
	for i, a in ipairs(v.awards) do
		local col = (i % 2 == 1) and left or right
		col[#col + 1] = award_card(a)
	end
	local nodes = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			{ n = G.UIT.C, config = { align = "tm", padding = 0.06 }, nodes = left },
			{ n = G.UIT.C, config = { align = "tm", padding = 0.06 }, nodes = right },
		} },
	}
	if #v.awards == 0 then nodes[1] = { n = G.UIT.R, config = { align = "cm", padding = 0.2 }, nodes = { T(L("k_ms_no_awards", "Play with friends for awards!"), 0.4) } } end
	local ln = lineup_node(v)
	if ln then nodes[#nodes + 1] = ln end
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, minh = 5.6, minw = 13 }, nodes = nodes }
end

-- one panel per player: place | name | a row of small "label over value box" stats
MS.STAT_W = { dealt = 1.3, best = 2.4, jokers = 1.0, livesLost = 1.15, pvpWon = 1.05, money = 1.1, ante = 0.85 }
MS.PANEL_W = 12.8
local function player_panel(p)
	local boxes = {}
	for _, x in ipairs(p.stats) do boxes[#boxes + 1] = stat_box(x, MS.STAT_W[x.key] or 1.2) end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.1, colour = PANEL(), emboss = 0.05, minw = MS.PANEL_W }, nodes = {
		{ n = G.UIT.C, config = { align = "cm", minw = 0.75, minh = 0.9, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
			T(tostring(p.place), 0.6, p.place == 1 and G.C.GOLD or G.C.WHITE) } },
		{ n = G.UIT.C, config = { align = "cl", padding = 0.06, minw = 2.3, maxw = 2.3 }, nodes = {
			{ n = G.UIT.R, config = { align = "cl" }, nodes = { T(p.name, 0.42, p.you and G.C.GOLD or G.C.WHITE, 2.2) } },
			{ n = G.UIT.R, config = { align = "cl" }, nodes = { T((function()
				local sub = p.team and L("k_ms_team", "Team #1#", { p.team }) or ""
				if p.lives_text and p.lives_text ~= "" then sub = (sub ~= "" and (sub .. " · ") or "") .. p.lives_text end
				if sub == "" and p.out then sub = L("k_sp_out", "out") end
				return sub
			end)(), 0.3, G.C.UI.TEXT_INACTIVE, 2.2) } },
		} },
		{ n = G.UIT.C, config = { align = "cm" }, nodes = boxes },
	} }
end

function MS.players_tab(v)
	local list, pages, page = MS.page_of(v.players, MS.page, MS.PER_PAGE)
	MS.page = page
	local nodes = {}
	for _, p in ipairs(list) do nodes[#nodes + 1] = player_panel(p) end
	if pages > 1 then
		local opts = {}
		for i = 1, pages do opts[i] = localize and L("k_ms_page", "Page #1#/#2#", { i, pages }) or (i .. "/" .. pages) end
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			create_option_cycle({ options = opts, w = 4.5, cycle_shoulders = true, opt_callback = "mp_ms_page", current_option = page,
				colour = G.C.RED, no_pips = true, focus_args = { snap_to = true, nav = "wide" } }) } }
	end
	return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minh = 5.6, minw = 13, padding = 0.05 }, nodes = nodes }
end

local TEAM_COLOURS = { "chips", "red", "green", "purple" }
function MS.teams_tab(v)
	local nodes = {}
	for i, t in ipairs(v.team_panels or {}) do
		local boxes = {}
		for _, s in ipairs(t.stats) do boxes[#boxes + 1] = stat_box(s, 1.6) end
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.1, colour = PANEL(), emboss = 0.05, minw = MS.PANEL_W }, nodes = {
			{ n = G.UIT.C, config = { align = "cm", minw = 0.75, minh = 1.05, r = 0.1, colour = colour(TEAM_COLOURS[(i - 1) % 4 + 1]), emboss = 0.05 }, nodes = {
				T(t.team, 0.6, G.C.WHITE) } },
			{ n = G.UIT.C, config = { align = "cl", padding = 0.06, minw = 3.6, maxw = 3.6 }, nodes = {
				{ n = G.UIT.R, config = { align = "cl" }, nodes = { T(L("k_ms_team", "Team #1#", { t.team }), 0.42, t.winner and G.C.GOLD or G.C.WHITE, 3.4) } },
				{ n = G.UIT.R, config = { align = "cl" }, nodes = { T(t.members .. ((t.lives ~= nil) and (" · " .. L("k_ms_lives_left", "#1# lives", { t.lives })) or ""), 0.3, G.C.UI.TEXT_INACTIVE, 3.4) } },
			} },
			{ n = G.UIT.C, config = { align = "cm" }, nodes = boxes },
		} }
	end
	return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR, minh = 5.6, minw = 13, padding = 0.05 }, nodes = nodes }
end

--- Pure: which tabs the screen has
function MS.tab_list(v)
	local t = { { id = "awards", label = L("b_ms_tab_awards", "Awards") }, { id = "players", label = L("b_ms_tab_players", "Players") } }
	if v.team_panels and #v.team_panels > 0 then t[#t + 1] = { id = "teams", label = L("b_ms_tab_teams", "Teams") } end
	return t
end

function MS.ui(st)
	local v = MS.view(st, MP.LOBBY and MP.LOBBY.my_id)
	local build = { awards = MS.awards_tab, players = MS.players_tab, teams = MS.teams_tab }
	local tabs = {}
	for _, t in ipairs(MS.tab_list(v)) do
		tabs[#tabs + 1] = { label = t.label, chosen = (MS.tab or "awards") == t.id,
			tab_definition_function = function() MS.tab = t.id; return build[t.id](v) end }
	end
	local back = "Back"
	pcall(function() local b = localize("b_back"); if type(b) == "string" and b ~= "ERROR" then back = b end end)
	local contents = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { dyn(v.title, 1.1, G.C.GOLD, { pop_in = 0.4, rotate = true, spacing = 6, maxw = 9 }) } },
	}
	if v.winner ~= "" then contents[#contents + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { dyn(v.winner, 0.6, G.C.WHITE, { bump = true }) } } end
	contents[#contents + 1] = create_tabs({ tabs = tabs, snap_to_nav = true, colour = G.C.BOOSTER, tab_h = 5.8, tab_w = 13.2, text_scale = 0.45 })
	return create_UIBox_generic_options({ back_func = "mp_ms_close", back_label = back, contents = contents })
end

function MS.open()
	if not MS.last then
		pcall(sendWarnMessage, L("k_ms_later", "Match stats appear when the match is over"), "MULTIPLAYER")
		pcall(function()
			attention_text({ scale = 0.6, text = L("k_ms_later", "Match stats appear when the match is over"), hold = 3,
				align = "cm", offset = { x = 0, y = -2.5 }, major = G.ROOM_ATTACH })
		end)
		return
	end
	MS.show_at, MS.tab, MS.page = nil, "awards", 1
	if MP.SPECTATE and MP.SPECTATE.state.active then MP.SPECTATE.state.active = false end
	local ok, err = pcall(function() G.FUNCS.overlay_menu({ definition = MS.ui(MS.last) }) end)
	if not ok then pcall(sendWarnMessage, "Match stats screen failed: " .. tostring(err), "MULTIPLAYER") end
end

function MS.close()
	-- back to the game-over / win screen when we came from a finished run
	if G.STAGE == G.STAGES.RUN and MP.LOBBY.code and MP.UI and MP.UI.create_UIBox_mp_game_end
		and (G.STATE == G.STATES.GAME_OVER or MP.GAME.won or (MP.GAME.lives or 0) <= 0) then
		local ok = pcall(G.FUNCS.overlay_menu, { definition = MP.UI.create_UIBox_mp_game_end(MP.GAME.won and true or false) })
		if ok then return end
	end
	pcall(G.FUNCS.exit_overlay_menu)
end

--- Winner, teams and per-player lines on the game-over screen once the host has sent them.
function MS.end_block()
	if not MS.last then return { n = G.UIT.R, config = { align = "cm" }, nodes = {} } end
	local lines = MS.result_lines(MS.last)
	local nodes = {}
	local cap = 8
	for i = 1, math.min(#lines, cap) do
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { text = lines[i], scale = 0.28, colour = G.C.UI.TEXT_LIGHT, maxw = 3.9, shadow = true } },
		} }
	end
	if #lines > cap then
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { text = "+" .. tostring(#lines - cap), scale = 0.28, colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT, maxw = 3.9 } },
		} }
	end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = nodes }
end

--- Game-over / win screen button
function MS.end_button()
	if not (MP.LOBBY and MP.LOBBY.code) then return { n = G.UIT.R, config = { align = "cm" }, nodes = {} } end
	return UIBox_button({ button = "mp_ms_open", label = { L("b_ms_open", "Match stats") }, colour = G.C.PURPLE or G.C.BLUE,
		minw = 4, maxw = 4, minh = 0.75 })
end

function MS.register()
	if MS.registered then return end
	MS.registered = true
	G.FUNCS.mp_ms_open = function() MS.open() end
	G.FUNCS.mp_ms_close = function() MS.close() end
	G.FUNCS.mp_ms_page = function(args)
		MS.page, MS.tab = args and args.to_key or 1, "players"
		local ok, err = pcall(function() G.FUNCS.overlay_menu({ definition = MS.ui(MS.last) }) end)
	if not ok then pcall(sendWarnMessage, "Match stats screen failed: " .. tostring(err), "MULTIPLAYER") end
	end
	MP.register_action("matchStats", function(p)
		MS.last = p
		MS.show_at = now() + MS.AUTO_DELAY
	end)
	if MP.ACTIONS and MP.ACTIONS.play_hand then
		local ph = MP.ACTIONS.play_hand
		MP.ACTIONS.play_hand = function(...)
			pcall(MS.report) -- before the hand, so the host has it when the PvP resolves
			return ph(...)
		end
	end
	local upd = Game.update
	local t = 0
	function Game:update(dt)
		local r = upd(self, dt)
		t = t - (dt or 0)
		if t <= 0 then
			t = MS.REPORT_EVERY
			pcall(MS.report)
		end
		if MS.show_at and now() >= MS.show_at and not (MP.REJOIN and MP.REJOIN.pending) then
			MS.show_at = nil
			if MP.LOBBY and MP.LOBBY.code then pcall(MS.open) end
		end
		return r
	end
end
