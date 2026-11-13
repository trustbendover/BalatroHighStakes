local Disableable_Toggle = MP.UI.Disableable_Toggle

function G.FUNCS.lobby_info(e)
	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu({
		definition = MP.UI.lobby_info(),
	})
end

function MP.UI.lobby_info()
	return create_UIBox_generic_options({
		contents = {
			create_tabs({
				tabs = {
					{
						label = localize("b_players"),
						chosen = true,
						tab_definition_function = MP.UI.create_UIBox_players,
					},
					{
						label = localize("b_lobby_info"),
						chosen = false,
						tab_definition_function = MP.UI.create_UIBox_settings, -- saying settings because _options is used in lobby
					},
				},
				tab_h = 8,
				snap_to_nav = true,
			}),
		},
	})
end

function MP.UI.create_UIBox_settings() -- optimize this please
	local ruleset = string.sub(MP.LOBBY.config.ruleset, 12, -1)
	local gamemode = string.sub(MP.LOBBY.config.gamemode, 13, -1)
	local seed = MP.LOBBY.config.custom_seed == "random" and localize("k_random") or MP.LOBBY.config.custom_seed
	return {
		n = G.UIT.ROOT,
		config = {
			emboss = 0.05,
			minh = 6,
			r = 0.1,
			minw = 10,
			align = "tm",
			padding = 0.2,
			colour = G.C.BLACK,
		},
		nodes = {
			MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
				MP.UI.UTILS.create_text_node((localize("k_" .. ruleset) .. " " .. ((MP.MODES and MP.MODES.display_name) and MP.MODES.full_name("gamemode_mp_" .. gamemode) or localize("k_" .. gamemode))), {
					colour = G.C.UI.TEXT_LIGHT,
					scale = 0.6,
				}),
			}),
			MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
				MP.UI.UTILS.create_text_node((localize("k_current_seed") .. seed), {
					colour = G.C.UI.TEXT_LIGHT,
					scale = 0.6,
				}),
			}),
			MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
				MP.UI.UTILS.create_text_node((function()
					local key = (MP.LOBBY.config.lobby_public and "k_lobby_public_on") or "k_lobby_public_off"
					local s = localize(key)
					if type(s) ~= "string" or s == "ERROR" or s == key then
						return MP.LOBBY.config.lobby_public and "Public lobby" or "Private lobby"
					end
					return s
				end)(), {
					colour = G.C.UI.TEXT_LIGHT,
					scale = 0.5,
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_cb_money"),
					ref_table = MP.LOBBY.config,
					ref_value = "gold_on_life_loss",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_no_gold_on_loss"),
					ref_table = MP.LOBBY.config,
					ref_value = "no_gold_on_round_loss",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_death_on_loss"),
					ref_table = MP.LOBBY.config,
					ref_value = "death_on_round_loss",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_diff_seeds"),
					ref_table = MP.LOBBY.config,
					ref_value = "different_seeds",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_player_diff_deck"),
					ref_table = MP.LOBBY.config,
					ref_value = "different_decks",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_multiplayer_jokers"),
					ref_table = MP.LOBBY.config,
					ref_value = "multiplayer_jokers",
				}),
			}),
			MP.UI.UTILS.create_row({ padding = 0, align = "cr" }, {
				Disableable_Toggle({
					enabled_ref_table = MP.LOBBY,
					label = localize("b_opts_normal_bosses"),
					ref_table = MP.LOBBY.config,
					ref_value = "normal_bosses",
				}),
			}),
		},
	}
end

function MP.UI.create_UIBox_players()
	local players = {}
	for i = 1, math.max(2, MP.THREEP.seat_count()) do
		players[#players + 1] = MP.UI.create_UIBox_player_row("seat" .. i)
	end

	local t = {
		n = G.UIT.ROOT,
		config = { align = "cm", minw = 3, padding = 0.1, r = 0.1, colour = G.C.CLEAR },
		nodes = {
			MP.UI.UTILS.create_row({ align = "cm", padding = 0.04 }, players),
		},
	}

	return t
end

function MP.UI.create_UIBox_mods_list(type)
	return {
		n = G.UIT.R,
		config = { align = "cm", colour = G.C.WHITE, r = 0.1 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm" },
				nodes = MP.UI.modlist_to_view(
					MP.THREEP.lobby_player(type).config.Mods,
					G.C.UI.TEXT_DARK
				),
			},
		},
	}
end

function MP.UI.create_UIBox_player_row(type)
	local seat = MP.THREEP.lobby_player(type)
	local lives = MP.GAME.enemy.lives
	local highest_score = MP.GAME.enemy.highest_score
	local skips = MP.GAME.enemy.skips or 0
	-- 3P fork: look up this row's opponent by server id before any label that reads them.
	local idx = MP.THREEP.seat_index(type)
	local pl = MP.LOBBY.player_list and MP.LOBBY.player_list[idx]
	local is_me = (pl and MP.LOBBY.my_id and pl.id == MP.LOBBY.my_id)
		or (not pl and ((idx == 1 and MP.LOBBY.is_host) or (idx == 2 and not MP.LOBBY.is_host)))
	local e = pl and MP.GAME.enemies and MP.GAME.enemies[pl.id]
	local player_name = (MP.TEAMS and MP.TEAMS.seat_label and seat.username) and MP.TEAMS.seat_label(seat) or seat.username or "?"
	if MP.PRESENCE then
		local kind = MP.PRESENCE.kind({
			spectator = (pl and pl.spectator) or seat.spectator,
			rejoining = (e and e.rejoining) or (pl and pl.rejoining) or seat.rejoining,
			away = e and e.away, eliminated = e and e.eliminated and e.away, connected = true,
		})
		local word = MP.PRESENCE.label(kind, localize)
		if word ~= "" then player_name = player_name .. " · " .. word end
	end
	if e and not is_me then
		lives = e.lives or lives
		highest_score = e.real_score or highest_score
		skips = e.skips or skips
	end
	if is_me then
		lives = MP.GAME.lives
		highest_score = MP.GAME.highest_score
		skips = G.GAME.skips or 0
	end
	return {
		n = G.UIT.R,
		config = {
			align = "cm",
			padding = MP.THREEP.seat_count() > 4 and 0.04 or 0.1,
			r = 0.1,
			colour = darken(G.C.JOKER_GREY, 0.1),
			emboss = 0.05,
			hover = true,
			force_focus = true,
			on_demand_tooltip = {
				text = { localize("k_mods_list") },
				filler = { func = MP.UI.create_UIBox_mods_list, args = type },
			},
		},
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm" },
				nodes = {
					{
						n = G.UIT.C,
						config = {
							align = "cm",
							padding = 0.05,
							r = 0.1,
							colour = G.C.MULT,
							minw = 2,
							maxw = 2,
							outline = 0.5,
							outline_colour = G.C.MULT,
							emboss = 0.07,
						},
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = tostring(lives) .. " " .. localize("k_lives"),
									scale = 0.375,
									colour = G.C.UI.TEXT_LIGHT,
									shadow = true,
								},
							},
						},
					},
				},
			},
			{
				n = G.UIT.C,
				config = { align = "cl", padding = 0, minw = 4 },
				nodes = {
					{
						n = G.UIT.C,
						config = { align = "cm", minw = 4.5, maxw = 4.5 },
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = "" .. player_name,
									scale = 0.4,
									maxw = 4.4,
									colour = G.C.UI.TEXT_LIGHT,
									shadow = true,
								},
							},
						},
					},
				},
			},
			(MP.LOBBY.config.timer_display_threshold or 0) <= 0 and {
				n = G.UIT.C,
				config = { align = "cm" },
				nodes = {
					{
						n = G.UIT.C,
						config = {
							align = "cm",
							padding = 0.05,
							r = 0.1,
							colour = G.C.PURPLE,
							minw = 1.75,
							maxw = 1.75,
							outline = 0.5,
							outline_colour = G.C.PURPLE,
							emboss = 0.07,
						},
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = tostring(skips) .. " " .. localize("k_skips"),
									scale = 0.375,
									colour = G.C.UI.TEXT_LIGHT,
                                    shadow = true,
								},
							},
						},
					},
                    -- Let's keep it for future, just in case
					-- {
					-- 	n = G.UIT.C,
					-- 	config = { align = "cr", padding = 0.01, r = 0.1, colour = G.C.CHIPS, minw = 1.1 },
					-- 	nodes = {
					-- 		{
					-- 			n = G.UIT.T,
					-- 			config = {
					-- 				text = "???", -- Will be hands in the future
					-- 				scale = 0.45,
					-- 				colour = G.C.UI.TEXT_LIGHT,
					-- 			},
					-- 		},
					-- 		{ n = G.UIT.B, config = { w = 0.08, h = 0.01 } },
					-- 	},
					-- },
					-- {
					-- 	n = G.UIT.C,
					-- 	config = { align = "cl", padding = 0.01, r = 0.1, colour = G.C.MULT, minw = 1.1 },
					-- 	nodes = {
					-- 		{ n = G.UIT.B, config = { w = 0.08, h = 0.01 } },
					-- 		{
					-- 			n = G.UIT.T,
					-- 			config = {
					-- 				text = "???", -- Will be discards in the future
					-- 				scale = 0.45,
					-- 				colour = G.C.UI.TEXT_LIGHT,
					-- 			},
					-- 		},
					-- 	},
					-- },
				},
			} or nil,
			{
				n = G.UIT.C,
				config = { align = "cm", padding = 0.05, colour = G.C.L_BLACK, r = 0.1, minw = 3, maxw = 3 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = (MP.UI.aij_blind_drawn and MP.UI.aij_blind_drawn() and not ((type == "host" and MP.LOBBY.is_host) or (type == "guest" and not MP.LOBBY.is_host)))
								and "???" or MP.INSANE_INT.to_string(highest_score), -- All in Jest "Blind Drawn"
							scale = 0.425,
							colour = G.C.FILTER,
							shadow = true,
						},
					},
				},
			},
		},
	}
end
