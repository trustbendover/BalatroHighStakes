-- Balatro High Stakes 0.6.8: spectator mode. GPL-3.0.
-- Who: players that are out (Deathmatch, Attrition, KotH, Teams, ...) and players who join a lobby
-- whose match is already running. The host (networking/p2p_server.lua) marks them as spectator /
-- eliminated: they never count as alive for win checks or PvP pairing and their game actions are
-- ignored. This file only shows the live state of the remaining players and lets you switch
-- which player you follow. Leaving goes back to the lobby.
MP.SPECTATE = MP.SPECTATE or {}
local SP = MP.SPECTATE

SP.MAX_ROWS = 8
SP.REFRESH = 0.5
-- 0.6.8 layout: fixed widths (UI units) so the panel never grows or jumps when a row changes.
-- Rows are columns: marker | "1. name" | lives | score | status. Texts are fitted in SP.lines.
SP.ROW_SCALE = 0.35
SP.COL = { mark = 0.3, name = 3.4, lives = 1.45, score = 1.8, status = 2.1 }
SP.BOX_W = 9.5 -- black list box (columns + padding)
SP.CELL_PAD = 0.02
SP.TEXT_W = 9.2 -- follow / detail / where lines
SP.state = SP.state or { active = false, follow = nil, joined = false, match = false }
SP.view = SP.view or {}

local function L(key, fallback, vars)
	local ok, s = pcall(localize, vars and { type = "variable", key = key, vars = vars } or key)
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then return s end
	if vars then
		for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", (tostring(v):gsub("%%", "%%%%"))) end
	end
	return fallback
end
SP.L = L

local function clean(n) return (tostring(n or "?"):gsub("~.*$", "")) end

-- identity fallback if lib/fit.lua is missing (never crash the panel)
local NOFIT = { width = function(s, sc) return #tostring(s or "") * 0.44 * (sc or 1) end,
	ellipsize = function(s) return tostring(s or "") end, number = function(s) return tostring(s or "") end,
	join = function(p) return table.concat(p, "   ") end }
local function fit() return MP.FIT or NOFIT end
local function F_colour(dst, src) if MP.FIT then MP.FIT.set_colour(dst, src) end end

-- "[A] " in Teams mode (same tag as the lobby), else ""
local function team_tag(id)
	local ok, letter = pcall(function() return MP.TEAMS and MP.TEAMS.is_active() and MP.TEAMS.team_of(id) end)
	return (ok and letter) and ("[" .. tostring(letter) .. "] ") or ""
end
SP.team_tag = team_tag

local function num(s)
	if type(s) == "number" then return s end
	return tonumber(s) or tonumber(tostring(s or ""):match("^[%d%.eE%+%-]+")) or 0
end

--- Pure: the players you can watch, best first (alive, then most lives, then highest score, then name).
function SP.rows(enemies, names)
	local list = {}
	for id, e in pairs(enemies or {}) do
		if type(e) == "table" and not e.spectator and id ~= "legacy" then
			list[#list + 1] = {
				id = e.id or id,
				name = clean((names and names[e.id or id]) or e.username),
				team = team_tag(e.id or id),
				lives = tonumber(e.lives) or 0,
				score = e.raw_score or "0",
				hands = tonumber(e.hands) or 0,
				ante = tonumber(e.ante),
				location = e.location,
				away = e.away and true or false,
				out = e.eliminated and true or false,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.out ~= b.out then return not a.out end
		if a.lives ~= b.lives then return a.lives > b.lives end
		local sa, sb = num(a.score), num(b.score)
		if sa ~= sb then return sa > sb end
		return a.name < b.name
	end)
	return list
end

--- Pure: who is ahead (first alive row), or nil.
function SP.leader(rows)
	for _, r in ipairs(rows or {}) do if not r.out then return r end end
	return nil
end

--- Pure: the id to follow after `cur` in direction dir (+1 / -1). Skips players that are out
--- while anyone is still alive. Keeps a valid id; falls back to the leader.
function SP.step(rows, cur, dir)
	local pool = {}
	for _, r in ipairs(rows or {}) do if not r.out then pool[#pool + 1] = r end end
	if #pool == 0 then pool = rows or {} end
	if #pool == 0 then return nil end
	local at = nil
	for i, r in ipairs(pool) do if r.id == cur then at = i end end
	if not at then return pool[1].id end
	if not dir or dir == 0 then return cur end
	return pool[((at - 1 + dir) % #pool) + 1].id
end

--- Pure: the text lines of the panel for `rows` while following `follow`.
--- v.rows[i] = the whole row as one string (logs/tests); v.cells[i] = the fitted column texts.
function SP.lines(rows, follow)
	local v = { rows = {}, cells = {} }
	local F, C, S = fit(), SP.COL, SP.ROW_SCALE
	local f = nil
	for _, r in ipairs(rows or {}) do if r.id == follow then f = r end end
	local lead = SP.leader(rows)
	if not f then
		v.follow = L("k_sp_nobody", "Nobody left to watch")
		v.detail, v.where = "", ""
	else
		local label = L("k_sp_following", "Following: #1#", { "" })
		local room = SP.TEXT_W - F.width(label, 0.5)
		v.follow = L("k_sp_following", "Following: #1#", { F.ellipsize((f.team or "") .. f.name, 0.5, room) })
		local score = F.number(f.score, 0.4, 2.4)
		local bits = { L("k_sp_lives", "Lives: #1#", { f.lives }), L("k_sp_score", "Score: #1#", { score }),
			L("k_sp_hands", "Hands left: #1#", { f.hands }) }
		if f.ante then bits[#bits + 1] = L("k_sp_ante", "Ante #1#", { f.ante }) end
		v.detail = F.join(bits, 0.4, SP.TEXT_W)
		local where = f.out and L("k_sp_out", "out") or f.away and L("k_sp_away", "disconnected")
			or (f.location and tostring(f.location)) or ""
		v.where = where ~= "" and F.ellipsize(L("k_sp_where", "Now: #1#", { where }), 0.4, SP.TEXT_W) or ""
	end
	for i = 1, SP.MAX_ROWS do
		local r = rows and rows[i]
		if r then
			local kind = r.out and "out" or r.away and "away" or (lead and lead.id == r.id and #rows > 1) and "ahead" or ""
			local status = kind == "out" and L("k_sp_out", "out") or kind == "away" and L("k_sp_away", "disconnected")
				or kind == "ahead" and L("k_sp_ahead", "ahead") or ""
			local cell = {
				mark = r.id == follow and ">" or "",
				name = F.ellipsize(string.format("%d. %s%s", i, r.team or "", r.name), S, C.name - 2 * SP.CELL_PAD),
				lives = F.ellipsize(L("k_sp_lives", "Lives: #1#", { r.lives }), S, C.lives - 2 * SP.CELL_PAD),
				score = F.number(r.score, S, C.score - 2 * SP.CELL_PAD),
				status = F.ellipsize(status, S, C.status - 2 * SP.CELL_PAD),
				kind = kind, following = r.id == follow,
			}
			v.cells[i] = cell
			v.rows[i] = string.format("%s%s   %s / %s%s", cell.mark ~= "" and "> " or "", cell.name, cell.lives, cell.score,
				status ~= "" and (" - " .. status) or "")
		else
			v.rows[i] = ""
			v.cells[i] = { mark = "", name = "", lives = "", score = "", status = "", kind = "" }
		end
	end
	return v
end

--- Is a match running that we are not playing in?
function SP.watching()
	return SP.state.joined or (MP.GAME and MP.GAME.lives == 0 and SP.state.match) or false
end

function SP.refresh()
	local rows = SP.rows(MP.GAME and MP.GAME.enemies, MP.LOBBY and MP.LOBBY.names_by_id)
	local f = SP.state.follow
	local ok = false
	for _, r in ipairs(rows) do if r.id == f and (not r.out or not SP.leader(rows)) then ok = true end end
	if not ok then SP.state.follow = SP.step(rows, nil, 0) end
	local v = SP.lines(rows, SP.state.follow)
	SP.view.title = L("k_sp_title", "Spectating")
	SP.view.follow, SP.view.detail, SP.view.where = v.follow, v.detail, v.where
	SP.view.rejoin = SP.rejoin_label(SP.state.held, love and love.timer and love.timer.getTime() or os.clock())
	SP.colours = SP.colours or {}
	for i = 1, SP.MAX_ROWS do
		local c = v.cells[i]
		SP.view["row" .. i] = v.rows[i]
		for _, k in ipairs({ "mark", "name", "lives", "score", "status" }) do SP.view["r" .. i .. "_" .. k] = c[k] end
		SP.colours[i] = SP.colours[i] or { name = { 1, 1, 1, 1 }, status = { 1, 1, 1, 1 } }
		pcall(function()
			local grey = G.C.UI.TEXT_INACTIVE
			F_colour(SP.colours[i].name, c.kind == "out" and grey or c.following and G.C.GOLD or G.C.UI.TEXT_LIGHT)
			F_colour(SP.colours[i].status, c.kind == "ahead" and G.C.GREEN or c.kind == "away" and G.C.ORANGE or grey)
		end)
	end
	return rows
end

local function text(ref, scale, colour)
	return { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
		{ n = G.UIT.T, config = { ref_table = SP.view, ref_value = ref, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } },
	} }
end

local function cell(i, key, w, align, colour)
	return { n = G.UIT.C, config = { align = align or "cl", minw = w, maxw = w, padding = SP.CELL_PAD }, nodes = {
		{ n = G.UIT.T, config = { ref_table = SP.view, ref_value = "r" .. i .. "_" .. key, scale = SP.ROW_SCALE,
			colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } },
	} }
end

--- one list row: fixed-width columns, so long names / scores / statuses never widen the box
function SP.row_node(i)
	local C, col = SP.COL, SP.colours and SP.colours[i] or {}
	return { n = G.UIT.R, config = { align = "cl", padding = 0.01, minh = 0.42 }, nodes = {
		cell(i, "mark", C.mark, "cm", G.C.GOLD),
		cell(i, "name", C.name, "cl", col.name),
		cell(i, "lives", C.lives, "cl"),
		cell(i, "score", C.score, "cr"),
		{ n = G.UIT.C, config = { minw = 0.15 } },
		cell(i, "status", C.status, "cl", col.status),
	} }
end

local function line(ref, scale, colour)
	return { n = G.UIT.R, config = { align = "cm", padding = 0.03, minw = SP.TEXT_W, maxw = SP.TEXT_W }, nodes = {
		{ n = G.UIT.T, config = { ref_table = SP.view, ref_value = ref, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } },
	} }
end

function SP.ui()
	SP.refresh()
	local rows = {}
	for i = 1, SP.MAX_ROWS do rows[#rows + 1] = SP.row_node(i) end
	local contents = {
			text("title", 0.6, G.C.GOLD),
			line("follow", 0.5),
			line("detail", 0.4),
			line("where", 0.4, G.C.UI.TEXT_INACTIVE),
			{ n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK, minw = SP.BOX_W, maxw = SP.BOX_W }, nodes = rows },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
				UIBox_button({ button = "mp_sp_prev", label = { L("b_sp_prev", "< Prev") }, minw = 2.2, minh = 0.6, scale = 0.4, col = true }),
				{ n = G.UIT.C, config = { minw = 0.2 } },
				UIBox_button({ button = "mp_sp_next", label = { L("b_sp_next", "Next >") }, minw = 2.2, minh = 0.6, scale = 0.4, col = true }),
			} },
	}
	-- 0.6.9: you hold a seat in this match: take it back while the grace runs
	if SP.state.held then contents[#contents + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
				{ n = G.UIT.C, config = { button = "mp_sp_rejoin", colour = G.C.BLUE, r = 0.1, minw = 4.6, minh = 0.7,
					align = "cm", hover = true, shadow = true }, nodes = {
					{ n = G.UIT.T, config = { ref_table = SP.view, ref_value = "rejoin", scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } } } } } end
	contents[#contents + 1] = UIBox_button({ button = "mp_sp_back", label = { L("b_sp_back", "Back to lobby") }, colour = G.C.RED, minw = 4.6, minh = 0.7, scale = 0.45 })
	return create_UIBox_generic_options({ no_back = true, contents = contents })
end

function SP.open()
	SP.state.active = true
	local ok, err = pcall(function() G.FUNCS.overlay_menu({ definition = SP.ui() }) end)
	if not ok then SP.state.active = false; pcall(sendWarnMessage, "Spectator panel failed: " .. tostring(err), "MULTIPLAYER") end
end

function SP.close()
	SP.state.active = false
	pcall(G.FUNCS.exit_overlay_menu)
end

local function follow_step(dir)
	local rows = SP.refresh()
	SP.state.follow = SP.step(rows, SP.state.follow, dir)
	SP.refresh()
end

function SP.register()
	if SP.registered then return end
	SP.registered = true

	G.FUNCS.mp_sp_prev = function() follow_step(-1) end
	G.FUNCS.mp_sp_next = function() follow_step(1) end
	G.FUNCS.mp_sp_open = function() SP.open() end
	G.FUNCS.mp_sp_rejoin = function()
		local h = SP.state.held
		if not h or not (MP.LOBBY and MP.LOBBY.code) then return end
		SP.close()
		MP.ACTIONS.rejoin_held(MP.LOBBY.code, h.token)
	end
	G.FUNCS.mp_sp_back = function()
		SP.close()
		-- out of a run (game-over screen): back to the lobby like "Return to lobby"
		if G.STAGE == G.STAGES.RUN and MP.ACTIONS and MP.ACTIONS.stop_game then pcall(MP.ACTIONS.stop_game) end
	end

	-- Server: you joined a running match as spectator
	MP.register_action("spectateStart", function(p)
		SP.state.joined, SP.state.match = true, true
		SP.on_spectate_start(p, love and love.timer and love.timer.getTime() or os.clock())
		MP.GAME.lives = 0
		pcall(sendWarnMessage, L("k_sp_joined", "You are watching the running match"), "MULTIPLAYER")
		SP.open()
	end)
	MP.register_action("spectatorJoined", function(p)
		pcall(sendWarnMessage, L("k_sp_spectator_joined", "#1# is watching", { clean(p.username) }), "MULTIPLAYER")
	end)
	MP.register_action("spectatorLeft", function(p) end)
	MP.register_action("matchOver", function(p)
		local name = p.winnerId and MP.LOBBY and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.winnerId]
		pcall(sendWarnMessage, name and L("k_sp_winner", "#1# won the match", { clean(name) }) or L("k_sp_over", "The match is over"), "MULTIPLAYER")
		if SP.state.active and MP.UI and MP.UI.UTILS and MP.UI.UTILS.overlay_message then
			SP.close()
			pcall(MP.UI.UTILS.overlay_message, name and L("k_sp_winner", "#1# won the match", { clean(name) }) or L("k_sp_over", "The match is over"))
		end
		SP.on_match_end()
	end)

	-- Lobby: while a match runs that you are not in, the start/ready button becomes "Watch match"
	if MP.UI and MP.UI.create_lobby_main_button then
		local main_ref = MP.UI.create_lobby_main_button
		MP.UI.create_lobby_main_button = function(text_scale)
			if SP.state.joined and SP.state.match then
				return UIBox_button({ button = "mp_sp_open", colour = G.C.GREEN, minw = 3.65, minh = 1.55,
					label = { L("b_sp_watch", "Watch match") }, scale = text_scale * 1.5, col = true })
			end
			return main_ref(text_scale)
		end
	end

	local upd = Game.update
	local t = 0
	function Game:update(dt)
		local r = upd(self, dt)
		if SP.state.active then
			t = t - (dt or 0)
			if t <= 0 then
				t = SP.REFRESH
				pcall(SP.refresh)
			end
		end
		return r
	end
end

--- Game-over screen: "Spectate" while the match is still running (empty row otherwise).
function SP.end_button()
	if not (MP.LOBBY and MP.LOBBY.code and SP.state.match and MP.GAME and (MP.GAME.lives or 0) <= 0 and not MP.GAME.won) then
		return { n = G.UIT.R, config = { align = "cm" }, nodes = {} }
	end
	return UIBox_button({ button = "mp_sp_open", label = { L("b_sp_spectate", "Spectate") }, colour = G.C.GREEN,
		minw = 4, maxw = 4, minh = 0.75 })
end

--- Match state hooks (called from action_handlers)
function SP.on_match_start() SP.state.match, SP.state.joined, SP.state.follow = true, false, nil end
--- 0.6.9: spectateStart: drop the enemies of an earlier run (fresh enemyInfo follows) and remember a held seat.
function SP.on_spectate_start(p, t)
	if p and p.reset and MP.GAME then MP.GAME.enemies = {} end
	SP.state.follow = nil
	local h = p and p.heldSeat
	SP.state.held = (type(h) == "table" and tonumber(h.left)) and { end_time = t + tonumber(h.left), token = h.token } or nil
end

--- Pure: label of the Rejoin button ("Rejoin (2:41)"), "" when there is no held seat.
function SP.rejoin_label(held, t)
	if not held then return "" end
	local left = math.max(0, math.floor((held.end_time or 0) - t))
	if left <= 0 then return L("b_sp_rejoin_gone", "Seat expired") end
	return L("b_sp_rejoin", "Rejoin (#1#)", { string.format("%d:%02d", math.floor(left / 60), left % 60) })
end

function SP.on_rejoined() SP.state.joined, SP.state.held = false, nil; if SP.state.active then SP.close() end end

function SP.on_match_end()
	SP.state.held = nil
	SP.state.match, SP.state.joined = false, false
	if SP.state.active then SP.close() end
end
