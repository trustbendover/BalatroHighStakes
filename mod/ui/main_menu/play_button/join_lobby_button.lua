function G.UIDEF.create_UIBox_join_lobby_button()
	return (
		create_UIBox_generic_options({
			back_func = "play_options",
			contents = {
				{
					n = G.UIT.R,
					config = {
						padding = 0,
						align = "cm",
					},
					nodes = {
						{
							n = G.UIT.R,
							config = {
								padding = 0.5,
								align = "cm",
							},
							nodes = {
								create_text_input({
									w = 4,
									h = 1,
									max_length = 5,
									all_caps = true,
									prompt_text = localize("k_enter_lobby_code"),
									ref_table = MP.LOBBY,
									ref_value = "temp_code",
									extended_corpus = false,
									keyboard_offset = 4,
									minw = 5,
									callback = function(val)
										MP.ACTIONS.join_lobby(MP.LOBBY.temp_code)
									end,
								}),
							},
						},
						-- 0.6.9: watch a running match (also while your own seat is held)
						{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
							UIBox_button({ button = "mp_join_spectate", colour = G.C.GREEN, minw = 4, minh = 0.7, scale = 0.45,
								label = { (MP.SPECTATE and MP.SPECTATE.L and MP.SPECTATE.L("b_sp_watch", "Watch match")) or "Watch match" } }),
						} },
					},
				},
			},
		})
	)
end

function G.FUNCS.mp_join_spectate(e)
	local code = tostring(MP.LOBBY.temp_code or ""):upper()
	if #code == 5 then MP.ACTIONS.spectate_lobby(code) end
end
