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
function SP.lines(rows, follow)
	local v = { rows = {} }
	local f = nil
	for _, r in ipairs(rows or {}) do if r.id == follow then f = r end end
	local lead = SP.leader(rows)
	if not f then
		v.follow = L("k_sp_nobody", "Nobody left to watch")
		v.detail, v.where = "", ""
	else
		v.follow = L("k_sp_following", "Following: #1#", { f.name })
		local bits = { L("k_sp_lives", "Lives: #1#", { f.lives }), L("k_sp_score", "Score: #1#", { f.score }),
			L("k_sp_hands", "Hands left: #1#", { f.hands }) }
		if f.ante then bits[#bits + 1] = L("k_sp_ante", "Ante #1#", { f.ante }) end
		v.detail = table.concat(bits, "   ")
		local where = f.out and L("k_sp_out", "out") or f.away and L("k_sp_away", "disconnected")
			or (f.location and tostring(f.location)) or ""
		v.where = where ~= "" and L("k_sp_where", "Now: #1#", { where }) or ""
	end
	for i = 1, SP.MAX_ROWS do
		local r = rows and rows[i]
		if r then
			local tag = r.out and (" - " .. L("k_sp_out", "out")) or r.away and (" - " .. L("k_sp_away", "disconnected"))
				or (lead and lead.id == r.id and #rows > 1) and (" - " .. L("k_sp_ahead", "ahead")) or ""
			v.rows[i] = string.format("%s%d. %s   %s / %s%s", r.id == follow and "> " or "", i, r.name,
				L("k_sp_lives", "Lives: #1#", { r.lives }), r.score, tag)
		else
			v.rows[i] = ""
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
	for i = 1, SP.MAX_ROWS do SP.view["row" .. i] = v.rows[i] end
	return rows
end

local function text(ref, scale, colour)
	return { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
		{ n = G.UIT.T, config = { ref_table = SP.view, ref_value = ref, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } },
	} }
end

function SP.ui()
	SP.refresh()
	local rows = {}
	for i = 1, SP.MAX_ROWS do rows[#rows + 1] = text("row" .. i, 0.35) end
	return create_UIBox_generic_options({
		no_back = true,
		contents = {
			text("title", 0.6, G.C.GOLD),
			text("follow", 0.5),
			text("detail", 0.4),
			text("where", 0.4, G.C.UI.TEXT_INACTIVE),
			{ n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK, minw = 7 }, nodes = rows },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
				UIBox_button({ button = "mp_sp_prev", label = { L("b_sp_prev", "< Prev") }, minw = 2.2, minh = 0.6, scale = 0.4, col = true }),
				{ n = G.UIT.C, config = { minw = 0.2 } },
				UIBox_button({ button = "mp_sp_next", label = { L("b_sp_next", "Next >") }, minw = 2.2, minh = 0.6, scale = 0.4, col = true }),
			} },
			UIBox_button({ button = "mp_sp_back", label = { L("b_sp_back", "Back to lobby") }, colour = G.C.RED, minw = 4.6, minh = 0.7, scale = 0.45 }),
		},
	})
end

function SP.open()
	SP.state.active = true
	pcall(G.FUNCS.overlay_menu, { definition = SP.ui() })
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
	G.FUNCS.mp_sp_back = function()
		SP.close()
		-- out of a run (game-over screen): back to the lobby like "Return to lobby"
		if G.STAGE == G.STAGES.RUN and MP.ACTIONS and MP.ACTIONS.stop_game then pcall(MP.ACTIONS.stop_game) end
	end

	-- Server: you joined a running match as spectator
	MP.register_action("spectateStart", function(p)
		SP.state.joined, SP.state.match = true, true
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
function SP.on_match_end()
	SP.state.match, SP.state.joined = false, false
	if SP.state.active then SP.close() end
end
