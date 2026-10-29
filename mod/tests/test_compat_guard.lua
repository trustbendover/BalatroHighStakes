-- luajit tests/test_compat_guard.lua (run from mod/): 0.6.8 startup compatibility guard + safe mode
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local clock = 100
love = { timer = { getTime = function() return clock end } }
local saved, logs = 0, {}
function sendInfoMessage(m) logs[#logs + 1] = m end
function sendWarnMessage(m) logs[#logs + 1] = "WARN " .. m end
NFS = { read = function(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end }
local function fresh_smods(cfg)
	SMODS = { version = "1.0.0~BETA-1620a-STEAMODDED",
		Mods = { Multiplayer = { version = "0.6.8~3P", config = cfg or {} }, Lovely = { version = "0.10.0" } },
		save_mod_config = function() saved = saved + 1 end }
end
fresh_smods()
G = { VERSION = "1.0.1o-FULL", STAGES = { MAIN_MENU = 1, RUN = 2 }, STAGE = 1, MAIN_MENU_UI = {}, SETTINGS = { language = "en-us" },
	C = { GREEN = "green", RED = "red", FILTER = "orange", WHITE = "white", BLACK = "black", UI = { TEXT_LIGHT = "w", TEXT_INACTIVE = "i" } },
	UIT = { R = 1, C = 2, T = 3, B = 4, O = 5, ROOT = 0 }, FUNCS = {} }
local overlays = {}
function G.FUNCS.overlay_menu(a) G.OVERLAY_MENU = { config = {}, def = a.definition }; overlays[#overlays + 1] = a.definition end
function G.FUNCS.exit_overlay_menu() G.OVERLAY_MENU = nil end
function create_UIBox_generic_options(t) return { generic = t } end
function UIBox_button(t) return { button = t } end
function create_option_cycle(t) return { cycle = t } end
MP = { LOBBY = { connected = true }, path = ".", LOAD_ERRORS = {} }
dofile("lib/compat_guard.lua")
local CG = MP.COMPAT_GUARD

-- version handling
ok(CG.norm("1.0.1o-FULL") == "1.0.1o" and CG.norm("1.0.0~BETA-1620a-STEAMODDED") == "1.0.0~BETA-1620a" and CG.norm("v0.10.0") == "0.10.0" and CG.norm(nil) == nil, "normalise game/loader version strings")
ok(CG.cmp("1.0.1o", "1.0.1n") == 1 and CG.cmp("1.0.1o", "1.0.1o-FULL") == 0 and CG.cmp("1.0.1", "1.0.1o") == -1 and CG.cmp("1.0.2", "1.0.1o") == 1, "Balatro versions compare (letters after numbers)")
ok(CG.cmp("1.0.0~BETA-1620a", "1.0.0~BETA-1620b") == -1 and CG.cmp("1.0.0~BETA-1715a", "1.0.0~BETA-1620a") == 1 and CG.cmp("1.0.0~BETA-0614a", "1.0.0~BETA-1620a") == -1, "Steamodded betas compare by build number and letter")
ok(CG.cmp("1.0.0~BETA-1620a", "1.0.0") == -1 and CG.cmp("1.0.0", "1.0.0~BETA-1620a") == 1 and CG.cmp("1.1.0~ALPHA-1", "1.0.0") == 1, "a pre-release (~) is older than its release")
ok(CG.cmp("0.10.0", "0.9.0") == 1 and CG.cmp("0.10.0", "0.10") == 1 and CG.cmp("0.9", "0.9") == 0, "Lovely versions compare numerically (0.10 > 0.9)")

-- compat.json (real file, tiny JSON reader since luajit has no json module here)
local compat = CG.load_compat()
ok(CG.valid(compat) and compat.balatro.tested[1] == "1.0.1o" and compat.steamodded.tested[1] == "1.0.0~BETA-1620a" and compat.lovely.tested[1] == "0.10.0", "loads the shipped compat.json")
ok(compat.steamodded.pin.sha256:match("^%x+$") and #compat.steamodded.pin.sha256 == 64 and #compat.lovely.pin.sha256 == 64, "pins carry SHA256 hashes")
local ver_line = io.open("Multiplayer.json"):read("*a"):match('"version"%s*:%s*"([^"~]+)')
ok(ver_line == compat.mod_version, "compat.json mod_version matches Multiplayer.json (" .. tostring(ver_line) .. ")")
ok(CG.json_decode('{"a":[1,2,{"b":"x\\"y"}],"t":true,"f":false,"n":null}').a[3].b == 'x"y' and CG.json_decode("{bad") == nil, "JSON reader: nesting, escapes, garbage")
ok(not CG.valid({ schema = 2 }) and not CG.valid({ schema = 1, balatro = "x" }) and not CG.valid(nil), "invalid compat tables are rejected")

-- decisions
local tested = { balatro = "1.0.1o", steamodded = "1.0.0~BETA-1620a", lovely = "0.10.0" }
local r = CG.check(tested, compat, {})
ok(r.status == "ok" and CG.decide(r) == "ok", "tested versions -> no warning")
r = CG.check({ balatro = "1.0.2a", steamodded = "1.0.0~BETA-1620a", lovely = "0.10.0" }, compat, {})
ok(r.status == "untested" and CG.decide(r) == "warn" and r.items[1].state == "untested" and r.items[1].tested == "1.0.1o", "new Balatro update -> warning naming Balatro")
r = CG.check({ balatro = "1.0.1o", steamodded = "1.0.0~BETA-1801a", lovely = "0.10.0" }, compat, {})
ok(r.status == "untested" and r.items[2].state == "untested", "newer Steamodded -> warning naming Steamodded")
ok(CG.decide(r, r.signature) == "ok" and CG.decide(r, "other") == "warn", "'Play anyway' is remembered for exactly this combination")
r = CG.check({ balatro = "1.0.1o", steamodded = "1.0.0~BETA-1620a", lovely = nil }, compat, {})
ok(r.status == "untested" and r.items[3].state == "unknown", "unknown Lovely version -> warning, not safe mode")
r = CG.check({ balatro = "1.0.1o", steamodded = "1.0.0~BETA-1620a", lovely = "0.8.0" }, compat, {})
ok(r.status == "blocked" and CG.decide(r, r.signature) == "safe", "Lovely older than min -> safe mode (even after Play anyway)")
local blocked = { schema = 1, balatro = compat.balatro, steamodded = compat.steamodded, lovely = compat.lovely,
	blocked = { { component = "steamodded", version = "1.0.0~BETA-1801a", reason = "breaks lobbies" } } }
r = CG.check({ balatro = "1.0.1o", steamodded = "1.0.0~BETA-1801a-STEAMODDED", lovely = "0.10.0" }, blocked, {})
ok(r.status == "blocked" and r.items[2].reason == "breaks lobbies", "blocklisted Steamodded -> safe mode with the reason")
r = CG.check(tested, compat, { { file = "networking/action_handlers.lua", err = "boom" }, { file = "objects/jokers/x.lua", err = "meh" } })
ok(r.status == "blocked" and #r.failed == 1 and r.failed[1] == "networking/action_handlers.lua", "a core file failing to load -> safe mode (a joker file alone does not)")
r = CG.check(tested, compat, { { file = "objects/jokers/x.lua", err = "meh" } })
ok(r.status == "ok", "non-core load error -> logged only")

-- pop-up timing
local env = { pending = true, main_menu = true, overlay = false, menu_age = 3 }
ok(CG.can_show(env), "warning shows on a calm main menu")
ok(not CG.can_show({ pending = true, main_menu = true, overlay = true, menu_age = 9 }), "never on top of another pop-up")
ok(not CG.can_show({ pending = true, main_menu = true, in_lobby = true, menu_age = 9 }) and not CG.can_show({ pending = true, main_menu = true, in_run = true, menu_age = 9 }), "never in a lobby or a run")
ok(not CG.can_show({ pending = true, main_menu = true, updater_busy = true, menu_age = 4 }) and CG.can_show({ pending = true, main_menu = true, updater_busy = true, menu_age = 8 }), "waits (max 7 s) for a newer compat.json from the update check")
ok(CG.can_show({ pending = true, main_menu = true, updater_busy = true, safe = true, menu_age = 3 }), "safe mode notice does not wait for the updater")

-- remote compat.json (newer release)
local remote = [[{"schema":1,"mod_version":"0.6.9","applies_from":"0.6.8","balatro":{"tested":["1.0.1o","1.0.2a"]},
 "steamodded":{"tested":["1.0.0~BETA-1801a"]},"lovely":{"tested":["0.10.0"]},
 "blocked":[{"component":"steamodded","version":"1.0.0~BETA-1620a","reason":"bogus"},{"component":"lovely","version":"0.11.0","reason":"crash"}]}]]
local merged, why = CG.merge(compat, CG.json_decode(remote), "0.6.8")
ok(not why and CG.state("balatro", "1.0.2a", merged) == "tested" and CG.state("steamodded", "1.0.0~BETA-1801a", merged) == "tested", "newer release marks a new Balatro / Steamodded as tested")
ok(CG.state("steamodded", "1.0.0~BETA-1620a", merged) == "tested", "a remote block can never hit the versions this build shipped as tested")
ok(CG.state("lovely", "0.11.0", merged) == "blocked", "a remote block for another version applies")
local _, why2 = CG.merge(compat, CG.json_decode(remote:gsub('"applies_from":"0.6.8"', '"applies_from":"0.7.0"')), "0.6.8")
ok(why2 == "not for this version", "remote compat for newer mods only is ignored")
local _, why3 = CG.merge(compat, CG.json_decode('{"schema":9}'), "0.6.8")
ok(why3 == "invalid", "garbage remote compat is ignored")

-- start-up glue: untested Balatro -> pending warning, networking allowed
G.VERSION = "1.0.2a-FULL"
ok(CG.startup() == true and CG.action == "warn" and CG.pending and not MP.SAFE_MODE, "startup: untested Balatro -> warn, multiplayer stays on")
CG.menu_since = nil; CG.tick(); clock = clock + 3; MP.UPDATER = { state = "none" }; CG.tick()
ok(CG.is_open() and overlays[#overlays].generic, "warning pop-up opens on the main menu")
local function texts(node, out)
	out = out or {}
	if type(node) ~= "table" then return out end
	if node.config and node.config.text then out[#out + 1] = node.config.text end
	if node.button and node.button.label then out[#out + 1] = node.button.label[1] end
	for _, v in pairs(node) do if type(v) == "table" then texts(v, out) end end
	return out
end
local all = table.concat(texts(overlays[#overlays]), "|")
ok(all:find("Balatro") and all:find("1.0.2a") and all:find("UNTESTED") and all:find("Play anyway") and all:find("Disable multiplayer for now"), "warning names the component and has both choices")
-- patch notes must not stack on it
dofile("lib/patch_notes.lua")
local PN = MP.PATCH_NOTES
ok(PN.env().compat_pending == true and not PN.can_auto_show({ main_menu = true, menu_age = 9, compat_pending = true }), "patch notes wait while the compat warning is pending/open")
G.FUNCS.mp3p_compat_play()
ok(not CG.is_open() and not CG.pending and SMODS.Mods.Multiplayer.config.compat_ack == CG.result.signature and saved > 0, "'Play anyway' closes and remembers the combination")
ok(PN.env().compat_pending == false, "patch notes may show after the warning is answered")
fresh_smods({ compat_ack = SMODS.Mods.Multiplayer.config.compat_ack }); CG.result = nil
ok(CG.startup() and CG.action == "ok" and not CG.pending, "next start with the same versions: no warning")

-- remote apply closes a pending warning
fresh_smods(); G.OVERLAY_MENU = nil
CG.startup(); ok(CG.pending, "untested again with a fresh config")
ok(CG.apply_remote(remote) and CG.action == "ok" and not CG.pending and SMODS.Mods.Multiplayer.config.compat_cache == remote, "newer compat.json marks it tested: no warning, cached")
fresh_smods({ compat_cache = remote }); CG.startup()
ok(CG.action == "ok", "cached remote compat.json is used on the next (offline) start")

-- "Disable multiplayer for now"
fresh_smods(); MP.STEAM_P2P = { shutdown = function() MP._p2p_down = true end }
CG.startup(); G.OVERLAY_MENU = nil; CG.open()
G.FUNCS.mp3p_compat_disable()
ok(MP.SAFE_MODE and MP.SAFE_MODE.by_user and MP.STEAM_P2P == nil and MP._p2p_down and MP.LOBBY.connected == false, "'Disable multiplayer for now': networking stopped for this session")
ok(CG.note() == "Multiplayer is off for now", "main menu shows a short note")
ok(SMODS.Mods.Multiplayer.config.compat_ack == nil, "disabling is not remembered (asks again next start)")

-- blocked -> safe mode at startup, networking not allowed
MP.SAFE_MODE = nil; G.VERSION = "1.0.1o"; SMODS.Mods.Lovely.version = "0.8.0"; logs = {}
ok(CG.startup() == false and MP.SAFE_MODE and not MP.SAFE_MODE.by_user, "blocked Lovely -> startup refuses networking (safe mode)")
local logged = table.concat(logs, "\n")
ok(logged:find("SAFE MODE") and logged:find("Lovely 0.8.0"), "safe mode is logged clearly with the reason")
G.OVERLAY_MENU = nil; CG.menu_since = nil; CG.tick(); clock = clock + 3; CG.tick()
all = table.concat(texts(overlays[#overlays]), "|")
ok(CG.is_open() and all:find("BLOCKED") and all:find("OK") and not all:find("Play anyway"), "safe mode notice: blocked badge, only OK")
G.FUNCS.mp3p_compat_ok(); ok(not CG.is_open(), "OK closes it")
ok(CG.note() == "Multiplayer is off (safe mode)", "main menu note for safe mode")

-- Dutch
G.SETTINGS.language = "nl"; G.OVERLAY_MENU = nil; CG.open()
all = table.concat(texts(overlays[#overlays]), "|")
ok(all:find("veilige modus") and all:find("GEBLOKKEERD"), "Dutch texts")
G.FUNCS.mp3p_compat_ok(); G.SETTINGS.language = "en-us"

-- hooks
MP.SAFE_MODE = nil; SMODS.Mods.Lovely.version = "0.10.0"
local okc = MP.safe_call("cosmetic", function() error("menu moved") end)
ok(okc == false and MP.HOOK_ERRORS[1].name == "cosmetic" and not MP.SAFE_MODE, "a failing cosmetic hook is caught and logged, multiplayer stays on")
CG.hook_failed("play button", "nil index", true)
ok(MP.SAFE_MODE and MP.SAFE_MODE.reason:find("play button") and CG.pending, "a failing critical hook -> safe mode + notice")
CG.check_texts = nil
-- in-game update check downloads compat.json from the latest release (async, fail-silent)
do
	local pending = {}
	G.E_MANAGER = { add_event = function() end }
	function Event(t) return t end
	package.loaded["SMODS.https"] = { asyncRequest = function(url, opts, cb) pending[#pending + 1] = { url = url, cb = cb } end }
	MP.ENV = {}; MP.UPDATER = nil; MP.SAFE_MODE = nil
	fresh_smods(); G.VERSION = "1.0.2a-FULL"; SMODS.Mods.Lovely.version = "0.10.0"
	local U = dofile("lib/updater.lua")
	CG.startup(); ok(CG.pending and CG.action == "warn", "fetch: starts with an untested Balatro")
	U.check()
	local rel = '{"tag_name":"v0.6.9","assets":[{"name":"BalatroMultiplayer3P-v0.6.9-Installer.zip"},'
		.. '{"name":"compat.json","browser_download_url":"https://github.com/x/y/releases/download/v0.6.9/compat.json"}]}'
	ok(U.parse_compat_asset(rel) == "https://github.com/x/y/releases/download/v0.6.9/compat.json" and U.parse_compat_asset("{}") == nil, "finds the compat.json release asset")
	pending[1].cb(200, rel)
	ok(pending[2] and pending[2].url:find("/v0.6.9/compat.json$") and U.compat_state == "fetching", "downloads compat.json from the latest release")
	ok(CG.env().updater_busy, "warning waits while compat.json is downloading")
	pending[2].cb(200, remote)
	ok(U.compat_state == "done" and not CG.pending and SMODS.Mods.Multiplayer.config.compat_cache == remote, "newer release marks Balatro 1.0.2a tested: warning dropped, cached")
	-- offline / no asset -> main copy, failure silent
	pending = {}; U.state = "idle"; U.compat_state = nil
	U.check(); pending[1].cb(nil, nil); pending[2].cb(nil, nil)
	ok(pending[3] and pending[3].url == U.COMPAT_RAW_URL, "no release answer -> compat.json from main")
	pending[3].cb(404, nil)
	local last = pending[#pending]
	ok(last.url == U.COMPAT_RAW_URLS[2] and U.compat_state == "fetching", "compat.json: new repo name 404 -> old name")
	last.cb(404, nil)
	ok(U.compat_state == "failed", "download failure is silent")
	pending = {}; U.state = "idle"; U.compat_state = nil
	U.check(); pending[1].cb(200, rel); pending[2].cb(200, "<html>garbage")
	ok(U.compat_state == "failed", "garbage compat.json ignored")
	pending = {}; U.state = "idle"; U.compat_state = nil; MP.ENV.compat_check = false
	U.check(); pending[1].cb(200, rel)
	ok(#pending == 1 and U.compat_state == nil, ".env compat_check=false turns the download off")
	MP.ENV = {}
end
-- 0.6.8: clash with the official Balatro Multiplayer (legacy Multiplayer / 1.0 MultiplayerPvP + MultiplayerAPI)
do
	local own = { name = "Balatro High Stakes", path = "C:/x/Mods/BalatroMultiplayer3P/" }
	local mods = { Multiplayer = own, Lovely = { version = "0.10.0" },
		MultiplayerPvP = { name = "Multiplayer PvP", path = "C:/x/Mods/BalatroMultiplayerPvP/" },
		MultiplayerAPI = { name = "Multiplayer API", path = "C:\\x\\Mods\\MPAPI\\" },
		MultiplayerSPDRN = { name = "Speedrun", path = "C:/x/Mods/SPD/", can_load = false },
		SomeOtherMod = { name = "Other", path = "C:/x/Mods/Other/" } }
	local cl = CG.find_clashes(mods, own)
	ok(#cl == 2 and cl[1].id == "MultiplayerAPI" and cl[1].folder == "MPAPI" and cl[2].id == "MultiplayerPvP" and cl[2].folder == "BalatroMultiplayerPvP",
		"clash: MultiplayerAPI + MultiplayerPvP found (folder names only), our own mod, unrelated and not-loaded mods ignored")
	ok(#CG.find_clashes({ Multiplayer = own }, own) == 0 and #CG.find_clashes(nil, nil) == 0, "clash: nothing else installed -> no clash")
	mods.MultiplayerPvP.disabled = true
	ok(#CG.find_clashes(mods, own) == 1, "clash: a mod disabled in the Mods menu does not count")
	local r2 = CG.check(tested, compat, {}, cl)
	ok(r2.status == "untested" and r2.clash and CG.decide(r2, nil) == "warn" and r2.signature:find("clash=MultiplayerPvP", 1, true), "clash -> warning (not safe mode), remembered per combination")
	ok(CG.decide(r2, r2.signature) == "ok", "clash: Play anyway is remembered for the same mods")
	ok(CG.decide(CG.check(tested, compat, {}, {}), r2.signature) == "ok" and CG.check(tested, compat, {}).signature ~= r2.signature, "no clash -> no warning, different signature")
	for _, lang in ipairs({ "en", "nl" }) do
		local T = CG.TEXT[lang]
		ok(T.clash and T.clash_title and T.clash_body and T.clash_body2 and #T.clash_body <= 62 and #T.clash_body2 <= 62, lang .. ": clash texts exist and are short")
		local def = CG.definition({ result = r2, lang = lang, safe = false })
		local s = {}
		local function walk(n) if type(n) ~= "table" then return end if n.text then s[#s + 1] = n.text end for _, v in pairs(n) do walk(v) end end
		walk(def)
		local all = table.concat(s, "|")
		ok(all:find(T.clash_title, 1, true) and all:find(T.clash_body, 1, true) and all:find(T.clash, 1, true) and all:find("BalatroMultiplayerPvP", 1, true), lang .. ": clash pop-up shows the title, the text and the folder")
	end
	SMODS.Mods.MultiplayerPvP = { name = "Multiplayer PvP", path = "/m/BalatroMultiplayerPvP/" }
	logs = {}
	local live = CG.clashes()
	ok(#live == 1 and live[1].id == "MultiplayerPvP" and table.concat(logs, "\n"):find("another Multiplayer mod is loaded: MultiplayerPvP", 1, true), "CG.clashes() reads SMODS.Mods and logs a warning")
	SMODS.Mods.MultiplayerPvP = nil
end
print("all compat guard tests passed")
