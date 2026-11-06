-- Balatro High Stakes: helpers for lobbies of 2 to 8 players (file name kept from the 3P fork).
-- GPL-3.0, based on Balatro-Multiplayer/BalatroMultiplayer.
MP.THREEP = MP.THREEP or {}

--- True when the current lobby has more than 2 players (any 3-8 player lobby).
function MP.THREEP.is_3p()
	return MP.LOBBY ~= nil and (MP.LOBBY.player_count or 0) > 2
end

--- The alive rival with the highest score this blind (ties: more lives). Teammates are
--- never the focus in Teams mode (they are on your side).
function MP.THREEP.pick_focus()
	local best = nil
	for _, e in pairs((MP.GAME and MP.GAME.enemies) or {}) do
		if not e.eliminated and not (MP.TEAMS and MP.TEAMS.is_teammate(e.id)) then
			if
				best == nil
				or MP.INSANE_INT.greater_than(e.real_score, best.real_score)
				or (MP.INSANE_INT.equal(e.real_score, best.real_score) and (e.lives or 0) > (best.lives or 0))
			then
				best = e
			end
		end
	end
	return best
end

--- Opponents for display: alive first, then highest score, then name.
function MP.THREEP.sorted_enemies()
	local list = {}
	for _, e in pairs((MP.GAME and MP.GAME.enemies) or {}) do
		list[#list + 1] = e
	end
	table.sort(list, function(a, b)
		if (a.eliminated and true or false) ~= (b.eliminated and true or false) then return not a.eliminated end
		local sa, sb = a.real_score or MP.INSANE_INT.empty(), b.real_score or MP.INSANE_INT.empty()
		local ok, gt = pcall(MP.INSANE_INT.greater_than, sa, sb)
		local ok2, lt = pcall(MP.INSANE_INT.greater_than, sb, sa)
		if ok and ok2 and (gt or lt) then return gt end
		return tostring(a.username) < tostring(b.username)
	end)
	return list
end

-- How many opponents the one-line HUD lists by name before "+N more" (up to 7 opponents).
MP.THREEP.HUD_MAX_NAMED = 3

--- Pure: the HUD line for a list of opponent entries (tested in tests/test_three_player.lua).
--- entries: { username, score_text, hands, lives, eliminated, away, crown, ally }
function MP.THREEP.hud_line(entries, max_named)
	max_named = max_named or MP.THREEP.HUD_MAX_NAMED
	local parts, alive_hidden, out_count = {}, 0, 0
	local compact = #entries > max_named
	for _, e in ipairs(entries) do
		if e.eliminated then
			out_count = out_count + 1
			if not compact then parts[#parts + 1] = tostring(e.username) .. " X" end
		elseif #parts < max_named then
			local tag = (e.crown or "") .. (e.ally and "+" or "")
			local mark = ""
			if e.rejoining or e.away then
				if MP.PRESENCE then
					mark = " " .. MP.PRESENCE.label(MP.PRESENCE.kind({ rejoining = e.rejoining, away = e.away }), localize)
				elseif e.away then mark = " (away)" end
			end
			if compact then
				parts[#parts + 1] = string.format("%s%s %s %sL%s", tag, tostring(e.username), e.score_text, tostring(e.lives or "?"), mark)
			else
				parts[#parts + 1] = string.format("%s%s %s (%sh) %sL%s", tag, tostring(e.username), e.score_text, tostring(e.hands or "?"), tostring(e.lives or "?"), mark)
			end
		else
			alive_hidden = alive_hidden + 1
		end
	end
	if alive_hidden > 0 then parts[#parts + 1] = "+" .. alive_hidden end
	if compact and out_count > 0 then parts[#parts + 1] = out_count .. " out" end
	return table.concat(parts, " | ")
end

--- Rebuild the text shown in the PvP blind HUD and lobby info, e.g.
--- "Bob 1,200 (3h) 2L | Carol ??? (4h) 3L"; with 4+ opponents: "Bob 1,200 2L | Carol 900 3L | Dave 800 1L | +3 | 1 out".
--- Teams mode: team totals first, teammates marked with "+".
function MP.THREEP.refresh_hud()
	if not MP.GAME or not MP.GAME.enemy then return end
	local hide = MP.LOBBY.config.hide_score_until_played
		and MP.is_pvp_boss
		and MP.is_pvp_boss()
		and G.GAME
		and G.GAME.current_round
		and G.GAME.current_round.hands_played == 0
	local entries = {}
	for _, e in ipairs(MP.THREEP.sorted_enemies()) do
		entries[#entries + 1] = {
			username = e.username,
			score_text = hide and "???" or MP.INSANE_INT.to_string(e.real_score or MP.INSANE_INT.empty()),
			hands = e.hands,
			lives = e.lives,
			eliminated = e.eliminated,
			away = e.away,
			rejoining = e.rejoining,
			crown = (MP.KOTH and MP.KOTH.name_prefix) and MP.KOTH.name_prefix(e.id) or "",
			ally = MP.TEAMS and MP.TEAMS.is_teammate(e.id) or false,
		}
	end
	local line = MP.THREEP.hud_line(entries)
	if MP.TEAMS and MP.TEAMS.is_active() and MP.TEAMS.state() then
		local tt = MP.TEAMS.hud_text(hide)
		if tt ~= "" then line = tt .. "  ||  " .. line end
	end
	if line == "" then
		MP.GAME.enemy.hud_title = MP.GAME.enemy.username or ""
	else
		MP.GAME.enemy.hud_title = line
	end
	if MP.GAME.koth and MP.KOTH and MP.KOTH.status_text then
		local st = MP.GAME.koth
		if st.kingId and st.kingId == st.you then MP.GAME.enemy.hud_title = "[K] " .. MP.GAME.enemy.hud_title end
	end
	MP.GAME.enemy.opponents_text = MP.GAME.enemy.hud_title
	-- 0.6.8: the blind-name DynaText applies its maxw only when it is set up; scores, "???" -> numbers,
	-- "(away)" and team totals change the line later, so re-fit it whenever the text changes.
	if MP.GAME.enemy.hud_title ~= MP.THREEP.last_hud_title then
		MP.THREEP.last_hud_title = MP.GAME.enemy.hud_title
		pcall(function()
			local el = G.HUD_blind and G.HUD_blind:get_UIE_by_ID("HUD_blind_name")
			local obj = el and el.config and el.config.object
			if obj and obj.config and obj.config.mp_maxw and MP.FIT then MP.FIT.refit_dynatext(obj) end
		end)
	end
end

--- Lobby seat table by role ("host" | "guest" | "third" | "seat1".."seat8"); never nil.
function MP.THREEP.lobby_player(role)
	local t
	local n = type(role) == "string" and tonumber(role:match("^seat(%d+)$"))
	if n then
		t = MP.LOBBY.seats and MP.LOBBY.seats[n]
		if not t then t = (n == 1 and MP.LOBBY.host) or (n == 2 and MP.LOBBY.guest) or (n == 3 and MP.LOBBY.third) end
	else
		t = (role == "host" and MP.LOBBY.host) or (role == "guest" and MP.LOBBY.guest) or (role == "third" and MP.LOBBY.third)
	end
	t = t or {}
	if t.config and t.config.Mods then return t end
	return { username = t.username, hash = t.hash, team = t.team, config = { Mods = {} } }
end

--- Seat index for a role string (host=1, guest=2, third=3, seatN=N).
function MP.THREEP.seat_index(role)
	return ({ host = 1, guest = 2, third = 3 })[role] or tonumber(tostring(role):match("^seat(%d+)$"))
end

--- Number of filled lobby seats (1..8).
function MP.THREEP.seat_count()
	local n = 0
	for i = 1, 8 do
		local s = MP.LOBBY.seats and MP.LOBBY.seats[i]
		if s and s.username then n = i end
	end
	if n == 0 and MP.LOBBY.host and MP.LOBBY.host.username then n = 1 end
	return n
end

--- Game-over "nemesis" (2-8 players; in Teams only rivals count): who to show on the Game Over screen (name + jokers + deck).
--- Lost: the strongest opponent still in the game (most lives, then highest score).
--- Won: the last opponent eliminated (the runner-up). Falls back to any known opponent.
function MP.THREEP.pick_nemesis(won)
	local enemies = (MP.GAME and MP.GAME.enemies) or {}
	local function alive(e) return not e.eliminated and (e.lives == nil or e.lives > 0) end
	local function rival(e) return not (MP.TEAMS and MP.TEAMS.is_teammate(e.id)) end
	local function stronger(a, b)
		if b == nil then return true end
		if (a.lives or 0) ~= (b.lives or 0) then return (a.lives or 0) > (b.lives or 0) end
		local ok, gt = pcall(MP.INSANE_INT.greater_than, a.real_score or MP.INSANE_INT.empty(), b.real_score or MP.INSANE_INT.empty())
		return ok and gt
	end
	if won then
		local order = (MP.GAME and MP.GAME.elim_order) or {}
		for i = #order, 1, -1 do
			if enemies[order[i]] and rival(enemies[order[i]]) then return enemies[order[i]] end
		end
	end
	local best, any = nil, nil
	for _, e in pairs(enemies) do
		if rival(e) then
			any = any or e
			if alive(e) and stronger(e, best) then best = e end
		end
	end
	if best then return best end
	-- nobody alive (or all away): last eliminated, then anyone
	local order = (MP.GAME and MP.GAME.elim_order) or {}
	for i = #order, 1, -1 do
		if enemies[order[i]] and rival(enemies[order[i]]) then return enemies[order[i]] end
	end
	if any then return any end
	return next(enemies) and select(2, next(enemies)) or nil
end

--- Display name for the Game Over nemesis; never "ERROR".
function MP.THREEP.nemesis_name(e)
	local name = e and ((MP.LOBBY.names_by_id and e.id and MP.LOBBY.names_by_id[e.id]) or e.username)
	if name and name ~= "" and name ~= "?" then return name end
	local other = (MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host) or {}
	if other.username and other.username ~= "" then return other.username end
	if MP.GAME and MP.GAME.enemy and MP.GAME.enemy.username and MP.GAME.enemy.username ~= "" then
		return MP.GAME.enemy.username
	end
	return "Opponent"
end

--- Choose the nemesis for this game end and remember its id for targeted requests.
function MP.THREEP.set_game_end_nemesis(won)
	local e = MP.THREEP.pick_nemesis(won)
	MP.GAME.nemesis_id = (e and e.id ~= "legacy") and e.id or nil
	MP.GAME.nemesis_name = MP.THREEP.nemesis_name(e)
	sendInfoMessage("Game over nemesis: " .. tostring(MP.GAME.nemesis_name) .. " (" .. tostring(MP.GAME.nemesis_id) .. ")", "MULTIPLAYER")
	return e
end
