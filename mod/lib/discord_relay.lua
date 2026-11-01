-- Balatro High Stakes: relay "Report a bug" via the hs-bug-relay worker to Discord #bug-reports. GPL-3.0.
-- Only the sanitized report (lib/bug_report.lua: BR.sanitize: no paths, Steam IDs, IPs, tokens, names or
-- lobby codes) is sent. Rate limited (1 per 2 minutes, 5 per session) and silent when offline.
MP.DISCORD_RELAY = MP.DISCORD_RELAY or {}
local DR = MP.DISCORD_RELAY

DR.MIN_GAP = 120
DR.MAX_SESSION = 5
DR.LOG_LINES = 15
DR.sent = DR.sent or { n = 0, last = nil }
-- Discord embed limits (title 256, description 4096, field value 1024, total 6000)
DR.LIM = { title = 256, desc = 1500, field = 1024, log = 900 }

local function now() return (love and love.timer and love.timer.getTime()) or os.clock() end

--- Pure: cut to n bytes on a UTF-8 boundary, with an ellipsis
function DR.cut(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	local i = n - 3
	while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 0x80 and s:byte(i + 1) < 0xC0 do i = i - 1 end
	return s:sub(1, i) .. "..."
end

--- Pure: may we send now? (t = clock seconds)
function DR.allowed(t)
	if DR.sent.n >= DR.MAX_SESSION then return false, "session limit" end
	if DR.sent.last and t - DR.sent.last < DR.MIN_GAP then return false, "too soon" end
	return true
end

DR.URL = "https://hs-bug-relay.framewise.workers.dev"

--- Pure: the relay payload {description, version, mode, players, log} from BR.collect() data
function DR.payload(data, ctx, info)
	local BR = MP.BUG_REPORT
	local S = function(x) return BR.sanitize(x, ctx) end
	info = info or {}
	local title, desc = S(data.title or ""), S(data.desc or "")
	local d = title ~= "" and (title .. (desc ~= "" and ("\n" .. desc) or "")) or desc
	return {
		description = DR.cut(d ~= "" and d or "(no description)", DR.LIM.desc),
		version = DR.cut(info.version or BR.mod_version(), 100),
		mode = DR.cut(S(info.mode or "?"), 100),
		players = tostring(info.players or "?"),
		log = DR.cut(S(BR.tail(data.log or "", DR.LOG_LINES)), DR.LIM.log),
	}
end

local function get_https()
	local ok, h = pcall(require, "SMODS.https")
	if ok and type(h) == "table" and type(h.asyncRequest) == "function" then return h end
	return nil
end

--- Send (async, never raises, never logs the URL). Returns true when a request was started.
function DR.send(data, ctx)
	if MP.UPDATER and MP.UPDATER.env_off and MP.UPDATER.env_off("discord_bug_relay") then return false end
	local t = now()
	if not DR.allowed(t) then return false end
	local url, h = DR.URL, get_https()
	if not h then return false end
	local cfg = (MP.LOBBY and MP.LOBBY.config) or {}
	local okj, json = pcall(require, "json")
	if not okj then return false end
	local body = json.encode(DR.payload(data, ctx, { mode = cfg.gamemode, players = MP.LOBBY and MP.LOBBY.player_count }))
	DR.sent.n, DR.sent.last = DR.sent.n + 1, t
	pcall(h.asyncRequest, url, { method = "POST", data = body,
		headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "BalatroHighStakes", ["x-hs-client"] = "balatro-high-stakes" } }, function() end)
	return true
end

--- Open the community Discord
DR.INVITE = "https://discord.gg/WSYkhUJ6tx"
if G and G.FUNCS then
	function G.FUNCS.mp_open_discord() pcall(love.system.openURL, DR.INVITE) end
end

return DR
