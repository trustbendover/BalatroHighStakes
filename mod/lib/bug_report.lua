-- Balatro High Stakes: in-game "Report a bug" (0.6.8). GPL-3.0.
-- Main menu / lobby only (never during a match). Collects versions, lobby settings, mods and a log tail,
-- strips personal data, saves the full report in <save dir>/bug_reports/ and opens a prefilled GitHub
-- "new issue" page in the browser. Nothing is ever sent automatically: no tokens, no network calls.
MP.BUG_REPORT = MP.BUG_REPORT or {}
local BR = MP.BUG_REPORT

-- Repo for the issue page. One place to change on rename day (GitHub also redirects the old name).
BR.ISSUE_REPO = "trustbendover/BalatroMultiplayer3P"
BR.MAX_URL = 6000 -- browsers/GitHub cope with longer, but stay well clear
BR.LOG_LINES_FILE = 400 -- full report file
BR.LOG_LINES_URL = 25 -- issue body
BR.DIR = "bug_reports"

BR.TEXT = {
	en = { button = "Report a bug", title = "Report a bug", f_title = "Short title", f_desc = "What happened? (what did you do, what did you expect)",
		submit = "Open bug report", cancel = "Cancel", need_title = "Please enter a short title",
		saved = "Report saved. Your browser opens GitHub; drag the report file from the opened folder into the issue.",
		drag = "Full sanitized report: please drag the file %s (from the folder that just opened) into this issue." },
	nl = { button = "Bug melden", title = "Bug melden", f_title = "Korte titel", f_desc = "Wat gebeurde er? (wat deed je, wat verwachtte je)",
		submit = "Bugmelding openen", cancel = "Annuleren", need_title = "Vul een korte titel in",
		saved = "Melding opgeslagen. Je browser opent GitHub; sleep het bestand uit de geopende map in de melding.",
		drag = "Full sanitized report: please drag the file %s (from the folder that just opened) into this issue." },
}
function BR.lang(code)
	code = code or (G and G.SETTINGS and G.SETTINGS.language)
	if type(code) == "string" and code:lower():sub(1, 2) == "nl" then return "nl" end
	return "en"
end
function BR.T(k) local t = BR.TEXT[BR.lang()] or BR.TEXT.en; return t[k] or BR.TEXT.en[k] or k end

local function esc(s) return (tostring(s):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end

--- Remove personal data. ctx.names / ctx.codes: extra literal strings (player names, lobby codes) to hide.
function BR.sanitize(text, ctx)
	text = tostring(text or "")
	ctx = ctx or {}
	-- user directories (Windows, macOS, Linux; both slash styles)
	text = text:gsub("([A-Za-z]:[\\/]+[Uu]sers[\\/]+)[^\\/\r\n\"']+", "%1USER")
	text = text:gsub("([\\/][Uu]sers[\\/]+)[^\\/\r\n\"']+", "%1USER")
	text = text:gsub("(/home/)[^/\r\n\"']+", "%1USER")
	-- Steam IDs (64-bit, and [U:1:n] style)
	text = text:gsub("7656119%d%d%d%d%d%d%d%d%d%d", "STEAMID")
	text = text:gsub("%[U:%d:%d+%]", "[STEAMID]")
	-- IPv4 (+ port)
	text = text:gsub("%d+%.%d+%.%d+%.%d+", "IP")
	-- tokens / secrets / hashes passed as key=value or key: value
	for _, k in ipairs({ "token", "rejoin_token", "secret", "password", "encryptID", "serversideConnectionID", "hostHash", "guestHash", "auth" }) do
		text = text:gsub("(" .. k .. "%s*[=:]%s*)[^%s,;%)\"']+", "%1REDACTED")
	end
	-- lobby codes and Steam lobby ids
	text = text:gsub("([Cc]ode%s*[=:]?%s*)%u%u%u%u%u%f[^%w]", "%1CODE")
	text = text:gsub("Ldev%d+_[%w_]+", "LOBBY")
	text = text:gsub("(lobby%s+)L[%w_]+", "%1LOBBY")
	-- usernames in log messages ("username: x", "name = x")
	text = text:gsub("(username%s*[=:]%s*)[^%s,;%)\"']+", "%1PLAYER")
	for i, n in ipairs(ctx.names or {}) do
		if type(n) == "string" and #n >= 2 then text = text:gsub(esc(n), "Player" .. i) end
	end
	for _, c in ipairs(ctx.codes or {}) do
		if type(c) == "string" and #c >= 3 then text = text:gsub(esc(c), "CODE") end
	end
	return text
end

function BR.url_encode(s)
	return (tostring(s):gsub("\n", "\r\n"):gsub("([^%w%-%.%_%~ ])", function(c) return string.format("%%%02X", string.byte(c)) end):gsub(" ", "+"))
end

--- Prefilled new-issue URL, total length <= max (the body is cut from the end, on a line break)
function BR.build_url(title, body, max, repo)
	max = max or BR.MAX_URL
	local base = "https://github.com/" .. (repo or BR.ISSUE_REPO) .. "/issues/new?labels=bug&title=" .. BR.url_encode(title or "") .. "&body="
	local b = tostring(body or "")
	local note = "\n\n_(cut: see the attached report file)_"
	local url = base .. BR.url_encode(b)
	while #url > max and #b > 0 do
		local cut = math.max(0, #b - math.max(200, #url - max))
		b = b:sub(1, cut):gsub("\n[^\n]*$", "")
		url = base .. BR.url_encode(b .. note)
	end
	return url
end

function BR.tail(text, n)
	local lines = {}
	for l in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
	while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
	local from = math.max(1, #lines - n + 1)
	return table.concat(lines, "\n", from, #lines)
end

-- ---------- collecting (game side) ----------
local function read_latest_log()
	local ok, res = pcall(function()
		local NFS = rawget(_G, "NFS") or require("nativefs")
		local dir = (SMODS and SMODS.MODS_DIR or "") .. "/lovely/log"
		local best
		for _, f in ipairs(NFS.getDirectoryItems(dir) or {}) do
			if f:match("%.log$") and (not best or f > best) then best = f end
		end
		return best and NFS.read(dir .. "/" .. best) or ""
	end)
	return ok and res or ""
end

function BR.context()
	local names, codes = {}, {}
	local function add(n) if type(n) == "string" and n ~= "" then names[#names + 1] = n end end
	pcall(function()
		add(MP.LOBBY and MP.LOBBY.username)
		for _, p in ipairs((MP.LOBBY and MP.LOBBY.player_list) or {}) do add(type(p) == "table" and (p.username or p.name) or p) end
		if G.STEAM and G.STEAM.friends and G.STEAM.friends.getPersonaName then add(G.STEAM.friends.getPersonaName()) end
		local u = os.getenv("USERNAME") or os.getenv("USER"); add(u)
		if MP.LOBBY and MP.LOBBY.code then codes[#codes + 1] = tostring(MP.LOBBY.code) end
	end)
	return { names = names, codes = codes }
end

function BR.collect(title, desc)
	local cfg = (MP.LOBBY and MP.LOBBY.config) or {}
	local lines = {}
	local function L(s) lines[#lines + 1] = s end
	L("Mod: Balatro High Stakes " .. tostring(MP.MOD_VERSION or (SMODS and SMODS.Mods and SMODS.Mods.Multiplayer and SMODS.Mods.Multiplayer.version) or "?"))
	L("Balatro: " .. tostring(G and G.VERSION or "?") .. " | Steamodded: " .. tostring(SMODS and SMODS.version or MP.SMODS_VERSION or "?")
		.. " | Lovely: " .. tostring((SMODS and SMODS.Mods and SMODS.Mods.Lovely and SMODS.Mods.Lovely.version) or (rawget(_G, "lovely") and lovely.version) or "?"))
	L("OS: " .. tostring(love and love.system and love.system.getOS() or "?") .. " | Language: " .. tostring(G and G.SETTINGS and G.SETTINGS.language or "?"))
	L("In lobby: " .. tostring(MP.LOBBY and MP.LOBBY.code ~= nil) .. " | Host: " .. tostring(MP.LOBBY and MP.LOBBY.is_host or false))
	L("Gamemode: " .. tostring(cfg.gamemode) .. " | Ruleset: " .. tostring(cfg.ruleset))
	local keys = {}
	for k, v in pairs(cfg) do if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k end end
	table.sort(keys)
	local opts = {}
	for _, k in ipairs(keys) do opts[#opts + 1] = k .. "=" .. tostring(cfg[k]) end
	L("Lobby settings: " .. table.concat(opts, ", "))
	local mods = {}
	pcall(function()
		for id, m in pairs(SMODS.Mods or {}) do
			if type(m) == "table" and (m.can_load or m.lovely_only) then mods[#mods + 1] = tostring(id) .. " " .. tostring(m.version or "") end
		end
	end)
	table.sort(mods)
	L("Mods (" .. #mods .. "): " .. table.concat(mods, ", "))
	return { title = title or "", desc = desc or "", info = table.concat(lines, "\n"), log = read_latest_log() }
end

--- Pure: report text (file) and issue body (URL) from collected data
function BR.render(data, ctx, fname)
	local log_full = BR.sanitize(BR.tail(data.log, BR.LOG_LINES_FILE), ctx)
	local log_short = BR.sanitize(BR.tail(data.log, BR.LOG_LINES_URL), ctx)
	local info = BR.sanitize(data.info, ctx)
	local desc = BR.sanitize(data.desc, ctx)
	local file = "# " .. BR.sanitize(data.title, ctx) .. "\n\n" .. desc .. "\n\n## Environment\n" .. info .. "\n\n## Log (last " .. BR.LOG_LINES_FILE .. " lines)\n" .. log_full .. "\n"
	local body = "### What happened\n" .. desc .. "\n\n### Environment\n```\n" .. info .. "\n```\n\n### Log tail\n```\n" .. log_short
		.. "\n```\n\n" .. string.format(BR.TEXT.en.drag, fname or "bug_report.txt") .. "\n"
	return file, body
end

function BR.submit(title, desc)
	local ctx = BR.context()
	local data = BR.collect(title, desc)
	local fname = "bug_report_" .. os.date("%Y%m%d-%H%M%S") .. ".txt"
	local file, body = BR.render(data, ctx, fname)
	pcall(function()
		love.filesystem.createDirectory(BR.DIR)
		love.filesystem.write(BR.DIR .. "/" .. fname, file)
		love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/" .. BR.DIR)
	end)
	local url = BR.build_url(BR.sanitize(title, ctx), body)
	pcall(love.system.openURL, url)
	BR.last = { fname = fname, url = url }
	return fname, url
end

-- ---------- UI ----------
function BR.allowed()
	return G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU
end
BR.form = BR.form or { title = "", desc = "" }
function BR.form_def()
	return create_UIBox_generic_options({
		back_func = "exit_overlay_menu",
		contents = {
			{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
				{ n = G.UIT.T, config = { text = BR.T("title"), scale = 0.6, colour = G.C.WHITE, shadow = true } } } },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { text = BR.T("f_title"), scale = 0.35, colour = G.C.UI.TEXT_LIGHT } } } },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
				create_text_input({ id = "br_title", max_length = 60, w = 8, ref_table = BR.form, ref_value = "title", prompt_text = BR.T("f_title"), extended_corpus = true }) } },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { text = BR.T("f_desc"), scale = 0.35, colour = G.C.UI.TEXT_LIGHT } } } },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
				create_text_input({ id = "br_desc", max_length = 240, w = 12, ref_table = BR.form, ref_value = "desc", prompt_text = BR.T("f_desc"), extended_corpus = true }) } },
			{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
				UIBox_button({ label = { BR.T("submit") }, button = "mp_bug_report_submit", colour = G.C.GREEN, minw = 4, minh = 0.6, scale = 0.45 }) } },
		},
	})
end
function G.FUNCS.mp_bug_report_open()
	if not BR.allowed() then return end
	G.FUNCS.overlay_menu({ definition = BR.form_def() })
end
function G.FUNCS.mp_bug_report_submit()
	if not BR.allowed() then return end
	if (BR.form.title or ""):gsub("%s", "") == "" then
		if attention_text then attention_text({ scale = 0.6, text = BR.T("need_title"), hold = 2, align = "cm", offset = { x = 0, y = -2.5 }, major = G.ROOM_ATTACH }) end
		return
	end
	BR.submit(BR.form.title, BR.form.desc)
	BR.form.title, BR.form.desc = "", ""
	G.FUNCS.exit_overlay_menu()
	if attention_text then attention_text({ scale = 0.45, text = BR.T("saved"), hold = 6, align = "cm", offset = { x = 0, y = -2.5 }, major = G.ROOM_ATTACH }) end
end

--- Small button under the Patch notes button (main menu and lobby screen; the run never shows it)
function BR.add_menu_button()
	pcall(function()
		if G.MP3P_BUGREPORT_UI then G.MP3P_BUGREPORT_UI:remove(); G.MP3P_BUGREPORT_UI = nil end
		if not (BR.allowed() and G.ROOM_ATTACH) then return end
		local y = ((MP.PATCH_NOTES and MP.PATCH_NOTES.menu_button_y) or 1.3) + 0.65
		G.MP3P_BUGREPORT_UI = UIBox({
			definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
				UIBox_button({ label = { BR.T("button") }, button = "mp_bug_report_open", colour = G.C.RED, minw = 2.6, minh = 0.5, scale = 0.38 }),
			} },
			config = { align = "tri", bond = "Weak", offset = { x = 0, y = y }, major = G.ROOM_ATTACH },
		})
	end)
end

return BR
