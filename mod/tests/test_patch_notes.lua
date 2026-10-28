-- luajit tests/test_patch_notes.lua (run from mod/): patch notes pop-up logic + the real note files
local function ok(c, m) assert(c, m); print("ok: " .. m) end
-- minimal game stubs
local clock = 100
love = { timer = { getTime = function() return clock end } }
local saved = 0
local overlays = {}
SMODS = { Mods = { Multiplayer = { version = "0.6.8~3P", config = {} } },
	load_file = function(path) local f = loadfile(path); return f end,
	save_mod_config = function() saved = saved + 1 end }
G = { STAGES = { MAIN_MENU = 1, RUN = 2 }, STAGE = 1, MAIN_MENU_UI = {}, SETTINGS = { language = "en-us" },
	C = { GREEN = "green", CHIPS = "blue", ORANGE = "orange", RED = "red", GOLD = "gold", BLACK = "black", UI = { TEXT_LIGHT = "w" } },
	UIT = { R = 1, C = 2, T = 3, B = 4, ROOT = 0 }, FUNCS = {} }
function G.FUNCS.overlay_menu(a) G.OVERLAY_MENU = { config = {}, def = a.definition }; overlays[#overlays + 1] = a.definition end
function G.FUNCS.exit_overlay_menu() G.OVERLAY_MENU = nil end
function create_UIBox_generic_options(t) return { generic = t } end
function UIBox_button(t) return { button = t } end
function create_option_cycle(t) return { cycle = t } end
MP = { LOBBY = {} }
dofile("lib/patch_notes.lua")
local PN = MP.PATCH_NOTES

-- versions
ok(PN.ver("0.6.8~3P") == "0.6.8" and PN.ver("v0.6.7") == "0.6.7" and PN.ver("0.6.8-preview") == "0.6.8" and PN.ver("x") == nil, "version normalisation")
ok(PN.cmp("0.6.10", "0.6.9") == 1 and PN.cmp("0.6.8~3P", "0.6.8") == 0 and PN.cmp("0.6.7", "0.6.8") == -1 and PN.cmp("1.0", "0.9.9") == 1, "version comparison")
local V = { "0.6.8", "0.6.7", "0.6.6", "0.6.9" }
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
ok(same(PN.pending(nil, "0.6.8~3P", V), { "0.6.8" }), "fresh install: only the current version")
ok(same(PN.pending("0.6.7", "0.6.8~3P", V), { "0.6.8" }), "update 0.6.7 -> 0.6.8: 0.6.8 only")
ok(same(PN.pending("0.6.5", "0.6.8", V), { "0.6.8", "0.6.7", "0.6.6" }), "skipped versions: all since last seen, newest first")
ok(#PN.pending("0.6.8", "0.6.8~3P", V) == 0 and #PN.pending("0.6.9", "0.6.8", V) == 0, "already seen (or downgraded): nothing")
ok(not PN.pending("0.6.5", "0.6.8", V)[4], "future notes (0.6.9) never shown for 0.6.8")
local many = {}; for i = 1, 20 do many[i] = "0.7." .. i end
ok(#PN.pending("0.6.0", "0.7.20", many) == PN.MAX_VERSIONS, "many skipped versions: capped at " .. PN.MAX_VERSIONS)

-- real files
local notes, versions = PN.load(function(p) return dofile(p) end)
ok(notes["0.6.8"] and notes["0.6.7"] and versions[1] == "0.6.8", "loads patchnotes/0.6.8.lua and 0.6.7.lua from the index")
for _, v in ipairs(versions) do
	for _, lang in ipairs({ "en", "nl" }) do
		for _, s in ipairs(PN.SECTIONS) do
			assert(type(notes[v][lang]) == "table" and type(notes[v][lang][s]) == "table" and #notes[v][lang][s] > 0, v .. " " .. lang .. " has section " .. s)
			assert(#notes[v][lang][s] == #notes[v].en[s], v .. ": NL and EN have the same number of bullets in " .. s)
		end
	end
end
ok(true, "0.6.8 and 0.6.7 have New/Changed/Fixed/Known issues in EN and NL")
local bad = PN.load(function(p)
	if p:find("index") then return { "9.9", "1.0" } end
	if p:find("9%.9") then error("syntax error") end
	return { en = { new = { "x" } } }
end)
ok(bad["1.0"] and not bad["9.9"], "a broken note file is skipped, the rest still loads")

-- language + fallback
ok(PN.lang("nl") == "nl" and PN.lang("en-us") == "en" and PN.lang("de") == "en" and PN.lang(nil) == "en", "language: nl, otherwise English")
local function texts(ls) local t = {} for _, l in ipairs(ls) do t[#t + 1] = l.text or "" end return table.concat(t, "\n") end
local nl = texts(PN.lines(notes, { "0.6.8" }, "nl"))
ok(nl:find("Nieuw") and nl:find("Bekende problemen") and nl:find("Host%-migratie"), "Dutch headers and text")
local mixed = { ["1.0"] = { version = "1.0", en = { new = { "English new" }, fixed = { "English fix" } }, nl = { new = { "Nederlands nieuw" } } } }
local mt = texts(PN.lines(mixed, { "1.0" }, "nl"))
ok(mt:find("Nederlands nieuw") and mt:find("English fix") and not mt:find("English new"), "missing Dutch section falls back to English")
local en = PN.lines(notes, { "0.6.8", "0.6.7" }, "en")
local heads = 0; for _, l in ipairs(en) do if l.kind == "version" then heads = heads + 1 end end
ok(heads == 2 and en[1].text:find("0.6.8"), "combined notes: one header per version, newest first")
for _, l in ipairs(en) do assert(not l.text or #l.text <= PN.WRAP, "line too long: " .. tostring(l.text)) end
ok(true, "long bullets are wrapped to " .. PN.WRAP .. " characters")
local w = PN.wrap("aaa bbb ccc ddd", 7)
ok(#w == 2 and w[1] == "aaa bbb" and w[2] == "ccc ddd", "word wrap")

-- pages
local pages = PN.pages(en, PN.LINES_PER_PAGE)
local n = 0
for pi, pg in ipairs(pages) do
	assert(#pg <= PN.LINES_PER_PAGE + 2, "page " .. pi .. " not too long")
	local last = pg[#pg].kind
	assert(last ~= "version" and last ~= "title" and last ~= "section", "page " .. pi .. " does not end with a header")
	assert(pg[1].kind ~= "gap" and pg[1].kind ~= "cont", "page " .. pi .. " starts cleanly")
	for _, l in ipairs(pg) do if l.kind ~= "gap" then n = n + 1 end end
end
local m = 0; for _, l in ipairs(en) do if l.kind ~= "gap" then m = m + 1 end end
ok(#pages >= 2 and n == m, "long notes split into " .. #pages .. " pages, nothing lost")

-- when may it pop up by itself
local calm = { main_menu = true, menu_age = 5 }
ok(PN.can_auto_show(calm), "calm main menu: yes")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 1 }), "not in the first seconds (update button first)")
ok(not PN.can_auto_show({ main_menu = false, menu_age = 9 }), "not outside the main menu")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 9, in_lobby = true }), "not in a lobby")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 9, in_run = true }), "not in a run / match")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 9, p2p_busy = true }), "not while a Steam invite is being joined")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 9, overlay = true }), "not on top of another pop-up")
ok(not PN.can_auto_show({ main_menu = true, menu_age = 5, updater_busy = true }) and PN.can_auto_show({ main_menu = true, menu_age = 9, updater_busy = true }),
	"waits for the update check, at most " .. PN.UPDATER_WAIT .. " s")

-- full flow in the stubbed game
local function frames(secs) for _ = 1, secs * 4 do clock = clock + 0.25; PN.tick() end end
frames(2)
ok(#overlays == 0, "nothing in the first 2 s on the main menu")
frames(2)
ok(#overlays == 1 and PN.view and PN.view.versions[1] == "0.6.8" and #PN.view.versions == 1, "fresh install: 0.6.8 notes pop up once on the main menu")
ok(SMODS.Mods.Multiplayer.config.patchnotes_seen == "0.6.8" and saved >= 1, "last seen version saved in the mod config")
local def = overlays[1].generic
local function find(t, pred, seen) seen = seen or {}; if type(t) ~= "table" or seen[t] then return nil end; seen[t] = true
	if pred(t) then return t end; for _, v in pairs(t) do local r = find(v, pred, seen); if r then return r end end end
ok(find(def, function(x) return x.button and x.button.button == "mp3p_patchnotes_close" and x.button.label[1] == "Got it" end), "'Got it' button")
ok(find(def, function(x) return x.cycle and x.cycle.opt_callback == "mp3p_patchnotes_page" end) or #PN.view.pages == 1, "page switcher when there is more than one page")
G.FUNCS.mp3p_patchnotes_close()
ok(G.OVERLAY_MENU == nil and PN.view == nil, "'Got it' closes it")
frames(10)
ok(#overlays == 1, "not shown again in the same session")
-- next start of the game, same version
PN.auto_done, PN.menu_since = nil, nil
frames(10)
ok(#overlays == 1, "next start, same version: not shown again")
-- update from 0.6.6 straight to 0.6.8 (Dutch game)
SMODS.Mods.Multiplayer.config.patchnotes_seen = "0.6.6"
G.SETTINGS.language = "nl"
PN.auto_done, PN.menu_since = nil, nil
frames(5)
ok(#overlays == 2 and #PN.view.versions == 2 and PN.view.lang == "nl" and PN.view.combined, "skipped 0.6.7: combined 0.6.8 + 0.6.7 notes, in Dutch")
ok(find(overlays[2], function(x) return x.button and x.button.label[1] == "Begrepen" end), "'Begrepen' button in Dutch")
G.FUNCS.mp3p_patchnotes_close()
-- invite / lobby: waits, then shows on the menu later
SMODS.Mods.Multiplayer.config.patchnotes_seen = "0.6.7"
PN.auto_done, PN.menu_since = nil, nil
MP.STEAM_P2P = { mode = "local", pending_invite = "123" }
frames(10)
ok(#overlays == 2, "game started from a Steam invite: no pop-up while joining")
MP.STEAM_P2P = { mode = "guest" }; MP.LOBBY.code = "ABCD"
frames(10)
ok(#overlays == 2, "no pop-up in the lobby")
G.STAGE = 2; frames(5)
ok(#overlays == 2, "no pop-up mid-match")
G.STAGE = 1; MP.STEAM_P2P = { mode = "local" }; MP.LOBBY.code = nil
frames(5)
ok(#overlays == 3 and PN.view.versions[1] == "0.6.8", "back on the main menu after the match: now it shows")
-- an invite arrives while it is open: it closes
MP.LOBBY.code = "EFGH"; PN.tick()
ok(G.OVERLAY_MENU == nil and PN.view == nil, "a lobby join while it is open closes it")
ok(SMODS.Mods.Multiplayer.config.patchnotes_seen == "0.6.7", "... and it is not counted as seen")
MP.LOBBY.code = nil
frames(5)
ok(#overlays == 4 and SMODS.Mods.Multiplayer.config.patchnotes_seen == "0.6.8", "it comes back on the calm main menu afterwards")
G.FUNCS.mp3p_patchnotes_close()
-- the Patch notes button reopens it any time
G.FUNCS.mp3p_patchnotes_open()
ok(G.OVERLAY_MENU and PN.view and PN.view.versions[1] == "0.6.8", "Patch notes button reopens the current notes")
print("PASS: patch notes")
