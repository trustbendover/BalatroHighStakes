function G.FUNCS.setup_run_singleplayer(e)
	G.SETTINGS.paused = true
	MP.LOBBY.config.ruleset = nil
	MP.LOBBY.config.gamemode = nil
	MP.SP.ruleset = nil
	MP.SP.practice = false
	MP.GHOST.clear()
	MP.MODIFIERS = {}

	G.FUNCS.overlay_menu({
		definition = G.UIDEF.ruleset_selection_tabs("sp"),
	})
end

function G.FUNCS.start_sp_run(e)
	G.FUNCS.exit_overlay_menu()
	G.FUNCS.setup_run(e)
end

function G.FUNCS.start_vanilla_sp(e)
	MP.LOBBY.config.ruleset = nil
	MP.LOBBY.config.gamemode = nil
	MP.SP.ruleset = nil
	MP.SP.practice = false
	MP.GHOST.clear()
	G.FUNCS.setup_run(e)
end

function G.FUNCS.play_options(e)
	G.SETTINGS.paused = true

	G.FUNCS.overlay_menu({
		definition = G.UIDEF.override_main_menu_play_button(),
	})
end

function G.FUNCS.create_lobby(e)
	G.SETTINGS.paused = true

	-- Clear practice/ghost state so it can't shadow MP reads during lobby setup.
	MP.SP.practice = false
	MP.GHOST.clear()
	MP.MODIFIERS = {}

	G.FUNCS.overlay_menu({
		definition = G.UIDEF.ruleset_selection_tabs("mp"),
	})
end

function G.FUNCS.select_gamemode(e)
	G.SETTINGS.paused = true

	G.FUNCS.overlay_menu({
        definition =  G.UIDEF.gamemode_selection_tabs(),
	})
end

function G.FUNCS.join_lobby(e)
	G.SETTINGS.paused = true

	-- Same isolation as create_lobby; modifiers arrive from the host.
	MP.SP.practice = false
	MP.GHOST.clear()

	G.FUNCS.overlay_menu({
		definition = G.UIDEF.create_UIBox_join_lobby_button(),
	})
	local text_input = G.OVERLAY_MENU:get_UIE_by_ID("text_input")
	G.FUNCS.select_text_input(text_input)
end

function G.FUNCS.weekly_interrupt(e)
	if (not MP.LOBBY.config.weekly) or (MP.LOBBY.config.weekly ~= MP.LOBBY.fetched_weekly) then
		G.SETTINGS.paused = true

		G.FUNCS.overlay_menu({
			definition = G.UIDEF.weekly_interrupt(not not MP.LOBBY.config.weekly),
		})
		return true
	end
	return false
end

function G.FUNCS.set_weekly(e)
	SMODS.Mods["Multiplayer"].config.weekly = MP.LOBBY.fetched_weekly
	SMODS.save_mod_config(SMODS.Mods["Multiplayer"])
	SMODS.restart_game() -- idk if this works well...
end

function G.FUNCS.skip_tutorial(e)
	G.SETTINGS.tutorial_complete = true
	G.SETTINGS.tutorial_progress = nil
	G.FUNCS.play_options(e)
end

function G.FUNCS.join_from_clipboard(e)
	local paste = MP.UTILS.get_from_clipboard()
	if not paste then return end
	-- 3P Steam mode: the clipboard may hold a Steam lobby id / steam://joinlobby link or a code
	if MP.STEAM_P2P and MP.STEAM_P2P.join_text then
		local how = MP.STEAM_P2P.join_text(paste)
		sendInfoMessage("Join from clipboard (Steam mode): " .. tostring(how), "MULTIPLAYER")
		if how then return end
	end
	MP.LOBBY.temp_code = string.sub(string.upper(paste:gsub("[^%a]", "")), 1, 5) -- cursed
	MP.ACTIONS.join_lobby(MP.LOBBY.temp_code)
end

function G.FUNCS.start_lobby(e)
	G.SETTINGS.paused = false

	MP.SP.practice = false
	MP.GHOST.clear()

	MP.reset_lobby_config(true)

	MP.LOBBY.config.multiplayer_jokers = MP.current_ruleset().multiplayer_content

	-- Hide opponent score until you play: default on for standard-layer rulesets
	-- only. Set before force_lobby_options() so a forcing ruleset can override it.
	MP.LOBBY.config.hide_score_until_played = MP.current_ruleset().standard == true

	MP.LOBBY.config.forced_config = MP.current_ruleset():force_lobby_options()

	MP.LOBBY.config.modifier_layers = MP.modifiers_serialize()

	if MP.MODES and MP.MODES.default_lives(MP.LOBBY.config.gamemode) then
		MP.LOBBY.config.starting_lives = MP.MODES.default_lives(MP.LOBBY.config.gamemode)
	end
	-- Versus 2v2/3v3/4v4: the menu entry survives the config reset above
	local fmt = MP.LOBBY.config.gamemode == "gamemode_mp_teams" and tostring(MP.LOBBY.gamemode_entry or ""):match("^teams(%d)$")
	MP.LOBBY.config.teams_format = fmt and tonumber(fmt) or 0
	if fmt then MP.LOBBY.config.teams_size = tonumber(fmt) end
	if MP.LOBBY.config.gamemode == "gamemode_mp_teams" then
		MP.LOBBY.config.teams_size = MP.LOBBY.config.teams_size or 2
		MP.LOBBY.config.teams_order = nil
	end
	if MP.LOBBY.config.gamemode == "gamemode_mp_gambel_time" then
		MP.LOBBY.config.gambel_ante = tonumber(MP.LOBBY.config.gambel_ante) or 8
	end
	if MP.LOBBY.config.gamemode == "gamemode_mp_koth" then
		MP.LOBBY.config.starting_lives = 3 -- King of the Hill: 3 lives (crown shield + bounty lives)
	end
	if MP.LOBBY.config.gamemode == "gamemode_mp_survival" then
		MP.LOBBY.config.starting_lives = 1
		MP.LOBBY.config.disable_live_and_timer_hud = true
	else
		MP.LOBBY.config.disable_live_and_timer_hud = false
	end

	-- Check if the current gamemode is valid. If it's not, default to attrition.
	local gamemode_check = false
	for k, _ in pairs(MP.Gamemodes) do
		if k == MP.LOBBY.config.gamemode then gamemode_check = true end
	end
	MP.LOBBY.config.gamemode = gamemode_check and MP.LOBBY.config.gamemode or "gamemode_mp_attrition"

	MP.LOBBY.config.cocktail = SMODS.Mods["Multiplayer"].config.cocktail

	MP.ACTIONS.create_lobby(string.sub(MP.LOBBY.config.gamemode, 13))
	G.FUNCS.exit_overlay_menu()
end

function G.FUNCS.join_game_submit(e)
	G.FUNCS.exit_overlay_menu()
	MP.ACTIONS.join_lobby(MP.LOBBY.temp_code)
end

function G.FUNCS.join_game_paste(e)
	MP.LOBBY.temp_code = MP.UTILS.get_from_clipboard()
	MP.ACTIONS.join_lobby(MP.LOBBY.temp_code)
	G.FUNCS.exit_overlay_menu()
end

-- Creating forced gamemode buttons for each gamemode, since I am not sure how to pass variables through button presses
for gamemode, _ in pairs(MP.Gamemodes) do
	G.FUNCS["force_" .. gamemode] = function(e)
		MP.LOBBY.config.gamemode = gamemode
		G.FUNCS.start_lobby(e)
	end
end

-- 3P fork: retry the last Steam invite (if accepting it did not get you into the lobby)
function G.FUNCS.mp3p_retry_invite(e)
	if MP.STEAM_P2P and MP.STEAM_P2P.retry_invite then
		sendInfoMessage("Retry Steam invite -> " .. tostring(MP.STEAM_P2P.retry_invite()), "MULTIPLAYER")
	end
end
