-- Heat Rush. One player races the clock. Two to eight play a free-for-all
-- with the same blinds as Attrition, plus a Heat meter.
MP.Gamemode({
	key = "heat_rush",
	get_blinds_by_ante = function(self, ante)
		local n = 0
		local list = MP.LOBBY and MP.LOBBY.player_list
		if type(list) == "table" then
			for _, pl in ipairs(list) do
				if type(pl) ~= "table" or not pl.spectator then n = n + 1 end
			end
		end
		if n == 0 then n = tonumber(MP.LOBBY and MP.LOBBY.player_count) or 1 end
		if n <= 1 then return nil, nil, nil end
		local boss, effects = MP.MATCH.pvp_boss(ante, MP.LOBBY.config)
		if effects and G.GAME and G.GAME.round_resets and G.GAME.round_resets.pvp_blind_choices then
			G.GAME.round_resets.pvp_blind_choices.Boss = true
		end
		return nil, nil, boss
	end,
	banned_jokers = { "j_mr_bones", "j_luchador", "j_matador", "j_chicot" },
	banned_consumables = {},
	banned_vouchers = { "v_hieroglyph", "v_petroglyph", "v_directors_cut", "v_retcon" },
	banned_enhancements = {},
	banned_tags = { "tag_boss" },
	banned_blinds = { "bl_wall", "bl_final_vessel" },
	reworked_jokers = {},
	reworked_consumables = {},
	reworked_vouchers = {},
	reworked_enhancements = {},
	reworked_tags = {},
	reworked_blinds = {},
	create_info_menu = function()
		return {
			{
				n = G.UIT.R,
				config = { align = "tm" },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = select(1, MP.UTILS.mode_desc("k_heat_rush_description")),
							scale = select(2, MP.UTILS.mode_desc("k_heat_rush_description")),
							colour = G.C.UI.TEXT_LIGHT,
						},
					},
				},
			},
		}
	end,
}):inject()
