-- ─── DON'T PATCH THIS FILE ───────────────────────────────────────────────────
-- This file owns the core network action dispatch. The contents move; the
-- string literals in here are NOT an API. HANDLERS is a file-local on
-- purpose — there is no global, no MP.HANDLERS, no _G shim coming to save you.
--
-- If you want to handle a network action from a mod, use one of:
--
--   MP.register_mod_action(name, cb)  -- PREFERRED. Pair with the
--                                     -- "moddedAction" envelope on the server:
--                                     --   {action = "moddedAction",
--                                     --    modId = …, modAction = name, …}
--                                     -- Keeps your action names namespaced to
--                                     -- your modId; no collisions with core
--                                     -- or other mods.
--
--   MP.register_action(name, cb)      -- Escape hatch for legacy server code
--                                     -- that emits flat top-level action
--                                     -- names. Refuses to register over an
--                                     -- existing handler (including core) —
--                                     -- first registration wins, collisions
--                                     -- warn and are dropped. Use the mod API
--                                     -- above if you can.
-- ─────────────────────────────────────────────────────────────────────────────

local json = require("json")

Client = {}

local no_log_actions = {
    dataSync = true,
    keepAlive = true,
    keepAliveAck = true,
}

function Client.send(msg)
	if MP.SAFE_MODE then return end -- 0.6.8 compat guard: multiplayer is off, send nothing
	if MP.STEAM_P2P and type(msg) == "table" then
		if not (msg.action and no_log_actions[msg.action]) then
			sendTraceMessage("Client sent P2P message: " .. tostring(msg.action), "MULTIPLAYER")
		end
		local ok, err = pcall(MP.STEAM_P2P.send, msg)
		if not ok then sendWarnMessage("Steam P2P send error: " .. tostring(err), "MULTIPLAYER") end
		return
	end
	-- 0.6.8: Steam P2P only - there is no TCP server any more, so without Steam nothing is sent
	if not (msg and msg.action and no_log_actions[msg.action]) then
		sendTraceMessage("No Steam P2P connection, not sent: " .. tostring(type(msg) == "table" and msg.action or msg), "MULTIPLAYER")
	end
end

-- Server to Client
function MP.ACTIONS.set_username(username)
	MP.LOBBY.username = username or "Guest"
	if MP.LOBBY.connected then
		Client.send({
			action = "username",
			username = MP.LOBBY.username .. "~" .. MP.LOBBY.blind_col,
			modHash = MP.MOD_STRING,
		})
	end
end

function MP.ACTIONS.set_blind_col(num)
	MP.LOBBY.blind_col = num or 1
end

-- Reconnection state (persists across connections)
local reconnectToken = nil
local lastLobbyCode = nil

-- 3P fork: persist the reconnect info on disk so a crashed / restarted game
-- can rejoin the running lobby automatically on its next connection.
local RECONNECT_FILE = "mp3p_reconnect.txt"
local RECONNECT_MAX_AGE = 6 * 60 * 60
local function save_reconnect_info()
	if reconnectToken and lastLobbyCode then
		pcall(love.filesystem.write, RECONNECT_FILE, lastLobbyCode .. "\n" .. reconnectToken .. "\n" .. tostring(os.time()))
	end
end
local function clear_reconnect_info()
	pcall(love.filesystem.remove, RECONNECT_FILE)
end
local function load_reconnect_info()
	local ok, content = pcall(love.filesystem.read, RECONNECT_FILE)
	if not ok or not content then return nil end
	local code, token, ts = content:match("^(%S+)\n(%S+)\n(%d+)")
	if not code or (os.time() - (tonumber(ts) or 0)) > RECONNECT_MAX_AGE then
		clear_reconnect_info()
		return nil
	end
	return code, token
end
MP.THREEP = MP.THREEP or {}
MP.THREEP.clear_reconnect_info = function()
	reconnectToken = nil
	lastLobbyCode = nil
	clear_reconnect_info()
end

local function action_connected()
	MP.LOBBY.connected = true
	MP.UI.update_connection_status()
	Client.send({
		action = "username",
		username = MP.LOBBY.username .. "~" .. MP.LOBBY.blind_col,
		modHash = MP.MOD_STRING,
	})

	-- If we have reconnect info, attempt to rejoin the lobby
	if not (reconnectToken and lastLobbyCode) and not MP.LOBBY.code then
		-- 3P: after a crash/restart, use the token saved on disk
		local code, token = load_reconnect_info()
		if code then
			lastLobbyCode, reconnectToken = code, token
			sendWarnMessage("Found a running game (" .. code .. "), trying to rejoin...", "MULTIPLAYER")
		end
	end
	if reconnectToken and lastLobbyCode then
		Client.send({
			action = "rejoinLobby",
			code = lastLobbyCode,
			reconnectToken = reconnectToken,
		})
	end
end

local function action_joinedLobby(p)
	local code, type, token = p.code, p.type, p.reconnectToken
	MP.LOBBY.code = code
	MP.LOBBY.type = type
	MP.LOBBY.ready_to_start = false
	-- Store reconnect info for potential future reconnection
	if token then reconnectToken = token end
	lastLobbyCode = code
	save_reconnect_info()
	MP.ACTIONS.sync_client()
	MP.ACTIONS.lobby_info()
	MP.UI.update_connection_status()
end

local function action_rejoinedLobby(p)
	local code, type, token = p.code, p.type, p.reconnectToken
	MP.LOBBY.code = code
	MP.LOBBY.type = type
	-- Update reconnect token
	reconnectToken = token
	lastLobbyCode = code
	save_reconnect_info()
	MP.self_reconnect_countdown = nil
	MP.GAME.timer_started = false
	MP.GAME.nemesis_timer_started = false
	MP.GAME.timer_threshold_pending = false
	MP.ACTIONS.sync_client()
	MP.ACTIONS.lobby_info()
	MP.UI.update_connection_status()
	sendWarnMessage("Reconnected to lobby!", "MULTIPLAYER")
	G.FUNCS.exit_overlay_menu()
	MP.UI.UTILS.overlay_message("Reconnected to lobby!")
end

-- 0.6.8 host migration (Steam P2P): texts and popups live in lib/host_migration_ui.lua
local function action_host_migrating(p)
	if MP.HOST_MIGRATION then MP.HOST_MIGRATION.on_migrating(p) end
end

local function action_host_migrated(p)
	-- like rejoinedLobby, but silent: our run simply continues on the new host
	MP.LOBBY.code = p.code or MP.LOBBY.code
	MP.LOBBY.type = p.type or MP.LOBBY.type
	if p.reconnectToken then reconnectToken = p.reconnectToken end
	lastLobbyCode = MP.LOBBY.code
	save_reconnect_info()
	MP.LOBBY.connected = true
	MP.self_reconnect_countdown = nil
	MP.UI.update_connection_status()
	if MP.HOST_MIGRATION then MP.HOST_MIGRATION.on_migrated(p) end
end

local function action_host_migration_failed(p)
	-- fall back to the old behaviour: back to the menu with a clear message
	clear_reconnect_info()
	MP.enemy_disconnect_countdown = nil
	if G.STAGE ~= G.STAGES.MAIN_MENU then
		pcall(G.FUNCS.go_to_menu)
		pcall(MP.reset_game_states)
	end
	if MP.HOST_MIGRATION then MP.HOST_MIGRATION.on_failed(p) end
end

-- Countdown state for disconnect overlays
MP.enemy_disconnect_countdown = nil
MP.self_reconnect_countdown = nil

-- Shared timeout handler for both countdowns
local function handle_reconnect_timeout(message)
	message = message .. "\nYour seat is held: restart the game or\njoin with the same lobby code to rejoin."
	G.FUNCS.exit_overlay_menu()
	MP.LOBBY.connected = false
	if MP.LOBBY.code then MP.LOBBY.code = nil end
	reconnectToken = nil
	lastLobbyCode = nil
	MP.UI.update_connection_status()
	if G.STAGE ~= G.STAGES.MAIN_MENU then
		MP.reset_game_states()
		G.FUNCS.go_to_menu()
	end
	MP.UI.UTILS.overlay_message(message)
end

-- Hook into Game.update to tick countdown displays
local _disconnect_gupdate = Game.update
function Game:update(dt)
	if MP.enemy_disconnect_countdown then
		local remaining = math.max(0, math.ceil(MP.enemy_disconnect_countdown.end_time - love.timer.getTime()))
		MP.enemy_disconnect_countdown.display = remaining .. "s remaining"
		-- No client-side timeout needed: the server sends stopGame
		-- when the grace period expires, which handles the cleanup
	end
	if MP.self_reconnect_countdown then
		local remaining = math.max(0, math.ceil(MP.self_reconnect_countdown.end_time - love.timer.getTime()))
		MP.self_reconnect_countdown.display = remaining .. "s remaining"
		if remaining <= 0 then
			MP.self_reconnect_countdown = nil
			handle_reconnect_timeout("Reconnection failed.\nReturning to main menu.")
		end
	end
	return _disconnect_gupdate(self, dt)
end

local function action_enemyDisconnected(p)
	if p.held then
		-- 3P: the server holds their seat until the game ends and skips them in
		-- PvP while they're away, so we just keep playing.
		local name = (p.playerId and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId]) or "A player"
		sendWarnMessage(name .. " disconnected (seat held)", "MULTIPLAYER")
		if MP.GAME.enemies and p.playerId and MP.GAME.enemies[p.playerId] then MP.GAME.enemies[p.playerId].away = true end
		if MP.THREEP.refresh_hud then MP.THREEP.refresh_hud() end
		-- 0.6.8: a status bar with the rejoin countdown instead of a popup (lib/rejoin.lua)
		if MP.REJOIN and not p.eliminated then MP.REJOIN.on_away(p) end
		return
	end
	local timeout = p.timeout or 60
	sendWarnMessage("Opponent disconnected, waiting for reconnection...", "MULTIPLAYER")
	if p.playerId and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId] then sendWarnMessage("(" .. MP.LOBBY.names_by_id[p.playerId] .. ")", "MULTIPLAYER") end

	MP.GAME.timer_started = false
	MP.GAME.nemesis_timer_started = false
	MP.GAME.timer_threshold_pending = false

	MP.enemy_disconnect_countdown = {
		end_time = love.timer.getTime() + timeout,
		display = timeout .. "s remaining",
	}

	MP.UI.UTILS.overlay_message_countdown(
		"Opponent disconnected,\nwaiting for reconnection...",
		MP.enemy_disconnect_countdown,
		true
	)
end

local function action_enemyReconnected(p)
	if p and p.playerId and MP.GAME.enemies and MP.GAME.enemies[p.playerId] then MP.GAME.enemies[p.playerId].away = nil end
	MP.enemy_disconnect_countdown = nil
	if p and p.playerId and MP.REJOIN then
		MP.REJOIN.on_back(p)
		if MP.THREEP.refresh_hud then pcall(MP.THREEP.refresh_hud) end
		return
	end
	sendWarnMessage("Opponent reconnected!", "MULTIPLAYER")
	G.FUNCS.exit_overlay_menu()
	MP.UI.UTILS.overlay_message("Opponent reconnected!")
end

local function action_lobbyInfo(p)
	if p.inGame == false and MP.SPECTATE and MP.SPECTATE.state.joined then MP.SPECTATE.on_match_end() end
	local host, hostHash, hostCached = p.host, p.hostHash, p.hostCached
	local guest, guestHash, guestCached, guestReady = p.guest, p.guestHash, p.guestCached, p.guestReady
	local is_host = p.isHost
	MP.LOBBY.players = {}
	MP.LOBBY.is_host = is_host
	-- 3P fork: the server sends the full ordered player list.
	MP.LOBBY.my_id = p.you or MP.LOBBY.my_id
	MP.LOBBY.player_list = p.players or {}
	MP.LOBBY.player_count = (p.players and #p.players or ((guest ~= nil) and 2 or 1)) + (p.away and #p.away or 0)
	if p.players and p.players[2] then
		guest, guestHash, guestCached = p.players[2].username, p.players[2].hash, p.players[2].cached
	end
	local function parseName(name)
		local username, col_str = string.match(name, "([^~]+)~(%d+)")
		username = username or "Guest"
		local col = tonumber(col_str) or 1
		col = math.max(1, math.min(col, 25))
		return username, col
	end
	local hostName, hostCol = parseName(host)
	local hostConfig, hostMods = MP.UTILS.parse_Hash(hostHash)
	MP.LOBBY.host = {
		username = hostName,
		blind_col = hostCol,
		hash_str = hostMods,
		hash = hash(hostMods),
		cached = hostCached,
		config = hostConfig,
	}

	if guest ~= nil then
		local guestName, guestCol = parseName(guest)
		local guestConfig, guestMods = MP.UTILS.parse_Hash(guestHash)
		MP.LOBBY.guest = {
			username = guestName,
			blind_col = guestCol,
			hash_str = guestMods,
			hash = hash(guestMods),
			cached = guestCached,
			config = guestConfig,
		}
	else
		MP.LOBBY.guest = {}
	end

	MP.LOBBY.third = {}
	if p.players and p.players[3] then
		local tName, tCol = parseName(p.players[3].username)
		local tConfig, tMods = MP.UTILS.parse_Hash(p.players[3].hash)
		MP.LOBBY.third = {
			username = tName,
			blind_col = tCol,
			hash_str = tMods,
			hash = hash(tMods),
			cached = p.players[3].cached,
			config = tConfig,
		}
	end
	-- All seats 1..8 in server order (seat 1 = host). host/guest/third stay as aliases.
	MP.LOBBY.seats = { MP.LOBBY.host, MP.LOBBY.guest.username and MP.LOBBY.guest or nil, MP.LOBBY.third.username and MP.LOBBY.third or nil }
	for i = 4, #(p.players or {}) do
		local pl = p.players[i]
		local sName, sCol = parseName(pl.username)
		local sConfig, sMods = MP.UTILS.parse_Hash(pl.hash)
		MP.LOBBY.seats[i] = {
			username = sName,
			blind_col = sCol,
			hash_str = sMods,
			hash = hash(sMods),
			cached = pl.cached,
			config = sConfig,
		}
	end
	for i, pl in ipairs(p.players or {}) do
		if MP.LOBBY.seats[i] then
			MP.LOBBY.seats[i].team = pl.team
			MP.LOBBY.seats[i].id = pl.id
		end
	end
	MP.LOBBY.max_players = p.maxPlayers or MP.LOBBY.max_players
	-- Map player ids -> display names (for the HUD)
	MP.LOBBY.names_by_id = {}
	for _, pl in ipairs(MP.LOBBY.player_list) do
		MP.LOBBY.names_by_id[pl.id] = (parseName(pl.username))
	end

	-- Ready when the player count fits the mode (MP.MODES.start_problem) and every non-host is ready
	if p.players then
		local all_ready = #p.players >= 2
		if is_host and MP.MODES and MP.MODES.start_problem(#p.players) then all_ready = false end
		local unready = 0
		for i = 2, #p.players do
			if not p.players[i].ready then all_ready = false; unready = unready + 1 end
		end
		MP.LOBBY.ready_to_start = all_ready
		MP.LOBBY.unready_count = unready -- 0.6.8: for the host's "waiting for N players" hint
	else
		MP.LOBBY.ready_to_start = guest ~= nil and guestReady
	end

	if MP.LOBBY.is_host then MP.ACTIONS.lobby_options() end

	if G.STAGE == G.STAGES.MAIN_MENU then MP.ACTIONS.update_player_usernames() end

	-- Re-arm the mismatch modal when all mismatches clear (opponent left or was replaced).
	if #MP.UTILS.version_mismatches() == 0 then MP._version_mismatch_shown = false end
end

local function action_error(p)
	local message = p.message
	sendWarnMessage(message, "MULTIPLAYER")

	MP.UI.UTILS.overlay_message(message)
end

local function action_keep_alive()
	Client.send({
		action = "keepAliveAck",
	})
end

local function action_disconnected()
	MP.LOBBY.connected = false
	if MP.REJOIN then MP.REJOIN.reset() end
	if MP.SPECTATE then MP.SPECTATE.on_match_end() end
	MP.self_reconnect_countdown = nil
	if MP.LOBBY.code then MP.LOBBY.code = nil end
	-- Clear reconnect state since all reconnection attempts failed
	reconnectToken = nil
	lastLobbyCode = nil
	MP.UI.update_connection_status()
end

local function action_reconnecting()
	-- Only show if we were in a lobby and don't already have a countdown running
	if reconnectToken and lastLobbyCode and not MP.self_reconnect_countdown then
		MP.LOBBY.connected = false
		MP.GAME.timer_started = false
		MP.GAME.nemesis_timer_started = false
		MP.GAME.timer_threshold_pending = false
		MP.UI.update_connection_status()
		sendWarnMessage("Connection lost, attempting to reconnect...", "MULTIPLAYER")

		MP.self_reconnect_countdown = {
			end_time = love.timer.getTime() + 150,
			display = "150s remaining",
		}

		MP.UI.UTILS.overlay_message_countdown(
			"Connection lost,\nattempting to reconnect...",
			MP.self_reconnect_countdown,
			true
		)
	end
end

local function action_start_game(p)
	local seed = p.seed
	sendDebugMessage(string.format("Game starting — %s", os.date("%Y-%m-%dT%H:%M:%S%z")), "MULTIPLAYER")
	-- Clear any stale practice/ghost state so it can't leak into real MP
	MP.SP.practice = false
	MP.GHOST.clear()

	MP.reset_game_states()
	if MP.REJOIN then MP.REJOIN.on_start(p) end
	if MP.SPECTATE then MP.SPECTATE.on_match_start() end
	if MP.MATCH_STATS then MP.MATCH_STATS.on_start() end
	local stake = tonumber(p.stake)
	MP.ACTIONS.set_ante(0)
	if not MP.LOBBY.config.different_seeds and MP.LOBBY.config.custom_seed ~= "random" then
		seed = MP.LOBBY.config.custom_seed
	end

	-- Open a new replay-log block for this game with everything needed to
	-- reconstruct it deterministically later. Uses the resolved seed.
	MP.RLOG.begin_run({
		seed = seed,
		-- Steam P2P startGame carries no stake (the run uses the lobby config): record that one
		stake = stake or tonumber(MP.LOBBY.deck and MP.LOBBY.deck.stake) or tonumber(MP.LOBBY.config.stake) or 1,
		deck = MP.LOBBY.config.back,
		sleeve = MP.LOBBY.config.sleeve,
		challenge = MP.LOBBY.config.challenge,
		ruleset = MP.LOBBY.config.ruleset,
		gamemode = MP.LOBBY.config.gamemode,
		modifier_layers = MP.LOBBY.config.modifier_layers,
		lobby_config = MP.LOBBY.config,
		the_order_enabled = MP.should_use_the_order(),
		different_seeds = MP.LOBBY.config.different_seeds,
		mod_version = SMODS.Mods["Multiplayer"] and SMODS.Mods["Multiplayer"].version,
		mod_hash = MP.MOD_STRING,
		smods_version = MP.SMODS_VERSION,
		lovely_version = MP.REQUIRED_LOVELY_VERSION,
		lobby_code = MP.LOBBY.code,
		is_host = MP.LOBBY.is_host,
		player = MP.LOBBY.username,
		opponent = (MP.LOBBY.is_host and MP.LOBBY.guest and MP.LOBBY.guest.username)
			or (MP.LOBBY.host and MP.LOBBY.host.username),
		start_ts = os.date("%Y-%m-%dT%H:%M:%S%z"),
	})

	G.FUNCS.lobby_start_run(nil, { seed = seed, stake = stake })
	MP.LOBBY.ready_to_start = false
end

local function begin_pvp_blind()
	if MP.GAME.next_blind_context then
		G.FUNCS.select_blind(MP.GAME.next_blind_context)
        MP.GAME.enemy.skips_before_pvp = 0
        MP.GAME.skips_before_pvp = 0
        MP.GAME.skips_difference = 0
        MP.GAME.timer_started = false
        MP.GAME.timer_was_started = false
        MP.GAME.nemesis_timer_started = false
        MP.GAME.nemesis_timer_was_started = false
        MP.GAME.timer_threshold_pending = false
        MP.GAME.timer_consumed = false
        MP.GAME.timer = MP.UTILS.pvp_timer_base()
	else
		sendErrorMessage("No next blind context", "MULTIPLAYER")
	end
end

local function action_start_blind(p)
	local first_player = p.firstPlayer
	-- Reset the stored opponent score each blind so the first frame after we
	-- play (which lifts the "???" mask) shows 0, not last blind's stale score.
	MP.GAME.enemy.score = MP.INSANE_INT.empty()
	MP.GAME.enemy.real_score = MP.INSANE_INT.empty()
	MP.GAME.enemy.score_text = "0"
	-- Re-mask the opponent's hands until the first enemyInfo of the new blind.
	MP.GAME.enemy.info_received = false
    MP.GAME.enemy.skips_before_pvp = 0
    MP.GAME.skips_before_pvp = 0
    MP.GAME.skips_difference = 0
	MP.GAME.ready_blind = false
	MP.GAME.pvp_reached = false
    MP.GAME.pvp_timer_order = nil
    MP.GAME.pvp_timer_activated = false
	if p.firstPlayerId ~= nil then
		MP.GAME.pvp_reached_first = p.firstPlayerId == MP.LOBBY.my_id
	else
		MP.GAME.pvp_reached_first = (MP.LOBBY.is_host and "host" or "guest") == first_player
	end
	-- 3P: reset every opponent's per-blind state
	for _, e in pairs(MP.GAME.enemies or {}) do
		e.real_score = MP.INSANE_INT.empty()
		e.raw_score = "0"
		e.info_received = false
		e.hands = 4
	end
	if MP.THREEP then MP.THREEP.refresh_hud() end
	-- 0.6.8: the host broadcasts startBlind to the whole lobby; a player who is already out (game over /
	-- spectating) has no blind to start (logged "No next blind context" as an ERROR before)
	if MP.player_is_out and MP.player_is_out() then return end
	MP.UI.start_pvp_countdown(begin_pvp_blind)
end

--- true once this player's own run is over in a running match (eliminated / game over / watching others)
function MP.player_is_out()
	if G and G.STATE and G.STATES and G.STATE == G.STATES.GAME_OVER then return true end
	if MP.SPECTATE and MP.SPECTATE.watching and MP.SPECTATE.watching() then return true end
	return false
end

local function action_enemy_info(p)
    local score
	local hands_left = tonumber(p.handsLeft)
	local skips = tonumber(p.skips)
	local lives = tonumber(p.lives)

	-- No-animation timer: If opponent skip, add time immediately
	if skips and MP.GAME.enemy.skips ~= skips then
		for i = 1, skips - MP.GAME.enemy.skips do
			MP.GAME.enemy.spent_in_shop[#MP.GAME.enemy.spent_in_shop + 1] = 0
            MP.GAME.enemy.skips_before_pvp = (MP.GAME.enemy.skips_before_pvp or 0) + 1
            MP.UI.update_matching_skip_timer(true)

			if
				MP.GAME.enemy.skips < skips
				and MP.LOBBY.config.timer
				and not MP.GAME.timer_started
				and not MP.GAME.nemesis_timer_started
				and not MP.GAME.timer_consumed
				and MP.is_any_layer_active({ "no_animation_timer", "pressure_timer" })
				and (MP.LOBBY.config.timer_increment_seconds or 0) > 0
			then
				MP.UI.restore_timer(MP.LOBBY.config.timer_increment_seconds)
			end
		end
	end

    if not p.noScore then
        score = MP.INSANE_INT.from_string(p.score)
    end

    if score then
        if MP.INSANE_INT.greater_than(score, MP.GAME.enemy.highest_score) then MP.GAME.enemy.highest_score = score end

        if not MP.INSANE_INT.equal(MP.GAME.enemy.score, score) then
            G.E_MANAGER:add_event(Event({
                blockable = false,
                blocking = false,
                trigger = "ease",
                delay = 0.75,
                timer = "REAL",
                ref_table = MP.GAME.enemy.score,
                ref_value = "e_count",
                ease_to = score.e_count,
                func = function(t)
                    return math.floor(t)
                end,
            }))
    
            G.E_MANAGER:add_event(Event({
                blockable = false,
                blocking = false,
                trigger = "ease",
                delay = 0.75,
                timer = "REAL",
                ref_table = MP.GAME.enemy.score,
                ref_value = "coeffiocient", -- why is this misspelled
                ease_to = score.coeffiocient,
                func = function(t)
                    local mult = 1
                    if score.exponent > 0 then mult = 100 end
                    return math.floor(t * mult) / mult
                end,
            }))
    
            G.E_MANAGER:add_event(Event({
                blockable = false,
                blocking = false,
                trigger = "ease",
                delay = 0.75,
                timer = "REAL",
                ref_table = MP.GAME.enemy.score,
                ref_value = "exponent",
                ease_to = score.exponent,
                func = function(t)
                    return math.floor(t)
                end,
            }))
        end

        MP.GAME.enemy.real_score = score
        MP.GAME.enemy.info_received = true
    end

    -- PvP timer: server determines who and when can activate pvp timer
    if p.pvpTimerOrder ~= nil and MP.is_pvp_boss() and MP.is_layer_active("pvp_timer") then
        MP.GAME.pvp_timer_order = p.pvpTimerOrder
        if (MP.LOBBY.is_host and "host" or "guest") == MP.GAME.pvp_timer_order then
            MP.GAME.nemesis_timer_started = false
            if
                not MP.GAME.timer_started
                and MP.UI.can_timer_opponent()
                and MP.GAME.pvp_timer_activated
                and SMODS.Mods["Multiplayer"].config.automatic_pvp_timer
            then
                MP.ACTIONS.start_ante_timer()
            end
        else
            MP.GAME.timer_started = false
        end
    end

	if MP.GAME.enemy.lives > lives then
		play_sound("holo1", 0.865, 0.9)
		play_sound("gong", 0.765, 0.4)
	end
	if MP.GAME.enemy.skips < skips and not MP.LOBBY.config.enemy_location_disabled then
		play_sound("negative", 0.865, 0.4)
		play_sound("gong", 0.765, 0.4)
	end

	MP.GAME.enemy.hands = hands_left or 0
	MP.GAME.enemy.skips = skips or 0
	MP.GAME.enemy.lives = lives or 0
	if MP.UI.juice_up_pvp_hud then MP.UI.juice_up_pvp_hud() end
end

-- 3P fork: per-opponent state lives in MP.GAME.enemies[playerId]. The legacy
-- MP.GAME.enemy table (which lots of UI/jokers hold references to) is kept as a
-- compat shim that always mirrors the "focus" opponent: the alive opponent
-- with the highest score this blind (ties: most lives). Sells / shop spend
-- counters on MP.GAME.enemy accumulate across all opponents.
local action_enemy_info_single = action_enemy_info
action_enemy_info = function(p)
	MP.GAME.enemies = MP.GAME.enemies or {}
	local id = p.playerId or "legacy"
	local e = MP.GAME.enemies[id]
	if not e then
		e = { id = id, real_score = MP.INSANE_INT.empty(), hands = 4, lives = MP.LOBBY.config.starting_lives, skips = 0 }
		MP.GAME.enemies[id] = e
	end
	e.username = (MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[id]) or p.username or e.username or "?"
	e.hands = tonumber(p.handsLeft) or e.hands
	e.lives = tonumber(p.lives) or e.lives
	e.skips = tonumber(p.skips) or e.skips
	e.eliminated = p.eliminated and true or false
	e.ante = tonumber(p.ante) or e.ante
	e.away = p.away and true or nil
	if not p.noScore and p.score ~= nil then
		e.raw_score = tostring(p.score)
		e.real_score = MP.INSANE_INT.from_string(e.raw_score)
		e.info_received = true
	end

	-- PvP timer ownership is decided by id in 3P
	if p.pvpOrder ~= nil and MP.LOBBY.my_id then
		local my_role = MP.LOBBY.is_host and "host" or "guest"
		local other_role = MP.LOBBY.is_host and "guest" or "host"
		p.pvpTimerOrder = (p.pvpOrder[1] == MP.LOBBY.my_id) and my_role or other_role
	end

	-- 0.6.8: spectating from the lobby: just keep the per-player table (no run, no HUD)
	if G.STAGE ~= G.STAGES.RUN and MP.SPECTATE and MP.SPECTATE.state.joined then return end
	local prev_focus = MP.GAME.enemy_focus_id
	local focus = MP.THREEP.pick_focus()
	MP.GAME.enemy_focus_id = focus and focus.id or id
	if MP.GAME.enemy_focus_id == id then
		action_enemy_info_single(p)
	elseif prev_focus ~= MP.GAME.enemy_focus_id and focus then
		-- Focus switched to another opponent: replay their state into the shim
		action_enemy_info_single({
			handsLeft = focus.hands,
			skips = MP.GAME.enemy.skips, -- don't re-trigger skip effects
			lives = focus.lives,
			score = focus.raw_score or "0",
			pvpTimerOrder = p.pvpTimerOrder,
		})
	end
	MP.GAME.enemy.username = MP.GAME.enemies[MP.GAME.enemy_focus_id] and MP.GAME.enemies[MP.GAME.enemy_focus_id].username or MP.GAME.enemy.username
	MP.THREEP.refresh_hud()
end

local function action_player_eliminated(p)
	MP.GAME.enemies = MP.GAME.enemies or {}
	local e = MP.GAME.enemies[p.playerId]
	if e then e.eliminated = true; e.lives = 0 end
	if p.reason == "disconnected" and MP.REJOIN then MP.REJOIN.on_expired(p) end
	MP.GAME.elim_order = MP.GAME.elim_order or {}
	table.insert(MP.GAME.elim_order, p.playerId)
	MP.GAME.enemy_focus_id = nil
	local focus = MP.THREEP.pick_focus()
	if focus and G.STAGE == G.STAGES.RUN then
		MP.GAME.enemy_focus_id = focus.id
		action_enemy_info_single({ handsLeft = focus.hands, skips = MP.GAME.enemy.skips, lives = focus.lives, score = focus.raw_score or "0" })
		MP.GAME.enemy.username = focus.username
	end
	if G.STAGE == G.STAGES.RUN then MP.THREEP.refresh_hud() end
	local name = (MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId]) or p.username or "?"
	sendWarnMessage(name .. " eliminated", "MULTIPLAYER")
	if MP.UI.UTILS and MP.UI.UTILS.overlay_message and G.STAGE ~= G.STAGES.RUN then MP.UI.UTILS.overlay_message(name .. " is out!") end
end

-- 3P: (re)join a running game. Called after rejoinedLobby (rejoin) or
-- joinedLobby (late join). If our run is still alive locally (network blip)
-- we just continue; otherwise we start a fresh run on the lobby seed and jump
-- to the given ante.
local function restart_at_ante(p)
	local target_ante = math.max(1, tonumber(p.ante) or 1)
	sendWarnMessage(string.format("Resuming game at ante %d (%s)", target_ante, p.lateJoin and "late join" or "rejoin"), "MULTIPLAYER")
	if G.STAGE == G.STAGES.RUN then MP.reset_game_states() end
	action_start_game({ seed = p.seed })
	if MP.MATCH_STATS then MP.MATCH_STATS.on_resume(p) end
	-- We can't finish a PvP blind that's already running with a fresh run
	Client.send({ action = "resumeRestarted" })
	local function jump()
		if not (G.GAME and G.GAME.round_resets) then return false end
		local cur = G.GAME.round_resets.ante or 1
		if target_ante > cur then
			G.GAME.round_resets.ante = target_ante
			G.GAME.round_resets.blind_ante = target_ante
			if get_new_boss and G.GAME.round_resets.blind_choices then
				G.GAME.round_resets.blind_choices.Boss = get_new_boss()
			end
			-- Catch-up money for the antes skipped: $8 per ante, max $40
			local bonus = math.min(40, 8 * (target_ante - cur))
			G.GAME.dollars = (G.GAME.dollars or 0) + bonus
			MP.ACTIONS.set_ante(target_ante)
		end
		return true
	end
	if not jump() then
		G.E_MANAGER:add_event(Event({ blockable = false, blocking = false, func = jump }))
	end
	-- 0.6.8: no usable checkpoint, but the host knows how much money we had
	local known = p.runState and tonumber(p.runState.dollars)
	if not p.lateJoin and known then
		G.E_MANAGER:add_event(Event({ blockable = false, blocking = false, func = function()
			if not (G.GAME and G.GAME.round_resets and (G.GAME.round_resets.ante or 1) >= target_ante) then return false end
			G.GAME.dollars = math.max(G.GAME.dollars or 0, known)
			return true
		end }))
	end
	if p.lives then MP.GAME.lives = tonumber(p.lives) or MP.GAME.lives end
	MP.UI.UTILS.overlay_message(p.lateJoin and ("Joined the running game at ante " .. target_ante .. "!")
		or (MP.SPECTATE and MP.SPECTATE.L("k_rj_restarted", "Rejoined! Your run restarts at ante #1# (same seed, lives kept)", { target_ante }))
		or ("Rejoined! Your run restarts at ante " .. target_ante .. "\n(same seed, lives kept)."))
end
MP.THREEP.restart_at_ante = restart_at_ante

-- 0.6.8: our own checkpoint (lib/rejoin.lua) restores the run when it matches the lobby;
-- otherwise restart_at_ante. Both wait until the lobby screen has settled after the rejoin.
local function action_resume_game(p)
	local run_alive = G.STAGE == G.STAGES.RUN and not p.lateJoin and MP.GAME and (MP.GAME.lives or 0) > 0
		and G.STATE ~= G.STATES.GAME_OVER
	if run_alive then
		sendWarnMessage("Rejoined - continuing current run", "MULTIPLAYER")
		return
	end
	if p.eliminated then
		MP.GAME.lives = 0
		if MP.SPECTATE then
			MP.SPECTATE.state.match, MP.SPECTATE.state.joined = true, G.STAGE ~= G.STAGES.RUN
			MP.UI.UTILS.overlay_message(MP.SPECTATE.L("k_rj_out", "Rejoined, but you are already out - you can watch the match"))
		else
			MP.UI.UTILS.overlay_message("Rejoined, but you are already eliminated.")
		end
		return
	end
	if MP.SPECTATE then MP.SPECTATE.state.match, MP.SPECTATE.state.joined = true, false end
	if MP.REJOIN and not p.lateJoin then return MP.REJOIN.queue(p) end
	return restart_at_ante(p)
end

local function action_player_joined(p)
	local name = p.username and (p.username:match("([^~]+)") or p.username) or "A player"
	sendWarnMessage(name .. " joined the game", "MULTIPLAYER")
	MP.UI.UTILS.overlay_message(name .. " joined the running game!")
end

local function action_rejoin_failed(p)
	-- Saved token no longer valid (game over / lobby gone): forget it silently
	MP.THREEP.clear_reconnect_info()
	sendDebugMessage("Rejoin failed: " .. tostring(p.message), "MULTIPLAYER")
end

local function action_player_left(p)
	action_player_eliminated(p)
end

local function action_stop_game()
	clear_reconnect_info()
	if MP.REJOIN then MP.REJOIN.clear(); MP.REJOIN.reset() end
	if MP.SPECTATE then MP.SPECTATE.on_match_end() end
	MP.enemy_disconnect_countdown = nil
	if G.STAGE ~= G.STAGES.MAIN_MENU then
		G.FUNCS.go_to_menu()
		MP.UI.update_connection_status()
		MP.reset_game_states()
	end
	MP.RLOG.end_run({ result = "stop" })
	MP.UTILS.emit_log_checksum()
end

local function action_end_pvp(p)
	local lost, pvpTimerLost = p.lost, p.pvpTimerLost
	if lost and pvpTimerLost then
		if G.GAME.current_round.hands_left > 0 then
            stop_use()
			SMODS.calculate_context({ mp_pvp_loss = true, mp_hands_left = G.GAME.current_round.hands_left })
		end
	end
	MP.GAME.end_pvp = true
	MP.GAME.timer = MP.UTILS.timer_base()
	MP.GAME.timer_consumed = false
	MP.GAME.timer_started = false
    MP.GAME.timer_was_started = false
	MP.GAME.nemesis_timer_started = false
    MP.GAME.nemesis_timer_was_started = false
	MP.GAME.timer_threshold_pending = false
	MP.GAME.ready_blind = false
	MP.GAME.pvp_reached = false
    MP.GAME.pvp_reached_first = false
    MP.GAME.pvp_timer_activated = false
	MP.GAME.score = nil

    -- Sanity check
    G.E_MANAGER:add_event(Event({
        func = function()
            G.E_MANAGER:add_event(Event({
                func = function()
                    MP.GAME.timer = MP.UTILS.timer_base()
                    MP.GAME.timer_started = false
                    MP.GAME.timer_was_started = false
                    MP.GAME.nemesis_timer_started = false
                    MP.GAME.nemesis_timer_was_started = false
                    MP.GAME.pvp_timer_activated = false
                    MP.GAME.timer_threshold_pending = false
                    return true
                end,
            }))
            return true
        end,
    }))
end

local function action_player_info(p)
	local lives = p.lives
	if MP.GAME.lives ~= lives then
		if MP.GAME.lives ~= 0 and MP.LOBBY.config.gold_on_life_loss then
			MP.GAME.comeback_bonus_given = false
			MP.GAME.comeback_bonus = MP.GAME.comeback_bonus + 1
		end
		MP.UI.ease_lives(lives - MP.GAME.lives, true)
		if MP.LOBBY.config.no_gold_on_round_loss and (G.GAME.blind and G.GAME.blind.dollars) then
			G.GAME.blind.dollars = 0
		end
	end
	MP.GAME.lives = lives
end

local function action_win_game()
	MP.end_game_jokers_payload = ""
	MP.nemesis_deck_string = ""
	MP.end_game_jokers_received = false
	MP.nemesis_deck_received = false
	MP.GAME.won = true
	clear_reconnect_info()
	if MP.REJOIN then MP.REJOIN.clear(); MP.REJOIN.reset() end
	if MP.SPECTATE then MP.SPECTATE.on_match_end() end
	MP.STATS.record_match(true)
	MP.RLOG.end_run({ result = "win" })
	MP.UTILS.log_mem_debug_messages()
	MP.UTILS.emit_log_checksum()
	win_game()
end

local function action_lose_game()
	MP.end_game_jokers_payload = ""
	MP.nemesis_deck_string = ""
	MP.end_game_jokers_received = false
	MP.nemesis_deck_received = false
	MP.STATS.record_match(false)
	clear_reconnect_info()
	if MP.REJOIN then MP.REJOIN.clear() end
	G.STATE_COMPLETE = false
	G.STATE = G.STATES.GAME_OVER
	MP.RLOG.end_run({ result = "loss" })
	MP.UTILS.log_mem_debug_messages()
	MP.UTILS.emit_log_checksum()
end

local function action_lobby_options(options)
	local different_decks_before = MP.LOBBY.config.different_decks
	for k, v in pairs(options) do
		if k == "ruleset" then
			if not MP.Rulesets[v] then
				G.FUNCS.lobby_leave(nil)
				MP.UI.UTILS.overlay_message(localize({
					type = "variable",
					key = "k_failed_to_join_lobby",
					vars = { localize("k_ruleset_not_found") },
				}))
				return
			end
			local disabled = MP.Rulesets[v].is_disabled()
			if disabled then
				G.FUNCS.lobby_leave(nil)
				MP.UI.UTILS.overlay_message(
					localize({ type = "variable", key = "k_failed_to_join_lobby", vars = { disabled } })
				)
				return
			end
			MP.LOBBY.config.ruleset = v
			goto continue
		end
		if k == "gamemode" then
			MP.LOBBY.config.gamemode = v
			goto continue
		end
		if k == "modifier_layers" then
			MP.LOBBY.config.modifier_layers = v
			MP.modifiers_parse(v)
			goto continue
		end

		local parsed_v = v
		if v == "true" then
			parsed_v = true
		elseif v == "false" then
			parsed_v = false
		end

		if
			k == "starting_lives"
			or k == "pvp_start_round"
			or k == "timer_base_seconds"
			or k == "timer_increment_seconds"
			or k == "showdown_starting_antes"
			or k == "pvp_countdown_seconds"
			or k == "timer_forgiveness"
		then
			parsed_v = tonumber(v)
		end

		MP.LOBBY.config[k] = parsed_v
		if MP.UI.update_lobby_option_toggle then MP.UI.update_lobby_option_toggle(k) end
		::continue::
	end
	if different_decks_before ~= MP.LOBBY.config.different_decks then
		G.FUNCS.exit_overlay_menu() -- throw out guest from any menu.
	end
	MP.ACTIONS.update_player_usernames() -- render new DECK button state
end

local function action_send_phantom(p)
	local key = p.key
	-- Carbon: exogenous opponent effect. Keyed by content (not a board index),
	-- logged in received order so a solo re-sim reproduces it faithfully.
	MP.RLOG.record("net_phantom_add", key, "action:netPhantomAdd,key:" .. tostring(key))
	local menu = G.OVERLAY_MENU -- we are spoofing a menu here, which disables duplicate protection
	G.OVERLAY_MENU = G.OVERLAY_MENU or true
	local new_card = create_card("Joker", MP.shared, false, nil, nil, nil, key)
	new_card:set_edition("e_mp_phantom")
	new_card:add_to_deck()
	MP.shared:emplace(new_card)
	G.OVERLAY_MENU = menu
end

local function action_remove_phantom(p)
	MP.RLOG.record("net_phantom_remove", p.key, "action:netPhantomRemove,key:" .. tostring(p.key))
	local card = MP.UTILS.get_phantom_joker(p.key)
	if card then
		card:remove_from_deck()
		card:start_dissolve({ G.C.RED }, nil, 1.6)
		MP.shared:remove_card(card)
	end
end

-- card:remove is called in an event so we have to hook the function instead of doing normal things
local cardremove = Card.remove
function Card:remove()
	local menu = G.OVERLAY_MENU
	if self.edition and self.edition.type == "mp_phantom" then G.OVERLAY_MENU = G.OVERLAY_MENU or true end
	cardremove(self)
	G.OVERLAY_MENU = menu
end

-- and smods find card STILL needs to be patched here
local smodsfindcard = SMODS.find_card
function SMODS.find_card(key, count_debuffed)
	local ret = smodsfindcard(key, count_debuffed)
	local new_ret = {}
	for i, v in ipairs(ret) do
		if not v.edition or v.edition.type ~= "mp_phantom" then new_ret[#new_ret + 1] = v end
	end
	return new_ret
end

-- don't poll edition
local origedpoll = poll_edition
function poll_edition(_key, _mod, _no_neg, _guaranteed, _options)
	if G.OVERLAY_MENU then return nil end
	return origedpoll(_key, _mod, _no_neg, _guaranteed, _options)
end

local function action_speedrun()
	SMODS.calculate_context({ mp_speedrun = true })
end

local function enemyLocation(options)
	local location = options.location
	local value = ""

	if string.find(location, "-") then
		local split = {}
		for str in string.gmatch(location, "([^-]+)") do
			table.insert(split, str)
		end
		location = split[1]
		value = split[2] or ""
	end

	local loc_location = G.localization.misc.dictionary[location]

	if loc_location == nil then
		if location ~= nil then
			loc_location = location
		else
			loc_location = "Unknown"
		end
	end

	-- 0.6.8: per player too (spectator panel)
	local e = options.playerId and MP.GAME.enemies and MP.GAME.enemies[options.playerId]
	if e then e.location = loc_location end
	if G.STAGE ~= G.STAGES.RUN and MP.SPECTATE and MP.SPECTATE.state.joined then return end
	MP.GAME.enemy.location = loc_location
	MP.GAME.enemy.location_blind = value
	MP.GAME.enemy.location_type = location
	MP.GAME.enemy.location_full = location .. "-" .. value
	MP.UI.update_enemy_location_render()
end

local function action_version()
	MP.ACTIONS.version()
end

local action_asteroid_ref = action_asteroid
	or function()
		if MP.UI.show_asteroid_hand_level_up then MP.UI.show_asteroid_hand_level_up() end
	end
local function action_asteroid(p)
	MP.RLOG.record("net_asteroid", nil, "action:netAsteroid")
	return action_asteroid_ref(p)
end

local function action_sold_joker()
	-- HACK: this action is being sent when any card is being sold, since Taxes is now reworked
	MP.GAME.enemy.sells = MP.GAME.enemy.sells + 1
	MP.GAME.enemy.sells_per_ante[G.GAME.round_resets.ante] = (
		(MP.GAME.enemy.sells_per_ante[G.GAME.round_resets.ante] or 0) + 1
	)
end

local function action_lets_go_gambling_nemesis()
	local card = MP.UTILS.get_phantom_joker("j_mp_lets_go_gambling")
	if card then card:juice_up() end
	ease_dollars(card and card.ability and card.ability.extra and card.ability.extra.nemesis_dollars or 5)
end

local function action_eat_pizza(p)
	local discards = p.whole -- rename to "discards" when possible
	MP.RLOG.record("net_pizza", discards, "action:netPizza,discards:" .. tostring(discards))
	MP.GAME.pizza_discards = MP.GAME.pizza_discards + discards
	G.GAME.round_resets.discards = G.GAME.round_resets.discards + discards
	ease_discard(discards)
end

local function action_spent_last_shop(p)
	MP.GAME.enemy.spent_in_shop[#MP.GAME.enemy.spent_in_shop + 1] = tonumber(p.amount)
end

local function action_magnet()
	MP.RLOG.record("net_magnet", nil, "action:netMagnet")
	local card = nil
	for _, v in pairs(G.jokers.cards) do
		if not card or v.sell_cost > card.sell_cost then card = v end
	end

	if card then
		local candidates = {}
		for _, v in pairs(G.jokers.cards) do
			if v.sell_cost == card.sell_cost then table.insert(candidates, v) end
		end

		-- Scale the pseudo from 0 - 1 to the number of candidates
		local random_index = math.floor(pseudorandom("j_mp_magnet") * #candidates) + 1
		local chosen_card = candidates[random_index]
		sendTraceMessage(
			string.format("Sending magnet joker: %s", MP.UTILS.joker_to_string(chosen_card)),
			"MULTIPLAYER"
		)

		local card_save = chosen_card:save()
		local card_encoded = MP.UTILS.str_pack_and_encode(card_save)
		MP.ACTIONS.magnet_response(card_encoded)
	end
end

local function action_jimbo_appear(p)
	local pos = tonumber(p.pos)
	local text = p.text
	if not pos or pos < 1 or pos > 4 then
		sendDebugMessage("jimboAppear: invalid pos: " .. tostring(pos), "MULTIPLAYER")
		return
	end
	if text and type(text) ~= "string" then
		sendDebugMessage("jimboAppear: invalid text type: " .. type(text), "MULTIPLAYER")
		return
	end
	MP.UI.create_jimbo(pos)
	if text and text ~= "" then MP.UI.jimbo_say(text) end
end

local function action_jimbo_talk(p)
	local text = p.text
	if not text or type(text) ~= "string" or text == "" then
		sendDebugMessage("jimboTalk: invalid or empty text", "MULTIPLAYER")
		return
	end
	MP.UI.jimbo_say(text)
end

local function action_jimbo_move(p)
	local pos = tonumber(p.pos)
	if not pos or pos < 1 or pos > 4 then
		sendDebugMessage("jimboMove: invalid pos: " .. tostring(pos), "MULTIPLAYER")
		return
	end
	MP.UI.move_jimbo(pos)
end

local function action_jimbo_remove()
	MP.UI.remove_jimbo()
end

local function action_magnet_response(p)
	local card_save, success, err

	card_save, err = MP.UTILS.str_decode_and_unpack(p.key)
	if not card_save then
		sendDebugMessage(string.format("Failed to unpack magnet joker: %s", err), "MULTIPLAYER")
		return
	end

	local card =
		Card(G.jokers.T.x + G.jokers.T.w / 2, G.jokers.T.y, G.CARD_W, G.CARD_H, G.P_CENTERS.j_joker, G.P_CENTERS.c_base)
	-- Avoid crashing if the load function ends up indexing a nil value
	success, err = pcall(card.load, card, card_save)
	if not success then
		sendDebugMessage(string.format("Failed to load magnet joker: %s", err), "MULTIPLAYER")
		return
	end

	-- BALATRO BUG (version 1.0.1o): `card.VT.h` is mistakenly set to nil after calling `card:load()`
	-- Without this call to `card:hard_set_VT()`, the game will crash later when the card is drawn
	card:hard_set_VT()

	-- Enforce "add to deck" effects (e.g. increase hand size effects)
	card.added_to_deck = nil

	card:add_to_deck()
	G.jokers:emplace(card)
	sendTraceMessage(string.format("Received magnet joker: %s", MP.UTILS.joker_to_string(card)), "MULTIPLAYER")
end

local function action_data_sync(data)
    if data.timer then
        MP.GAME.enemy.last_timer = data.timer or 0
    end
end

function G.FUNCS.load_end_game_jokers()
	local card_area_save, success, err

	if not MP.end_game_jokers or not MP.end_game_jokers_payload then return end

	card_area_save, err = MP.UTILS.str_decode_and_unpack(MP.end_game_jokers_payload)
	if not card_area_save then
		sendDebugMessage(string.format("Failed to unpack enemy jokers: %s", err), "MULTIPLAYER")
		return
	end

	-- Avoid crashing if the load function ends up indexing a nil value
	success, err = pcall(MP.end_game_jokers.load, MP.end_game_jokers, card_area_save)
	if not success then
		sendDebugMessage(string.format("Failed to load enemy jokers: %s", err), "MULTIPLAYER")
		-- Reset the card area if loading fails to avoid inconsistent state
		MP.end_game_jokers:remove()
		MP.end_game_jokers:init(
			---@diagnostic disable-next-line: param-type-mismatch
			0,
			0,
			5 * G.CARD_W,
			G.CARD_H,
			{ card_limit = G.GAME.starting_params.joker_slots, type = "joker", highlight_limit = 1, fixed_limit = true }
		)
		return
	end

	-- Log the jokers
	if MP.end_game_jokers.cards then
		local jokers_str = ""
		for _, card in pairs(MP.end_game_jokers.cards) do
			jokers_str = jokers_str .. ";" .. MP.UTILS.joker_to_string(card)
		end
		sendTraceMessage(string.format("Received end game jokers: %s", jokers_str), "MULTIPLAYER")
	end
end

local function action_receive_end_game_jokers(p)
	-- 3P: only accept the jokers of the chosen nemesis; never let an empty reply overwrite real jokers
	if MP.GAME.nemesis_id and p.playerId and p.playerId ~= MP.GAME.nemesis_id then
		sendTraceMessage("Ignoring end game jokers from " .. tostring(p.playerId) .. " (nemesis is " .. MP.GAME.nemesis_id .. ")", "MULTIPLAYER")
		return
	end
	if type(p.keys) ~= "string" or p.keys == "" then
		if MP.end_game_jokers_received and MP.end_game_jokers_payload and MP.end_game_jokers_payload ~= "" then return end
		p.keys = ""
	end
	MP.end_game_jokers_from = p.playerId
	MP.end_game_jokers_payload = p.keys
	MP.end_game_jokers_received = true
	G.FUNCS.load_end_game_jokers()
end

local function action_get_end_game_jokers(p)
	local reply_to = p and p.playerId or nil
	if not G.jokers or not G.jokers.cards then
		Client.send({
			action = "receiveEndGameJokers",
			keys = "",
			targetId = reply_to,
		})
		return
	end

	-- Log the jokers
	local jokers_str = ""
	for _, card in pairs(G.jokers.cards) do
		jokers_str = jokers_str .. ";" .. MP.UTILS.joker_to_string(card)
	end
	sendTraceMessage(string.format("Sending end game jokers: %s", jokers_str), "MULTIPLAYER")

	local jokers_save = G.jokers:save()
	local jokers_encoded = MP.UTILS.str_pack_and_encode(jokers_save)

	Client.send({
		action = "receiveEndGameJokers",
		keys = jokers_encoded,
		targetId = reply_to,
	})
end

local function action_get_nemesis_deck(p)
	local deck_str = ""
	for _, card in ipairs(G.playing_cards or {}) do
		deck_str = deck_str .. ";" .. MP.UTILS.card_to_string(card)
	end
	Client.send({
		action = "receiveNemesisDeck",
		cards = deck_str,
		targetId = p and p.playerId or nil,
	})
end

local function action_send_game_stats(p)
	local reply_to = p and p.playerId or nil
	if not MP.GAME.stats then
		Client.send({
			action = "nemesisEndGameStats",
			targetId = reply_to,
		})
		return
	end

	local stats = {
		action = "nemesisEndGameStats",
		targetId = reply_to,
		reroll_count = MP.GAME.stats.reroll_count,
		reroll_cost_total = MP.GAME.stats.reroll_cost_total,
	}

	-- Extract voucher keys where value is true and join them with a dash
	local voucher_keys = ""
	if G.GAME.used_vouchers then
		local keys = {}
		for k, v in pairs(G.GAME.used_vouchers) do
			if v == true then table.insert(keys, k) end
		end
		voucher_keys = table.concat(keys, "-")
	end

	-- Add voucher keys to stats string
	if voucher_keys ~= "" then stats.vouchers = voucher_keys end

	Client.send(stats)
end

function G.FUNCS.load_nemesis_deck()
	if not MP.nemesis_deck_string or not MP.nemesis_deck or not MP.nemesis_cards or not MP.LOBBY.code then return end

	local card_strings = MP.UTILS.string_split(MP.nemesis_deck_string, ";")

	for k, _ in pairs(MP.nemesis_cards) do
		MP.nemesis_cards[k] = nil
	end

	for _, card_str in pairs(card_strings) do
		if card_str == "" then goto continue end

		local card_params = MP.UTILS.string_split(card_str, "-")

		local suit = card_params[1]
		local rank = card_params[2]
		local enhancement = card_params[3]
		local edition = card_params[4]
		local seal = card_params[5]

		-- Validate the card parameters
		-- If invalid suit or rank, skip the card
		-- If invalid enhancement, edition, or seal, fallback to "none"
		local front_key = tostring(suit) .. "_" .. tostring(rank)
		if not G.P_CARDS[front_key] then
			sendDebugMessage(string.format("Invalid playing card key: %s", front_key), "MULTIPLAYER")
			goto continue
		end
		if not enhancement or (enhancement ~= "none" and not G.P_CENTERS[enhancement]) then
			sendDebugMessage(string.format("Invalid enhancement: %s", enhancement), "MULTIPLAYER")
			enhancement = "none"
		end
		if not edition or (edition ~= "none" and not G.P_CENTERS["e_" .. edition]) then
			sendDebugMessage(string.format("Invalid edition: %s", edition), "MULTIPLAYER")
			edition = "none"
		end
		if not seal or (seal ~= "none" and not G.P_SEALS[seal]) then
			sendDebugMessage(string.format("Invalid seal: %s", seal), "MULTIPLAYER")
			seal = "none"
		end

		-- Create the card
		local card = create_playing_card({
			front = G.P_CARDS[front_key],
			center = enhancement ~= "none" and G.P_CENTERS[enhancement] or nil,
		}, MP.nemesis_deck, true, true, nil, false)
		if edition ~= "none" then card:set_edition({ [edition] = true }, true, true) end
		if seal ~= "none" then card:set_seal(seal, true, true) end

		-- Remove the card from G.playing_cards and insert into MP.nemesis_cards
		table.remove(G.playing_cards, #G.playing_cards)
		table.insert(MP.nemesis_cards, card)

		::continue::
	end
end

local function action_receive_nemesis_deck(p)
	if MP.GAME.nemesis_id and p.playerId and p.playerId ~= MP.GAME.nemesis_id then return end
	MP.nemesis_deck_from = p.playerId
	MP.nemesis_deck_string = p.cards
	MP.nemesis_deck_received = true
	G.FUNCS.load_nemesis_deck()
end

-- Dual-call: dispatched from network (fromNemesis defaults to true) or self-triggered
-- by MP.ACTIONS.start_ante_timer (passes fromNemesis = false explicitly).
local function action_start_ante_timer(p)
	if p.isPvP and (MP.GAME.end_pvp or not MP.is_pvp_boss() or G.GAME.current_round.hands_left <= 0) then return end

	local time = p.time
	local from_nemesis = p.fromNemesis
	if from_nemesis == nil then from_nemesis = true end

	local option = SMODS.Mods["Multiplayer"].config.timersfx or 1
	local timersfx = (option == 1) or (option == 2 and G.timer_ante ~= G.GAME.round_resets.ante)
	G.timer_ante = G.GAME.round_resets.ante

	if timersfx then
		for i = 1, 3 do
			local wait_time = (0.15 * (i - 1))
			G.E_MANAGER:add_event(Event({
				blocking = false,
				blockable = false,
				trigger = "after",
				delay = G.SETTINGS.GAMESPEED * wait_time,
				func = function()
					play_sound("timpani", 0.55 + 0.25 * i, 0.7)
					play_sound("generic1", 0.75 + 0.25 * i, 0.7)
					return true
				end,
			}))
		end
	end
	-- Default timer is server-synced; pressure/no-anim/pvp timers run locally.
	if not MP.timer_is_local() then
		if type(time) == "string" then time = tonumber(time) end
		if time then MP.GAME.timer = time end
	end
	if from_nemesis then
		MP.GAME.nemesis_timer_started = true
        MP.GAME.nemesis_timer_was_started = true
	else
		MP.GAME.timer_started = true
        MP.GAME.timer_was_started = true
	end
end

local function action_pause_ante_timer(p)
	local time = p.time
	local from_nemesis = p.fromNemesis
	if from_nemesis == nil then from_nemesis = true end

	-- Default timer is server-synced; pressure/no-anim/pvp timers run locally.
	if not MP.timer_is_local() then
		if type(time) == "string" then time = tonumber(time) end
		if time then MP.GAME.timer = time end
	end
	if from_nemesis then
		MP.GAME.nemesis_timer_started = false
	else
		MP.GAME.timer_started = false
	end
end

local function action_modded_action(p)
	local registry = MP.MOD_ACTIONS[p.modId]
	if registry and registry[p.modAction] then registry[p.modAction](p) end
end

-- #region Client to Server
function MP.ACTIONS.create_lobby(gamemode)
	Client.send({
		action = "createLobby",
		gameMode = gamemode,
	})
end

function MP.ACTIONS.join_lobby(code)
	Client.send({
		action = "joinLobby",
		code = code,
	})
end

function MP.ACTIONS.ready_lobby()
	Client.send({
		action = "readyLobby",
	})
end

function MP.ACTIONS.unready_lobby()
	Client.send({
		action = "unreadyLobby",
	})
end

function MP.ACTIONS.lobby_info()
	Client.send({
		action = "lobbyInfo",
	})
end

function MP.ACTIONS.leave_lobby()
	-- Clear reconnect state on voluntary leave
	reconnectToken = nil
	lastLobbyCode = nil
	clear_reconnect_info()
	Client.send({
		action = "leaveLobby",
	})
	MP.UTILS.emit_log_checksum()
end

function MP.ACTIONS.start_game()
	Client.send({
		action = "startGame",
	})
end

function MP.ACTIONS.ready_blind(e)
	MP.GAME.next_blind_context = e
	Client.send({
		action = "readyBlind",
	})
end

function MP.ACTIONS.unready_blind()
	Client.send({
		action = "unreadyBlind",
	})
end

function MP.ACTIONS.stop_game()
	Client.send({
		action = "stopGame",
	})
end

function MP.ACTIONS.fail_round(hands_used)
	if MP.LOBBY.config.no_gold_on_round_loss then G.GAME.blind.dollars = 0 end
	if hands_used == 0 then return end
	Client.send({
		action = "failRound",
	})
end

function MP.ACTIONS.version()
	Client.send({
		action = "version",
		version = MULTIPLAYER_VERSION,
	})
end

function MP.ACTIONS.set_location(location, blind)
	local location_type = location
	local location_blind = blind
	if string.find(location, "-") then
		local split = {}
		for str in string.gmatch(location, "([^-]+)") do
			table.insert(split, str)
		end
		location_type = split[1]
		location_blind = split[2] or ""
	else
		location_blind = MP.UTILS.get_blind_to_display(blind) or ""
	end
	location = location_type .. "-" .. location_blind

	if MP.GAME.location == location then return end
	MP.GAME.location = location
	MP.GAME.location_type = location_type
	MP.GAME.location_blind = location_blind
	MP.GAME.location_full = location
	Client.send({
		action = "setLocation",
		location = location,
	})
end

function MP.ACTIONS.update_location(keep_blind)
	if MP.GAME.location_type then
		MP.ACTIONS.set_location(MP.GAME.location_type, keep_blind and MP.GAME.location_blind or nil)
	end
end

---@param score number
---@param hands_left number
function MP.ACTIONS.play_hand(score, hands_left)
	local fixed_score = tostring(to_big(score))
	-- Credit to sidmeierscivilizationv on discord for this fix for Talisman
	if string.match(fixed_score, "[eE]") == nil and string.match(fixed_score, "[.]") then
		-- Remove decimal from non-exponential numbers
		fixed_score = string.sub(string.gsub(fixed_score, "%.", ","), 1, -3)
	end
	fixed_score = string.gsub(fixed_score, ",", "") -- Remove commas

	local insane_int_score = MP.INSANE_INT.from_string(fixed_score)
	MP.GAME.score = insane_int_score
	if MP.INSANE_INT.greater_than(insane_int_score, MP.GAME.highest_score) then
		MP.GAME.highest_score = insane_int_score
	end

	Client.send({
		action = "playHand",
		score = fixed_score,
		handsLeft = hands_left,
	})
end

function MP.ACTIONS.lobby_options()
	---@type table<string, any>
	local msg = {
		action = "lobbyOptions",
	}
	for k, v in pairs(MP.LOBBY.config) do
		msg[tostring(k)] = v
	end
	Client.send(msg)
end

function MP.ACTIONS.set_ante(ante)
	Client.send({
		action = "setAnte",
		ante = ante,
	})
end

function MP.ACTIONS.new_round()
	MP.GAME.duplicate_end = false
	MP.GAME.round_ended = false
	Client.send({
		action = "newRound",
	})
end

function MP.ACTIONS.set_furthest_blind(furthest_blind)
	Client.send({
		action = "setFurthestBlind",
		furthestBlind = furthest_blind,
	})
end

function MP.ACTIONS.skip(skips)
	Client.send({
		action = "skip",
		skips = skips,
	})
end

function MP.ACTIONS.send_phantom(key)
	Client.send({
		action = "sendPhantom",
		key = key,
	})
end

function MP.ACTIONS.remove_phantom(key)
	Client.send({
		action = "removePhantom",
		key = key,
	})
end

function MP.ACTIONS.asteroid()
	Client.send({
		action = "asteroid",
	})
end

function MP.ACTIONS.sold_joker()
	Client.send({
		action = "soldJoker",
	})
end

function MP.ACTIONS.lets_go_gambling_nemesis()
	Client.send({
		action = "letsGoGamblingNemesis",
	})
end

function MP.ACTIONS.eat_pizza(discards)
	Client.send({
		action = "eatPizza",
		whole = discards,
	})
end

function MP.ACTIONS.spent_last_shop(amount)
	Client.send({
		action = "spentLastShop",
		amount = amount,
	})
end

function MP.ACTIONS.magnet()
	Client.send({
		action = "magnet",
	})
end

function MP.ACTIONS.magnet_response(key)
	Client.send({
		action = "magnetResponse",
		key = key,
	})
end

function MP.ACTIONS.get_end_game_jokers()
	Client.send({
		action = "getEndGameJokers",
		targetId = MP.GAME.nemesis_id,
	})
end

function MP.ACTIONS.get_nemesis_deck()
	Client.send({
		action = "getNemesisDeck",
		targetId = MP.GAME.nemesis_id,
	})
end

function MP.ACTIONS.send_game_stats()
	Client.send({
		action = "sendGameStats",
	})
	action_send_game_stats()
end

function MP.ACTIONS.request_nemesis_stats()
	Client.send({
		action = "endGameStatsRequested",
		targetId = MP.GAME.nemesis_id,
	})
end

function MP.ACTIONS.start_ante_timer()
	local is_pvp = MP.is_pvp_boss() and MP.is_layer_active("pvp_timer")
	local threshold = MP.LOBBY.config.timer_display_threshold or 0

	action_start_ante_timer({ time = MP.GAME.timer, fromNemesis = false })

	if threshold > 0 and MP.GAME.timer > threshold then
		MP.GAME.timer_threshold_pending = true
	else
		Client.send({
			action = "startAnteTimer",
			time = MP.GAME.timer,
			isPvP = is_pvp or nil,
		})
	end
end

function MP.ACTIONS.pause_ante_timer()
	if MP.GAME.timer_threshold_pending then
		MP.GAME.timer_threshold_pending = false
	else
		Client.send({
			action = "pauseAnteTimer",
			time = MP.GAME.timer,
		})
	end
	action_pause_ante_timer({ time = MP.GAME.timer, fromNemesis = false })
end

function MP.ACTIONS.fail_timer()
	Client.send({
		action = "failTimer",
	})
end
function MP.ACTIONS.fail_pvp_timer()
	Client.send({
		action = "failPvPTimer",
	})
end

function MP.ACTIONS.sync_client()
	Client.send({
		action = "syncClient",
		isCached = _RELEASE_MODE,
	})
end

-- Live carbon-log stream: batches of "MP_RLOG: ..." lines pushed while the game
-- is in progress, keyed by game_id so the server can group them and drop them
-- once the final package below lands. See lib/replay_log.lua (MP.RLOG).
function MP.ACTIONS.stream_log_lines(game_id, lines)
	Client.send({
		action = "streamLogLines",
		gameId = game_id,
		lines = lines,
	})
end

-- End-of-game replay-log fingerprints. The server stores these (keyed by
-- lobby + seed + game) so a presented log can later be re-hashed and compared
-- without a line-by-line diff, and uses game_id to delete the live stream in
-- favour of this complete package. See lib/replay_log.lua (MP.RLOG).
function MP.ACTIONS.submit_log_hashes(carbon, human, seed, log, game_id)
	Client.send({
		action = "submitLogHashes",
		carbon = carbon,
		human = human,
		seed = seed,
		log = log,
		gameId = game_id,
	})
end

function MP.ACTIONS.modded(modId, modAction, params, target)
	local msg = {
		action = "moddedAction",
		modId = modId,
		modAction = modAction,
	}
	if params then
		for k, v in pairs(params) do
			msg[k] = v
		end
	end
	if target then msg.target = target end
	Client.send(msg)
end

-- #endregion Client to Server

-- Utils
function MP.ACTIONS.connect()
	Client.send({
		action = "connect",
	})
end

function MP.ACTIONS.update_player_usernames()
	if MP.LOBBY.code then
		if G.MAIN_MENU_UI then G.MAIN_MENU_UI:remove() end
		set_main_menu_UI()
	end
end

function MP.ACTIONS.data_sync()
    local timer = (MP.is_layer_active("speedlatro_timer") and MP.speedlatro_timer and MP.speedlatro_timer.real) or MP.GAME.timer
    Client.send({
        action = "dataSync",
        timer = timer
    })
end

local function string_to_table(str)
	local tbl = {}
	for part in string.gmatch(str, "([^,]+)") do
		local key, value = string.match(part, "([^:]+):(.+)")
		if key and value then tbl[key] = value end
	end
	return tbl
end

local last_game_seed = nil

local function noop() end

local HANDLERS = {
	connected = action_connected,
	version = action_version,
	disconnected = action_disconnected,
	reconnecting = action_reconnecting,
	joinedLobby = action_joinedLobby,
	rejoinedLobby = action_rejoinedLobby,
	hostMigrating = action_host_migrating,
	hostMigrated = action_host_migrated,
	hostMigrationFailed = action_host_migration_failed,
	enemyDisconnected = action_enemyDisconnected,
	enemyReconnected = action_enemyReconnected,
	lobbyInfo = action_lobbyInfo,
	startGame = action_start_game,
	startBlind = action_start_blind,
	enemyInfo = function(p) return action_enemy_info(p) end,
	playerEliminated = action_player_eliminated,
	playerLeft = action_player_left,
	resumeGame = action_resume_game,
	playerJoined = action_player_joined,
	rejoinFailed = action_rejoin_failed,
	stopGame = action_stop_game,
	endPvP = action_end_pvp,
	playerInfo = action_player_info,
	winGame = action_win_game,
	loseGame = action_lose_game,
	lobbyOptions = action_lobby_options,
	enemyLocation = enemyLocation,
	sendPhantom = action_send_phantom,
	removePhantom = action_remove_phantom,
	speedrun = action_speedrun,
	asteroid = action_asteroid,
	soldJoker = action_sold_joker,
	letsGoGamblingNemesis = action_lets_go_gambling_nemesis,
	eatPizza = action_eat_pizza,
	spentLastShop = action_spent_last_shop,
	magnet = action_magnet,
	magnetResponse = action_magnet_response,
	getEndGameJokers = action_get_end_game_jokers,
	receiveEndGameJokers = action_receive_end_game_jokers,
	getNemesisDeck = action_get_nemesis_deck,
	receiveNemesisDeck = action_receive_nemesis_deck,
	endGameStatsRequested = action_send_game_stats,
	nemesisEndGameStats = noop, -- logged only, no handler
	startAnteTimer = action_start_ante_timer,
	pauseAnteTimer = action_pause_ante_timer,
	jimboAppear = action_jimbo_appear,
	jimboTalk = action_jimbo_talk,
	jimboMove = action_jimbo_move,
	jimboRemove = action_jimbo_remove,
	moddedAction = action_modded_action,
	error = action_error,
	keepAlive = action_keep_alive,
    dataSync = action_data_sync,
}

function MP.register_action(name, cb)
	if HANDLERS[name] then
		sendWarnMessage(
			"MP.register_action: '" .. name .. "' already has a handler; refusing to register. Use MP.register_mod_action if possible.",
			"MULTIPLAYER"
		)
		return
	end
	HANDLERS[name] = cb
end

local network_to_ui_channel = love.thread.getChannel("networkToUi")

local game_update_ref = Game.update
---@diagnostic disable-next-line: duplicate-set-field
function Game:update(dt)
	game_update_ref(self, dt)

	repeat
		if MP.SAFE_MODE then network_to_ui_channel:clear(); break end -- 0.6.8: multiplayer is off
		local msg = network_to_ui_channel:pop()
		if msg then
			-- horribly messy catch
			if string.sub(msg, 1, 1) == "a" then
				if msg ~= "action:keepAlive" then
					local networkToUiChannel = love.thread.getChannel("networkToUi")
					networkToUiChannel:push(json.encode({
						action = "error",
						message = "Attempting to connect to outdated server",
					}))
					networkToUiChannel:push('{"action":"disconnected"}')
				end
				return
			end

			local ok, parsedAction = pcall(json.decode, msg)
            if ok then
                if not no_log_actions[parsedAction.action] then
                    local log = string.format("Client got %s message: ", parsedAction.action)
                    for k, v in pairs(parsedAction) do
                        if parsedAction.action == "startGame" and k == "seed" then
                            last_game_seed = v
                        else
                            log = log .. string.format(" (%s: %s) ", k, v)
                        end
                    end
                    if
                        (parsedAction.action == "receiveEndGameJokers" or parsedAction.action == "stopGame")
                        and last_game_seed
                    then
                        log = log .. string.format(" (seed: %s) ", last_game_seed)
                    end
                    sendTraceMessage(log, "MULTIPLAYER")
                end
    
                local handler = HANDLERS[parsedAction.action]
                if handler then
                    if MP.SPECTATE and MP.SPECTATE.state.joined and G.STAGE ~= G.STAGES.RUN then
                        -- 0.6.8: watching from the lobby (no run): match messages must never crash the menu
                        local hok, herr = pcall(handler, parsedAction)
                        if not hok then sendDebugMessage("Spectator ignored " .. tostring(parsedAction.action) .. ": " .. tostring(herr), "MULTIPLAYER") end
                    else
                        handler(parsedAction)
                    end
                end
            else
                sendWarnMessage(
                    "Invalid server response: " .. msg,
                    "MULTIPLAYER"
                )
            end
		end
	until not msg
end
