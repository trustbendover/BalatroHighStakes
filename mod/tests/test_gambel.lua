-- ESC must not leave Double or Nothing behind, and a closed modal must not reopen.
-- run from mod/: luajit tests/test_gambel.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end

MP = { LOBBY = { config = { gamemode = "gambel_time" } }, GAME = {} }
MP.load_mp_file = function(p) return dofile(p) end
G = {
	STATES = { SHOP = 1, MENU = 0 },
	STATE = 1,
	FUNCS = {},
	UIT = { ROOT = "ROOT", R = "R", C = "C", T = "T", O = "O" },
	C = {
		WHITE = { 1, 1, 1, 1 }, RED = { 1, 0, 0, 1 }, BLACK = { 0, 0, 0, 1 },
		GREY = { 0.4, 0.4, 0.4, 1 }, BLUE = { 0.2, 0.4, 1, 1 }, CLEAR = { 0, 0, 0, 0 },
		UI = { TEXT_LIGHT = { 1, 1, 1, 1 }, BACKGROUND_INACTIVE = { 0.2, 0.2, 0.2, 1 } },
	},
}
Game = { update = function() return "base" end }
local notices = {}
function attention_text(t) notices[#notices + 1] = t end

dofile("lib/gambel.lua")
local R = MP.GAMBEL
ok(R.active(), "the test lobby is Gambel Time")

local flashed = {}
local real_flash = R.flash
function R.flash(text)
	flashed[#flashed + 1] = text
	return real_flash(text)
end

local function piece()
	return { REMOVED = false, remove = function(self) self.REMOVED = true end }
end

R.double_view = {
	picked = "red", stake = 4, show_close = false, face = "back",
	area = piece(), card = piece(),
	flip = { done = false, line = "-$4", t = 0, flip_dur = 0.70, hold_dur = 0.55 },
}
G.OVERLAY_MENU = nil
local rebuilt = 0
G.FUNCS.overlay_menu = function() rebuilt = rebuilt + 1 end
local r = Game:update(0.016)
ok(r == "base", "the gambel update still runs the original update")
ok(flashed[1] == "-$4" and #flashed == 1, "ESC mid-flip announces the stake once")
ok(R.double_view == nil, "ESC mid-flip clears the double view")
R.tick(2)
ok(rebuilt == 0 and R.double_view == nil, "the flip cannot pop the closed modal back open")

R.double_view = {
	picked = "black", stake = 8, show_close = true, result = "+$8", outcome = "win", face = "front",
	area = piece(), card = piece(),
}
G.OVERLAY_MENU = nil
flashed = {}
Game:update(0.016)
ok(#flashed == 0, "ESC on the result screen does not announce again")
ok(R.double_view == nil, "ESC on the result screen clears the double view")
R.can_double = function() return true end
R.double_definition = function() return { n = "ROOT" } end
G.FUNCS.overlay_menu = function()
	rebuilt = rebuilt + 1
	G.OVERLAY_MENU = { id = "double" }
end
R.open_double()
ok(rebuilt == 1 and R.double_view and R.double_view.picked == false, "Double or Nothing can open again after ESC")

G.OVERLAY_MENU = nil
rebuilt = 0
G.FUNCS.overlay_menu = function() rebuilt = rebuilt + 1 end
R.reshow_double()
ok(rebuilt == 0, "reshow_double stays closed when the overlay is already gone")
G.OVERLAY_MENU = { id = "double" }
R.reshow_double()
ok(rebuilt == 1, "reshow_double still rebuilds while the overlay is open")

local removed = false
R.double_view = { area = { remove = function() removed = true end }, card = { REMOVED = true } }
R.reset()
ok(removed and R.double_view == nil, "reset drops the Ace before forgetting the view")

notices = {}
R.double_view = nil
R.wheel_view = nil
G.OVERLAY_MENU = nil
R.show_notice("Double Interest and a longer twist name")
ok(notices[1] and notices[1].maxw == 10 and notices[1].scale == 0.65, "a gambel notice stays within a readable width")

print("PASS: gambel esc")
