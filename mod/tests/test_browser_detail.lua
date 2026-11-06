-- Host match facts on a public lobby card. Missing or junk data stays unknown, never "off".
-- run from mod/: luajit tests/test_browser_detail.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local Browser = dofile("networking/lobby_browser.lua")
local opt = { public = true, version = "0.6.9.1", max_players = function() return 8 end, max_spectators = 8 }
local function pub(options, mode)
	return Browser.publish({
		gameMode = mode or "attrition", isInGame = false,
		players = { { username = "Ann" } }, options = options,
	}, opt)
end
local on = pub({ normal_bosses = true, starting_lives = 6, pvp_start_round = 3, timer = false, teams_format = 2 }, "teams")
ok(on.mp3p_boss == "1" and on.mp3p_lives == "6" and on.mp3p_pvp == "3" and on.mp3p_timer == "0" and on.mp3p_fmt == "2", "explicit host settings are published")
ok(on.mp3p_show == "", "showdown ante is not invented for another mode")
local off = pub({ normal_bosses = false, timer = true })
ok(off.mp3p_boss == "0" and off.mp3p_timer == "1", "explicit off is off")
local bare = pub({})
ok(bare.mp3p_boss == "" and bare.mp3p_lives == "" and bare.mp3p_timer == "" and bare.mp3p_pvp == "", "a host that sent no value publishes nothing, not off")
local show = pub({ showdown_starting_antes = 4, normal_bosses = false }, "showdown")
ok(show.mp3p_show == "4", "showdown publishes its ante")

local function base(extra)
	local d = {
		mp3p_discover = "1", mp3p_mod = "hs", mp3p_version = "0.6.9.1", mp3p_name = "Ann",
		mp3p_mode = "teams", mp3p_fmt = "2", mp3p_players = "4", mp3p_max = "8",
		mp3p_state = "wait", mp3p_watch = "0", mp3p_code = "ABCDE",
	}
	for k, v in pairs(extra or {}) do d[k] = v end
	return d
end
local known = Browser.accept(base({ mp3p_boss = "1", mp3p_lives = "4", mp3p_pvp = "2", mp3p_timer = "0" }), { version = "0.6.9.1" })
ok(known and known.boss == true and known.lives == 4 and known.pvp_at == 2 and known.timer == false and known.fmt == "2", "a current public lobby keeps teams and host settings")
ok(known.code == nil, "the card still has no lobby code")
local old = Browser.accept(base(), { version = "0.6.9.1" })
ok(old and old.boss == nil and old.lives == nil and old.timer == nil, "an older lobby is unknown, not boss-effects off")
local junk = Browser.accept(base({ mp3p_boss = "yes", mp3p_lives = "lots", mp3p_pvp = "9.5", mp3p_timer = "maybe" }), { version = "0.6.9.1" })
ok(junk and junk.boss == nil and junk.lives == nil and junk.pvp_at == nil and junk.timer == nil, "malformed settings stay unknown")
ok(Browser.accept(base({ mp3p_discover = "0", mp3p_boss = "1" }), { version = "0.6.9.1" }) == nil, "private is still excluded even with settings attached")
local play = Browser.accept(base({ mp3p_state = "play", mp3p_watch = "1", mp3p_boss = "0" }), { version = "0.6.9.1" })
ok(play and Browser.action(play) == "watch" and play.boss == false, "Watch still requires a running match, and explicit off stays off")
ok(Browser.action(known) == "join", "Join still requires a waiting lobby with room")
print("PASS: browser detail")
