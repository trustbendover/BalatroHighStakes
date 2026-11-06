local Disableable_Button = MP.UI.Disableable_Button

--- 0.6.8: the host's Start button text while it is greyed out
function MP.UI.start_wait_text()
	local n = MP.LOBBY.unready_count or 0
	local count = MP.LOBBY.player_list and #MP.LOBBY.player_list or 0
	local problem = count >= 2 and MP.MODES and MP.MODES.start_problem(count)
	if count >= 2 and not problem and n > 0 then
		local head = localize("b_wait_for_players")
		head = type(head) == "table" and head[1] or "WAITING FOR"
		return { head, localize({ type = "variable", key = n == 1 and "k_wait_ready_btn_one" or "k_wait_ready_btn", vars = { n } }) }
	end
	-- too few (or a wrong number of) players for the mode, e.g. alone in the lobby: same style, no count.
	-- ("NEED N MORE" was left out: Duel can also have too many, Teams needs an even count.)
	-- a missing translation returns the string "ERROR": the button needs a list of lines (crashed the lobby)
	local t = localize("b_wait_for_players")
	return type(t) == "table" and t or { "WAITING FOR", "PLAYERS" }
end

local function get_warnings()
	local warnings = {}
	-- 0.6.8: host sees how many guests still have to press Ready
	if MP.LOBBY.is_host and not MP.LOBBY.ready_to_start and (MP.LOBBY.unready_count or 0) > 0 then
		local n = MP.LOBBY.unready_count
		table.insert(warnings, { localize({ type = "variable", key = n == 1 and "k_wait_ready_one" or "k_wait_ready", vars = { n } }), G.C.UI.TEXT_LIGHT, 0.3 })
	end
	-- 0.6.8: alone in the lobby (the mode's own player-count message covers 2+ players)
	if MP.LOBBY.is_host and not MP.LOBBY.ready_to_start and MP.LOBBY.player_list and #MP.LOBBY.player_list < 2 then
		table.insert(warnings, { localize("k_wait_join"), G.C.UI.TEXT_LIGHT, 0.3 })
	end

	-- Player count vs. mode (1v1 Duel: exactly 2, Teams: 4-8 including 3v2 and 4v3, others 2-8)
	local count = MP.LOBBY.player_list and #MP.LOBBY.player_list or 0
	local problem = count >= 2 and MP.MODES and MP.MODES.start_problem(count)
	if problem then table.insert(warnings, { problem, SMODS.Gradients.warning_text, 0.35 }) end

	-- Unmodded/cached-file warning for any other seat (up to 8 players)
	for i = 1, 8 do
		local seat = MP.LOBBY.seats and MP.LOBBY.seats[i]
		if i > 2 and seat and seat.username and seat.cached == false then
			table.insert(warnings, { localize("k_warning_cheating1") .. " (" .. tostring(seat.username) .. ")", SMODS.Gradients.warning_text, 0.3 })
		end
	end

	-- Check the other player (guest if we're host, host if we're guest)
	local other_player = MP.LOBBY.is_host and MP.LOBBY.guest or MP.LOBBY.host

	if other_player and other_player.cached == false then
		table.insert(warnings, { localize("k_warning_cheating1"), SMODS.Gradients.warning_text, 0.4 })
		table.insert(
			warnings,
			{ string.format(localize("k_warning_cheating2"), MP.UTILS.random_message()), SMODS.Gradients.warning_text }
		)
	end

	if other_player and other_player.config and other_player.config.unlocked == false then
		table.insert(warnings, {
			localize("k_warning_nemesis_unlock"),
			SMODS.Gradients.warning_text,
			0.25,
		})
	end

	local bothPlayersInLobby = MP.LOBBY.guest and MP.LOBBY.guest.config ~= nil

	-- Content mod compatibility warnings (currently Extra Credit only)
	if bothPlayersInLobby then
		local hostExtraCreditVersion = MP.LOBBY.host
			and MP.LOBBY.host.config
			and MP.LOBBY.host.config.Mods["extracredit"]
		local guestExtraCreditVersion = MP.LOBBY.guest
			and MP.LOBBY.guest.config
			and MP.LOBBY.guest.config.Mods["extracredit"]

		if hostExtraCreditVersion ~= guestExtraCreditVersion then
			table.insert(warnings, {
				"Extra Credit mismatch - players may see different jokers",
				SMODS.Gradients.warning_text,
			})
		elseif hostExtraCreditVersion ~= nil and hostExtraCreditVersion == guestExtraCreditVersion then
			table.insert(warnings, {
				"Extra Credit active - curated jokers replaced with full pool",
				G.C.GREEN,
				0.25,
			})
		end
	end

	if MP.LOBBY.ready_to_start or not MP.LOBBY.is_host then
		local hostSteamoddedVersion = MP.LOBBY.host and MP.LOBBY.host.config and MP.LOBBY.host.config.Mods["Steamodded"]
		local guestSteamoddedVersion = MP.LOBBY.guest
			and MP.LOBBY.guest.config
			and MP.LOBBY.guest.config.Mods["Steamodded"]

		if hostSteamoddedVersion ~= guestSteamoddedVersion then
			table.insert(warnings, {
				localize("k_steamodded_warning"),
				SMODS.Gradients.warning_text,
			})
		end
	end

	if MP.UTILS.mp_version_mismatch() then
		table.insert(warnings, {
			localize("k_mp_version_warning"),
			G.C.RED,
			0.4,
		})
	end

	local host_banned_mods = MP.LOBBY.host
			and MP.LOBBY.host.config
			and MP.UTILS.get_banned_mods(MP.LOBBY.host.config.Mods)
		or {}
	local guest_banned_mods = MP.LOBBY.guest
			and MP.LOBBY.guest.config
			and MP.UTILS.get_banned_mods(MP.LOBBY.guest.config.Mods)
		or {}

	if #host_banned_mods > 0 or #guest_banned_mods > 0 then
		table.insert(warnings, {
			localize("k_warning_banned_mods"),
			G.C.RED,
			0.4,
		})
	end

	SMODS.Mods["Multiplayer"].config.unlocked = MP.UTILS.unlock_check()
	if not SMODS.Mods["Multiplayer"].config.unlocked then
		table.insert(warnings, {
			localize("k_warning_unlock_profile"),
			SMODS.Gradients.warning_text,
			0.25,
		})
	end

	if MP.LOBBY.username == "Guest" then table.insert(warnings, {
		localize("k_set_name"),
		G.C.UI.TEXT_LIGHT,
	}) end

	if #warnings == 0 then table.insert(warnings, {
		" ",
		G.C.UI.TEXT_LIGHT,
	}) end

	return warnings
end

function MP.UI.lobby_status_display()
	local warnings = get_warnings()

	local warning_texts = {}
	for k, v in pairs(warnings) do
		table.insert(
			warning_texts,
			MP.UI.UTILS.create_row({ align = "cm", padding = -0.25 }, {
				MP.UI.UTILS.create_text_node(v[1], {
					colour = v[2],
					scale = v[3] or 0.25,
				}),
			})
		)
	end

	return MP.UI.UTILS.create_row({ padding = 0.35, align = "cm" }, warning_texts)
end

-- Component for main start/ready button in lobby
function MP.UI.create_lobby_main_button(text_scale)
	if MP.LOBBY.is_host then
		return Disableable_Button({
			id = "lobby_menu_start",
			button = "lobby_start_game",
			colour = G.C.BLUE,
			minw = 3.65,
			minh = 1.55,
			label = { localize("b_start") },
			disabled_text = MP.UI.start_wait_text(),
			scale = text_scale * 2,
			col = true,
			enabled_ref_table = MP.LOBBY,
			enabled_ref_value = "ready_to_start",
		})
	else
		return UIBox_button({
			id = "lobby_menu_start",
			button = "lobby_ready_up",
			colour = MP.LOBBY.ready_to_start and G.C.GREEN or G.C.RED,
			minw = 3.65,
			minh = 1.55,
			label = { MP.LOBBY.ready_to_start and localize("b_unready") or localize("b_ready") },
			scale = text_scale * 2,
			col = true,
		})
	end
end
