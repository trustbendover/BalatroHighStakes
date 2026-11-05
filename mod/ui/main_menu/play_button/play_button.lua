function G.UIDEF.override_main_menu_play_button()
	if not G.SETTINGS.tutorial_complete or G.SETTINGS.tutorial_progress ~= nil then
		return (
			create_UIBox_generic_options({
				contents = {
					UIBox_button({
						label = { localize("b_singleplayer") },
						colour = G.C.BLUE,
						button = "setup_run_singleplayer",
						minw = 5,
					}),
					{
						n = G.UIT.R,
						config = {
							align = "cm",
							padding = 0.5,
						},
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = localize("k_tutorial_not_complete"),
									colour = G.C.UI.TEXT_LIGHT,
									scale = 0.45,
								},
							},
						},
					},
					UIBox_button({
						label = { localize("b_skip_tutorial") },
						colour = G.C.RED,
						button = "skip_tutorial",
						minw = 5,
					}),
				},
			})
		)
	end

	return (
		create_UIBox_generic_options({
			contents = {
				UIBox_button({
					label = { localize("b_singleplayer") },
					colour = G.C.BLUE,
					button = "start_vanilla_sp",
					minw = 5,
				}),
				UIBox_button({
					label = { localize("b_sp_with_ruleset") },
					colour = G.C.ORANGE,
					button = "setup_practice_mode",
					minw = 5,
				}),
				MP.LOBBY.connected and UIBox_button({
					label = { localize("b_create_lobby") },
					colour = G.C.GREEN,
					button = "create_lobby",
					minw = 5,
				}) or nil,
				MP.LOBBY.connected and UIBox_button({
					label = { localize("b_join_lobby") },
					colour = G.C.RED,
					button = "join_lobby",
					minw = 5,
					minh = 0.7,
				}) or nil,
				MP.LOBBY.connected and UIBox_button({
					label = { localize("b_public_lobbies") },
					colour = G.C.BLUE,
					button = "mp_open_browser",
					minw = 5,
					minh = 0.7,
				}) or nil,
				MP.LOBBY.connected and UIBox_button({
					label = { localize("b_join_lobby_clipboard") },
					colour = G.C.PURPLE,
					button = "join_from_clipboard",
					minw = 5,
					minh = 0.7,
				}) or nil,
				MP.LOBBY.connected and MP.STEAM_P2P and MP.STEAM_P2P.last_invite and UIBox_button({
					label = { "Join Steam invite again" },
					colour = G.C.BLUE,
					button = "mp3p_retry_invite",
					minw = 5,
					minh = 0.7,
				}) or nil,
				MP.SAFE_MODE and {
					n = G.UIT.R,
					config = { align = "cm", padding = 0.2 },
					nodes = { { n = G.UIT.T, config = {
						text = (MP.COMPAT_GUARD and MP.COMPAT_GUARD.note and MP.COMPAT_GUARD.note()) or "Multiplayer is off (safe mode)",
						colour = G.C.UI.TEXT_INACTIVE, scale = 0.4 } } },
				} or nil,
				not MP.LOBBY.connected and not MP.SAFE_MODE and UIBox_button({
					label = { localize("b_reconnect") },
					colour = G.C.RED,
					button = "reconnect",
					minw = 5,
				}) or nil,
			},
		})
	)
end
