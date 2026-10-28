-- Balatro High Stakes: patch notes pop-up. GPL-3.0, see FORK_NOTICE.md.
-- Shown once on the main menu after an update (or after a fresh install), never in a lobby, a
-- match or while a Steam invite is being joined, and never on top of another pop-up. Reopen with
-- the "Patch notes" button. Content: patchnotes/index.lua + patchnotes/<version>.lua.
-- The last version seen is stored in the mod config (config/Multiplayer.jkr), which updates keep.
MP = MP or {}
MP.PATCH_NOTES = MP.PATCH_NOTES or {}
local PN = MP.PATCH_NOTES

PN.SECTIONS = { "new", "changed", "fixed", "known" }
PN.HEADERS = {
	en = { new = "New", changed = "Changed", fixed = "Fixed", known = "Known issues" },
	nl = { new = "Nieuw", changed = "Veranderd", fixed = "Opgelost", known = "Bekende problemen" },
}
PN.TEXT = {
	en = { title = "Patch notes", got_it = "Got it", page = "Page", button = "Patch notes", version = "Version", combined = "What changed since you last played" },
	nl = { title = "Patch notes", got_it = "Begrepen", page = "Pagina", button = "Patch notes", version = "Versie", combined = "Wat er veranderd is sinds je laatst speelde" },
}
PN.MAX_VERSIONS = 5   -- skipped many versions: show at most this many (newest first)
PN.WRAP = 62          -- characters per line at the bullet text size
PN.LINES_PER_PAGE = 14
PN.MENU_DELAY = 3     -- seconds on the main menu before it may pop up (after the update button at 2 s)
PN.UPDATER_WAIT = 8   -- wait at most this long for the update check to finish

----------------------------------------------------------------------------- pure logic (tested)
--- "0.6.8~3P", "v0.6.8-preview", "0.6.8" -> "0.6.8"; nil if not a version
function PN.ver(v)
	if type(v) ~= "string" then return nil end
	return v:gsub("^%s*[vV]", ""):match("^%d+[%.%d]*%d") or v:match("^%s*[vV]?(%d+)%s*$")
end

--- -1 / 0 / 1 like a comparator on dotted versions
function PN.cmp(a, b)
	local x, y = {}, {}
	for n in tostring(PN.ver(a) or ""):gmatch("%d+") do x[#x + 1] = tonumber(n) end
	for n in tostring(PN.ver(b) or ""):gmatch("%d+") do y[#y + 1] = tonumber(n) end
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then return p < q and -1 or 1 end
	end
	return 0
end

--- Which versions to show, newest first.
--- last_seen nil (fresh install, or first time with this feature): only the current version.
--- Skipped versions: every version newer than last_seen up to the current one (max MAX_VERSIONS).
function PN.pending(last_seen, current, versions)
	local cur = PN.ver(current)
	if not cur then return {} end
	local list = {}
	for _, v in ipairs(versions or {}) do
		if PN.ver(v) and PN.cmp(v, cur) <= 0 then list[#list + 1] = PN.ver(v) end
	end
	table.sort(list, function(a, b) return PN.cmp(a, b) > 0 end)
	local seen = PN.ver(last_seen)
	if not seen then return { list[1] } end
	if PN.cmp(seen, cur) >= 0 then return {} end
	local out = {}
	for _, v in ipairs(list) do
		if PN.cmp(v, seen) > 0 and #out < PN.MAX_VERSIONS then out[#out + 1] = v end
	end
	return out
end

function PN.lang(code)
	code = code or (G and G.SETTINGS and G.SETTINGS.language)
	if type(code) == "string" and code:lower():sub(1, 2) == "nl" then return "nl" end
	return "en"
end

local function is_list(t)
	if type(t) ~= "table" then return false end
	for _, x in ipairs(t) do if type(x) ~= "string" then return false end end
	return true
end

--- A patch note file is valid when it has an English part with at least one section.
function PN.valid(note)
	if type(note) ~= "table" or type(note.en) ~= "table" then return false end
	for _, s in ipairs(PN.SECTIONS) do if is_list(note.en[s]) and #note.en[s] > 0 then return true end end
	return false
end

--- Load the index and the per-version files with loader(path) -> table|nil. Bad files are skipped.
function PN.load(loader)
	local ok, index = pcall(loader, "patchnotes/index.lua")
	local notes, versions = {}, {}
	if not ok or type(index) ~= "table" then return notes, versions end
	for _, v in ipairs(index) do
		local okf, note = pcall(loader, "patchnotes/" .. tostring(v) .. ".lua")
		if okf and PN.valid(note) then
			notes[PN.ver(v)] = note
			versions[#versions + 1] = PN.ver(v)
		end
	end
	return notes, versions
end

--- Word wrap to at most `width` characters per line.
function PN.wrap(text, width)
	local lines, line = {}, ""
	for word in tostring(text):gmatch("%S+") do
		if line == "" then line = word
		elseif #line + 1 + #word <= width then line = line .. " " .. word
		else lines[#lines + 1] = line; line = word end
		while #line > width do lines[#lines + 1] = line:sub(1, width); line = line:sub(width + 1) end
	end
	if line ~= "" then lines[#lines + 1] = line end
	return lines
end

--- Flat list of display lines for the given versions (newest first):
--- { kind = "version" | "title" | "section" | "bullet" | "cont" | "gap", text, section }
function PN.lines(notes, versions, lang)
	lang = lang or "en"
	local H = PN.HEADERS[lang] or PN.HEADERS.en
	local T = PN.TEXT[lang] or PN.TEXT.en
	local out = {}
	for i, v in ipairs(versions) do
		local note = notes[v]
		if note then
			local loc = type(note[lang]) == "table" and note[lang] or {}
			if i > 1 then out[#out + 1] = { kind = "gap" } end
			local date = note.date and (" (" .. tostring(note.date) .. ")") or ""
			out[#out + 1] = { kind = "version", text = T.version .. " " .. v .. date }
			local title = loc.title or note.en.title
			if title then out[#out + 1] = { kind = "title", text = title } end
			for _, s in ipairs(PN.SECTIONS) do
				local items = is_list(loc[s]) and #loc[s] > 0 and loc[s] or note.en[s] -- per-section fallback to English
				if is_list(items) and #items > 0 then
					out[#out + 1] = { kind = "section", text = H[s], section = s }
					for _, b in ipairs(items) do
						for j, l in ipairs(PN.wrap(b, PN.WRAP - 2)) do
							out[#out + 1] = { kind = j == 1 and "bullet" or "cont", text = l, section = s }
						end
					end
				end
			end
		end
	end
	return out
end

--- Split lines into pages; a header never ends a page and pages never start with a gap.
function PN.pages(lines, per_page)
	per_page = per_page or PN.LINES_PER_PAGE
	-- lines a header needs below it on the same page (version -> title -> section -> bullet)
	local need = { version = 3, title = 2, section = 1 }
	local pages, cur = {}, {}
	local function flush() if #cur > 0 then pages[#pages + 1] = cur; cur = {} end end
	for _, l in ipairs(lines) do
		local limit = l.kind == "cont" and per_page + 2 or per_page -- a wrapped bullet may run over a little
		if #cur >= limit or (need[l.kind] and #cur + need[l.kind] >= per_page) then flush() end
		if not (l.kind == "gap" and #cur == 0) then cur[#cur + 1] = l end
	end
	flush()
	return pages
end

--- May the pop-up appear by itself now? env: { main_menu, overlay, in_lobby, in_run, p2p_busy,
--- updater_busy, menu_age, shown }
function PN.can_auto_show(env)
	if env.shown or not env.main_menu or env.overlay or env.in_lobby or env.in_run or env.p2p_busy then return false end
	if (env.menu_age or 0) < PN.MENU_DELAY then return false end
	if env.updater_busy and (env.menu_age or 0) < PN.UPDATER_WAIT then return false end
	return true
end

----------------------------------------------------------------------------- game glue
local function log(m) pcall(sendInfoMessage, m, "MULTIPLAYER-PATCHNOTES") end

function PN.current_version()
	local ok, v = pcall(function() return SMODS.Mods["Multiplayer"].version end)
	return ok and v or nil
end
local function config()
	local ok, c = pcall(function() return SMODS.Mods["Multiplayer"].config end)
	return ok and type(c) == "table" and c or nil
end
function PN.last_seen() local c = config(); return c and c.patchnotes_seen or nil end
function PN.mark_seen(v)
	local c = config()
	if not c or not PN.ver(v) then return end
	c.patchnotes_seen = PN.ver(v)
	pcall(SMODS.save_mod_config, SMODS.Mods["Multiplayer"])
end

function PN.ensure_loaded()
	if PN.notes then return end
	PN.notes, PN.versions = PN.load(function(path)
		local chunk = SMODS.load_file(path, "Multiplayer")
		return chunk and chunk() or nil
	end)
	log("loaded patch notes for " .. #PN.versions .. " version(s)")
end

local function colour_of(section)
	if not G or not G.C then return nil end
	if section == "new" then return G.C.GREEN end
	if section == "changed" then return G.C.CHIPS or G.C.BLUE end
	if section == "fixed" then return G.C.ORANGE end
	if section == "known" then return G.C.RED end
	return G.C.UI.TEXT_LIGHT
end

local function text_row(text, scale, colour, pad_left)
	local nodes = {}
	if pad_left then nodes[#nodes + 1] = { n = G.UIT.B, config = { w = pad_left, h = 0.1 } } end
	nodes[#nodes + 1] = { n = G.UIT.T, config = { text = text, scale = scale, colour = colour, shadow = true } }
	return { n = G.UIT.R, config = { align = "cl", padding = 0.02 }, nodes = nodes }
end

--- UI definition for one page (also used by the preview renderer)
function PN.definition(view)
	local T = PN.TEXT[view.lang] or PN.TEXT.en
	local page = view.pages[view.page] or {}
	local rows = {}
	for _, l in ipairs(page) do
		if l.kind == "version" then rows[#rows + 1] = text_row(l.text, 0.55, G.C.GOLD)
		elseif l.kind == "title" then rows[#rows + 1] = text_row(l.text, 0.45, G.C.UI.TEXT_LIGHT)
		elseif l.kind == "section" then rows[#rows + 1] = text_row(l.text, 0.5, colour_of(l.section), 0.1)
		elseif l.kind == "bullet" then rows[#rows + 1] = text_row("- " .. l.text, 0.42, G.C.UI.TEXT_LIGHT, 0.3)
		elseif l.kind == "cont" then rows[#rows + 1] = text_row("  " .. l.text, 0.42, G.C.UI.TEXT_LIGHT, 0.3)
		elseif l.kind == "gap" then rows[#rows + 1] = { n = G.UIT.R, config = { minh = 0.2 } } end
	end
	local contents = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			{ n = G.UIT.T, config = { text = "Balatro High Stakes - " .. T.title, scale = 0.7, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
		view.combined and { n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { text = T.combined, scale = 0.4, colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT } },
		} } or nil,
		{ n = G.UIT.R, config = { align = "tl", padding = 0.15, r = 0.1, colour = G.C.BLACK, minw = 13.5, minh = 7, emboss = 0.05 }, nodes = {
			{ n = G.UIT.C, config = { align = "tl" }, nodes = rows },
		} },
	}
	if #view.pages > 1 then
		local opts = {}
		for i = 1, #view.pages do opts[i] = T.page .. " " .. i .. "/" .. #view.pages end
		contents[#contents + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			create_option_cycle({ options = opts, current_option = view.page, opt_callback = "mp3p_patchnotes_page",
				w = 4, scale = 0.8, colour = G.C.RED, no_pips = #view.pages > 8 }),
		} }
	end
	contents[#contents + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
		UIBox_button({ label = { T.got_it }, button = "mp3p_patchnotes_close", colour = G.C.GREEN, minw = 4, minh = 0.8, scale = 0.6 }),
	} }
	return create_UIBox_generic_options({ no_back = true, contents = contents })
end

--- Open the pop-up for a list of versions (default: the current one).
function PN.open(versions, page)
	PN.ensure_loaded()
	if not versions or #versions == 0 then
		versions = PN.pending(nil, PN.current_version(), PN.versions)
		if #versions == 0 then versions = { PN.versions[1] } end
	end
	if #versions == 0 or not versions[1] then return false end
	local lang = PN.lang()
	local pages = PN.pages(PN.lines(PN.notes, versions, lang))
	if #pages == 0 then return false end
	PN.view = { versions = versions, pages = pages, page = math.max(1, math.min(page or 1, #pages)), lang = lang, combined = #versions > 1 }
	local ok, err = pcall(function()
		G.FUNCS.overlay_menu({ definition = PN.definition(PN.view) })
		G.OVERLAY_MENU.config.mp3p_patchnotes = true
	end)
	if not ok then log("could not open patch notes: " .. tostring(err)); PN.view = nil; return false end
	return true
end

function PN.is_open()
	return G and G.OVERLAY_MENU and G.OVERLAY_MENU.config and G.OVERLAY_MENU.config.mp3p_patchnotes and PN.view ~= nil
end

if G and G.FUNCS then
	G.FUNCS.mp3p_patchnotes_open = function() PN.open() end
	G.FUNCS.mp3p_patchnotes_close = function() PN.view = nil; G.FUNCS.exit_overlay_menu() end
	G.FUNCS.mp3p_patchnotes_page = function(args)
		if not (PN.view and args and args.to_key) then return end
		local versions, page = PN.view.versions, args.to_key
		-- rebuild after the option cycle has finished with its own UI element
		G.E_MANAGER:add_event(Event({ trigger = "immediate", blocking = false, blockable = false, no_delete = true, timer = "REAL",
			func = function() if PN.view then PN.open(versions, page) end return true end }))
	end
end

--- Small "Patch notes" button on the main menu (under the version text, top right)
function PN.add_menu_button()
	pcall(function()
		if G.MP3P_PATCHNOTES_UI then G.MP3P_PATCHNOTES_UI:remove(); G.MP3P_PATCHNOTES_UI = nil end
		local T = PN.TEXT[PN.lang()] or PN.TEXT.en
		G.MP3P_PATCHNOTES_UI = UIBox({
			definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
				UIBox_button({ label = { T.button }, button = "mp3p_patchnotes_open", colour = G.C.BLUE, minw = 2.6, minh = 0.5, scale = 0.38 }),
			} },
			config = { align = "tri", bond = "Weak", offset = { x = -0.1, y = 1.0 }, major = G.ROOM_ATTACH },
		})
	end)
end

--- Environment for can_auto_show, read from the game
function PN.env()
	local R = MP.STEAM_P2P
	local U = MP.UPDATER
	local main_menu = G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
	return {
		shown = PN.auto_done,
		main_menu = main_menu,
		overlay = G and G.OVERLAY_MENU ~= nil,
		in_lobby = MP.LOBBY and (MP.LOBBY.code ~= nil) or false,
		in_run = G and G.STAGES and G.STAGE == G.STAGES.RUN,
		p2p_busy = R and (R.joining or R.pending_invite ~= nil or R.invite_retry ~= nil or (R.mode and R.mode ~= "local")) or false,
		updater_busy = U and (U.state == "idle" or U.state == "checking") or false,
		menu_age = PN.menu_since and (love.timer.getTime() - PN.menu_since) or 0,
	}
end

--- Called every frame (cheap): shows the pending notes once the main menu is calm.
function PN.tick()
	local main_menu = G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
	if not main_menu then PN.menu_since = nil else PN.menu_since = PN.menu_since or love.timer.getTime() end
	-- an invite / lobby join started while the notes are open: get out of the way
	if PN.is_open() and MP.LOBBY and MP.LOBBY.code then
		local v = PN.view
		PN.view = nil
		pcall(G.FUNCS.exit_overlay_menu)
		if v.auto then -- it was barely seen: show it again next time the main menu is calm
			local c = config()
			if c then c.patchnotes_seen = v.prev_seen; pcall(SMODS.save_mod_config, SMODS.Mods["Multiplayer"]) end
			PN.auto_done = false
		end
	end
	if PN.auto_done or not main_menu then return end
	local t = love.timer.getTime()
	if PN.next_check and t < PN.next_check then return end
	PN.next_check = t + 0.5
	if not PN.can_auto_show(PN.env()) then return end
	PN.auto_done = true
	PN.ensure_loaded()
	local cur = PN.current_version()
	local list = PN.pending(PN.last_seen(), cur, PN.versions)
	if #list == 0 then
		if not PN.last_seen() and cur then PN.mark_seen(cur) end
		return
	end
	local prev = PN.last_seen()
	if PN.open(list) then
		PN.view.auto, PN.view.prev_seen = true, prev
		log("showing patch notes for " .. table.concat(list, ", ") .. " (last seen " .. tostring(PN.last_seen()) .. ")")
		PN.mark_seen(cur)
	end
end

if Game and Game.update and not PN.hooked then
	PN.hooked = true
	local update_ref = Game.update
	function Game:update(dt)
		pcall(PN.tick)
		return update_ref(self, dt)
	end
end

return PN
