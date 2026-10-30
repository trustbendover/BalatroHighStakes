-- Balatro High Stakes - DEV ONLY. GPL-3.0. Scripted test scenarios on top of autoplay.
-- Every instance runs the same scenario name; each one acts on its own role/name.
--   full_match   : host makes the lobby, guests join + Ready, host starts, bots play to the end
--   host_leave   : as full_match, the host closes Balatro at ante 2 (host migration)
--   guest_rejoin : as full_match, dev2 closes Balatro at ante 2; the launcher starts it again (-RestartAfter)
--   elimination  : 1 life each, so players drop out early and become spectators
--   presets      : host loads the built-in "Quick Duel" preset in the lobby, screenshots the Presets tab
--   ready_gating : guests wait 25 s before Ready; the host tries to Start early (refused) and screenshots the hint
local S = { step = 0, shots = {} }

local function ante() return G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 0 end
local function once(D, key, label) if not S.shots[key] then S.shots[key] = true; D.shot(label or key) end end
-- blind-select texts ("Choose your next Blind") pop in letter by letter: shoot a bit later
S.pending = {}
local function later(D, key, label, t, delay)
	if S.shots[key] or S.pending[key] then return end
	S.pending[key] = { at = t + (delay or 2.5), label = label }
end
local function flush(D, t)
	for k, p in pairs(S.pending) do if t >= p.at then S.pending[k] = nil; once(D, k, p.label) end end
end

function S.setup(D)
	if D.scenario == "ready_gating" and D.role == "guest" then D.ready_after = 25 end
	D.on_action = function() end
end

function S.tick(D, dt, t)
	if S.step == 0 then S.setup(D); S.step = 1 end
	local menu = G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
	local in_lobby = MP.LOBBY and MP.LOBBY.code
	-- 1. host creates the lobby; guests join with the code the host wrote to the shared folder
	if S.step == 1 and menu and not in_lobby and t > 6 and not G.OVERLAY_MENU then
		if D.role == "host" then
			MP.LOBBY.config.ruleset = MP.LOBBY.config.ruleset or "ruleset_mp_blitz"
			MP.LOBBY.config.gamemode = "gamemode_mp_" .. D.mode
			D.log("scenario: creating lobby " .. D.mode)
			G.FUNCS.start_lobby(nil)
			S.step = 2
		else
			local code = D.read_code()
			if code then D.log("scenario: joining " .. code); MP.ACTIONS.join_lobby(code); S.step = 2; S.join_t = t end
		end
	end
	if S.step == 2 and in_lobby then
		S.step = 3
		if D.role == "host" then
			D.write_code(MP.LOBBY.code)
			if D.scenario == "elimination" then MP.LOBBY.config.starting_lives = 1; MP.ACTIONS.lobby_options() end
		end
		S.lobby_t = t
	elseif S.step == 2 and D.role == "guest" and S.join_t and t - S.join_t > 15 then
		S.step = 1 -- not in yet: try again (host still starting)
	end
	if S.step == 3 and in_lobby then
		if t - S.lobby_t > 3 then once(D, "lobby") end
		if D.role == "host" and D.scenario == "presets" and not S.preset_done and t - S.lobby_t > 5 and MP.PRESETS then
			S.preset_done = true
			MP.PRESETS.apply({ options = MP.PRESETS.BUILTIN[2].options, log_id = "built-in quick" }, "Quick Duel")
			MP.PRESETS.reopen()
			S.preset_shot_at = t + 1.5
		end
		if S.preset_shot_at and t > S.preset_shot_at then S.preset_shot_at = nil; D.shot("presets_tab"); G.FUNCS.exit_overlay_menu() end
		if D.role == "host" and D.scenario == "ready_gating" and not S.gate_done and t - S.lobby_t > 12 then
			S.gate_done = true
			D.shot("waiting_for_ready")
			MP.ACTIONS.start_game() -- the host core must refuse this (guests not ready)
			D.log("scenario: early start sent (expect 'Waiting for N player(s) to ready up')")
		end
	end
	-- 2. in the run
	if G.STAGE == G.STAGES.RUN then
		S.step = math.max(S.step, 4)
		once(D, "run_start", "run_start")
		local a = ante()
		if a >= 2 then later(D, "ante2", "ante2", t) end
		if MP.GAME and MP.GAME.pvp_reached then later(D, "pvp_" .. a, "pvp_ante" .. a, t) end
		-- host migration: this instance became host (or the host changed) during the run
		local h = MP.LOBBY and MP.LOBBY.is_host and true or false
		if S.was_host ~= nil and S.was_host ~= h then later(D, "migrated_" .. tostring(h), h and "now_host" or "after_host_migration", t, 4) end
		S.was_host = h
		if a >= 2 and not S.quit_at then
			if (D.scenario == "host_leave" and D.role == "host") or (D.scenario == "guest_rejoin" and D.name == "dev2") then
				S.quit_at = t + 3
				D.log("scenario: closing Balatro in 3 s (" .. D.scenario .. ")")
			end
		end
		if S.quit_at and t > S.quit_at then S.quit_at = math.huge; love.event.quit() end
	end
	if MP.UI and MP.UI.sentinel_label_hidden and G.STATE ~= G.STATES.GAME_OVER then once(D, "blind_sentinel") end
	if G.STATE == G.STATES.SELECTING_HAND and G.GAME.blind and type(G.GAME.blind.chips) == "number" and G.GAME.blind.chips > 0 and not (MP.is_pvp_boss and MP.is_pvp_boss()) then later(D, "blind_normal", "blind_normal", t, 1.0) end
	if MP.SPECTATE and MP.SPECTATE.watching and MP.SPECTATE.watching() then later(D, "spectating", "spectating", t, 1.5) end
	if G.STATE == G.STATES.GAME_OVER then later(D, "game_over", "game_over", t, 2) end
	flush(D, t)
end

return S
