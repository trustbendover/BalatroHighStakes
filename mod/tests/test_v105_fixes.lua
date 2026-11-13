-- Steamodded 26.829 seal patch plus the v1.0.5 fixes that apply to this fork.
-- run from mod/: luajit tests/test_v105_fixes.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { UTILS = {}, LOBBY = { code = "ABCDE" } }
dofile("lib/smods_compat.lua")

ok(MP.UTILS.shop_spend(12) == 12 and MP.UTILS.shop_spend("40") == 40, "a normal shop spend is kept")
ok(MP.UTILS.shop_spend("nan") == 0 and MP.UTILS.shop_spend(-5) == 0 and MP.UTILS.shop_spend(math.huge) == 0, "a bad shop spend counts as 0")
ok(MP.UTILS.shop_spend(5e9) == MP.UTILS.SHOP_SPEND_CAP, "a huge finite spend is the cap, not 0")
ok(MP.UTILS.live_skip_count(2, 3) == 1, "one new skip still counts")
ok(MP.UTILS.live_skip_count(0, 4) == 0, "a rejoin's lifetime skip total is not four new skips")

local seen
local wrapped = MP.UTILS.wrap_probability_vars(function(_, n, d, _, _, no_mod)
	seen = no_mod
	return n, d
end)
seen = nil
wrapped({ ability = {}, edition = { type = "mp_phantom" } }, 1, 6, "phantom", false, nil)
ok(seen == true, "a phantom roll ignores this player's Oops! All 6s")
seen = nil
wrapped({ ability = {} }, 1, 6, "mine", false, nil)
ok(seen == nil, "our own joker still uses our probability modifiers")
MP.end_game_jokers = {}
seen = nil
wrapped({ ability = {}, area = MP.end_game_jokers }, 1, 4, "end", false, nil)
ok(seen == true, "the opponent's end-screen jokers ignore our odds")

ok(not MP.UTILS.duplicate_play(nil, "10", 3), "the first Play is sent")
ok(MP.UTILS.duplicate_play({ score = "10", hands = 3 }, "10", 3), "the same Play twice is not sent")
ok(not MP.UTILS.duplicate_play({ score = "10", hands = 3 }, "10", 2), "the next hand is sent")

-- Nemesis view deck must not touch our deck.
G = {
	FUNCS = {},
	CARD_W = 1, CARD_H = 1,
	P_CARDS = { S_A = { name = "S_A" }, H_K = { name = "H_K" } },
	P_CENTERS = { c_base = { name = "c_base" }, m_glass = { name = "m_glass" } },
	P_SEALS = { Red = {} },
}
function sendDebugMessage() end
function Card(x, y, w, h, front, center)
	return { front = front, center = center, x = x, y = y,
		set_edition = function(self, edition) self.edition = edition end,
		set_seal = function(self, seal) self.seal = seal end }
end
local function make_area(cards)
	return { cards = cards, T = { x = 0, y = 0 }, emplace = function(self, card)
		if not self.cards then error("removed area") end
		self.cards[#self.cards + 1] = card
	end }
end
local function load_fn()
	local text = assert(io.open("networking/action_handlers.lua")):read("*a")
	local start = assert(text:find("function G.FUNCS.load_nemesis_deck()", 1, true))
	local finish = assert(text:find("local function action_receive_nemesis_deck", start, true))
	assert((loadstring or load)(text:sub(start, finish - 1)))()
end
dofile("lib/string_utils.lua")
load_fn()
local function own(n)
	local t = {}
	for i = 1, n do t[i] = { own = i } end
	return t
end
G.playing_cards = own(52)
MP.nemesis_deck = make_area(nil)
MP.nemesis_cards = {}
MP.nemesis_deck_string = ";S-A-m_glass-foil-Red"
ok(pcall(G.FUNCS.load_nemesis_deck) and #G.playing_cards == 52, "a removed nemesis area does not add cards to our deck")
G.playing_cards = own(52)
G.playing_card = 52
MP.nemesis_deck = make_area({})
MP.nemesis_cards = {}
MP.nemesis_deck_string = ";S-A-m_glass-none-Red;H-K-none-none-none"
G.FUNCS.load_nemesis_deck()
ok(#MP.nemesis_cards == 2 and #MP.nemesis_deck.cards == 2, "both nemesis cards load into their area")
ok(#G.playing_cards == 52 and G.playing_cards[52].own == 52 and G.playing_card == 52, "our deck and its counter stay untouched")
ok(MP.nemesis_cards[1].front == G.P_CARDS.S_A and MP.nemesis_cards[1].seal == "Red", "enhancement and seal stay on the nemesis card")

local Core = dofile("networking/p2p_server.lua")
local _, live = Core.restore({
	v = 1, code = "ABCDE", gameMode = "attrition", isInGame = true, lastStats = { winnerId = "old" }, winnerId = "old",
	players = { { id = "a", username = "Ann", reconnectToken = "t" } },
}, { oldHostId = "a", newHostId = "b" })
ok(live.lastStats == nil and live.winnerId == nil, "taking over a live match drops the previous match result")
local _, done = Core.restore({
	v = 1, code = "ABCDE", gameMode = "attrition", isInGame = false, lastStats = { winnerId = "old" }, winnerId = "old",
	players = { { id = "a", username = "Ann", reconnectToken = "t" } },
}, { oldHostId = "a", newHostId = "b" })
ok(done.lastStats and done.lastStats.winnerId == "old", "a finished lobby still keeps its own result")

local order = io.open("lovely/TheOrder.toml"):read("*a")
ok(order:find("26.829", 1, true) and order:find("seal_poll > 1", 1, true) and order:find("guaranteed or pseudorandom", 1, true),
	"the seal patch matches 1620a and the already-fixed 26.829 form")
local dollars = io.open("overrides/game.lua"):read("*a")
ok(dollars:find("function ease_dollars(mod, ...)", 1, true) and dollars:find("ease_dollars_ref(mod, ...)", 1, true),
	"ease_dollars forwards every argument after the amount")
local modes = io.open("gamemodes/attrition.lua"):read("*a")
ok(modes:find('"tag_boss"', 1, true), "the Boss Tag that rerolls the blind stays banned")

print("PASS: v1.0.5 fixes")
