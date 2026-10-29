-- luajit tests/test_lobby_presets.lua (run from mod/): lobby presets - cleaning, file format, apply rules,
-- host-only loading, delete confirm, and that the Presets tab fits (EN + NL, longest names).
local function ok(c, m) assert(c, m); print("ok: " .. m) end
_G.G = { UIT = { ROOT = 0, R = 1, C = 2, T = 3, O = 4, B = 5 }, C = setmetatable({ UI = { TEXT_LIGHT = {}, TEXT_INACTIVE = {}, BACKGROUND_INACTIVE = {}, TRANSPARENT_DARK = {} } }, { __index = function() return {} end }),
	FUNCS = {}, SETTINGS = { profile = 2 } }
local files = {}
_G.love = { filesystem = { read = function(p) return files[p] end, write = function(p, s) files[p] = s; return true end,
	getInfo = function(p) return true end, createDirectory = function() end } }
local sent = 0
_G.MP = { UI = {}, LOBBY = { code = "ABCD", is_host = true, config = {} }, ACTIONS = { lobby_options = function() sent = sent + 1 end }, DECK = { MAX_STAKE = 8 } }
local UM = dofile("tests/ui_measure.lua")
_G.localize = function(k) return "ERROR" end
dofile("lib/fit.lua")
_G.UIBox_button = function(a)
	-- same shape as the game's UIBox_button with col = true: C > C(button) > R > T
	return { n = G.UIT.C, config = { align = "cm" }, nodes = { { n = G.UIT.C, config = { minw = a.minw, minh = a.minh, button = a.button or "exit_overlay_menu", colour = a.colour }, nodes = {
		{ n = G.UIT.R, config = {}, nodes = { { n = G.UIT.T, config = { text = a.label[1], scale = a.scale } } } } } } } }
end
_G.UIBox = function(a) return { definition = a.definition, remove = function() end, recalculate = function() end } end
local LP = dofile("lib/lobby_presets.lua")
local function base() return { gamemode = "gamemode_mp_attrition", ruleset = "ruleset_mp_blitz", starting_lives = 4, timer = true, timer_base_seconds = 150,
	back = "Red Deck", sleeve = "sleeve_casl_none", stake = 1, challenge = "", custom_seed = "random", different_decks = false } end

-- 1. cleaning: unknown keys, wrong types, clamps, snaps
local c = LP.clean({ name = "x\1y", gamemode = "gamemode_mp_duel", options = { starting_lives = 99, timer_base_seconds = 100, rejoin_grace = "250",
	timer = "true", the_order = "maybe", stake = -3, custom_seed = "ab12", back = "Bad=Deck", unknown_key = 5, pvp_countdown_seconds = "nan" } })
ok(c.options.starting_lives == 16 and c.options.timer_base_seconds == 90 and c.options.rejoin_grace == 300, "numbers clamp/snap to allowed values (99->16, 100s->90s, 250->300)")
ok(c.options.timer == true and c.options.the_order == nil and c.options.unknown_key == nil and c.options.back == nil, "bad bools, unknown keys and bad names are ignored")
ok(c.options.stake == 1 and c.options.custom_seed == "AB12" and c.options.pvp_countdown_seconds == nil and c.name == "xy", "stake clamps, seed upper-cased, NaN ignored, name cleaned")
ok(LP.clean({ options = { foo = 1 } }) == nil and LP.clean("junk") == nil, "nothing valid -> no preset")

-- 2. file round trip; old/odd/newer files
LP.slots = { [1] = LP.capture(base()), [3] = { options = { starting_lives = 2, timer = false } } }
LP.loaded_profile = 2
ok(LP.save() and files["2/hs_lobby_presets.cfg"], "saved in the profile folder as hs_lobby_presets.cfg (not save.jkr, no .json)")
local slots, ver = LP.parse(files["2/hs_lobby_presets.cfg"])
ok(ver == 1 and slots[1].options.starting_lives == 4 and slots[1].gamemode == "gamemode_mp_attrition" and slots[2] == nil and slots[3].options.timer == false, "round trip keeps slots and gaps")
local weird = "version=7\r\n[slot 2]\r\nstarting_lives=3\r\nfuture_option=1\r\ngarbage line\r\n[slot 9]\r\nstarting_lives=5\r\n[slot 4]\r\nnothing=1\r\n"
local ws, wv = LP.parse(weird)
ok(wv == 7 and ws[2].options.starting_lives == 3 and ws[9] == nil and ws[4] == nil, "newer version, CRLF, unknown keys, bad slots: read what is understood")
ok(next(LP.parse(nil)) == nil and next(LP.parse("")) == nil, "missing/empty file -> no presets")

-- 3. apply rules
local cfg = base()
local ch, notes = LP.apply_to(cfg, { gamemode = "gamemode_mp_deathmatch", ruleset = "ruleset_mp_blitz", options = { starting_lives = 2, timer = false, stake = 20 } }, { max_stake = 5 })
ok(cfg.starting_lives == 2 and cfg.timer == false and cfg.stake == 5 and notes.mode_differs == "gamemode_mp_deathmatch" and cfg.gamemode == "gamemode_mp_attrition", "options applied, stake capped, mode never switched (noted)")
local k = base(); k.gamemode = "gamemode_mp_koth"; k.starting_lives = 3
LP.apply_to(k, { options = { starting_lives = 8 } })
ok(k.starting_lives == 3, "King of the Hill / Survival keep their fixed lives")
local d = base(); local _, n2 = LP.apply_to(d, { options = { back = "Ghost Deck Of A Removed Mod" } }, { valid_back = function(n) return n == "Red Deck" end })
ok(d.back == "Red Deck" and n2.deck_missing, "deck from a removed mod is skipped")
for _, b in ipairs(LP.BUILTIN) do
	local cc = base(); LP.apply_to(cc, { options = b.options })
	ok(LP.clean({ options = b.options }) and cc.starting_lives >= 1, "built-in preset valid: " .. b.id)
end

-- 4. host only, normal sync path
MP.LOBBY.config = base()
ok(LP.apply({ options = { starting_lives = 7 } }, "x") and sent == 1 and MP.LOBBY.config.starting_lives == 7, "host: applied and sent via lobby_options")
MP.LOBBY.is_host = false
ok(not LP.apply({ options = { starting_lives = 2 } }, "x") and sent == 1 and MP.LOBBY.config.starting_lives == 7, "guest: cannot apply, nothing sent")
MP.LOBBY.is_host = true; MP.LOBBY.config.forced_config = true
ok(not LP.apply({ options = { starting_lives = 2 } }, "x"), "forced ruleset: presets do not override")
MP.LOBBY.config.forced_config = nil

-- 5. save / delete with confirm (game functions), each logged once
local logged = {}
_G.sendInfoMessage = function(m) logged[#logged + 1] = m end
G.OVERLAY_MENU = nil
G.FUNCS.mp3p_preset_save_2()
ok(LP.slots[2] and LP.parse(files["2/hs_lobby_presets.cfg"])[2].options.starting_lives == 7, "Save stores the current lobby in the slot and on disk")
G.FUNCS.mp3p_preset_delete_2()
ok(LP.slots[2] and LP.confirm_delete == 2, "first Delete click only asks to confirm")
G.FUNCS.mp3p_preset_delete_2()
ok(LP.slots[2] == nil and LP.parse(files["2/hs_lobby_presets.cfg"])[2] == nil, "second click deletes")
G.UIDEF = { create_UIBox_lobby_options = function() return {} end }; G.FUNCS.overlay_menu = function() end
LP.slots[1] = LP.capture(base()); G.FUNCS.mp3p_preset_load_1()
ok(logged[1] == "Lobby presets: saved slot 2" and logged[2]:find("delete slot 2 asked", 1, true) and logged[3] == "Lobby presets: deleted slot 2"
	and logged[4]:find("loaded slot 1", 1, true), "save / delete-ask / delete / load each write one log line")

-- 6. layout: EN + NL, every slot filled with the longest auto-name, confirm state; no overflow, no cut labels
local function long_slot() return { options = { starting_lives = 16, timer_base_seconds = 240 }, gamemode = "gamemode_mp_showdown" } end
for _, lang in ipairs({ "en-us", "nl" }) do
	_G.localize = UM.localizer("localization/" .. lang .. ".lua")
	local Lz = function(k) local s = localize(k); assert(s ~= "ERROR", lang .. " missing " .. k); return s end
	for _, key in ipairs({ "k_lobby_presets", "k_preset_builtin", "k_preset_mine", "k_preset_classic", "k_preset_quick", "k_preset_party", "k_preset_relaxed",
		"k_preset_empty", "k_preset_load", "k_preset_save", "k_preset_overwrite", "k_preset_delete", "k_preset_sure", "k_preset_lives_fmt", "k_preset_no_timer",
		"k_preset_hint", "k_preset_only_host", "k_preset_loaded_fmt", "k_preset_mode_kept_fmt", "k_preset_saved_fmt", "k_preset_save_failed",
		"k_preset_delete_confirm", "k_preset_deleted_fmt" }) do Lz(key) end
	local S = LP.UI_SIZES
	for _, key in ipairs({ "k_preset_load", "k_preset_save", "k_preset_overwrite", "k_preset_delete", "k_preset_sure" }) do
		ok(MP.FIT.width(Lz(key), S.BTN_SCALE) <= S.BTN_W - 0.2, lang .. " button label fits uncut: " .. Lz(key))
	end
	for _, b in ipairs(LP.BUILTIN) do ok(MP.FIT.width(Lz(b.label), S.BTN_SCALE) <= S.BI_W - 0.2, lang .. " built-in label fits uncut: " .. Lz(b.label)) end
	for _, host in ipairs({ true, false }) do
		MP.LOBBY.is_host = host
		LP.slots = { long_slot(), long_slot(), long_slot(), long_slot() }; LP.confirm_delete = 3
		LP.status = { text = string.format(Lz("k_preset_loaded_fmt"), ("W"):rep(40)) .. " - " .. string.format(Lz("k_preset_mode_kept_fmt"), "Deathmatch"), colour = "GREEN" }
		local def = LP.area_def()
		local w, issues = UM.measure(def)
		ok(#issues == 0 and w <= 9.6, string.format("%s %s: presets area %.2f wide (tab is 10), no overflow", lang, host and "host" or "guest", w))
		local loads = UM.find(def, function(nd) return nd.config and type(nd.config.button) == "string" and nd.config.button:find("preset_load") end)
		local bi = UM.find(def, function(nd) return nd.config and type(nd.config.button) == "string" and nd.config.button:find("preset_builtin") end)
		ok(host and (#loads == 4 and #bi == 4) or (not host and #loads == 0 and #bi == 0), lang .. (host and " host: Load + built-ins clickable" or " guest: Load + built-ins disabled"))
		local exits = UM.find(def, function(nd) return nd.config and nd.config.button == "exit_overlay_menu" end)
		ok(#exits == 0, lang .. ": no disabled button falls back to closing the menu")
	end
end
print("PASS: lobby presets")
