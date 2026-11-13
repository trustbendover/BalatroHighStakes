-- 0.6.8: grouped Gamemodes menu. Versus = fixed formats (2v2-4v4 are Teams with a fixed team size),
-- Free-for-all = everyone against everyone, Challenge = co-op style.
MP.UI.GAMEMODE_GROUPS = {
	{ name = "k_versus", entries = { "duel", "teams2", "teams3", "teams4", "teams" } },
	{ name = "k_ffa", entries = { "attrition", "showdown", "koth", "deathmatch", "gambel_time" } },
	{ name = "k_challenge", entries = { "survival" } },
}
--- menu entry -> gamemode key + Versus team format (nil for a plain mode)
function MP.UI.gamemode_entry(entry)
	local f = tostring(entry):match("^teams(%d)$")
	if f then return "teams", tonumber(f) end
	return entry, nil
end
function MP.UI.gamemode_entry_label(entry)
	local mode, f = MP.UI.gamemode_entry(entry)
	if f then return f .. "v" .. f end
	return localize("k_" .. mode)
end
function MP.UI.gamemode_entry_sub(entry)
	local mode, f = MP.UI.gamemode_entry(entry)
	return MP.MODES.subtitle("gamemode_mp_" .. mode, { teams_format = f or 0 })
end
function MP.UI.gamemode_menu_groups()
	local out = {}
	for _, g in ipairs(MP.UI.GAMEMODE_GROUPS) do
		local buttons = {}
		for _, e in ipairs(g.entries) do
			buttons[#buttons + 1] = { button_id = e .. "_gamemode_button", button_localize_key = "k_" .. e, label = MP.UI.gamemode_entry_label(e) }
		end
		out[#out + 1] = { name = g.name, buttons = buttons }
	end
	return out
end
--- select a menu entry in the lobby config
function MP.UI.select_gamemode_entry(entry)
	local mode, f = MP.UI.gamemode_entry(entry)
	MP.LOBBY.config.gamemode = "gamemode_mp_" .. mode
	MP.LOBBY.config.teams_format = f or 0
	if f then MP.LOBBY.config.teams_size = f end
	MP.LOBBY.gamemode_entry = entry
end

function G.UIDEF.gamemode_selection_options()
	MP.UI.select_gamemode_entry("duel")

	local default_gamemode_area = UIBox({
		definition = G.UIDEF.gamemode_info("duel"),
		config = { align = "cm" },
	})

	local gamemode_buttons_data = MP.UI.gamemode_menu_groups()

	return MP.UI.Main_Lobby_Options(
		"gamemode_area",
		default_gamemode_area,
		"change_gamemode_selection",
		gamemode_buttons_data
	)
end

function G.UIDEF.gamemode_selection_tabs()
    local tabs = {
        {
            label = localize("k_gamemodes"),
            tab_definition_function = function()
                return G.UIDEF.gamemode_selection_options()
            end,
            chosen = true,
        }
    }
    local t = create_UIBox_generic_options({
		back_func = "create_lobby",
		contents = {
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0 },
				nodes = {
					create_tabs({
						tabs = tabs,
						colour = G.C.BOOSTER,
					}),
				},
			},
		},
	})
    return t
end

function G.FUNCS.change_gamemode_selection(e)
	MP.UI.Change_Main_Lobby_Options(
		e,
		"gamemode_area",
		G.UIDEF.gamemode_info,
		"duel_gamemode_button",
		function(entry) MP.UI.select_gamemode_entry(entry) end
	)
end

function G.UIDEF.gamemode_info(entry)
	local gamemode_name, fmt = MP.UI.gamemode_entry(entry)
	local gamemode = MP.Gamemodes["gamemode_mp_" .. gamemode_name]
	MP.UI.gamemode_card_entry = entry

	local gamemode_info_tabs = UIBox({
		definition = G.UIDEF.gamemode_tabs(gamemode),
		config = { align = "cm" },
	})

	return {
		n = G.UIT.ROOT,
		config = { align = "tm", minh = 8, maxh = 8, minw = 11, maxw = 11, colour = G.C.CLEAR },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "tm", padding = 0.2, r = 0.1, colour = G.C.BLACK },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cm" },
						nodes = {
							{ n = G.UIT.O, config = { object = gamemode_info_tabs } },
						},
					},
					{
						n = G.UIT.R,
						config = { align = "cm" },
						nodes = {
							{
								n = G.UIT.R,
								config = {
									id = "start_lobby_button",
									button = "start_lobby",
									align = "cm",
									padding = 0.05,
									r = 0.1,
									minw = 8,
									minh = 0.8,
									colour = G.C.BLUE,
									hover = true,
									shadow = true,
								},
								nodes = {
									{
										n = G.UIT.T,
										config = {
											text = localize("b_create_lobby"),
											scale = 0.5,
											colour = G.C.UI.TEXT_LIGHT,
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
end

function MP.UI.remember_gamemode_tabs(a) MP.UI.last_gamemode_tabs = a; return a end
function G.UIDEF.gamemode_tabs(gamemode)
	local default_tabs = UIBox({
		definition = G.UIDEF.lobby_setup_tabs_definition(gamemode, "overview", 1, false),
		config = { align = "cm", tab_type = "overview", chosen_tab = 1 },
	})

	return {
		n = G.UIT.ROOT,
		config = { align = "cm", colour = G.C.L_BLACK, r = 0.1 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm" },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "tm", colour = G.C.GREY, r = 0.1 },
						nodes = {
							{ n = G.UIT.O, config = { object = default_tabs } },
						},
					},
					{
						n = G.UIT.R,
						config = { align = "bm", padding = 0.05 },
						nodes = {
							create_option_cycle({
								options = { localize("k_mode_overview"), localize("k_info"), localize("k_bans"), localize("k_reworks") },
								current_option = 1,
								opt_callback = "gamemode_switch_tabs",
								opt_args = MP.UI.remember_gamemode_tabs({ ui = default_tabs, gamemode = gamemode }),
								w = 5,
								colour = G.C.ORANGE,
								cycle_shoulders = false,
							}),
						},
					},
				},
			},
		},
	}
end

function G.FUNCS.gamemode_switch_tabs(args)
	if not args or not args.cycle_config then return end
	local callback_args = args.cycle_config.opt_args

	local tabs_object = callback_args.ui
	local tabs_wrap = tabs_object.parent

	local active_tab = tabs_wrap.UIBox:get_UIE_by_ID("gamemode_active_tab")
	local active_tab_idx = active_tab and active_tab.config.tab_idx or 1

	local tab_type = (args.to_key == 2 and "rules") or (args.to_key == 3 and "banned") or (args.to_key == 4 and "rework") or "overview"
	local def = G.UIDEF.lobby_setup_tabs_definition(callback_args.gamemode, tab_type, active_tab_idx, false)

	tabs_object.config.tab_type = tab_type
	MP.LOBBY.config.gamemode = callback_args.gamemode.key
	MP.LOBBY.gamemode_preview = (tab_type == "rework")

	tabs_wrap.config.object:remove()
	tabs_wrap.config.object = UIBox({
		definition = def,
		config = { align = "cm", parent = tabs_wrap },
	})

	tabs_wrap.UIBox:recalculate()
end

--- 0.6.8 mode card. "overview": name, player count, one short line and the blind chips;
--- "rules": the full rules text only (so long text never overlaps the graphic).
function MP.UI.gamemode_card_nodes(gamemode, tab_type)
	local key = MP.MODES.key(gamemode.key)
	local entry = MP.UI.gamemode_card_entry
	local _, fmt = MP.UI.gamemode_entry(entry or key)
	if MP.UI.gamemode_entry(entry or key) ~= key then entry, fmt = key, nil end
	entry = entry or key
	local CARD_W = 10.2
	local function text_row(text, scale, colour)
		return { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
			{ n = G.UIT.T, config = { text = text, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT } } } }
	end
	local function add_lines(nodes, text, scale, colour, max_lines)
		if type(text) ~= "string" or text == "" then return end
		local lines, sc = MP.UTILS.fit_lines(text, scale, CARD_W, max_lines)
		for _, line in ipairs(lines) do nodes[#nodes + 1] = text_row(line, sc, colour) end
	end
	if tab_type == "rules" then
		local rk = "k_" .. key .. "_rules"
		local ok, v = pcall(localize, rk)
		if not ok or type(v) ~= "string" or v == "ERROR" or v == rk then
			rk = "k_" .. key .. "_description"
			ok, v = pcall(localize, rk)
		end
		local nodes = {}
		if ok and type(v) == "string" then add_lines(nodes, v, 0.4, G.C.UI.TEXT_LIGHT, 10) end
		return nodes
	end
	local nodes = {
		text_row(MP.UI.gamemode_entry_label(entry), 0.75, G.C.WHITE),
		{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			{ n = G.UIT.C, config = { align = "cm", colour = G.C.BLUE, r = 0.1, padding = 0.08 }, nodes = {
				{ n = G.UIT.T, config = { text = MP.MODES.players_label(key, fmt), scale = 0.4, colour = G.C.WHITE } } } } } },
	}
	add_lines(nodes, localize("k_" .. entry .. "_short"), 0.45, G.C.UI.TEXT_LIGHT, 3)
	local win_key = "k_" .. entry .. "_win"
	local win_ok, win_text = pcall(localize, win_key)
	if win_ok and type(win_text) == "string" and win_text ~= "" and win_text ~= "ERROR" and win_text ~= win_key then
		add_lines(nodes, win_text, 0.38, G.C.GOLD or G.C.UI.TEXT_LIGHT, 3)
	end
	local info = gamemode:create_info_menu()
	for i = 3, #info do nodes[#nodes + 1] = info[i] end
	return nodes
end
