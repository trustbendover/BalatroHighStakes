MP = SMODS.current_mod

-- Display names in one place (mirrored in mod/brand.json for the updater script, installer and build).
-- The mod id stays "Multiplayer" (save data, config, SMODS.Mods lookups) and the install folder and
-- release zip names stay "BalatroMultiplayer3P", so 0.6.6/0.6.7 installs keep finding and installing
-- updates. 0.6.8: the GitHub repo is renamed to BalatroHighStakes; the old name is the fallback
-- (GitHub redirects it; see docs/REPO_RENAME_NL.md).
MP.BRAND = {
	name = "Balatro High Stakes",
	short = "High Stakes",
	former_name = "Balatro Multiplayer 3P",
	author = "Trust Ben Dover",
	repo = "trustbendover/BalatroHighStakes",
	repo_old = "trustbendover/BalatroMultiplayer3P",
	asset_prefix = "BalatroMultiplayer3P",
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
	local prev = MP.LOBBY.config or {}
	-- Match keys live in networking/match_settings.lua (includes normal_bosses = false).
	-- weekly is personal (which weekly ruleset this profile has already seen) and stays local.
	local cfg = (MP.MATCH and MP.MATCH.fresh) and MP.MATCH.fresh() or {
		normal_bosses = false,
		ruleset = "ruleset_mp_blitz",
		gamemode = "gamemode_mp_attrition",
	}
	if persist_ruleset_and_gamemode then
		if prev.ruleset then cfg.ruleset = prev.ruleset end
		if prev.gamemode then cfg.gamemode = prev.gamemode end
	end
	local weekly = prev.weekly
	MP.LOBBY.config = cfg
	MP.LOBBY.config.weekly = weekly
end
if not MP.MATCH then MP.MATCH = MP.load_mp_file("networking/match_settings.lua") end
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

-- 0.6.8: spectator mode + rejoin (need action_handlers and the lobby UI loaded first)
if MP.SPECTATE and MP.SPECTATE.register then MP.SPECTATE.register() end
if MP.REJOIN and MP.REJOIN.register then MP.REJOIN.register() end
if MP.MATCH_STATS and MP.MATCH_STATS.register then MP.MATCH_STATS.register() end
if MP.CHAT and MP.CHAT.register then MP.CHAT.register() end

-- 0.6.8: Balatro High Stakes is Steam peer-to-peer ONLY. The host's Balatro runs the game server
-- (networking/p2p_server.lua) and friends join with the lobby code over Steam. The old TCP client
-- (server address / playit / Tailscale) was removed; an old .env with another mode is ignored.
-- Compat guard: untested Balatro/Steamodded/Lovely -> warning on the main menu; blocked
-- version or a core file that failed to load -> safe mode (no networking, singleplayer works)
local net_allowed = true
if MP.COMPAT_GUARD and MP.COMPAT_GUARD.startup then
	local gok, allowed = pcall(MP.COMPAT_GUARD.startup)
	net_allowed = not gok or allowed ~= false
end

if MP.ENV.mode ~= nil and MP.ENV.mode ~= "steam" then
	sendWarnMessage("'.env' mode=" .. tostring(MP.ENV.mode)
		.. " is no longer supported (server/TCP mode was removed in 0.6.8): using Steam P2P", "MULTIPLAYER")
end
if MP.ENV.server_url ~= nil or MP.ENV.server_port ~= nil then
	sendInfoMessage("'.env' server_url/server_port are ignored (Steam P2P only since 0.6.8)", "MULTIPLAYER")
end
MP.ENV.mode = "steam"

-- DEV ONLY: local test transport for several instances on one PC (tools/dev_local_match.ps1). mod/dev/ is never
-- shipped in a release zip (tools/build_release.py refuses), and even then it needs dev/DEV_BUILD + HS_DEV_LOCAL=1.
MP.DEV = nil
if os.getenv("HS_DEV_LOCAL") == "1" and NFS.getInfo(MP.path .. "/dev/DEV_BUILD") then
	MP.DEV = MP.load_mp_file("dev/dev_local.lua")
end

MP.STEAM_P2P = nil
do
	local function create_router()
		local P2P = MP.load_mp_file("networking/steam_p2p.lua")
		local Core = MP.load_mp_file("networking/p2p_server.lua")
		if not P2P or not Core then error("P2P modules failed to load") end
		Core.MATCH = Core.MATCH or MP.MATCH -- host match settings (join / start / rejoin)
		Core.KOTH = MP.load_mp_file("networking/koth_rules.lua") -- King of the Hill gamemode rules
		Core.TEAMS = MP.load_mp_file("networking/teams_rules.lua") -- Teams gamemode rules
		Core.PVP = MP.load_mp_file("networking/pvp_rules.lua") -- free-for-all life loss (2-8 players)
		local backend, berr
		if MP.DEV and MP.DEV.new_backend then backend, berr = MP.DEV.new_backend() else backend, berr = P2P.new_ffi_backend() end
		if not backend then error(berr) end
		local json = require("json")
		local ui = love.thread.getChannel("networkToUi")
		return P2P.new_router({
			backend = backend, Core = Core, json = json, now = os.time,
			Migration = MP.load_mp_file("networking/host_migration.lua"), -- 0.6.8: host migration
			version = MP.MOD_VERSION or "0",
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
	-- SteamAPI may be initialised after mods load: retry for 30 s, queueing messages meanwhile.
	-- If Steam stays unavailable, multiplayer is simply off (there is no server to fall back to);
	-- the Reconnect button calls MP.START_P2P() again.
	function MP.START_P2P()
		if MP.SAFE_MODE then return false end
		if MP.STEAM_P2P then return true end
		local ok, err = pcall(function() MP.STEAM_P2P = create_router() end)
		if ok then
			sendInfoMessage("Steam P2P mode active (no server needed)", "MULTIPLAYER")
			return true
		end
		sendInfoMessage("Steam P2P not ready yet (" .. tostring(err) .. "), retrying", "MULTIPLAYER")
		local queue, t, last = {}, 0, -1
		local stub = { pending = true }
		function stub.send(msg) queue[#queue + 1] = msg end
		function stub.invite() return false end
		function stub.update(dt)
			if MP.SAFE_MODE then MP.STEAM_P2P = nil; return end
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
				sendWarnMessage("Steam P2P unavailable: " .. tostring(r)
					.. " - multiplayer needs Steam (start Balatro from Steam, then press Reconnect)", "MULTIPLAYER")
				pcall(function() love.thread.getChannel("networkToUi"):push('{"action":"disconnected"}') end)
			end
		end
		MP.STEAM_P2P = stub
		return true
	end
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
	if net_allowed then MP.START_P2P() end
end

if net_allowed then MP.ACTIONS.connect() end
