MP = SMODS.current_mod

-- Display names in one place. The mod id stays "Multiplayer" (save data, config, SMODS.Mods lookups),
-- and the install folder / GitHub repo / release zip names stay "BalatroMultiplayer3P" so 0.6.6
-- installs keep finding updates (GitHub redirects if the repo is renamed later).
MP.BRAND = {
	name = "Balatro High Stakes",
	short = "High Stakes",
	former_name = "Balatro Multiplayer 3P",
	author = "Trust Ben Dover",
	repo = "trustbendover/BalatroMultiplayer3P",
	folder = "BalatroMultiplayer3P",
	min_players = 2,
	max_players = 8,
}

MP.BANNED_MODS = {
	["Incantation"] = true,
	["Brainstorm"] = true,
	["DVPreview"] = true,
	["Aura"] = true,
	["NotJustYet"] = true,
	["Showman"] = true,
	["TagPreview"] = true,
	["FantomsPreview"] = true,
}

MP.LOBBY = {
	connected = false,
	temp_code = "",
	temp_seed = "",
	code = nil,
	type = "",
	config = {}, -- Now set in MP.reset_lobby_config
	deck = {
		back = "Red Deck",
		sleeve = "sleeve_casl_none",
		stake = 1,
		challenge = "",
	},
	username = "Guest",
	blind_col = 1,
	host = {},
	guest = {},
	third = {}, -- seat 3 alias
	seats = {}, -- seats 1..8 (seat 1 = host)
	max_players = 8,
	player_list = {},
	player_count = 0,
	is_host = false,
	ready_to_start = false,
}
MP.GAME = {}
MP.UI = {}
MP.ACTIONS = {}
MP.MOD_ACTIONS = {}

-- SMODS flag: lets cards count as multiple enhancements at once (required by Alloy)
MP.optional_features = { quantum_enhancements = false }

function MP.register_mod_action(modAction, callback, modId)
	if not modId then
		local mod = SMODS.current_mod
		if not mod then
			sendWarnMessage("MP.register_mod_action called outside of mod init without a modId", "MULTIPLAYER")
			return
		end
		modId = mod.id
	end
	MP.MOD_ACTIONS[modId] = MP.MOD_ACTIONS[modId] or {}
	MP.MOD_ACTIONS[modId][modAction] = callback
end

MP.INTEGRATIONS = {
	Preview = SMODS.Mods["Multiplayer"].config.integrations.Preview,
}

MP.PREVIEW = {
	text = SMODS.Mods["Multiplayer"].config.preview.text,
	button = SMODS.Mods["Multiplayer"].config.preview.button,
}

MP.EXPERIMENTAL = {
	show_sandbox_collection = false,
	alt_stakes = false,
	suppress_dev_warning = false,
	mem_debug = true,
}

-- Override experimental flags and server config from .env file if present
MP.ENV = {}
local env_path = MP.path .. "/.env"
local env_info = NFS.getInfo(env_path)
if env_info then
	local content = NFS.read(env_path)
	if content then
		for line in content:gmatch("[^\r\n]+") do
			line = line:match("^%s*(.-)%s*$") -- trim
			if line ~= "" and not line:match("^#") then
				local key, val = line:match("^([%w_]+)%s*=%s*(.+)$")
				if key then
					if val == "true" then
						val = true
					elseif val == "false" then
						val = false
					end
					MP.ENV[key] = val
					if MP.EXPERIMENTAL[key] ~= nil then
						MP.EXPERIMENTAL[key] = val
					end
				end
			end
		end
		sendDebugMessage("Loaded .env overrides", "MULTIPLAYER")
	end
end

G.C.MULTIPLAYER = HEX("AC3232")

MP.SMODS_VERSION = "1.0.0~BETA-1620a"
MP.REQUIRED_LOVELY_VERSION = "0.9"

function MP.should_use_the_order()
	if MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.the_order and MP.LOBBY.code then
		return true
	elseif MP.is_practice_mode() then -- should actually check the ruleset but okay for now
		return true
	end
	return false
end

function MP.is_major_league_ruleset()
	return MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.ruleset == "ruleset_mp_majorleague" and MP.LOBBY.code
end

function MP.current_ruleset()
    return {}
end

-- 0.6.8: files that failed to load (the compat guard turns multiplayer off if a core one did)
MP.LOAD_ERRORS = MP.LOAD_ERRORS or {}
function MP.load_mp_file(file)
	local chunk, err = SMODS.load_file(file, "Multiplayer")
	if chunk then
		local ok, func = pcall(chunk)
		if ok then
			return func
		else
			sendWarnMessage("Failed to process file: " .. tostring(func), "MULTIPLAYER")
			MP.LOAD_ERRORS[#MP.LOAD_ERRORS + 1] = { file = file, err = tostring(func) }
		end
	else
		sendWarnMessage("Failed to find or compile file: " .. tostring(err), "MULTIPLAYER")
		MP.LOAD_ERRORS[#MP.LOAD_ERRORS + 1] = { file = file, err = tostring(err) }
	end
	return nil
end

function MP.load_mp_dir(directory, recursive)
	recursive = recursive or false
	local function has_prefix(name)
		return name:match("^_") ~= nil
	end

	local dir_path = MP.path .. "/" .. directory
	local items = NFS.getDirectoryItemsInfo(dir_path)
	-- sort by prefix like { _file, _dir, file, dir }
	table.sort(items, function(a, b)
		local ac, bc = 0, 0
		if has_prefix(a.name) then ac = ac + 100 end
		if has_prefix(b.name) then bc = bc + 100 end
		if a.type == "directory" then ac = ac + 10 end
		if b.type == "directory" then bc = bc + 10 end
		if ac ~= bc then return ac > bc end
		return string.lower(a.name) < string.lower(b.name)
	end)

	-- load sorted files/dirs
	for _, item in ipairs(items) do
		local path = directory .. "/" .. item.name
		if item.type ~= "directory" then
			MP.load_mp_file(path)
		elseif recursive then
			MP.load_mp_dir(path, recursive)
		end
	end
end

MP.load_mp_dir("lib")
MP.load_mp_dir("overrides")

function MP.reset_lobby_config(persist_ruleset_and_gamemode)
	sendDebugMessage("Resetting lobby options", "MULTIPLAYER")
	MP.LOBBY.config = {
		gold_on_life_loss = true,
		no_gold_on_round_loss = false,
		death_on_round_loss = true,
		different_seeds = false,
		the_order = true,
		starting_lives = 4,
		pvp_start_round = 2,
		timer_base_seconds = 150,
		timer_increment_seconds = 60,
		pvp_countdown_seconds = 3,
		showdown_starting_antes = 3,
		ruleset = persist_ruleset_and_gamemode and MP.LOBBY.config.ruleset or "ruleset_mp_blitz",
		gamemode = persist_ruleset_and_gamemode and MP.LOBBY.config.gamemode or "gamemode_mp_attrition",
		weekly = nil,
		custom_seed = "random",
		different_decks = false,
		random_loadout = false,
		back = "Red Deck",
		sleeve = "sleeve_casl_none",
		stake = 1,
		challenge = "",
		cocktail = "",
		multiplayer_jokers = true,
		timer = true,
		timer_forgiveness = 0,
		forced_config = false,
		preview_disabled = false,
		legacy_smallworld = false,
		-- Baseline off; start_lobby sets it on for standard-layer rulesets.
		hide_score_until_played = false,
		enemy_location_disabled = false,
		timer_display_threshold = 0,
	}
end
MP.reset_lobby_config()

function MP.reset_game_states()
	sendDebugMessage("Resetting game states", "MULTIPLAYER")
	MP.GAME = {
		ready_blind = false,
		ready_blind_text = localize("b_ready"),
		processed_round_done = false,
		lives = 0,
		loaded_ante = 0,
		loading_blinds = false,
		comeback_bonus_given = true,
		comeback_bonus = 0,
		end_pvp = false,
		-- 3P fork: per-opponent state keyed by server player id
		enemies = {},
		enemy_focus_id = nil,
		enemy = {
			username = "",
			hud_title = "",
			opponents_text = "",
			score = MP.INSANE_INT.empty(),
			real_score = MP.INSANE_INT.empty(),
			score_text = "0",
			hands = 4,
			hands_text = "4",
			-- Whether an enemyInfo message has arrived this blind. Used to mask
			-- the opponent's hands as "?" until we hear from them.
			info_received = false,
			location = localize("loc_selecting"),
			skips = 0,
            skips_before_pvp = 0,
			lives = MP.LOBBY.config.starting_lives,
			sells = 0,
			sells_per_ante = {},
			spent_in_shop = {},
			highest_score = MP.INSANE_INT.empty(),
		},
		location = "loc_selecting",
		next_blind_context = nil,
		ante_key = tostring(math.random()),
		antes_keyed = {},
		prevent_eval = false,
		round_ended = false,
		duplicate_end = false,
		misprint_display = "",
		spent_total = 0,
		spent_before_shop = 0,
		highest_score = MP.INSANE_INT.empty(),
		timer = MP.UTILS.timer_base(),
		timer_started = false,
        timer_was_started = false,
        nemesis_timer_started = false,
        nemesis_timer_was_started = false,
		timer_threshold_pending = false,
		timer_consumed = false,
		pvp_reached = false,
        pvp_reached_first = false,
		pvp_countdown = 0,
		real_money = 0,
		ce_cache = false,
		furthest_blind = 0,
		pincher_index = -3,
		pincher_unlock = false,
		asteroids = 0,
		pizza_discards = 0,
		wait_for_enemys_furthest_blind = false,
		disable_live_and_timer_hud = false,
		timers_forgiven = 0,
		stats = {
			reroll_count = 0,
			reroll_cost_total = 0,
			-- Add more stats here in the future
		},
        pvp_timer_order = nil,
        pvp_timer_activated = false,
        skips_before_pvp = 0,
        skips_difference = 0,
	}
end
MP.reset_game_states()

MP.LOBBY.username = MP.UTILS.get_username()
MP.LOBBY.blind_col = MP.UTILS.get_blind_col()

MP.LOBBY.config.weekly = MP.UTILS.get_weekly()

if not SMODS.current_mod.lovely then
	G.E_MANAGER:add_event(Event({
		no_delete = true,
		trigger = "immediate",
		blockable = false,
		blocking = false,
		func = function()
			if G.MAIN_MENU_UI then
				MP.UI.UTILS.overlay_message(
					MP.UTILS.wrapText(
						"Your Multiplayer Mod is not loaded correctly, make sure the Multiplayer folder does not have an extra Multiplayer folder around it.",
						50
					)
				)
				return true
			end
		end,
	}))
	return
end

SMODS.Atlas({
	key = "modicon",
	path = "modicon.png",
	px = 34,
	py = 34,
})

MP.load_mp_dir("compatibility")

MP.load_mp_file("networking/action_handlers.lua")

MP.load_mp_dir("gamemodes")
MP.load_mp_dir("layers")
MP.load_mp_dir("rulesets", true)
MP.load_mp_dir("ui", true)
MP.load_mp_dir("objects/editions")
MP.load_mp_dir("objects/enhancements")
MP.load_mp_dir("objects/seals")
MP.load_mp_dir("objects/stickers")
MP.load_mp_dir("objects/blinds")
MP.load_mp_dir("objects/decks")
MP.load_mp_dir("objects/jokers")
MP.load_mp_dir("objects/jokers/sandbox")
MP.load_mp_dir("objects/jokers/sandbox/extra-credit")
MP.load_mp_dir("objects/jokers/standard")
MP.load_mp_dir("objects/jokers/experimental")
MP.load_mp_dir("objects/jokers/threep") -- 3P fork: special 3-player jokers
MP.load_mp_dir("objects/stakes")
MP.load_mp_dir("objects/tags")
MP.load_mp_dir("objects/consumables")
MP.load_mp_dir("objects/consumables/sandbox")
MP.load_mp_dir("objects/boosters")
MP.load_mp_dir("objects/challenges")

-- 3P fork: optional Steam peer-to-peer mode (.env: mode=steam). TCP stays the default/fallback.
-- 0.6.8 compat guard: untested Balatro/Steamodded/Lovely -> warning on the main menu; blocked
-- version or a core file that failed to load -> safe mode (no networking, singleplayer works)
local net_allowed = true
if MP.COMPAT_GUARD and MP.COMPAT_GUARD.startup then
	local gok, allowed = pcall(MP.COMPAT_GUARD.startup)
	net_allowed = not gok or allowed ~= false
end

MP.STEAM_P2P = nil
if MP.ENV.mode == "steam" and net_allowed then
	local function create_router()
		local P2P = MP.load_mp_file("networking/steam_p2p.lua")
		local Core = MP.load_mp_file("networking/p2p_server.lua")
		if not P2P or not Core then error("P2P modules failed to load") end
		Core.KOTH = MP.load_mp_file("networking/koth_rules.lua") -- King of the Hill gamemode rules
		Core.TEAMS = MP.load_mp_file("networking/teams_rules.lua") -- Teams gamemode rules
		Core.PVP = MP.load_mp_file("networking/pvp_rules.lua") -- free-for-all life loss (2-8 players)
		local backend, berr = P2P.new_ffi_backend()
		if not backend then error(berr) end
		local json = require("json")
		local ui = love.thread.getChannel("networkToUi")
		return P2P.new_router({
			backend = backend, Core = Core, json = json, now = os.time,
			Migration = MP.load_mp_file("networking/host_migration.lua"), -- 0.6.8: host migration
			version = MP.MOD_VERSION or "3P",
			push = function(str) ui:push(str) end,
			-- invites are joined only once the main menu exists (joining during the splash broke the lobby UI)
			ready = function()
				local menu = G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
				if not menu then MP.P2P_MENU_AT = nil; return false end
				MP.P2P_MENU_AT = MP.P2P_MENU_AT or love.timer.getTime()
				return love.timer.getTime() - MP.P2P_MENU_AT > 1.5
			end,
			log = function(m) sendInfoMessage(m, "MULTIPLAYER-P2P") end,
		})
	end
	local ok, err = pcall(function() MP.STEAM_P2P = create_router() end)
	if not ok then
		-- SteamAPI may be initialised after mods load: retry for 30 s, queueing messages meanwhile
		sendInfoMessage("Steam P2P not ready yet (" .. tostring(err) .. "), retrying", "MULTIPLAYER")
		local queue, t, last = {}, 0, -1
		local stub = { pending = true }
		function stub.send(msg) queue[#queue + 1] = msg end
		function stub.invite() return false end
		function stub.update(dt)
			t = t + (dt or 0)
			if math.floor(t) == last then return end
			last = math.floor(t)
			local rok, r = pcall(create_router)
			if rok then
				MP.STEAM_P2P = r
				sendInfoMessage("Steam P2P mode active after " .. last .. "s (no server needed)", "MULTIPLAYER")
				for _, m in ipairs(queue) do r.send(m) end
			elseif t > 30 then
				MP.STEAM_P2P = nil
				sendWarnMessage("Steam P2P unavailable, falling back to TCP server: " .. tostring(r), "MULTIPLAYER")
				if MP.START_TCP then MP.START_TCP() end
				local json = require("json")
				for _, m in ipairs(queue) do love.thread.getChannel("uiToNetwork"):push(json.encode(m)) end
			end
		end
		MP.STEAM_P2P = stub
		ok = true
	end
	if ok then
		if not MP.STEAM_P2P.pending then sendInfoMessage("Steam P2P mode active (no server needed)", "MULTIPLAYER") end
		-- opt-in diagnostic (.env: p2p_selftest=true): hosts a lobby by itself and checks Steam
		local st = MP.ENV.p2p_selftest and { t = 0, step = 0 } or nil
		local function selftest(dt)
			local R, L = MP.STEAM_P2P, function(m) sendInfoMessage("P2P-SELFTEST " .. m, "MULTIPLAYER") end
			st.t = st.t + dt
			if st.step == 0 and st.t > 8 then
				st.step = 1
				L("my steamid " .. tostring(R.backend.my_id()))
				R.send({ action = "createLobby", gameMode = "attrition" })
			elseif st.step == 1 and R.lobby then
				st.step = 2
				local code = R.backend.get_data(R.lobby, "mp3p_code")
				L("lobby " .. R.lobby .. " code=" .. code .. " owner=" .. R.backend.owner(R.lobby)
					.. " members=" .. #R.backend.members(R.lobby) .. " callbacks=" .. tostring(R.backend.cb_on))
				L("launch args: " .. tostring(R.backend.launch_args()))
				st.code, st.tries, st.next = code, 0, st.t + 5
			elseif st.step == 2 and st.t > st.next and not st.busy then
				st.busy, st.tries = true, st.tries + 1
				R.backend.find_lobby(st.code, function(found)
					st.busy = false
					L("search #" .. st.tries .. " by code " .. st.code .. " -> " .. tostring(found) .. (found == R.lobby and " OK" or " MISMATCH"))
					if found == R.lobby or st.tries >= 4 then
						st.step = 3
						if MP.ENV.p2p_selftest_invite then L("opening invite overlay -> " .. tostring(R.invite())) end
					else st.next = st.t + 10 end
				end)
			elseif st.step == 1 and st.t > 40 then
				st.step = 3; L("FAIL no Steam lobby after 40s")
			end
		end
		local p2p_update_ref = Game.update
		function Game:update(dt)
			if st and st.step < 3 and MP.STEAM_P2P and not MP.STEAM_P2P.pending then
				local sok, serr = pcall(selftest, dt)
				if not sok then st.step = 3; sendWarnMessage("P2P-SELFTEST error " .. tostring(serr), "MULTIPLAYER") end
			end
			if MP.STEAM_P2P then
				local uok, uerr = pcall(MP.STEAM_P2P.update, dt)
				if not uok then sendWarnMessage("Steam P2P update error: " .. tostring(uerr), "MULTIPLAYER") end
			end
			return p2p_update_ref(self, dt)
		end
	else
		MP.STEAM_P2P = nil
		sendWarnMessage("Steam P2P unavailable, falling back to TCP server: " .. tostring(err), "MULTIPLAYER")
	end
end

local SOCKET = MP.load_mp_file("networking/socket.lua")
MP.NETWORKING_THREAD = love.thread.newThread(SOCKET)
local server_url = MP.ENV.server_url or SMODS.Mods["Multiplayer"].config.server_url
local server_port = tonumber(MP.ENV.server_port) or SMODS.Mods["Multiplayer"].config.server_port
sendInfoMessage(
	string.format("Connecting to %s:%s", tostring(server_url), tostring(server_port)),
	"MULTIPLAYER"
)
local tcp_started = false
function MP.START_TCP()
	if tcp_started or MP.SAFE_MODE then return end
	tcp_started = true
	MP.NETWORKING_THREAD:start(server_url, server_port)
end
if not MP.STEAM_P2P and net_allowed then MP.START_TCP() end
if net_allowed then MP.ACTIONS.connect() end
