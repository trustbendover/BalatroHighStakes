-- Gambel Time. One player faces The House. Two to eight play a free-for-all:
-- every boss is a Nemesis, and the host's Chaos Spin changes that boss.
MP.Gamemode({
	key = "gambel_time",
	get_blinds_by_ante = function(self, ante)
		-- Seated players only. player_count also counts spectators, and a watcher must not force a Nemesis.
		local n = 0
		local list = MP.LOBBY and MP.LOBBY.player_list
		if type(list) == "table" then
			for _, pl in ipairs(list) do
				if type(pl) ~= "table" or not pl.spectator then n = n + 1 end
			end
		end
		local away = MP.LOBBY and MP.LOBBY.away
		if type(away) == "table" then
			for _, pl in ipairs(away) do
				if type(pl) ~= "table" or not pl.spectator then n = n + 1 end
			end
		end
		if n == 0 then n = tonumber(MP.LOBBY and MP.LOBBY.player_count) or 1 end
		if n <= 1 then return nil, nil, nil end
		return nil, nil, "bl_mp_nemesis"
	end,
	banned_jokers = {
		"j_mr_bones",
		"j_luchador",
		"j_matador",
		"j_chicot",
	},
	banned_consumables = {},
	banned_vouchers = {
		"v_hieroglyph",
		"v_petroglyph",
		"v_directors_cut",
		"v_retcon",
	},
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
							text = select(1, MP.UTILS.mode_desc("k_gambel_time_description")),
							scale = select(2, MP.UTILS.mode_desc("k_gambel_time_description")),
							colour = G.C.UI.TEXT_LIGHT,
						},
					},
				},
			},
		}
	end,
}):inject()
