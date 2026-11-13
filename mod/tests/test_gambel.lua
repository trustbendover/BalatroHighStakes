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
G.GAME = { dollars = 10 }
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

-- High Contrast must not turn diamonds orange or clubs blue on this Ace.
G.SETTINGS = { colourblind_option = true }
G.ASSET_ATLAS = { cards_1 = { id = "cards_1" }, cards_2 = { id = "cards_2" } }
G.P_CARDS = {
	H_A = { pos = { x = 12, y = 0 } },
	D_A = { pos = { x = 12, y = 1 } },
	C_A = { pos = { x = 12, y = 3 } },
}
G.P_CENTERS = { c_base = {} }
G.CARD_W, G.CARD_H = 1.2, 1.6
local built_flag
function CardArea()
	return { emplace = function() end, REMOVED = false, remove = function(self) self.REMOVED = true end, states = { hover = {} } }
end
local function ace_card()
	built_flag = G.SETTINGS.colourblind_option
	local atlas = G.SETTINGS.colourblind_option and G.ASSET_ATLAS.cards_2 or G.ASSET_ATLAS.cards_1
	return {
		REMOVED = false, facing = "front", sprite_facing = "front", pinch = { x = false },
		states = { hover = {}, click = {}, drag = {}, visible = true },
		T = { w = 1, h = 1 },
		children = {
			front = { atlas = atlas, set_sprite_pos = function(self, p) self.pos = p end },
			back = { VT = {} },
		},
		set_base = function(self, def)
			self.base_flag = G.SETTINGS.colourblind_option
			self.children.front.atlas = G.SETTINGS.colourblind_option and G.ASSET_ATLAS.cards_2 or G.ASSET_ATLAS.cards_1
		end,
		set_sprites = function(self, _, def)
			self.sprite_flag = G.SETTINGS.colourblind_option
			self.children.front.atlas = G.ASSET_ATLAS.cards_2
			if def and def.pos then self.children.front:set_sprite_pos(def.pos) end
		end,
	}
end
function Card() return ace_card() end
local face = { face = "back" }
local card = R.make_double_card(face)
ok(card and built_flag == false, "the Ace is created while high contrast is off")
ok(G.SETTINGS.colourblind_option == true, "high contrast is restored after the Ace is created")
ok(card.children.front.atlas == G.ASSET_ATLAS.cards_1 and card.children.front.pos.y == 0, "creation forces the classic cards_1 atlas")
R.double_view = face
face.flip = { t = 0, flip_dur = 0.1, hold_dur = 10, swapped = false, suit = "D", key = "D_A", line = "", outcome = "win", done = false }
R.tick_double(0.06)
ok(card.base_flag == false and card.sprite_flag == false, "the flip uses classic suits for set_base and set_sprites")
ok(card.children.front.atlas == G.ASSET_ATLAS.cards_1 and card.children.front.pos.y == 1, "a diamond Ace stays on cards_1")
ok(G.SETTINGS.colourblind_option == true, "high contrast is restored after the flip")
card.set_base = function() error("boom") end
face.flip = { t = 0.04, flip_dur = 0.1, hold_dur = 10, swapped = false, suit = "D", key = "D_A", line = "", done = false }
R.tick_double(0.02)
ok(G.SETTINGS.colourblind_option == true, "high contrast is restored when set_base errors")
card.set_base = function(self, def)
	self.base_flag = G.SETTINGS.colourblind_option
	self.children.front.atlas = G.SETTINGS.colourblind_option and G.ASSET_ATLAS.cards_2 or G.ASSET_ATLAS.cards_1
end
face.face = "front"
face.suit_mark = "C"
face.flip = nil
card.children.front.atlas = G.ASSET_ATLAS.cards_2
R.hold_ace(face)
ok(card.children.front.atlas == G.ASSET_ATLAS.cards_1 and card.children.front.pos.y == 3, "holding the Ace forces clubs onto cards_1")
ok(G.SETTINGS.colourblind_option == true, "high contrast is restored after the Ace is held")

-- Shop buttons follow cash, the same way Reroll does.
G.C.ORANGE = { 1, 0.5, 0, 1 }
G.C.PURPLE = { 0.5, 0, 0.8, 1 }
G.C.BLACK = { 0, 0, 0, 1 }
G.C.GOLD = { 1, 0.8, 0, 1 }
G.GAME = { dollars = 10, round_resets = { ante = 1 } }
MP.GAME.gambel_bet_sent = false
G.GAME.mp_gambel_shop_used = nil
R.double_view = nil
R.wheel_view = nil
local function paint()
	return { config = {} }
end
local double_btn, wheel_btn = paint(), paint()
G.FUNCS.mp_gambel_double_btn(double_btn)
G.FUNCS.mp_gambel_wheel_btn(wheel_btn)
ok(double_btn.config.button == "mp_gambel_double" and double_btn.config.colour == G.C.ORANGE, "$10 keeps Double or Nothing orange and clickable")
ok(wheel_btn.config.button == "mp_gambel_wheel" and wheel_btn.config.colour == G.C.PURPLE, "$10 keeps the wheel purple and clickable")
G.GAME.dollars = 0
G.FUNCS.mp_gambel_double_btn(double_btn)
G.FUNCS.mp_gambel_wheel_btn(wheel_btn)
ok(double_btn.config.button == nil and double_btn.config.colour == G.C.UI.BACKGROUND_INACTIVE, "$0 greys Double or Nothing")
ok(wheel_btn.config.button == "mp_gambel_wheel", "the wheel stays clickable when cash is $0")
G.GAME.dollars = 1
G.FUNCS.mp_gambel_double_btn(double_btn)
ok(double_btn.config.button == nil, "$1 still cannot double")
G.GAME.dollars = 2
G.FUNCS.mp_gambel_double_btn(double_btn)
ok(double_btn.config.button == "mp_gambel_double" and double_btn.config.colour == G.C.ORANGE, "$2 turns Double or Nothing back on")
G.GAME.dollars = 10
G.GAME.mp_gambel_shop_used = true
G.FUNCS.mp_gambel_double_btn(double_btn)
G.FUNCS.mp_gambel_wheel_btn(wheel_btn)
ok(double_btn.config.button == nil and wheel_btn.config.button == nil, "a used shop bet disables both buttons")
G.GAME.mp_gambel_shop_used = nil
notices = {}
G.GAME.dollars = 1
R.open_double()
ok(R.double_view == nil and notices[#notices] and notices[#notices].text == "Need at least $2", "opening below $2 says so")
local quiet = #notices
G.GAME.dollars = 10
G.GAME.mp_gambel_shop_used = true
R.open_double()
ok(R.double_view == nil and #notices == quiet, "an already used bet does not toast")
G.GAME.mp_gambel_shop_used = nil
R.double_view = { area = piece(), card = piece() }
R.wheel_view = { spinning = false }
G.OVERLAY_MENU = nil
R.on_shop()
ok(R.double_view == nil and R.wheel_view == nil, "entering the shop drops a leftover double or wheel")
UIBox_button = function(args) return { config = args } end
local wired = {}
local function walk(node)
	if type(node) ~= "table" then return end
	if node.config and node.config.func then wired[#wired + 1] = node.config.func end
	if node.nodes then for _, child in ipairs(node.nodes) do walk(child) end end
end
walk(R.shop_row())
ok(wired[1] == "mp_gambel_double_btn" and wired[2] == "mp_gambel_wheel_btn", "the shop row refreshes both buttons every frame")

print("PASS: gambel esc")
