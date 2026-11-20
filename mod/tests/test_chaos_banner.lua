-- Chaos Spin and Boss Chaos say their name and what they do.
-- luajit tests/test_chaos_banner.lua from mod/
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { LOBBY = { config = { gamemode = "gambel_time" } }, GAME = {} }
MP.CHAT = { notes = {} }
function MP.CHAT.note(text) MP.CHAT.notes[#MP.CHAT.notes + 1] = text end
MP.load_mp_file = function(p) return dofile(p) end
G = {
	STATES = { SHOP = 1, MENU = 0 }, STATE = 1, FUNCS = {},
	UIT = { ROOT = 0, R = 1, C = 2, T = 3 },
	C = { WHITE = {}, RED = {}, BLACK = {}, GREY = {}, BLUE = {}, CLEAR = {}, GOLD = {},
		UI = { TEXT_LIGHT = {}, BACKGROUND_INACTIVE = {} } },
}
Game = { update = function() return "base" end }
function attention_text() end
dofile("lib/gambel.lua")
local R = MP.GAMBEL
local name, desc = R.effect_line("twist", "reverse")
ok(name:find("Reverse", 1, true) and desc:find("Lowest", 1, true), "Reverse Stakes names itself and says the lowest score wins")
local spin, sdesc = R.effect_line("spin", "wild_odds")
ok(spin:find("Wild", 1, true) and sdesc:find("doubled", 1, true), "Wild Odds says the chances are doubled")
local line = R.announce("twist", "double")
ok(type(line) == "string" and line:find("Double", 1, true) and line:find("2 lives", 1, true), "the banner is the name and the one-line effect")
ok(MP.CHAT.notes[1] == line, "the same line is written to chat")
ok(R.announce("spin", "nope") == nil or R.effect_line("spin", "nope") ~= nil, "an unknown id does not invent a second banner")
print("PASS: chaos banner")
