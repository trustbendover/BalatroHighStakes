-- Balatro High Stakes: Deathmatch client side (standings, elimination messages, spectating).
-- GPL-3.0. The rules run on the server (networking/p2p_server.lua / server/src/Lobby.ts).
MP.DEATHMATCH = MP.DEATHMATCH or {}
local D = MP.DEATHMATCH

local function L(key, fallback, vars)
	local ok, s = pcall(localize, vars and { type = "variable", key = key, vars = vars } or key)
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then return s end
	if vars then
		for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", tostring(v)) end
	end
	return fallback
end

function D.is_active()
	local g = MP.LOBBY ~= nil and MP.LOBBY.config ~= nil and MP.LOBBY.config.gamemode
	return g == "gamemode_mp_deathmatch" or g == "deathmatch"
end

function D.state() return MP.GAME and MP.GAME.deathmatch or nil end

local function name_of(id, fallback)
	return (MP.LOBBY and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[id]) or fallback or "?"
end

--- Pure: one-line standings, e.g. "Deathmatch: 3 left  |  Bob 3  Ann 2  Cy 1 (away)"
function D.standings_text(st)
	st = st or D.state()
	if not st then return "" end
	if not st.running then
		if st.winnerId then
			return st.winnerId == st.you and L("k_dm_you_won", "Deathmatch over: you are the last one standing!")
				or L("k_dm_won", "Deathmatch over: #1# wins", { name_of(st.winnerId, st.winnerName) })
		end
		return L("k_dm_over", "Deathmatch over")
	end
	local parts = {}
	for _, a in ipairs(st.alive or {}) do
		local s = (a.id == st.you and L("k_koth_you", "You") or name_of(a.id, a.username)) .. " " .. tostring(a.lives or 0)
		if a.away or a.rejoining then
			local word = (MP.PRESENCE and MP.PRESENCE.label(MP.PRESENCE.kind({ away = a.away, rejoining = a.rejoining, eliminated = a.eliminated }), localize))
				or L("k_dm_away", "(away)")
			s = s .. " " .. word
		end
		parts[#parts + 1] = s
	end
	return L("k_dm_left", "Deathmatch: #1# left", { #(st.alive or {}) }) .. "  |  " .. table.concat(parts, "  ")
end

--- Pure: which messages to show for an update given the previous state (tested in tests/test_deathmatch_client.lua)
function D.messages(prev, p)
	local out = {}
	local known = {}
	for _, o in ipairs((prev and prev.out) or {}) do known[o.id] = true end
	local seen = {} -- last known names (a dropped seat may arrive without one)
	for _, a in ipairs((prev and prev.alive) or {}) do seen[a.id] = a.username end
	local n_alive = #(p.alive or {})
	for _, o in ipairs(p.out or {}) do
		if not known[o.id] then
			if o.id == p.you then
				out[#out + 1] = p.running and L("k_dm_you_out", "You are out (place #1#). Watch the standings or return to the lobby.", { o.place or "?" })
					or L("k_dm_you_out_final", "You finished in place #1#", { o.place or "?" })
			elseif p.running then
				out[#out + 1] = L("k_dm_eliminated", "#1# eliminated - #2# left", { name_of(o.id, o.username or seen[o.id]), n_alive })
			end
		end
	end
	if not p.running and p.winnerId then out[#out + 1] = D.standings_text(p) end
	return out
end

--- Place (1 = winner) of a player from the standings, or nil while still alive.
function D.place(st, id)
	st = st or D.state()
	if not st then return nil end
	if st.winnerId == id then return 1 end
	for _, o in ipairs(st.out or {}) do if o.id == id then return o.place end end
	return nil
end

function D.on_update(p)
	if type(p) ~= "table" then return end
	MP.GAME = MP.GAME or {}
	local prev = MP.GAME.deathmatch
	MP.GAME.deathmatch = { you = p.you, alive = p.alive or {}, out = p.out or {}, running = p.running and true or false, winnerId = p.winnerId }
	MP.GAME.deathmatch_text = D.standings_text(MP.GAME.deathmatch)
	-- keep the opponents' lives in the 3P HUD in sync (also for spectators)
	if MP.GAME.enemies then
		for _, a in ipairs(p.alive or {}) do
			local e = MP.GAME.enemies[a.id]
			if e then e.lives = a.lives end
		end
	end
	for i, msg in ipairs(D.messages(prev, p)) do
		pcall(function()
			if G.STAGE == G.STAGES.RUN and G.STATE ~= G.STATES.GAME_OVER then
				G.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.4 + (i - 1) * 1.6, blocking = false, blockable = false,
					func = function()
						attention_text({ text = msg, scale = 0.6, hold = 2.5, major = G.play or G.ROOM_ATTACH, align = "cm",
							offset = { x = 0, y = -2.6 }, backdrop_colour = G.C.RED, silent = false })
						return true
					end }))
			else
				sendWarnMessage(msg, "MULTIPLAYER")
			end
		end)
	end
	pcall(MP.THREEP.refresh_hud)
end

--- Live standings row for the game-over / spectator screen (nil when not in a Deathmatch).
function D.spectate_row()
	if not D.is_active() or not D.state() then return nil end
	MP.GAME.deathmatch_text = D.standings_text()
	return {
		n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK }, nodes = {
			{ n = G.UIT.T, config = { ref_table = MP.GAME, ref_value = "deathmatch_text", scale = 0.35, colour = G.C.WHITE, shadow = true } },
		},
	}
end

return D
