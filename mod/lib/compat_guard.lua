-- Balatro High Stakes: startup compatibility guard. GPL-3.0, see FORK_NOTICE.md.
-- Compares the running Balatro, Steamodded and Lovely versions with compat.json (the same file
-- the installer pins from). Untested -> a friendly main-menu warning ("Play anyway" / "Disable
-- multiplayer for now"). Blocked version or a core file that failed to load -> safe mode:
-- networking stays off and singleplayer keeps working, instead of crashing mid-match.
-- A newer release's compat.json (fetched by the update check) can add tested versions.
MP = MP or {}
MP.COMPAT_GUARD = MP.COMPAT_GUARD or {}
local CG = MP.COMPAT_GUARD

CG.COMPONENTS = { "balatro", "steamodded", "lovely" }
CG.LABELS = { balatro = "Balatro", steamodded = "Steamodded", lovely = "Lovely" }
-- a load error in one of these breaks multiplayer -> safe mode
CG.CRITICAL = { "networking/", "lib/", "overrides/", "ui/lobby/", "ui/main_menu/", "gamemodes/", "rulesets/" }
CG.MENU_DELAY = 2.5 -- seconds on the main menu before the warning may appear (patch notes wait for it)
CG.UPDATER_WAIT = 7 -- wait at most this long for the update check's newer compat.json
CG.TEXT = {
	en = {
		title = "Heads up: untested versions",
		blocked_title = "Multiplayer is off (safe mode)",
		body = "Multiplayer was tested with other versions and may break.",
		body2 = "Singleplayer is not affected.",
		blocked_body = "A version below is known not to work with multiplayer.",
		failed_body = "Part of the mod failed to load, so multiplayer is off.",
		blocked_body2 = "Singleplayer still works. Update the mod or reinstall the tested versions.",
		tested = "TESTED", untested = "UNTESTED", unknown = "UNKNOWN", blocked = "BLOCKED",
		tested_with = "tested", play = "Play anyway", disable = "Disable multiplayer for now", ok = "OK",
		safe_note = "Multiplayer is off (safe mode)", user_note = "Multiplayer is off for now",
		clash = "CLASH", clash_title = "Heads up: another Multiplayer mod",
		clash_body = "These mods clash with Balatro High Stakes (same id/prefix).",
		clash_body2 = "Move them out of the Mods folder (Install.bat can do it).",
	},
	nl = {
		title = "Let op: niet-geteste versies",
		blocked_title = "Multiplayer staat uit (veilige modus)",
		body = "Multiplayer is getest met andere versies en kan stuk gaan.",
		body2 = "Singleplayer werkt gewoon.",
		blocked_body = "Een versie hieronder werkt zeker niet met multiplayer.",
		failed_body = "Een deel van de mod laadde niet, dus multiplayer staat uit.",
		blocked_body2 = "Singleplayer werkt nog. Update de mod of installeer de geteste versies.",
		tested = "GETEST", untested = "NIET GETEST", unknown = "ONBEKEND", blocked = "GEBLOKKEERD",
		tested_with = "getest", play = "Toch spelen", disable = "Multiplayer nu uitzetten", ok = "OK",
		safe_note = "Multiplayer staat uit (veilige modus)", user_note = "Multiplayer staat nu uit",
		clash = "BOTSING", clash_title = "Let op: nog een Multiplayer-mod",
		clash_body = "Deze mods botsen met Balatro High Stakes (zelfde id/prefix).",
		clash_body2 = "Haal ze uit de Mods-map (Install.bat kan dat doen).",
	},
}
-- 0.6.8: the official Balatro Multiplayer (legacy id "Multiplayer", 1.0 platform: MultiplayerPvP with the
-- same "mp" prefix, MultiplayerAPI, MultiplayerSPDRN) clashes with this fork
CG.CLASH_IDS = { Multiplayer = true, MultiplayerPvP = true, MultiplayerAPI = true, MultiplayerSPDRN = true }
CG.STATE_COLOUR = { tested = "GREEN", untested = "FILTER", unknown = "FILTER", blocked = "RED", clash = "RED" }

----------------------------------------------------------------------------- pure logic (tested)
--- Strip build tags the games/loaders add: "1.0.1o-FULL" -> "1.0.1o", "...-STEAMODDED" -> "...", "v0.10.0" -> "0.10.0"
function CG.norm(v)
	if type(v) ~= "string" then return nil end
	v = v:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[vV]", "")
	v = v:gsub("%-FULL$", ""):gsub("%-DEMO$", ""):gsub("%-STEAMODDED$", "")
	if v == "" then return nil end
	return v
end

--- "1.0.0~BETA-1620a" -> {1,0,0,"~","beta",1620,"a"}; "1.0.1o" -> {1,0,1,"o"}
function CG.tokens(v)
	v = CG.norm(v)
	local t = {}
	if not v then return t end
	for num, word, tilde in v:lower():gmatch("(%d*)(%a*)(~?)") do
		if num ~= "" then t[#t + 1] = tonumber(num) end
		if word ~= "" then t[#t + 1] = word end
		if tilde ~= "" then t[#t + 1] = "~" end
	end
	return t
end

--- -1 / 0 / 1. A "~" marks a pre-release ("1.0.0~BETA-x" < "1.0.0"); numbers compare numerically.
function CG.cmp(a, b)
	local ta, tb = CG.tokens(a), CG.tokens(b)
	for i = 1, math.max(#ta, #tb) do
		local x, y = ta[i], tb[i]
		if x == nil then return (y == "~") and 1 or -1 end
		if y == nil then return (x == "~") and -1 or 1 end
		if x ~= y then
			if x == "~" then return -1 elseif y == "~" then return 1 end
			if type(x) == type(y) then return (x < y) and -1 or 1 end
			return (type(x) == "number") and -1 or 1 -- "1.0.1" < "1.0.1o"
		end
	end
	return 0
end

function CG.same(a, b) return a ~= nil and b ~= nil and CG.norm(a):lower() == CG.norm(b):lower() end

local function list_has(list, v)
	for _, x in ipairs(type(list) == "table" and list or {}) do if CG.same(x, v) then return true end end
	return false
end

--- Is a compat table usable? (schema 1, tables where expected)
function CG.valid(c)
	if type(c) ~= "table" or c.schema ~= 1 then return false end
	for _, k in ipairs(CG.COMPONENTS) do
		if c[k] ~= nil and (type(c[k]) ~= "table" or (c[k].tested ~= nil and type(c[k].tested) ~= "table")) then return false end
	end
	return c.blocked == nil or type(c.blocked) == "table"
end

--- Merge a newer release's compat.json into ours: adds tested versions and blocks. Only when it says
--- it applies to this mod version (applies_from <= ours). Never removes what we shipped as tested.
function CG.merge(base, remote, mod_version)
	if not CG.valid(base) then return base end
	if not CG.valid(remote) then return base, "invalid" end
	if remote.applies_from and mod_version and CG.cmp(mod_version, remote.applies_from) < 0 then return base, "not for this version" end
	local out = { schema = 1, mod_version = base.mod_version, applies_from = base.applies_from, blocked = {}, merged = true }
	for _, k in ipairs(CG.COMPONENTS) do
		local b, r = base[k] or {}, remote[k] or {}
		local tested = {}
		for _, v in ipairs(b.tested or {}) do tested[#tested + 1] = v end
		for _, v in ipairs(r.tested or {}) do if not list_has(tested, v) then tested[#tested + 1] = v end end
		out[k] = { tested = tested, min = b.min, pin = b.pin }
	end
	for _, src in ipairs({ base.blocked or {}, remote.blocked or {} }) do
		for _, e in ipairs(src) do
			-- a block can never hit the exact versions this build shipped as tested
			if type(e) == "table" and e.component and e.version and not (src == remote.blocked and list_has((base[e.component] or {}).tested, e.version)) then
				out.blocked[#out.blocked + 1] = e
			end
		end
	end
	return out
end

--- state of one component: "tested" | "untested" | "unknown" | "blocked" (+ reason)
function CG.state(component, version, compat)
	local c = (compat or {})[component] or {}
	for _, e in ipairs((compat or {}).blocked or {}) do
		if type(e) == "table" and e.component == component and version and CG.same(e.version, version) then
			return "blocked", e.reason or "known not to work"
		end
	end
	if not version then return "unknown" end
	if c.min and CG.cmp(version, c.min) < 0 then return "blocked", "older than " .. tostring(c.min) end
	if list_has(c.tested, version) then return "tested" end
	return "untested"
end

--- Pure: other Multiplayer mods that loaded next to us. mods = SMODS.Mods, own = our entry.
--- -> sorted list of { id=, name=, folder= } (mods that did not load or are disabled are ignored)
function CG.find_clashes(mods, own)
	local out = {}
	for id, m in pairs(mods or {}) do
		if CG.CLASH_IDS[id] and type(m) == "table" and m ~= own and m.can_load ~= false and not m.disabled then
			local folder = type(m.path) == "string" and m.path:gsub("[/\\]+$", ""):match("([^/\\]+)$") or nil
			out[#out + 1] = { id = id, name = m.name or id, folder = folder }
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

--- versions: { balatro=, steamodded=, lovely= }; load_errors: { {file=, err=} }; clashes: CG.find_clashes()
--- -> { status = "ok"|"untested"|"blocked", items = {...}, failed = {files}, clash = bool, signature = "..." }
function CG.check(versions, compat, load_errors, clashes)
	local r = { status = "ok", items = {}, failed = {} }
	local sig = {}
	for _, k in ipairs(CG.COMPONENTS) do
		local v = versions[k]
		local st, why = CG.state(k, v, compat)
		local c = (compat or {})[k] or {}
		r.items[#r.items + 1] = { component = k, label = CG.LABELS[k], version = v, state = st, reason = why,
			tested = (c.tested and c.tested[1]) or nil }
		sig[#sig + 1] = k .. "=" .. tostring(v)
		if st == "blocked" then r.status = "blocked"
		elseif (st == "untested" or st == "unknown") and r.status == "ok" then r.status = "untested" end
	end
	for _, e in ipairs(load_errors or {}) do
		for _, p in ipairs(CG.CRITICAL) do
			if type(e.file) == "string" and e.file:sub(1, #p) == p then r.failed[#r.failed + 1] = e.file; break end
		end
	end
	if #r.failed > 0 then r.status = "blocked" end
	for _, c in ipairs(clashes or {}) do
		r.items[#r.items + 1] = { component = "clash", label = tostring(c.name), version = c.folder or c.id, state = "clash" }
		sig[#sig + 1] = "clash=" .. tostring(c.id)
		r.clash = true
		if r.status == "ok" then r.status = "untested" end -- warn with Play anyway / Disable multiplayer
	end
	r.signature = table.concat(sig, ";")
	return r
end

--- What to do at start-up: "ok" | "warn" | "safe". A "Play anyway" for this exact combo is remembered.
function CG.decide(result, acked_signature)
	if result.status == "blocked" then return "safe" end
	if result.status == "untested" then
		if acked_signature and acked_signature == result.signature then return "ok" end
		return "warn"
	end
	return "ok"
end

--- May the warning appear now? env: { main_menu, overlay, in_lobby, in_run, menu_age, pending,
--- updater_busy (a newer compat.json may still arrive), safe (safe mode: no need to wait) }
function CG.can_show(env)
	if not env.pending or not env.main_menu or env.overlay or env.in_lobby or env.in_run then return false end
	if env.updater_busy and not env.safe and (env.menu_age or 0) < CG.UPDATER_WAIT then return false end
	return (env.menu_age or 0) >= CG.MENU_DELAY
end

--- Tiny JSON reader for compat.json (objects, arrays, strings, numbers, true/false/null).
function CG.json_decode(s)
	if type(s) ~= "string" then return nil end
	local ok, json = pcall(require, "json")
	if ok and type(json) == "table" and json.decode then
		local ok2, v = pcall(json.decode, s)
		if ok2 then return v end
		return nil
	end
	local i = 1
	local function ws() i = s:find("[^%s]", i) or #s + 1 end
	local value
	local function str()
		local out, j = {}, i + 1
		while true do
			local ch = s:sub(j, j)
			if ch == "" then error("eof") end
			if ch == '"' then i = j + 1; return table.concat(out) end
			if ch == "\\" then
				local n = s:sub(j + 1, j + 1)
				local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
				if n == "u" then out[#out + 1] = "?"; j = j + 6
				else out[#out + 1] = map[n] or n; j = j + 2 end
			else out[#out + 1] = ch; j = j + 1 end
		end
	end
	function value()
		ws()
		local ch = s:sub(i, i)
		if ch == "{" then
			local t = {}; i = i + 1; ws()
			if s:sub(i, i) == "}" then i = i + 1; return t end
			while true do
				ws(); if s:sub(i, i) ~= '"' then error("key") end
				local k = str(); ws()
				if s:sub(i, i) ~= ":" then error(":") end
				i = i + 1; t[k] = value(); ws()
				local c = s:sub(i, i); i = i + 1
				if c == "}" then return t elseif c ~= "," then error(",") end
			end
		elseif ch == "[" then
			local t = {}; i = i + 1; ws()
			if s:sub(i, i) == "]" then i = i + 1; return t end
			while true do
				t[#t + 1] = value(); ws()
				local c = s:sub(i, i); i = i + 1
				if c == "]" then return t elseif c ~= "," then error(",") end
			end
		elseif ch == '"' then return str()
		elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			if not num or num == "" then error("value") end
			i = i + #num; return tonumber(num)
		end
	end
	local ok3, v = pcall(value)
	return ok3 and v or nil
end

----------------------------------------------------------------------------- game glue
local function log(m) pcall(sendInfoMessage, m, "MULTIPLAYER-COMPAT") end
local function warn(m) pcall(sendWarnMessage, m, "MULTIPLAYER-COMPAT") end
local function config() return SMODS and SMODS.Mods and SMODS.Mods["Multiplayer"] and SMODS.Mods["Multiplayer"].config end
local function save() pcall(SMODS.save_mod_config, SMODS.Mods["Multiplayer"]) end

function CG.lang()
	local code = G and G.SETTINGS and G.SETTINGS.language or "en-us"
	return (type(code) == "string" and code:sub(1, 2) == "nl") and "nl" or "en"
end

function CG.mod_version()
	local m = SMODS and SMODS.Mods and SMODS.Mods["Multiplayer"]
	local v = m and m.version or "0"
	return (tostring(v):gsub("~.*$", ""))
end

--- Running versions, read defensively
function CG.clashes()
	local ok, list = pcall(CG.find_clashes, SMODS and SMODS.Mods, SMODS and SMODS.Mods and SMODS.Mods["Multiplayer"])
	if not ok then return {} end
	for _, c in ipairs(list) do warn("another Multiplayer mod is loaded: " .. c.id .. " in folder " .. tostring(c.folder) .. " - it clashes with Balatro High Stakes") end
	return list
end

function CG.versions()
	local v = {}
	v.balatro = CG.norm((G and G.VERSION) or rawget(_G, "VERSION"))
	v.steamodded = CG.norm(SMODS and (SMODS.version or rawget(_G, "MODDED_VERSION")))
	local lv = SMODS and SMODS.Mods and SMODS.Mods["Lovely"] and SMODS.Mods["Lovely"].version
	if not lv then
		local ok, lovely = pcall(require, "lovely")
		if ok and type(lovely) == "table" then lv = lovely.version end
	end
	v.lovely = CG.norm(lv)
	return v
end

--- compat.json shipped with the mod, plus the cached remote one (if it applies to us)
function CG.load_compat()
	local base
	local ok, raw = pcall(function() return NFS.read(MP.path .. "/compat.json") end)
	if ok and raw then base = CG.json_decode(raw) end
	if not CG.valid(base) then
		warn("compat.json missing or invalid; using built-in defaults")
		base = { schema = 1, mod_version = CG.mod_version(), balatro = { tested = { "1.0.1o" } },
			steamodded = { tested = { MP.SMODS_VERSION or "1.0.0~BETA-1620a" } }, lovely = { tested = { "0.10.0" } }, blocked = {} }
	end
	CG.base = base
	local c = config()
	local cached = c and c.compat_cache and CG.json_decode(c.compat_cache)
	CG.compat = CG.merge(base, cached, CG.mod_version()) or base
	return CG.compat
end

function CG.note()
	local T = CG.TEXT[CG.lang()] or CG.TEXT.en
	if not MP.SAFE_MODE then return nil end
	return MP.SAFE_MODE.by_user and T.user_note or T.safe_note
end

--- Turn multiplayer off for this session (networking is not started / is stopped)
function CG.enter_safe_mode(reason, by_user)
	if MP.SAFE_MODE then return end
	MP.SAFE_MODE = { reason = reason, by_user = by_user or false }
	warn("SAFE MODE: multiplayer disabled (" .. tostring(reason) .. "). Singleplayer still works.")
	pcall(function()
		if MP.STEAM_P2P and MP.STEAM_P2P.shutdown then MP.STEAM_P2P.shutdown() end
	end)
	MP.STEAM_P2P = nil
	if MP.LOBBY then MP.LOBBY.connected = false end
	if by_user then
		-- refresh the main menu so the multiplayer buttons disappear
		pcall(function()
			if G and G.MAIN_MENU_UI and set_main_menu_UI then G.MAIN_MENU_UI:remove(); set_main_menu_UI() end
		end)
	else
		CG.pending = true -- tell the player once (OK pop-up) when the main menu is calm
	end
end

--- Run a hook body without crashing the game; failures are logged (and remembered for the log).
function MP.safe_call(name, f, ...)
	if type(f) ~= "function" then return false end
	local ok, err = pcall(f, ...)
	if not ok then CG.hook_failed(name, err, false) end
	return ok, err
end

--- A hook could not be applied. critical = multiplayer cannot work without it -> safe mode.
function CG.hook_failed(name, err, critical)
	MP.HOOK_ERRORS = MP.HOOK_ERRORS or {}
	MP.HOOK_ERRORS[#MP.HOOK_ERRORS + 1] = { name = name, err = tostring(err) }
	warn("hook '" .. tostring(name) .. "' failed: " .. tostring(err))
	if critical then CG.enter_safe_mode("hook '" .. tostring(name) .. "' failed (game update?)") end
end

--- Called by core.lua right before networking starts. Returns true if networking may start.
function CG.startup()
	local ok, err = pcall(function()
		CG.load_compat()
		CG.result = CG.check(CG.versions(), CG.compat, MP.LOAD_ERRORS, CG.clashes())
		local c = config()
		CG.action = CG.decide(CG.result, c and c.compat_ack)
		local parts = {}
		for _, it in ipairs(CG.result.items) do parts[#parts + 1] = it.label .. " " .. tostring(it.version) .. " " .. it.state end
		log("versions: " .. table.concat(parts, ", ") .. " -> " .. CG.action)
		if CG.action == "safe" then
			local why = {}
			for _, it in ipairs(CG.result.items) do
				if it.state == "blocked" then why[#why + 1] = it.label .. " " .. tostring(it.version) .. " (" .. tostring(it.reason) .. ")" end
			end
			for _, f in ipairs(CG.result.failed) do why[#why + 1] = "failed to load " .. f end
			CG.enter_safe_mode(table.concat(why, "; "))
		end
		CG.pending = (CG.action ~= "ok")
	end)
	if not ok then warn("compat check failed: " .. tostring(err) .. " (multiplayer stays on)") end
	return not MP.SAFE_MODE
end

--- A newer compat.json was fetched (update check): cache it and re-check. Returns true if applied.
function CG.apply_remote(raw)
	local remote = CG.json_decode(raw)
	if not CG.valid(remote) then warn("remote compat.json ignored (invalid)"); return false end
	local merged, why = CG.merge(CG.base or CG.load_compat(), remote, CG.mod_version())
	if why then log("remote compat.json not used: " .. why); return false end
	local c = config()
	if c then c.compat_cache = raw; save() end
	CG.compat = merged
	if CG.result and not MP.SAFE_MODE then
		local before = CG.action
		CG.result = CG.check(CG.versions(), CG.compat, MP.LOAD_ERRORS, CG.clashes())
		CG.action = CG.decide(CG.result, c and c.compat_ack)
		if before == "warn" and CG.action == "ok" then
			CG.pending = false
			if CG.is_open() then pcall(G.FUNCS.exit_overlay_menu) end
			log("newer release marks these versions as tested: no warning")
		end
	end
	return true
end

----------------------------------------------------------------------------- pop-up
local function T_node(text, scale, colour)
	return { n = G.UIT.T, config = { text = text, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true } }
end
local function colour(name)
	if MP.PATCH_NOTES and MP.PATCH_NOTES.colour then
		local key = ({ GREEN = "green", FILTER = "attention", RED = "mult" })[name]
		if key then return MP.PATCH_NOTES.colour(key) end
	end
	return G.C[name] or G.C.UI.TEXT_LIGHT
end

local function item_row(it, T)
	local label = T[it.state] or it.state
	local nodes = {
		{ n = G.UIT.C, config = { align = "cm", minw = 2.4, minh = 0.42, r = 0.1, colour = colour(CG.STATE_COLOUR[it.state]), padding = 0.03 },
			nodes = { T_node(label, 0.34, G.C.WHITE) } },
		{ n = G.UIT.B, config = { w = 0.25, h = 0.1 } },
		T_node(it.label .. " ", 0.48, colour(CG.STATE_COLOUR[it.state])),
		T_node(tostring(it.version or "?"), 0.42, G.C.UI.TEXT_LIGHT),
	}
	if it.state ~= "tested" and it.tested then
		nodes[#nodes + 1] = T_node("  (" .. T.tested_with .. ": " .. it.tested .. ")", 0.34, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT)
	end
	return { n = G.UIT.R, config = { align = "cl", padding = 0.05 }, nodes = nodes }
end

--- UI definition (also used by the preview renderer). view = { result=, lang=, safe= }
function CG.definition(view)
	local T = CG.TEXT[view.lang] or CG.TEXT.en
	local rows = {}
	for _, it in ipairs(view.result.items) do rows[#rows + 1] = item_row(it, T) end
	local failed = (view.result.failed and #view.result.failed > 0) or (MP.HOOK_ERRORS and #MP.HOOK_ERRORS > 0)
	local clash = view.result.clash and not view.safe
	local body = view.safe and (failed and T.failed_body or T.blocked_body) or (clash and T.clash_body) or T.body
	local body2 = view.safe and T.blocked_body2 or (clash and T.clash_body2) or T.body2
	local logo = (MP.PATCH_NOTES and MP.PATCH_NOTES.logo_node) and MP.PATCH_NOTES.logo_node() or nil
	local contents = {
		logo,
		{ n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { T_node(view.safe and T.blocked_title or (clash and T.clash_title) or T.title, 0.6, view.safe and colour("RED") or colour("FILTER")) } },
		{ n = G.UIT.R, config = { align = "cl", padding = 0.2, r = 0.1, colour = G.C.BLACK, minw = 11, emboss = 0.05 }, nodes = {
			{ n = G.UIT.C, config = { align = "cl" }, nodes = rows },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = { T_node(body, 0.4, G.C.UI.TEXT_LIGHT) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = { T_node(body2, 0.36, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT) } },
	}
	local buttons
	if view.safe then
		buttons = { UIBox_button({ label = { T.ok }, button = "mp3p_compat_ok", colour = G.C.GREEN, minw = 4, minh = 0.8, scale = 0.6 }) }
	else
		buttons = {
			UIBox_button({ label = { T.play }, button = "mp3p_compat_play", colour = G.C.GREEN, minw = 4.2, minh = 0.8, scale = 0.55 }),
			{ n = G.UIT.B, config = { w = 0.3, h = 0.1 } },
			UIBox_button({ label = { T.disable }, button = "mp3p_compat_disable", colour = G.C.RED, minw = 5.6, minh = 0.8, scale = 0.5 }),
		}
	end
	contents[#contents + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.12 }, nodes = buttons }
	local cleaned = {} -- drop the logo slot if there is none, keep the order
	for i = 1, #contents + 1 do if contents[i] then cleaned[#cleaned + 1] = contents[i] end end
	return create_UIBox_generic_options({ no_back = true, contents = cleaned })
end

function CG.is_open()
	return G and G.OVERLAY_MENU and G.OVERLAY_MENU.config and G.OVERLAY_MENU.config.mp3p_compat and CG.view ~= nil
end

function CG.open()
	if not CG.result then
		local ok, r = pcall(CG.check, CG.versions(), CG.compat or CG.load_compat(), MP.LOAD_ERRORS, CG.clashes())
		if not ok then return false end
		CG.result = r
	end
	CG.view = { result = CG.result, lang = CG.lang(), safe = MP.SAFE_MODE ~= nil and not MP.SAFE_MODE.by_user }
	local ok, err = pcall(function()
		G.FUNCS.overlay_menu({ definition = CG.definition(CG.view) })
		G.OVERLAY_MENU.config.mp3p_compat = true
	end)
	if not ok then warn("could not open compat warning: " .. tostring(err)); CG.view = nil; return false end
	return true
end

local function close()
	CG.view = nil
	CG.pending = false
	pcall(G.FUNCS.exit_overlay_menu)
end

if G and G.FUNCS then
	G.FUNCS.mp3p_compat_play = function()
		local c = config()
		if c and CG.result then c.compat_ack = CG.result.signature; save() end
		log("player chose Play anyway for " .. tostring(CG.result and CG.result.signature))
		close()
	end
	G.FUNCS.mp3p_compat_disable = function()
		close()
		CG.enter_safe_mode("player chose 'Disable multiplayer for now'", true)
	end
	G.FUNCS.mp3p_compat_ok = function() close() end
end

function CG.env()
	local U = MP.UPDATER
	local main_menu = G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
	return {
		pending = CG.pending,
		main_menu = main_menu,
		overlay = G and G.OVERLAY_MENU ~= nil,
		in_lobby = MP.LOBBY and (MP.LOBBY.code ~= nil) or false,
		in_run = G and G.STAGES and G.STAGE == G.STAGES.RUN,
		menu_age = CG.menu_since and (love.timer.getTime() - CG.menu_since) or 0,
		updater_busy = U and (U.state == "idle" or U.state == "checking" or U.compat_state == "fetching") or false,
		safe = MP.SAFE_MODE ~= nil,
	}
end

function CG.tick()
	local main_menu = G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil
	if not main_menu then CG.menu_since = nil else CG.menu_since = CG.menu_since or love.timer.getTime() end
	if not CG.pending or CG.is_open() then return end
	if CG.can_show(CG.env()) then
		if not CG.open() then CG.pending = false end
	end
end

if Game and Game.update and not CG.hooked then
	CG.hooked = true
	local update_ref = Game.update
	function Game:update(dt)
		pcall(CG.tick)
		return update_ref(self, dt)
	end
end

return CG
