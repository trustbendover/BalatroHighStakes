-- Balatro High Stakes 0.6.8: lobby settings presets. GPL-3.0.
-- Built-in presets plus user slots, stored per save profile in "<profile>/hs_lobby_presets.cfg" (plain key=value
-- text, not save.jkr; the .cfg name keeps Steamodded's metadata scan away). Only the host can apply a preset;
-- applying goes through the normal lobby option path (MP.ACTIONS.lobby_options), so guests sync as usual.
-- Mode and ruleset are fixed when the lobby is made, so a preset never switches them: options are applied, and
-- a short note says when the saved mode/ruleset differs from the current lobby.
MP.PRESETS = MP.PRESETS or {}
local LP = MP.PRESETS

LP.FILE_VERSION = 1
LP.FILE_NAME = "hs_lobby_presets.cfg"
LP.SLOTS = 4

local function ints(a, b) local t = {} for i = a, b do t[#t + 1] = i end return t end
-- every lobby option a preset may carry, with its allowed values (enums snap to the nearest, ranges clamp)
LP.SCHEMA = {
	starting_lives = { kind = "enum", values = ints(1, 16) },
	pvp_start_round = { kind = "enum", values = ints(1, 20) },
	timer_base_seconds = { kind = "enum", values = { 30, 60, 90, 120, 150, 180, 210, 240 } },
	timer_increment_seconds = { kind = "enum", values = { 0, 30, 60, 90, 120, 150, 180 } },
	showdown_starting_antes = { kind = "enum", values = ints(1, 20) },
	pvp_countdown_seconds = { kind = "enum", values = { 0, 3, 5, 10 } },
	rejoin_grace = { kind = "enum", values = { 0, 60, 120, 180, 300, 600 } },
	gold_on_life_loss = { kind = "bool" },
	no_gold_on_round_loss = { kind = "bool" },
	death_on_round_loss = { kind = "bool" },
	timer = { kind = "bool" },
	multiplayer_jokers = { kind = "bool" },
	different_decks = { kind = "bool" },
	random_loadout = { kind = "bool" },
	normal_bosses = { kind = "bool" },
	hide_score_until_played = { kind = "bool" },
	preview_disabled = { kind = "bool" },
	the_order = { kind = "bool" },
	legacy_smallworld = { kind = "bool" },
	different_seeds = { kind = "bool" },
	custom_seed = { kind = "seed" },
	back = { kind = "name" },
	sleeve = { kind = "name" },
	challenge = { kind = "name", empty_ok = true },
	stake = { kind = "int", min = 1, max = 8 },
}
LP.KEY_ORDER = {}
for k in pairs(LP.SCHEMA) do LP.KEY_ORDER[#LP.KEY_ORDER + 1] = k end
table.sort(LP.KEY_ORDER)
-- modes whose lives are fixed by the mode itself (start_lobby): a preset leaves them alone
LP.FIXED_LIVES = { gamemode_mp_koth = true, gamemode_mp_survival = true }

LP.BUILTIN = {
	{ id = "classic", label = "k_preset_classic", colour = "BLUE", options = {
		starting_lives = 4, pvp_start_round = 2, timer_base_seconds = 150, timer_increment_seconds = 60,
		showdown_starting_antes = 3, pvp_countdown_seconds = 3, rejoin_grace = 0, timer = true,
		gold_on_life_loss = true, no_gold_on_round_loss = false, death_on_round_loss = true, multiplayer_jokers = true } },
	{ id = "quick", label = "k_preset_quick", colour = "RED", options = {
		starting_lives = 2, pvp_start_round = 1, timer_base_seconds = 90, timer_increment_seconds = 30,
		showdown_starting_antes = 2, pvp_countdown_seconds = 3, rejoin_grace = 60, timer = true } },
	{ id = "party", label = "k_preset_party", colour = "GREEN", options = {
		starting_lives = 4, pvp_start_round = 2, timer_base_seconds = 120, timer_increment_seconds = 30,
		pvp_countdown_seconds = 5, rejoin_grace = 300, timer = true } },
	{ id = "relaxed", label = "k_preset_relaxed", colour = "ORANGE", options = {
		starting_lives = 6, pvp_start_round = 3, timer = false, rejoin_grace = 600, pvp_countdown_seconds = 10 } },
}

local function nearest(values, n)
	local best, bd
	for _, v in ipairs(values) do
		local d = math.abs(v - n)
		if not bd or d < bd then best, bd = v, d end
	end
	return best
end

--- One value checked against the schema: the clean value, or nil (= ignore)
function LP.clean_value(key, v)
	local s = LP.SCHEMA[key]
	if not s then return nil end
	if s.kind == "bool" then
		if v == true or v == "true" or v == 1 or v == "1" then return true end
		if v == false or v == "false" or v == 0 or v == "0" then return false end
		return nil
	end
	if s.kind == "enum" or s.kind == "int" then
		local n = tonumber(v)
		if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
		if s.kind == "int" then return math.max(s.min, math.min(s.max, math.floor(n + 0.5))) end
		return nearest(s.values, n)
	end
	if s.kind == "seed" then
		if type(v) ~= "string" then return nil end
		if v == "random" then return v end
		local up = v:upper()
		return up:match("^[%w]+$") and #up <= 8 and up or nil
	end
	if s.kind == "name" then
		if type(v) ~= "string" or #v > 64 or v:find("[%c=]") then return nil end
		if v == "" and not s.empty_ok then return nil end
		return v
	end
end

--- A whole preset table cleaned: unknown keys dropped, bad values dropped, numbers clamped
function LP.clean(p)
	if type(p) ~= "table" then return nil end
	local out = { options = {} }
	local opts = type(p.options) == "table" and p.options or p
	for _, k in ipairs(LP.KEY_ORDER) do
		local v = LP.clean_value(k, opts[k])
		if v ~= nil then out.options[k] = v end
	end
	for _, k in ipairs({ "gamemode", "ruleset" }) do
		local v = p[k]
		if type(v) == "string" and v:match("^[%w_]+$") and #v <= 64 then out[k] = v end
	end
	if type(p.name) == "string" then out.name = p.name:gsub("[%c]", ""):sub(1, 40) end
	if next(out.options) == nil then return nil end
	return out
end

--- Snapshot of the current lobby settings
function LP.capture(cfg)
	cfg = cfg or (MP.LOBBY and MP.LOBBY.config) or {}
	local p = { options = {}, gamemode = cfg.gamemode, ruleset = cfg.ruleset }
	for _, k in ipairs(LP.KEY_ORDER) do
		local v = LP.clean_value(k, cfg[k])
		if v ~= nil then p.options[k] = v end
	end
	return LP.clean(p)
end

--- Apply a cleaned preset onto cfg (a lobby config table). Returns the changed keys and notes.
--- ctx: { max_stake = n, valid_back = fn(name) -> bool }
function LP.apply_to(cfg, preset, ctx)
	ctx = ctx or {}
	local p = LP.clean(preset)
	local changed, notes = {}, {}
	if not p then return changed, notes end
	for _, k in ipairs(LP.KEY_ORDER) do
		local v = p.options[k]
		local skip = v == nil
		if not skip and k == "starting_lives" and LP.FIXED_LIVES[cfg.gamemode or ""] then skip = true; notes.lives_fixed = true end
		if not skip and k == "stake" and ctx.max_stake and ctx.max_stake > 0 then v = math.min(v, ctx.max_stake) end
		if not skip and k == "back" and ctx.valid_back and not ctx.valid_back(v) then skip = true; notes.deck_missing = true end
		if not skip and k == "sleeve" and ctx.valid_sleeve and not ctx.valid_sleeve(v) then skip = true end
		if not skip and cfg[k] ~= v then cfg[k] = v; changed[#changed + 1] = k end
	end
	if p.gamemode and cfg.gamemode and p.gamemode ~= cfg.gamemode then notes.mode_differs = p.gamemode end
	if p.ruleset and cfg.ruleset and p.ruleset ~= cfg.ruleset then notes.ruleset_differs = p.ruleset end
	return changed, notes
end

-- ---------------------------------------------------------------- file
local function esc(s) return (tostring(s):gsub("[%c=%[%]]", "")) end

function LP.serialize(slots)
	local lines = { "# Balatro High Stakes lobby presets", "version=" .. LP.FILE_VERSION }
	for i = 1, LP.SLOTS do
		local p = slots and slots[i] and LP.clean(slots[i])
		if p then
			lines[#lines + 1] = "[slot " .. i .. "]"
			if p.name then lines[#lines + 1] = "name=" .. esc(p.name) end
			if p.gamemode then lines[#lines + 1] = "gamemode=" .. p.gamemode end
			if p.ruleset then lines[#lines + 1] = "ruleset=" .. p.ruleset end
			for _, k in ipairs(LP.KEY_ORDER) do
				local v = p.options[k]
				if v ~= nil then lines[#lines + 1] = k .. "=" .. esc(v) end
			end
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

--- Parse the file text. Anything odd is skipped; a newer file version is read as far as it is understood.
function LP.parse(text)
	local slots, cur, version = {}, nil, nil
	if type(text) ~= "string" then return slots, nil end
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("\r$", "")
		local n = line:match("^%[slot (%d+)%]$")
		if n then
			n = tonumber(n)
			cur = (n >= 1 and n <= LP.SLOTS) and {} or nil
			if cur then slots[n] = cur end
		elseif not line:match("^%s*#") then
			local k, v = line:match("^([%w_]+)=(.*)$")
			if k == "version" and not cur then version = tonumber(v)
			elseif k and cur then cur[k] = v end
		end
	end
	for i = 1, LP.SLOTS do if slots[i] then slots[i] = LP.clean(slots[i]) end end
	return slots, version
end

function LP.path()
	local prof = G and G.SETTINGS and G.SETTINGS.profile or 1
	return tostring(prof) .. "/" .. LP.FILE_NAME
end

function LP.load()
	LP.slots = {}
	local ok, text = pcall(function() return love.filesystem.read(LP.path()) end)
	if ok and text then LP.slots = LP.parse(text) end
	LP.loaded_profile = G and G.SETTINGS and G.SETTINGS.profile
	return LP.slots
end

function LP.save()
	local ok, err = pcall(function()
		local prof = tostring(G and G.SETTINGS and G.SETTINGS.profile or 1)
		if love.filesystem.getInfo and not love.filesystem.getInfo(prof) then love.filesystem.createDirectory(prof) end
		assert(love.filesystem.write(LP.path(), LP.serialize(LP.slots or {})))
	end)
	if not ok and sendWarnMessage then sendWarnMessage("Lobby presets: could not save: " .. tostring(err), "MULTIPLAYER") end
	return ok
end

function LP.get_slots()
	if not LP.slots or LP.loaded_profile ~= (G and G.SETTINGS and G.SETTINGS.profile) then LP.load() end
	return LP.slots
end

-- ---------------------------------------------------------------- names
local function L(key, fallback)
	local ok, s = pcall(localize, key)
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then return s end
	return fallback or key
end
LP.L = L

function LP.mode_name(gamemode)
	if type(gamemode) ~= "string" then return "?" end
	local short = gamemode:gsub("^gamemode_mp_", "")
	if MP.MODES and MP.MODES.full_name then return MP.MODES.full_name(gamemode) end
	return L("k_" .. short, short:sub(1, 1):upper() .. short:sub(2))
end

--- Auto-name for a saved preset: "Attrition, 4 lives, 150s" (or "no timer")
function LP.auto_name(p)
	local o = p.options or {}
	local parts = { LP.mode_name(p.gamemode) }
	if o.starting_lives then parts[#parts + 1] = string.format(L("k_preset_lives_fmt", "%d lives"), o.starting_lives) end
	if o.timer == false then parts[#parts + 1] = L("k_preset_no_timer", "no timer")
	elseif o.timer_base_seconds then parts[#parts + 1] = o.timer_base_seconds .. "s" end
	return table.concat(parts, ", ")
end

--- Text that fits in `w` UI units at `scale` (shortened with ".." like the rest of the lobby)
function LP.fit(s, scale, w)
	s = tostring(s or "")
	if not (MP.FIT and MP.FIT.width) then return s end
	if MP.FIT.width(s, scale) <= w then return s end
	local chars = {}
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
	while #chars > 1 and MP.FIT.width(table.concat(chars) .. "..", scale) > w do chars[#chars] = nil end
	return table.concat(chars) .. ".."
end

-- ---------------------------------------------------------------- actions (game)
--- One info line in the Lovely log per preset action (no names or settings, just what happened)
function LP.log(msg)
	if sendInfoMessage then pcall(sendInfoMessage, "Lobby presets: " .. msg, "MULTIPLAYER") end
end

LP.status = nil
LP.confirm_delete = nil

local function ctx()
	return {
		max_stake = MP.DECK and MP.DECK.MAX_STAKE or nil,
		valid_back = function(name)
			if name == "Challenge Deck" then return true end
			if not (G and G.P_CENTERS) then return true end
			for _, c in pairs(G.P_CENTERS) do if c.set == "Back" and c.name == name then return true end end
			return false
		end,
	}
end

function LP.apply(preset, label)
	if not (MP.LOBBY and MP.LOBBY.is_host and MP.LOBBY.code) then return false end
	if MP.LOBBY.config.forced_config then return false end
	local before_decks = MP.LOBBY.config.different_decks
	local changed, notes = LP.apply_to(MP.LOBBY.config, preset, ctx())
	MP.ACTIONS.lobby_options()
	LP.log(string.format("loaded %s (%d settings changed%s)", tostring(preset.log_id or "preset"), #changed, notes.mode_differs and ", mode kept" or ""))
	if G.FUNCS.copy_host_deck and not MP.LOBBY.config.different_decks then pcall(G.FUNCS.copy_host_deck) end
	local msg = string.format(L("k_preset_loaded_fmt", "Loaded: %s"), label or "?")
	if notes.mode_differs then msg = msg .. " - " .. string.format(L("k_preset_mode_kept_fmt", "mode stays %s"), LP.mode_name(MP.LOBBY.config.gamemode)) end
	LP.status = { text = msg, colour = "GREEN" }
	if (before_decks ~= MP.LOBBY.config.different_decks) or changed[1] then
		if MP.ACTIONS.update_player_usernames then pcall(MP.ACTIONS.update_player_usernames) end
	end
	return true, changed, notes
end

-- ---------------------------------------------------------------- UI
-- widths (UI units): name 3.9 + 3 buttons x 1.75 + gaps = 9.45, inside the 10-wide tab; built-ins 4 x 2.25 + gaps = 9.3
local BTN_SCALE, NAME_SCALE, NAME_W, BTN_W, BI_W = 0.36, 0.34, 3.4, 1.75, 2.25
LP.UI_SIZES = { BTN_SCALE = BTN_SCALE, NAME_SCALE = NAME_SCALE, NAME_W = NAME_W, BTN_W = BTN_W, BI_W = BI_W }

-- func is "<name>_<index>" (UIBox_button has no per-button argument); a disabled button gets no func at all
local function button(label, func, colour, minw, enabled, ref)
	local b = UIBox_button({ label = { LP.fit(label, BTN_SCALE, minw - 0.2) }, button = func .. "_" .. ref.index, colour = enabled and colour or G.C.UI.BACKGROUND_INACTIVE,
		text_colour = enabled and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE, minw = minw, minh = 0.5, scale = BTN_SCALE, col = true })
	if not enabled then
		b.nodes[1].config.button = nil; b.nodes[1].config.hover = false; b.nodes[1].config.shadow = false
	end
	return b
end

function LP.area_def()
	local host = MP.LOBBY and MP.LOBBY.is_host
	local slots = LP.get_slots()
	local rows = {}
	local function text(s, scale, colour) return { n = G.UIT.T, config = { text = s, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT } } end
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { text(LP.fit(L("k_preset_builtin", "Built-in"), 0.4, 9), 0.4) } }
	local bi = {}
	for i, b in ipairs(LP.BUILTIN) do
		bi[#bi + 1] = button(L(b.label, b.id), "mp3p_preset_builtin", G.C[b.colour] or G.C.BLUE, BI_W, host, { index = i })
		if i < #LP.BUILTIN then bi[#bi + 1] = { n = G.UIT.B, config = { w = 0.1, h = 0.1 } } end
	end
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = bi }
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { text(LP.fit(L("k_preset_mine", "My presets"), 0.4, 9), 0.4) } }
	for i = 1, LP.SLOTS do
		local p = slots[i]
		local name = p and (p.name or LP.auto_name(p)) or L("k_preset_empty", "(empty)")
		local confirm = LP.confirm_delete == i
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			{ n = G.UIT.C, config = { align = "cl", minw = NAME_W + 0.5, maxw = NAME_W + 0.5, minh = 0.5, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK, padding = 0.05 }, nodes = {
				text(i .. ". " .. LP.fit(name, NAME_SCALE, NAME_W), NAME_SCALE, p and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) } },
			{ n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
			button(L("k_preset_load", "Load"), "mp3p_preset_load", G.C.BLUE, BTN_W, host and p ~= nil, { index = i }),
			{ n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
			button(L(p and "k_preset_overwrite" or "k_preset_save", p and "Overwrite" or "Save"), "mp3p_preset_save", G.C.GREEN, BTN_W, true, { index = i }),
			{ n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
			button(confirm and L("k_preset_sure", "Sure?") or L("k_preset_delete", "Delete"), "mp3p_preset_delete", confirm and G.C.MULT or G.C.RED, BTN_W, p ~= nil, { index = i }),
		} }
	end
	local st = LP.status or { text = host and L("k_preset_hint", "Load applies to the whole lobby") or L("k_preset_only_host", "Only the host can load presets"), colour = "UI" }
	local col = st.colour == "UI" and G.C.UI.TEXT_INACTIVE or (G.C[st.colour] or G.C.UI.TEXT_LIGHT)
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.08, minh = 0.4 }, nodes = { text(LP.fit(st.text, 0.32, 9.4), 0.32, col) } }
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = rows }
end

function MP.UI.create_lobby_presets_tab()
	LP.confirm_delete = nil
	if not LP.open_on_presets then LP.status = nil end
	return { n = G.UIT.ROOT, config = { emboss = 0.05, minh = 4, r = 0.1, minw = 10, align = "tm", padding = 0.2, colour = G.C.BLACK },
		nodes = { { n = G.UIT.O, config = { id = "mp3p_presets_area", object = UIBox({ definition = LP.area_def(), config = { align = "cm" } }) } } } }
end

function LP.refresh()
	local area = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID("mp3p_presets_area")
	if not area then return end
	if area.config.object then area.config.object:remove() end
	area.config.object = UIBox({ definition = LP.area_def(), config = { align = "cm", parent = area } })
	area.config.object:recalculate()
	if G.OVERLAY_MENU.recalculate then G.OVERLAY_MENU:recalculate() end
end

--- Re-open the lobby options on the Presets tab so every other tab shows the new values
function LP.reopen()
	LP.open_on_presets = true
	G.FUNCS.overlay_menu({ definition = G.UIDEF.create_UIBox_lobby_options() })
	LP.open_on_presets = nil
end

if G and G.FUNCS then
	LP.FUNCS = {}
	LP.FUNCS.builtin = function(i)
		local b = LP.BUILTIN[i]
		if b and LP.apply({ options = b.options, log_id = "built-in " .. b.id }, L(b.label, b.id)) then LP.reopen() end
	end
	LP.FUNCS.load = function(i)
		local p = i and LP.get_slots()[i]
		if p then p.log_id = "slot " .. i end
		if p and LP.apply(p, p.name or LP.auto_name(p)) then LP.reopen() end
	end
	LP.FUNCS.save = function(i)
		if not i then return end
		local p = LP.capture()
		if not p then return end
		LP.get_slots()[i] = p
		LP.confirm_delete = nil
		local saved = LP.save()
		LP.log(saved and ("saved slot " .. i) or ("saving slot " .. i .. " FAILED"))
		LP.status = saved and { text = string.format(L("k_preset_saved_fmt", "Saved in slot %d"), i), colour = "GREEN" }
			or { text = L("k_preset_save_failed", "Could not save"), colour = "RED" }
		LP.refresh()
	end
	LP.FUNCS.delete = function(i)
		if not i or not LP.get_slots()[i] then return end
		if LP.confirm_delete ~= i then
			LP.confirm_delete = i
			LP.status = { text = L("k_preset_delete_confirm", "Click again to delete"), colour = "RED" }
			LP.log("delete slot " .. i .. " asked (waiting for Sure?)")
		else
			LP.get_slots()[i] = nil
			LP.confirm_delete = nil
			LP.log((LP.save() and "deleted slot " or "deleting slot FAILED ") .. i)
			LP.status = { text = string.format(L("k_preset_deleted_fmt", "Slot %d deleted"), i), colour = "UI" }
		end
		LP.refresh()
	end
	for i = 1, math.max(LP.SLOTS, #LP.BUILTIN) do
		for name, f in pairs(LP.FUNCS) do G.FUNCS["mp3p_preset_" .. name .. "_" .. i] = function() f(i) end end
	end
end

return LP
