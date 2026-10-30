-- Balatro High Stakes: player limits per gamemode (client side; the servers enforce the same
-- limits in networking/p2p_server.lua Core.start_error and server/src/Lobby.ts startError).
-- GPL-3.0, based on Balatro Multiplayer.
MP.MODES = MP.MODES or {}
local M = MP.MODES

M.MIN_PLAYERS = 2
M.MAX_PLAYERS = 8
-- min/max players and default lives per mode key (gamemode_mp_<key>)
M.LIMITS = {
	duel = { min = 2, max = 2, lives = 4 },
	attrition = { min = 2, max = 8 },
	showdown = { min = 2, max = 8 },
	koth = { min = 2, max = 8, lives = 3 },
	teams = { min = 4, max = 8, lives = 4 },
	deathmatch = { min = 2, max = 8, lives = 4 },
	survival = { min = 2, max = 8 },
}

M.TEAMS_RULES = M.TEAMS_RULES or (MP.load_mp_file and MP.load_mp_file("networking/teams_rules.lua")) or nil

local function L(key, fallback, vars)
	-- the mode keys live in misc.dictionary, so substitute #n# here (type=variable only reads v_dictionary)
	local ok, s = pcall(localize, key)
	if not (ok and type(s) == "string" and s ~= "ERROR" and s ~= key) and vars then
		ok, s = pcall(localize, { type = "variable", key = key, vars = vars })
		if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then return s end
		s = nil
	end
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then fallback = s end
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key and not vars then return s end
	if vars then
		for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", tostring(v)) end
	end
	return fallback
end
M.L = L

--- "gamemode_mp_teams" -> "teams" (also accepts the bare key).
function M.key(gamemode)
	gamemode = tostring(gamemode or (MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode) or "")
	if gamemode:sub(1, 12) == "gamemode_mp_" then return gamemode:sub(13) end
	return gamemode
end

function M.limits(gamemode)
	return M.LIMITS[M.key(gamemode)] or { min = M.MIN_PLAYERS, max = M.MAX_PLAYERS }
end

function M.default_lives(gamemode)
	return M.limits(gamemode).lives
end

function M.is_teams(gamemode) return M.key(gamemode) == "teams" end
function M.is_duel(gamemode) return M.key(gamemode) == "duel" end

--- Why a lobby of n players cannot start in this mode (localized), or nil when it can.
--- 0.6.8: Versus team format (2, 3 or 4 per team) or nil for free Teams
function M.teams_format(options)
	local f = tonumber((options or {}).teams_format)
	if f and f >= 2 and f <= 4 then return math.floor(f) end
	return nil
end
--- Display name: "2v2" / "3v3" / "4v4" for a Versus team format, else the mode's own name
function M.display_name(gamemode, options)
	local key = M.key(gamemode)
	local f = key == "teams" and M.teams_format(options or (MP.LOBBY and MP.LOBBY.config))
	if f then return f .. "v" .. f end
	return L("k_" .. tostring(key), tostring(key))
end

--- "2 players" / "4 players" / "2-8 players" for a mode (Versus formats: exactly 2 x format)
function M.players_label(key, format)
	local lo, hi
	if key == "teams" and format then lo, hi = 2 * format, 2 * format
	else
		local lim = M.LIMITS[key] or { min = M.MIN_PLAYERS, max = M.MAX_PLAYERS }
		lo, hi = lim.min, lim.max
	end
	if lo == hi then return L("k_mode_players_exact", "#1# players", { lo }) end
	return L("k_mode_players_range", "#1#-#2# players", { lo, hi })
end

function M.start_problem(n, gamemode, options)
	n = tonumber(n) or 0
	local key = M.key(gamemode)
	local lim = M.limits(key)
	options = options or (MP.LOBBY and MP.LOBBY.config) or {}
	if key == "duel" and n ~= 2 then return L("k_mode_need_exactly_2", "1v1 Duel needs exactly 2 players") end
	if n < M.MIN_PLAYERS then return L("k_mode_need_min", "Need at least #1# players", { M.MIN_PLAYERS }) end
	if n > lim.max then return L("k_mode_too_many", "Too many players for this mode (max #1#)", { lim.max }) end
	if key == "teams" and M.teams_format(options) then
		local f = M.teams_format(options)
		if n ~= 2 * f then return L("k_mode_need_exactly_n", "#1# needs exactly #2# players", { M.display_name(gamemode, options), 2 * f }) end
		return nil
	end
	if key == "teams" then
		if n < lim.min or n % 2 ~= 0 then return L("k_mode_teams_split", "Teams needs 4, 6 or 8 players") end
		if M.TEAMS_RULES and not M.TEAMS_RULES.plan(n, options) then return L("k_mode_teams_split", "Teams needs 4, 6 or 8 players") end
	end
	return nil
end

return M
