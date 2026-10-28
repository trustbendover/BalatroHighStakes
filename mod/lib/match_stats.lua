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
MS.REPORT_EVERY = 3
MS.MAX_ROWS = 8
-- award key, Balatro colour name, text key, fallback
MS.AWARDS = {
	{ "damage", "red", "k_ms_damage", "Most damage" },
	{ "best", "chips", "k_ms_best", "Best hand" },
	{ "jokers", "purple", "k_ms_jokers", "Most jokers" },
	{ "lives", "green", "k_ms_lives", "Fewest lives lost" },
	{ "pvp", "attention", "k_ms_pvp", "Most PvPs won" },
	{ "money", "money", "k_ms_money", "Most money earned" },
	{ "ante", "important", "k_ms_ante", "Highest ante" },
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
	for i, t in ipairs(st.teams or {}) do
		v.teams[i] = L("k_ms_team_line", "Team #1#: damage #2#, PvPs won #3#, lives lost #4#",
			{ t.team, MS.short(t.dealt or 0), t.pvpWon or 0, t.livesLost or 0 })
	end
	local lw = w or rows[1]
	if lw and lw.lineup and #lw.lineup > 0 then
		local names = {}
		for i, k in ipairs(lw.lineup) do names[i] = joker_name(k) end
		v.lineup = L("k_ms_lineup", "#1#'s final jokers: #2#", { clean(lw.name), table.concat(names, ", ") })
	end
	return v
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
	local map = { red = C.RED, chips = C.CHIPS or C.BLUE, purple = C.PURPLE, green = C.GREEN, attention = C.ORANGE or C.FILTER,
		money = C.MONEY or C.GOLD, important = C.IMPORTANT or C.GOLD, gold = C.GOLD }
	return map[name] or C.WHITE
end

local function T(text, scale, col)
	return { n = G.UIT.T, config = { text = text, scale = scale, colour = col or G.C.UI.TEXT_LIGHT, shadow = true } }
end

function MS.ui(st)
	local v = MS.view(st, MP.LOBBY and MP.LOBBY.my_id)
	local nodes = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { T(v.title, 0.7, G.C.GOLD) } },
	}
	if v.winner ~= "" then nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { T(v.winner, 0.5, G.C.WHITE) } } end
	local aw = {}
	for _, a in ipairs(v.awards) do
		aw[#aw + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.03 }, nodes = {
			{ n = G.UIT.C, config = { align = "cm", colour = colour(a.colour), r = 0.08, padding = 0.05, minw = 2.9, emboss = 0.04 },
				nodes = { T(a.label, 0.34, G.C.WHITE) } },
			{ n = G.UIT.C, config = { align = "cl", padding = 0.05 }, nodes = {
				T(" " .. a.name, 0.36, a.you and G.C.GOLD or G.C.WHITE), T("  " .. a.value, 0.32, G.C.UI.TEXT_INACTIVE) } },
		} }
	end
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK }, nodes = aw }
	local widths = { 0.4, 2.2, 1.3, 2.6, 0.9, 1.1, 1, 1, 0.7 }
	local function row(cells, hl, head, you)
		local cs = {}
		for j, c in ipairs(cells) do
			local col = head and G.C.UI.TEXT_INACTIVE or (hl and hl[j] and colour(hl[j])) or (you and j == 2 and G.C.GOLD) or G.C.WHITE
			cs[j] = { n = G.UIT.C, config = { align = j <= 2 and "cl" or "cm", minw = widths[j] or 1, maxw = widths[j] or 1 },
				nodes = { T(c, head and 0.3 or 0.32, col) } }
		end
		return { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = cs }
	end
	local tbl = { row(v.header, nil, true) }
	for _, r in ipairs(v.rows) do tbl[#tbl + 1] = row(r.cells, r.hl, false, r.you) end
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK }, nodes = tbl }
	for _, t in ipairs(v.teams) do nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { T(t, 0.32, G.C.WHITE) } } end
	if v.lineup then nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { T(v.lineup, 0.3, G.C.UI.TEXT_INACTIVE) } } end
	nodes[#nodes + 1] = UIBox_button({ button = "mp_ms_close", label = { L("b_ms_close", "Close") }, minw = 3, minh = 0.65, scale = 0.45 })
	return create_UIBox_generic_options({ no_back = true, contents = nodes })
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
	MS.show_at = nil
	if MP.SPECTATE and MP.SPECTATE.state.active then MP.SPECTATE.state.active = false end
	pcall(G.FUNCS.overlay_menu, { definition = MS.ui(MS.last) })
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
			if MP.LOBBY and MP.LOBBY.code then MS.open() end
		end
		return r
	end
end
