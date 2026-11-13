local Disableable_Toggle = MP.UI.Disableable_Toggle

-- TODO repetition but w/e...
function send_lobby_options(value)
	MP.ACTIONS.lobby_options()
end

function create_lobby_option_cycle(id, label_key, scale, options, current_option, callback)
	return MP.UI.Disableable_Option_Cycle({
		id = id,
		enabled_ref_table = MP.LOBBY,
		enabled_ref_value = "is_host",
		label = localize(label_key),
		scale = scale,
		options = options,
		current_option = current_option,
		opt_callback = callback,
	})
end

-- Component for lobby options tab containing toggles and custom seed section
function create_lobby_option_toggle(id, label_key, ref_value, callback, label_text)
	local label = label_text
	if not label then
		label = localize(label_key)
		if type(label) ~= "string" or label == "" or label == "ERROR" or label == label_key then label = label_key end
	end
	return {
		n = G.UIT.R,
		config = {
			padding = 0,
			align = "cr",
		},
		nodes = {
			Disableable_Toggle({
				id = id,
				enabled_ref_table = MP.LOBBY,
				enabled_ref_value = "is_host",
				label = label,
				ref_table = MP.LOBBY.config,
				ref_value = ref_value,
				callback = callback or send_lobby_options,
			}),
		},
	}
end

G.FUNCS.change_starting_lives = function(args)
	MP.LOBBY.config.starting_lives = args.to_val
	send_lobby_options()
end

G.FUNCS.change_gambel_ante = function(args)
	MP.LOBBY.config.gambel_ante = args.to_val
	send_lobby_options()
end

-- This needs to have a parameter because its a callback for inputs
local function send_lobby_options(value)
	MP.ACTIONS.lobby_options()
end

-- Creates the lobby options tab UI containing toggles for various multiplayer settings
-- Returns a UI table with lobby configuration options like gold on life loss, different seeds, etc.
function MP.UI.create_lobby_options_tab()
	return {
		n = G.UIT.ROOT,
		config = {
			emboss = 0.05,
			minh = 4,
			r = 0.1,
			minw = 10,
			align = "tm",
			padding = 0.2,
			colour = G.C.BLACK,
		},
		nodes = {
			create_lobby_option_toggle("lobby_public_toggle", "b_lobby_public", "lobby_public", nil, (function()
				local s = localize("b_lobby_public")
				if type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= "b_lobby_public" then return s end
				return (G.SETTINGS and G.SETTINGS.language == "nl") and "Openbare lobby" or "Public lobby"
			end)()),
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0.02 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = (function()
								local s = localize("k_lobby_public_desc1")
								if type(s) ~= "string" or s == "ERROR" then
									return "Off: hidden on your Steam friends list, not marked for a lobby browser."
								end
								return s
							end)(),
							scale = 0.28,
							colour = G.C.UI.TEXT_LIGHT,
							maxw = 9.2,
						},
					},
				},
			},
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0.02 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = (function()
								local s = localize("k_lobby_public_desc2")
								if type(s) ~= "string" or s == "ERROR" then
									return "The lobby code and Steam invites still work either way."
								end
								return s
							end)(),
							scale = 0.28,
							colour = G.C.UI.TEXT_LIGHT,
							maxw = 9.2,
						},
					},
				},
			},
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0.04 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = (function()
								local s = localize("k_lobby_public_desc3")
								if type(s) ~= "string" or s == "ERROR" then
									return "On: the public lobby list can show this lobby. The code is not a password."
								end
								return s
							end)(),
							scale = 0.28,
							colour = G.C.UI.TEXT_LIGHT,
							maxw = 9.2,
						},
					},
				},
			},
			create_lobby_option_cycle(
				"starting_lives_option",
				"b_opts_lives",
				0.85,
				{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
				MP.LOBBY.config.starting_lives,
				"change_starting_lives"
			),
			(function()
				if MP.LOBBY.config.gamemode ~= "gamemode_mp_gambel_time" then
					return { n = G.UIT.R, config = { minh = 0.01 }, nodes = {} }
				end
				return create_lobby_option_cycle(
					"gambel_ante_option",
					"k_gambel_time",
					0.85,
					{ 4, 5, 6, 7, 8, 9, 10, 11, 12 },
					tonumber(MP.LOBBY.config.gambel_ante) or 8,
					"change_gambel_ante"
				)
			end)(),
			create_lobby_option_toggle("multiplayer_jokers_toggle", "b_opts_multiplayer_jokers", "multiplayer_jokers"),
			create_lobby_option_toggle("different_decks_toggle", "b_opts_player_diff_deck", "different_decks", function()
				send_lobby_options()
				MP.ACTIONS.update_player_usernames()
			end),
			create_lobby_option_toggle("random_loadout_toggle", "b_opts_random_loadout", "random_loadout", function()
				send_lobby_options()
				MP.ACTIONS.update_player_usernames()
			end),
			create_lobby_option_toggle("normal_bosses_toggle", "b_opts_normal_bosses", "normal_bosses"),
			create_lobby_option_toggle(
				"hide_score_until_played_toggle",
				"b_opts_hide_score",
				"hide_score_until_played"
			),
		},
	}
end
