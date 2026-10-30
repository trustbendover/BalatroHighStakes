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
		submit = "Open bug report", cancel = "Cancel", need_title = "Please enter a short title", ph_title = "Type a short title...", ph_desc = "Describe what happened...", hint = "Click to type",
		saved = "Report saved. Your browser opens GitHub; drag the report file from the opened folder into the issue.",
		drag = "Full sanitized report: please drag the file %s (from the folder that just opened) into this issue." },
	nl = { button = "Bug melden", title = "Bug melden", f_title = "Korte titel", f_desc = "Wat gebeurde er? (wat deed je, wat verwachtte je)",
		submit = "Bugmelding openen", cancel = "Annuleren", need_title = "Vul een korte titel in", ph_title = "Typ een korte titel...", ph_desc = "Beschrijf wat er gebeurde...", hint = "Klik om te typen",
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


-- ---------- multi-line description box (keyboard: type, Enter = new line, Backspace/Delete, arrows, Home/End, Ctrl+V) ----------
BR.DESC_MAX = 1000
BR.DESC_COLS = 64
BR.DESC_ROWS = 7
BR.ml = BR.ml or { text = "", cursor = 0, active = false }
BR.tl = BR.tl or { text = "", cursor = 0, active = false, max = 60, single = true }
BR.TITLE_MAX = 60
local function utf8_prev(s, i) -- byte index of the start of the char ending at i
	if i <= 0 then return 0 end
	local j = i
	while j > 1 and (s:byte(j) or 0) >= 0x80 and (s:byte(j) or 0) < 0xC0 do j = j - 1 end
	return j - 1
end
local function utf8_next(s, i)
	if i >= #s then return #s end
	local j = i + 1
	while j < #s and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do j = j + 1 end
	return j
end
function BR.ml_insert(st, str)
	str = tostring(str or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", " ")
	if st.single then str = str:gsub("\n", " ") end
	local room = (st.max or BR.DESC_MAX) - #st.text
	if room <= 0 then return false end
	if #str > room then -- cut on a whole UTF-8 character
		local keep = {}
		local n = 0
		for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			if n + #ch > room then break end
			keep[#keep + 1] = ch; n = n + #ch
		end
		str = table.concat(keep)
	end
	st.text = st.text:sub(1, st.cursor) .. str .. st.text:sub(st.cursor + 1)
	st.cursor = st.cursor + #str
	return true
end
function BR.ml_key(st, key, ctrl)
	if key == "backspace" then
		if st.cursor > 0 then local p = utf8_prev(st.text, st.cursor); st.text = st.text:sub(1, p) .. st.text:sub(st.cursor + 1); st.cursor = p end
	elseif key == "delete" then
		if st.cursor < #st.text then local n = utf8_next(st.text, st.cursor); st.text = st.text:sub(1, st.cursor) .. st.text:sub(n + 1) end
	elseif key == "left" then st.cursor = utf8_prev(st.text, st.cursor)
	elseif key == "right" then st.cursor = utf8_next(st.text, st.cursor)
	elseif key == "home" then local b = st.text:sub(1, st.cursor):match(".*()\n"); st.cursor = b or 0
	elseif key == "end" then local e = st.text:find("\n", st.cursor + 1, true); st.cursor = e and e - 1 or #st.text
	elseif key == "return" or key == "kpenter" then
		if st.single then return false end
		BR.ml_insert(st, "\n")
	elseif ctrl and key == "v" then
		local okc, clip = pcall(function() return love.system.getClipboardText() end)
		if okc and clip then BR.ml_insert(st, clip) end
	else return false end
	return true
end
--- Wrapped display rows (word wrap at cols, hard breaks on \n), with a "|" cursor when show_cursor;
--- scrolled so the cursor row is visible. Returns rows (always `rows` strings).
function BR.ml_lines(text, cursor, cols, rows, show_cursor)
	local t = text
	if show_cursor then t = text:sub(1, cursor) .. "\1" .. text:sub(cursor + 1) end
	local out, cur_row = {}, 1
	for para in (t .. "\n"):gmatch("([^\n]*)\n") do
		local line = ""
		for word, sp in para:gmatch("([^ ]*)( ?)") do
			if word == "" and sp == "" then break end
			local piece = word .. sp
			while #piece > cols do -- very long word: hard cut
				if #line > 0 then out[#out + 1] = line; line = "" end
				out[#out + 1] = piece:sub(1, cols); piece = piece:sub(cols + 1)
			end
			if #line + #word > cols and #line > 0 then out[#out + 1] = line; line = "" end
			line = line .. piece
		end
		out[#out + 1] = line
	end
	for i, l in ipairs(out) do if l:find("\1", 1, true) then cur_row = i; out[i] = l:gsub("\1", "|") end end
	local first = math.max(1, math.min(cur_row - rows + 1, #out - rows + 1))
	if not show_cursor then first = 1 end
	local res = {}
	for i = 1, rows do res[i] = out[first + i - 1] or "" end
	return res
end
-- one blink clock for both fields
local function blink_on() return math.floor(((love and love.timer and love.timer.getTime()) or 0) * 2) % 2 == 0 end
--- Refresh a field's display rows + placeholder (pure; testable). rows/cols default to the description box.
function BR.field_refresh(st, cols, nrows, placeholder, blink)
	local rows = BR.ml_lines(st.text, st.cursor, cols, nrows, st.active)
	if st.active and not blink then for i, r in ipairs(rows) do rows[i] = r:gsub("|", " ", 1) end end
	st.rows = st.rows or {}
	for i = 1, nrows do st.rows["r" .. i] = rows[i] end
	-- grey placeholder only while empty and not focused (focused+empty shows just the cursor)
	st.ph = (st.text == "" and not st.active) and (placeholder or "") or ""
	st.count = #st.text .. "/" .. (st.max or BR.DESC_MAX)
end
function BR.ml_refresh()
	local b = blink_on()
	BR.field_refresh(BR.ml, BR.DESC_COLS, BR.DESC_ROWS, BR.T("ph_desc"), b)
	BR.field_refresh(BR.tl, BR.DESC_COLS, 1, BR.T("ph_title"), b)
	BR.form.title = BR.tl.text
end
function BR.focused() return (BR.tl.active and BR.tl) or (BR.ml.active and BR.ml) or nil end
function BR.focus(which) -- "title" | "desc" | nil
	BR.tl.active = which == "title"; BR.ml.active = which == "desc"
	local st = BR.focused()
	if st then
		st.cursor = #st.text
		if G and G.CONTROLLER then G.CONTROLLER.text_input_hook = nil; G.CONTROLLER.text_input_id = nil end
		if love and love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, true) end
	end
	BR.ml_refresh()
end
-- keyboard hooks (only while a field has focus; everything else goes to the game as usual)
if love and not BR.hooked then
	BR.hooked = true
	local kp, ti = love.keypressed, love.textinput
	love.keypressed = function(key, ...)
		local st = BR.focused()
		if st then
			if key == "escape" then BR.focus(nil); return kp and kp(key, ...) end
			if key == "tab" then BR.focus(st == BR.tl and "desc" or "title"); return end
			if st.single and (key == "return" or key == "kpenter") then BR.focus("desc"); return end
			local ctrl = love.keyboard and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui"))
			BR.ml_key(st, key, ctrl); BR.ml_refresh()
			return -- swallow: no game hotkeys while typing
		end
		if kp then return kp(key, ...) end
	end
	love.textinput = function(t, ...)
		local st = BR.focused()
		if st then BR.ml_insert(st, t); BR.ml_refresh(); return end
		if ti then return ti(t, ...) end
	end
end

-- ---------- UI ----------
function BR.allowed()
	return G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU
end
BR.form = BR.form or { title = "", desc = "" }
-- field look: darker inset than the panel, thin grey border; focused = lighter fill + blue border
BR.FIELD = { bg = { 0.13, 0.16, 0.18, 1 }, bg_focus = { 0.20, 0.24, 0.27, 1 }, border = { 0.55, 0.6, 0.64, 1 }, ph = { 0.5, 0.55, 0.58, 1 } }
local function field_node(st, nrows, button, tick)
	local rows = {}
	for i = 1, nrows do
		local r = { n = G.UIT.T, config = { ref_table = st.rows, ref_value = "r" .. i, scale = 0.33, colour = G.C.WHITE } }
		local nodes = { r }
		if i == 1 then nodes = { { n = G.UIT.T, config = { ref_table = st, ref_value = "ph", scale = 0.33, colour = BR.FIELD.ph } }, r } end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cl", minh = 0.32 }, nodes = nodes }
	end
	return { n = G.UIT.R, config = { align = "tl", padding = 0.1, r = 0.08, minw = 12, maxw = 12, minh = nrows * 0.32 + 0.2,
		colour = BR.FIELD.bg, outline = 1.2, outline_colour = BR.FIELD.border, button = button, hover = true, func = tick },
		nodes = { { n = G.UIT.C, config = { align = "tl" }, nodes = rows } } }
end
local function label_row(text)
	return { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
		{ n = G.UIT.C, config = { align = "cl", minw = 9 }, nodes = { { n = G.UIT.T, config = { text = text, scale = 0.35, colour = G.C.UI.TEXT_LIGHT } } } },
		{ n = G.UIT.C, config = { align = "cr", minw = 3 }, nodes = { { n = G.UIT.T, config = { text = BR.T("hint"), scale = 0.26, colour = BR.FIELD.ph } } } } } }
end
local function style(e, st)
	if not (e and e.config) then return end
	e.config.colour = st.active and BR.FIELD.bg_focus or BR.FIELD.bg
	e.config.outline_colour = st.active and G.C.BLUE or BR.FIELD.border
	e.config.outline = st.active and 2 or 1.2
end
function BR.title_box_node()
	BR.ml_refresh()
	return { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { field_node(BR.tl, 1, "mp_bug_title_focus", "mp_bug_title_tick") } }
end
function BR.desc_box_node()
	BR.ml_refresh()
	return { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
		{ n = G.UIT.C, config = { align = "cm" }, nodes = {
			field_node(BR.ml, BR.DESC_ROWS, "mp_bug_desc_focus", "mp_bug_desc_tick"),
			{ n = G.UIT.R, config = { align = "cr", padding = 0.03 }, nodes = {
				{ n = G.UIT.T, config = { ref_table = BR.ml, ref_value = "count", scale = 0.28, colour = G.C.UI.TEXT_LIGHT } } } },
		} },
	} }
end
function G.FUNCS.mp_bug_desc_focus() BR.focus("desc") end
function G.FUNCS.mp_bug_title_focus() BR.focus("title") end
local function tick(e, st)
	if BR.focused() and (not G.OVERLAY_MENU or (G.CONTROLLER and G.CONTROLLER.text_input_hook)) then BR.focus(nil) end
	BR.ml_refresh(); style(e, st)
end
function G.FUNCS.mp_bug_desc_tick(e) tick(e, BR.ml) end
function G.FUNCS.mp_bug_title_tick(e) tick(e, BR.tl) end
function BR.form_def()
	return create_UIBox_generic_options({
		back_func = "exit_overlay_menu",
		contents = {
			{ n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
				{ n = G.UIT.T, config = { text = BR.T("title"), scale = 0.6, colour = G.C.WHITE, shadow = true } } } },
			label_row(BR.T("f_title")),
			BR.title_box_node(),
			label_row(BR.T("f_desc")),
			BR.desc_box_node(),
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
	BR.form.title = BR.tl.text
	if (BR.form.title or ""):gsub("%s", "") == "" then
		if attention_text then attention_text({ scale = 0.6, text = BR.T("need_title"), hold = 2, align = "cm", offset = { x = 0, y = -2.5 }, major = G.ROOM_ATTACH }) end
		return
	end
	BR.focus(nil)
	BR.submit(BR.form.title, BR.ml.text)
	BR.form.title, BR.form.desc = "", ""
	BR.ml.text, BR.ml.cursor = "", 0
	BR.tl.text, BR.tl.cursor = "", 0
	G.FUNCS.exit_overlay_menu()
	if attention_text then attention_text({ scale = 0.45, text = BR.T("saved"), hold = 6, align = "cm", offset = { x = 0, y = -2.5 }, major = G.ROOM_ATTACH }) end
end

--- Small button under the Patch notes button (main menu and lobby screen; the run never shows it)
function BR.add_menu_button()
	pcall(function()
		if G.MP3P_BUGREPORT_UI then G.MP3P_BUGREPORT_UI:remove(); G.MP3P_BUGREPORT_UI = nil end
		if not (BR.allowed() and G.ROOM_ATTACH) then return end
		if MP.PATCH_NOTES and MP.PATCH_NOTES.menu_buttons_visible and not MP.PATCH_NOTES.menu_buttons_visible() then return end
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
