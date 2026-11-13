-- Public lobby list for Balatro High Stakes. Pure Lua: no Steam and no UI.
-- The router asks Steam (ISteamMatchmaking) for lobbies and this module decides what may be shown.
--
-- Documented calls used by networking/steam_p2p.lua, not by this file:
--   AddRequestLobbyListStringFilter(key, value, k_ELobbyComparisonEqual = 0)
--   AddRequestLobbyListDistanceFilter(k_ELobbyDistanceFilterWorldwide = 3)
--   AddRequestLobbyListResultCountFilter(cap)
--   RequestLobbyList -> LobbyMatchList_t (callback 510)
--   GetLobbyByIndex / GetLobbyData on that result only
--   RequestLobbyData -> LobbyDataUpdate_t (callback 505) before a list Join or Watch
-- RequestLobbyList returns Public lobbies and also Invisible ones that match the filter.
-- Private here is Invisible, so the filter requires mp3p_discover=1. Absent or "0" stays off the list.
-- A lobby id from an older list is joined only after RequestLobbyData still says it is public.
-- Metadata is untrusted: wrong types, extra keys, and odd strings are dropped or clipped.
-- Nothing in a lobby field is executed.

local M = {}

M.MOD = "hs"
M.LIST_CAP = 48
M.PAGE = 6
M.NAME_MAX = 24

M.MODES = {
	attrition = true, duel = true, teams = true, showdown = true,
	koth = true, deathmatch = true, survival = true, gambel_time = true,
}

-- Cleared (empty value removes the key on Steam) whenever the lobby is not public.
M.CLEAR_KEYS = {
	"mp3p_mod", "mp3p_name", "mp3p_mode", "mp3p_fmt", "mp3p_split",
	"mp3p_players", "mp3p_max", "mp3p_state", "mp3p_watch",
	"mp3p_boss", "mp3p_lives", "mp3p_pvp", "mp3p_show", "mp3p_timer",
}

M.FAIL = {
	unavailable = "The lobby list needs Steam.",
	busy = "Already joining a lobby.",
	private = "That lobby is no longer public.",
	full = "That lobby is full.",
	playing = "That match is already in progress.",
	unconfirmed = "Could not confirm this lobby is still public.",
	closed = "That lobby cannot be joined from the list.",
	failed = "The lobby list could not be loaded.",
}

function M.version(s)
	s = tostring(s or "")
	if #s > 32 then s = s:sub(1, 32) end
	if not s:match("^[%w%._~+-]+$") then return "" end
	return s
end

function M.filters(version)
	return {
		{ key = "mp3p_discover", value = "1" },
		{ key = "mp3p_mod", value = M.MOD },
		{ key = "mp3p_version", value = M.version(version) },
	}
end

function M.read_keys()
	return {
		"mp3p_discover", "mp3p_mod", "mp3p_version", "mp3p_name", "mp3p_mode",
		"mp3p_fmt", "mp3p_players", "mp3p_max", "mp3p_state", "mp3p_watch", "mp3p_code",
		"mp3p_boss", "mp3p_lives", "mp3p_pvp", "mp3p_show", "mp3p_timer", "mp3p_split",
	}
end

function M.sanitize_name(s)
	if type(s) ~= "string" then return nil end
	local out, i, n = {}, 1, 0
	while i <= #s and n < M.NAME_MAX do
		local b = s:byte(i)
		if b < 32 or b == 127 then
			i = i + 1
		elseif b < 128 then
			local c = s:sub(i, i)
			if c:match("[%w %.,'%-_]") then
				out[#out + 1] = c
				n = n + 1
			end
			i = i + 1
		else
			local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or nil
			if not len or i + len - 1 > #s then break end
			local okc = true
			for j = 1, len - 1 do
				local cb = s:byte(i + j)
				if not cb or cb < 128 or cb >= 192 then okc = false end
			end
			if not okc then break end
			if n + 1 > M.NAME_MAX then break end
			out[#out + 1] = s:sub(i, i + len - 1)
			n = n + 1
			i = i + len
		end
	end
	local name = table.concat(out):gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " ")
	if name == "" then return nil end
	return name
end

local function blank()
	local out = { mp3p_discover = "0" }
	for _, k in ipairs(M.CLEAR_KEYS) do out[k] = "" end
	return out
end

--- Fields to write on the host's Steam lobby. Empty strings clear a previous public listing.
function M.publish(L, opt)
	opt = opt or {}
	local out = blank()
	if not opt.public or type(L) ~= "table" then return out end
	local mode = tostring(L.gameMode or "")
	if not M.MODES[mode] then return out end
	local ver = M.version(opt.version)
	if ver == "" then return out end
	local seated, specs = 0, 0
	for _, p in ipairs(L.players or {}) do
		if type(p) == "table" and p.spectator then specs = specs + 1
		elseif type(p) == "table" then seated = seated + 1 end
	end
	local maxp = 8
	if type(opt.max_players) == "function" then
		local ok, n = pcall(opt.max_players, mode)
		if ok and tonumber(n) then maxp = tonumber(n) end
	end
	maxp = math.floor(maxp)
	if maxp < 1 or maxp > 16 then maxp = 8 end
	if seated < 0 then seated = 0 end
	if seated > 16 then seated = 16 end
	local fmt, split = "", ""
	if mode == "teams" then
		local f = tonumber(type(L.options) == "table" and L.options.teams_format)
		if f == 2 or f == 3 or f == 4 then fmt = tostring(math.floor(f))
		elseif seated == 5 then split = "3v2"
		elseif seated == 7 then split = "4v3" end
	end
	local max_spec = tonumber(opt.max_spectators) or 8
	local host = type(L.players) == "table" and L.players[1] or nil
	local optn = type(L.options) == "table" and L.options or {}
	local function flag(v)
		if v == true or v == "true" or v == 1 or v == "1" then return "1" end
		if v == false or v == "false" or v == 0 or v == "0" then return "0" end
		return ""
	end
	local function whole(v, lo, hi)
		local n = tonumber(v)
		if not n or n ~= math.floor(n) or n < lo or n > hi then return "" end
		return tostring(math.floor(n))
	end
	out.mp3p_discover = "1"
	out.mp3p_mod = M.MOD
	out.mp3p_version = ver
	out.mp3p_name = M.sanitize_name(host and host.username) or ""
	out.mp3p_mode = mode
	out.mp3p_fmt = fmt
	out.mp3p_split = split
	out.mp3p_players = tostring(seated)
	out.mp3p_max = tostring(maxp)
	out.mp3p_state = L.isInGame and "play" or "wait"
	out.mp3p_watch = (L.isInGame and specs < max_spec) and "1" or "0"
	-- Only an explicit host value is published. Nil stays empty so a reader cannot treat it as off.
	out.mp3p_boss = flag(optn.normal_bosses)
	out.mp3p_lives = whole(optn.starting_lives, 1, 16)
	out.mp3p_pvp = whole(optn.pvp_start_round, 1, 20)
	out.mp3p_show = mode == "showdown" and whole(optn.showdown_starting_antes, 1, 20) or ""
	out.mp3p_timer = flag(optn.timer)
	return out
end

local function field(data, k)
	local v = data[k]
	if type(v) ~= "string" then return "" end
	if #v > 64 then v = v:sub(1, 64) end
	return v
end

--- nil when the row must not be shown. The lobby code is never copied onto the card.
function M.accept(data, opt)
	opt = opt or {}
	if type(data) ~= "table" then return nil end
	if field(data, "mp3p_discover") ~= "1" then return nil end
	if field(data, "mp3p_mod") ~= M.MOD then return nil end
	local ver = M.version(opt.version)
	if ver == "" or field(data, "mp3p_version") ~= ver then return nil end
	local mode = field(data, "mp3p_mode")
	if not M.MODES[mode] then return nil end
	local state = field(data, "mp3p_state")
	if state ~= "wait" and state ~= "play" then return nil end
	local players = tonumber(field(data, "mp3p_players"))
	local maxp = tonumber(field(data, "mp3p_max"))
	if not players or not maxp or players ~= math.floor(players) or maxp ~= math.floor(maxp) then return nil end
	if players < 0 or players > 16 or maxp < 1 or maxp > 16 then return nil end
	local fmt = field(data, "mp3p_fmt")
	if fmt ~= "" and fmt ~= "2" and fmt ~= "3" and fmt ~= "4" then return nil end
	-- Only an explicit host split. A missing key, or 2v1/5v3, is not guessed from the player count.
	local split = field(data, "mp3p_split")
	if fmt ~= "" or (split ~= "3v2" and split ~= "4v3") then split = "" end
	if (split == "3v2" and players ~= 5) or (split == "4v3" and players ~= 7) then split = "" end
	local watch = field(data, "mp3p_watch")
	if watch ~= "0" and watch ~= "1" then return nil end
	local mode_key = "k_" .. mode
	if mode == "teams" and fmt ~= "" then mode_key = "k_teams" .. fmt end
	local function tri(s)
		if s == "1" then return true end
		if s == "0" then return false end
		return nil
	end
	local function bounded(s, lo, hi)
		local n = tonumber(s)
		if s == "" or not n or n ~= math.floor(n) or n < lo or n > hi then return nil end
		return math.floor(n)
	end
	return {
		name = M.sanitize_name(field(data, "mp3p_name")) or "",
		mode = mode,
		mode_key = mode_key,
		players = players,
		max = maxp,
		state = state,
		watch = watch == "1",
		fmt = fmt,
		split = split ~= "" and split or nil,
		boss = tri(field(data, "mp3p_boss")),
		lives = bounded(field(data, "mp3p_lives"), 1, 16),
		pvp_at = bounded(field(data, "mp3p_pvp"), 1, 20),
		show_at = bounded(field(data, "mp3p_show"), 1, 20),
		timer = tri(field(data, "mp3p_timer")),
	}
end

function M.lobby_code(data)
	if type(data) ~= "table" or type(data.mp3p_code) ~= "string" then return nil end
	local c = data.mp3p_code:upper():gsub("[^A-Z]", "")
	if #c ~= 5 then return nil end
	return c
end

--- "join" for a waiting lobby with a free seat, "watch" only while a match runs and spectators fit.
function M.action(card)
	if type(card) ~= "table" then return nil, "closed" end
	if card.state == "wait" then
		if card.players >= card.max then return nil, "full" end
		return "join"
	end
	if card.state == "play" then
		if card.watch then return "watch" end
		return nil, "playing"
	end
	return nil, "closed"
end

function M.sort(rows)
	table.sort(rows, function(a, b)
		if a.state ~= b.state then return a.state == "wait" end
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.id or "") < tostring(b.id or "")
	end)
end

function M.page_count(n, size)
	size = size or M.PAGE
	if not n or n < 1 then return 1 end
	return math.ceil(n / size)
end

function M.slice(rows, page, size)
	size = size or M.PAGE
	local pages = M.page_count(#rows, size)
	page = math.max(1, math.min(tonumber(page) or 1, pages))
	local out, i0 = {}, (page - 1) * size
	for i = 1, size do
		local row = rows[i0 + i]
		if not row then break end
		out[#out + 1] = row
	end
	return out, page, pages
end

function M.fail_text(reason)
	return M.FAIL[reason] or M.FAIL.closed
end

return M
