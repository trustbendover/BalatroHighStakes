local function presence_label(player)
	if not (player and MP.PRESENCE) then return "" end
	local kind = MP.PRESENCE.kind({
		spectator = player.spectator, rejoining = player.rejoining, held = player.held, away = player.away,
		eliminated = player.eliminated, connected = true,
	})
	return MP.PRESENCE.label(kind, localize, player.grace)
end

local function create_player_info_row(player, player_type, text_scale)
	if not player or not player.username then return nil end
	player.display_name = (MP.TEAMS and MP.TEAMS.seat_label) and MP.TEAMS.seat_label(player) or player.username
	player.status_text = presence_label(player)

	return MP.UI.UTILS.create_row({ padding = MP.THREEP.seat_count() > 4 and 0.03 or 0.1, align = "cm" }, {
        MP.UI.UTILS.create_column({ align = "cm", maxw = 3 }, {
            MP.UI.UTILS.create_text_node(nil, {
                ref_table = player,
                ref_value = "display_name",
                scale = text_scale * (MP.THREEP.seat_count() > 4 and 0.65 or 0.8),
                colour = G.C.UI.TEXT_LIGHT,
                maxw = 3.5
            }),
            player.status_text ~= "" and MP.UI.UTILS.create_text_node(nil, {
                ref_table = player,
                ref_value = "status_text",
                scale = text_scale * 0.45,
                colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT,
                maxw = 3.5
            }) or nil,
        }),
		MP.UI.UTILS.create_blank(0.1, 0.1),
		player.hash and UIBox_button({
			id = player_type .. "_hash",
			button = "view_" .. player_type .. "_hash",
			label = { player.hash },
			minw = 0.75,
			minh = 0.3,
			scale = 0.25,
			shadow = false,
			colour = G.C.PURPLE,
			col = true,
		}) or nil,
	})
end

function MP.UI.create_players_section(text_scale)
	return MP.UI.UTILS.create_column({ align = "tm", minw = 2.65 }, {
		MP.UI.UTILS.create_row({ align = "cm", padding = 0.15 }, {
			MP.UI.UTILS.create_text_node(localize("k_connect_player"), {
				scale = text_scale * 0.8,
				colour = G.C.UI.TEXT_LIGHT,
			}),
		}),
		unpack(MP.UI.players_section_rows(text_scale)),
	})
end

--- One row per filled seat (up to 8). Seat 1 is the host.
function MP.UI.players_section_rows(text_scale)
	local rows = {}
	for i = 1, 8 do
		local seat = (MP.LOBBY.seats and MP.LOBBY.seats[i]) or (i == 1 and MP.LOBBY.host) or (i == 2 and MP.LOBBY.guest) or (i == 3 and MP.LOBBY.third)
		local row = create_player_info_row(seat, "seat" .. i, text_scale)
		if row then rows[#rows + 1] = row end
	end
	if MP.CHAT and MP.LOBBY and MP.LOBBY.code then
		local chrome = MP.CHAT.chrome and MP.CHAT.chrome() or {}
		rows[#rows + 1] = MP.UI.UTILS.create_row({ align = "cm", padding = 0.04 }, {
			UIBox_button({ id = "mp_chat_lobby", button = "mp_chat_toggle", label = { chrome.open or "Chat" },
				minw = 1.6, minh = 0.4, scale = 0.3, colour = G.C.BLUE, col = true }),
		})
	end
	-- Held seats are not in the seated list. Show them with the same status words.
	for i, a in ipairs(MP.LOBBY.away or {}) do
		if type(a) == "table" and a.username then
			local name = tostring(a.username):gsub("~.*$", "")
			rows[#rows + 1] = create_player_info_row({
				username = name, held = true, eliminated = a.eliminated, grace = a.left,
			}, "away" .. i, text_scale)
		end
	end
	-- Teams: the host picks who plays together. On 3v2/4v3 the first seats in that order are the larger side.
	if MP.LOBBY.is_host and MP.TEAMS and MP.TEAMS.is_active() then
		local fixed = MP.MODES.teams_format and MP.MODES.teams_format(MP.LOBBY.config)
		local seated = MP.LOBBY.player_list and #MP.LOBBY.player_list or #rows
		local rules = MP.MODES and MP.MODES.TEAMS_RULES
		local shape = (not fixed) and rules and rules.matchup and rules.matchup(seated, MP.LOBBY.config)
		if fixed then -- Versus 2v2/3v3/4v4: the team size is the format, only shuffling is left
			rows[#rows + 1] = MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
				UIBox_button({ id = "teams_shuffle", button = "mp_teams_shuffle", label = { MP.MODES.L("b_teams_shuffle", "Shuffle teams") },
					minw = 1.6, minh = 0.4, scale = 0.3, colour = G.C.ORANGE, col = true }),
			})
			return rows
		end
		if shape == "3v2" or shape == "4v3" then
			rows[#rows + 1] = MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
				UIBox_button({ id = "teams_shuffle", button = "mp_teams_shuffle", label = { MP.MODES.L("b_teams_shuffle", "Shuffle teams") },
					minw = 1.6, minh = 0.4, scale = 0.3, colour = G.C.ORANGE, col = true }),
				MP.UI.UTILS.create_blank(0.1, 0.1),
				MP.UI.UTILS.create_text_node(MP.MODES.L("k_teams_uneven", "#1#: first seats are the larger team", { shape }), {
					scale = text_scale * 0.55, colour = G.C.UI.TEXT_LIGHT, maxw = 2.2,
				}),
			})
			return rows
		end
		rows[#rows + 1] = MP.UI.UTILS.create_row({ align = "cm", padding = 0.05 }, {
			UIBox_button({ id = "teams_shuffle", button = "mp_teams_shuffle", label = { MP.MODES.L("b_teams_shuffle", "Shuffle teams") },
				minw = 1.6, minh = 0.4, scale = 0.3, colour = G.C.ORANGE, col = true }),
			MP.UI.UTILS.create_blank(0.1, 0.1),
			UIBox_button({ id = "teams_size", button = "mp_teams_size",
				label = { MP.MODES.L("b_teams_size", "Team size: #1#", { MP.LOBBY.config.teams_size or 2 }) },
				minw = 1.6, minh = 0.4, scale = 0.3, colour = G.C.BLUE, col = true }),
		})
	end
	return rows
end

-- Host buttons (Teams mode). The server answers with a new lobbyInfo holding the team preview.
function G.FUNCS.mp_teams_shuffle(e)
	local n = MP.LOBBY.player_list and #MP.LOBBY.player_list or 0
	if n < 2 then return end
	MP.LOBBY.config.teams_order = MP.TEAMS.shuffle(n)
	MP.ACTIONS.lobby_options()
end

function G.FUNCS.mp_teams_size(e)
	local n = MP.LOBBY.player_list and #MP.LOBBY.player_list or 4
	if n < 4 then n = 8 end
	MP.LOBBY.config.teams_size = MP.TEAMS.next_size(n, MP.LOBBY.config.teams_size or 2)
	MP.ACTIONS.lobby_options()
	if MP.ACTIONS.update_player_usernames then pcall(MP.ACTIONS.update_player_usernames) end
end
