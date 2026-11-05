-- Balatro High Stakes: host-authoritative match settings.
-- Pure Lua (no LOVE / Balatro). The host's copy of these keys is the match.
-- Guests apply that copy at join, start, and rejoin. A key the host never set
-- uses the default here, so a guest's leftover local value cannot stay in force.
-- Personal display / audio / accessibility preferences are not in this list and
-- are never written by apply_snapshot / apply_patch.
-- GPL-3.0.

local M = {}

-- kind: bool | num | str. Optional keys stay nil when the host did not set them
-- (0 would be a real value for some of them and would change mode defaults).
M.FIELDS = {
	gold_on_life_loss = "bool",
	no_gold_on_round_loss = "bool",
	death_on_round_loss = "bool",
	different_seeds = "bool",
	the_order = "bool",
	starting_lives = "num",
	pvp_start_round = "num",
	timer_base_seconds = "num",
	timer_increment_seconds = "num",
	pvp_countdown_seconds = "num",
	showdown_starting_antes = "num",
	ruleset = "str",
	gamemode = "str",
	custom_seed = "str",
	different_decks = "bool",
	random_loadout = "bool",
	back = "str",
	sleeve = "str",
	stake = "num",
	challenge = "str",
	cocktail = "str",
	multiplayer_jokers = "bool",
	timer = "bool",
	timer_forgiveness = "num",
	forced_config = "bool",
	preview_disabled = "bool",
	legacy_smallworld = "bool",
	hide_score_until_played = "bool",
	enemy_location_disabled = "bool",
	timer_display_threshold = "num",
	rejoin_grace = "num",
	-- PvP boss-blind effects. Off: the boss slot is the Nemesis blind (no vanilla
	-- boss debuff). On: a normal boss blind, and the round is still PvP.
	normal_bosses = "bool",
	modifier_layers = "str",
	teams_format = "num",
	teams_size = "num",
	disable_live_and_timer_hud = "bool",
	-- Steam lobby listing. Off (default, also when an old host omits it): not marked for a
	-- lobby browser. On: mp3p_discover=1. This does not change who may join with the code.
	lobby_public = "bool",
}

M.DEFAULTS = {
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
	ruleset = "ruleset_mp_blitz",
	gamemode = "gamemode_mp_attrition",
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
	hide_score_until_played = false,
	enemy_location_disabled = false,
	timer_display_threshold = 0,
	rejoin_grace = 0,
	normal_bosses = false,
	modifier_layers = "",
	teams_format = 0,
	teams_size = 2,
	disable_live_and_timer_hud = false,
	lobby_public = false,
}

-- Nil means "mode default", which is not the same as an explicit 0.
M.OPTIONAL = {
	teams_order = "str",
	deathmatch_grace = "num",
	koth_hold_target = "num",
	koth_bounty_money = "num",
	timer_base_multiplier = "num",
}

-- Never taken from the network and never put on the wire.
M.PERSONAL = {
	weekly = true,
	username = true,
	blind_col = true,
	logging = true,
	misprint_display = true,
	timersfx = true,
	integrations = true,
	unlocked = true,
	preview = true,
	joker_stats = true,
	match_history = true,
	ghost_replays = true,
	automatic_pvp_timer = true,
	hide_mp_content = true,
	language = true,
	gamespeed = true,
	reduced_motion = true,
	music = true,
	sound = true,
	screenshake = true,
	rumble = true,
	profile = true,
}

M.SKIP = {
	action = true,
	match_settings = true,
	seed = true,
	deck = true,
	playerCount = true,
	lives = true,
	ante = true,
	code = true,
	type = true,
	reconnectToken = true,
	config = true,
	lateJoin = true,
	eliminated = true,
	blindActive = true,
	inCurrentBlind = true,
	runState = true,
	stats = true,
	inGame = true,
	you = true,
	hostId = true,
	hostName = true,
}

local function clone(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = clone(x) end
	return o
end

function M.canon_gamemode(v)
	if type(v) ~= "string" or v == "" then return M.DEFAULTS.gamemode end
	if v:sub(1, 12) == "gamemode_mp_" then return v end
	return "gamemode_mp_" .. v
end

function M.coerce(key, v)
	local kind = M.FIELDS[key] or M.OPTIONAL[key]
	if kind == "bool" then
		if v == true or v == "true" or v == 1 or v == "1" then return true end
		if v == false or v == "false" or v == 0 or v == "0" then return false end
		if M.DEFAULTS[key] ~= nil then return M.DEFAULTS[key] end
		return false
	end
	if kind == "num" then
		local n = tonumber(v)
		if not n or n ~= n or n == math.huge or n == -math.huge then
			return M.DEFAULTS[key]
		end
		return n
	end
	if kind == "str" then
		if type(v) ~= "string" then v = tostring(v or "") end
		if #v > 200 then v = v:sub(1, 200) end
		return v
	end
	return v
end

function M.is_snapshot(src)
	if type(src) ~= "table" then return false end
	local f = src.match_settings
	return f == 1 or f == "1" or f == true or f == "true"
end

--- Lobby config for a brand-new host. Does not include personal keys.
function M.fresh()
	local c = {}
	for k, v in pairs(M.DEFAULTS) do c[k] = clone(v) end
	return c
end

--- Full host snapshot for the wire. Booleans are always present, including false.
function M.wire(cfg)
	cfg = cfg or {}
	local msg = { match_settings = 1 }
	for k, def in pairs(M.DEFAULTS) do
		if cfg[k] ~= nil then msg[k] = M.coerce(k, cfg[k]) else msg[k] = clone(def) end
	end
	for k in pairs(M.OPTIONAL) do
		if cfg[k] ~= nil then msg[k] = M.coerce(k, cfg[k]) end
	end
	msg.gamemode = M.canon_gamemode(msg.gamemode)
	return msg
end

--- Outbound view of whatever the host has stored. Missing keys become defaults
--- so a guest cannot keep a local value the host never agreed to. Does not
--- mutate opts (server rules keep using only what the host actually sent).
function M.complete(opts, game_mode)
	local msg = M.wire(opts)
	if game_mode ~= nil then msg.gamemode = M.canon_gamemode(game_mode) end
	return msg
end

local function write_known(cfg, src, fill_missing)
	for k, def in pairs(M.DEFAULTS) do
		if src[k] ~= nil then cfg[k] = M.coerce(k, src[k])
		elseif fill_missing then cfg[k] = clone(def) end
	end
	for k in pairs(M.OPTIONAL) do
		if src[k] ~= nil then cfg[k] = M.coerce(k, src[k])
		elseif fill_missing then cfg[k] = nil end
	end
	if cfg.gamemode ~= nil then cfg.gamemode = M.canon_gamemode(cfg.gamemode) end
end

--- Replace every match key. Absent keys become defaults (optional keys become nil).
function M.apply_snapshot(cfg, src)
	if type(cfg) ~= "table" or type(src) ~= "table" then return cfg end
	write_known(cfg, src, true)
	return cfg
end

--- Overwrite only keys the message actually carries. normal_bosses is the
--- exception: an old host message that omits it means Off, not "keep mine".
function M.apply_patch(cfg, src)
	if type(cfg) ~= "table" or type(src) ~= "table" then return cfg end
	write_known(cfg, src, false)
	if src.normal_bosses == nil then cfg.normal_bosses = false end
	return cfg
end

function M.apply(cfg, src)
	if M.is_snapshot(src) then return M.apply_snapshot(cfg, src) end
	return M.apply_patch(cfg, src)
end

--- Server-side store. A snapshot replaces match keys. A partial message (tests,
--- older clients) only overlays the keys it contains, and still publishes
--- normal_bosses = false when the host has never set it.
function M.store(prev, incoming)
	incoming = incoming or {}
	local out = {}
	if M.is_snapshot(incoming) then
		write_known(out, incoming, true)
		return out
	end
	for k, v in pairs(prev or {}) do
		if not M.PERSONAL[k] and not M.SKIP[k] then out[k] = v end
	end
	for k, v in pairs(incoming) do
		if not M.PERSONAL[k] and not M.SKIP[k] then
			if M.FIELDS[k] or M.OPTIONAL[k] then out[k] = M.coerce(k, v)
			else out[k] = v end
		end
	end
	if out.normal_bosses == nil then out.normal_bosses = false end
	return out
end

--- Boss slot once PvP has started.
--- Returns boss_key (nil = vanilla boss), effects (true = vanilla boss debuff on a PvP round).
function M.pvp_boss(ante, cfg)
	cfg = cfg or {}
	local start_at = tonumber(cfg.pvp_start_round) or M.DEFAULTS.pvp_start_round
	if (tonumber(ante) or 1) < start_at then return nil, false end
	local on = cfg.normal_bosses == true or cfg.normal_bosses == "true"
	if on then return nil, true end
	return "bl_mp_nemesis", false
end

if type(MP) == "table" then MP.MATCH = M end

return M
