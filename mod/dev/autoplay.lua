-- Balatro High Stakes - DEV ONLY. GPL-3.0. Simple bot player for unattended local test matches.
-- It presses the same buttons a player would (UIElement:click on the live UI), so the real game and
-- multiplayer paths run: Ready in the lobby, host Start, blind select / PvP Ready, play a hand, cash out,
-- buy one cheap joker, next round, skip packs, return to lobby after the match.
local A = { next_at = 0, gap = 0.8, shop_bought = false, menu_t = 0 }
local D_log = function() end
A.END_SCREEN_WAIT = 8 -- seconds the match-end stats stay up before the bot returns to the lobby

-- ---------------------------------------------------------------- pure helpers (tested)
--- cards = { { rank = 2..14, suit = "H", ref = any } }; returns up to 5 refs: flush > biggest same-rank group(s) > high cards
function A.pick_cards(cards)
	local by_suit, by_rank = {}, {}
	for _, c in ipairs(cards) do
		by_suit[c.suit] = by_suit[c.suit] or {}; table.insert(by_suit[c.suit], c)
		by_rank[c.rank] = by_rank[c.rank] or {}; table.insert(by_rank[c.rank], c)
	end
	local function hi(a, b) return a.rank > b.rank end
	for _, list in pairs(by_suit) do
		if #list >= 5 then table.sort(list, hi); local o = {} for i = 1, 5 do o[i] = list[i].ref end return o end
	end
	local groups = {}
	for r, list in pairs(by_rank) do if #list >= 2 then groups[#groups + 1] = { r = r, list = list } end end
	table.sort(groups, function(a, b) if #a.list ~= #b.list then return #a.list > #b.list end return a.r > b.r end)
	local out = {}
	for _, g in ipairs(groups) do
		for _, c in ipairs(g.list) do if #out < 5 then out[#out + 1] = c.ref end end
		if #out >= 4 then break end
	end
	if #out == 0 then
		local s = {} for i, c in ipairs(cards) do s[i] = c end
		table.sort(s, hi)
		for i = 1, math.min(5, #s) do out[i] = s[i].ref end
	end
	return out
end

--- which button to press for a game snapshot (nil = wait). Order matters: the first match wins.
function A.decide(s)
	if s.locked then return nil end
	if s.button_present.mp_return_to_lobby then return "mp_return_to_lobby" end
	if s.stage == "menu" then return nil end -- lobby creation/joining is the scenario's job
	if s.stage == "lobby" then
		if s.is_host then
			if s.can_start and s.players >= s.want_players and s.button_present.lobby_start_game then return "lobby_start_game" end
			return nil
		end
		if not s.lobby_ready and s.ready_allowed and s.button_present.lobby_ready_up then return "lobby_ready_up" end
		return nil
	end
	if s.button_present.skip_booster then return "skip_booster" end
	if s.state == "BLIND_SELECT" then
		if s.button_present.mp_toggle_ready and not s.blind_ready then return "mp_toggle_ready" end
		if s.skip_wanted and s.button_present.skip_blind and not s.button_present.mp_toggle_ready then return "skip_blind" end
		if s.button_present.select_blind then return "select_blind" end
	elseif s.state == "SELECTING_HAND" then
		if s.highlighted > 0 and s.intent == "discard" and s.button_present.discard_cards_from_highlighted then return "discard_cards_from_highlighted" end
		if s.highlighted > 0 and s.button_present.play_cards_from_highlighted then return "play_cards_from_highlighted" end
		if s.highlighted == 0 and s.hand_size > 0 then return "@pick" end
	elseif s.state == "ROUND_EVAL" then
		if s.button_present.cash_out then return "cash_out" end
	elseif s.state == "SHOP" then
		if not s.shop_bought then return "@buy" end
		if s.button_present.toggle_shop then return "toggle_shop" end
	end
	return nil
end


-- ---------------------------------------------------------------- per-bot personas (DEV ONLY, tested)
-- Every bot plays differently so PvP rounds have real winners/losers. Persona and decision seed come from
-- HS_DEV_PERSONA / HS_DEV_SEED, else from the instance name (dev1 aggressive, dev2 conservative, ...).
A.PERSONAS = { "aggressive", "conservative", "shopper", "saver", "random" }
A.PROFILE = {
	aggressive   = { discard = 0.0, skip = 0.0, buy_max = 1, keep = 0,  reroll = 0, best = 1.0 },
	conservative = { discard = 1.0, skip = 0.0, buy_max = 1, keep = 8,  reroll = 0, best = 0.6 },
	shopper      = { discard = 0.3, skip = 0.1, buy_max = 5, keep = 0,  reroll = 1, best = 0.9 },
	saver        = { discard = 0.5, skip = 0.6, buy_max = 0, keep = 25, reroll = 0, best = 0.8 },
	random       = { discard = 0.5, skip = 0.3, buy_max = 2, keep = 2,  reroll = 0, best = 0.0 },
}
function A.hash(str) local h = 5381 for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end return h end
--- own LCG (never touches the game's pseudorandom or math.random state)
function A.rng(seed)
	local x = (tonumber(seed) or 1) % 2147483647; if x <= 0 then x = x + 2147483646 end
	return function() x = (x * 16807) % 2147483647; return x / 2147483647 end
end
function A.persona_for(name, override)
	if override and A.PROFILE[override] then return override end
	local n = tonumber(tostring(name):match("(%d+)$") or "") or (A.hash(tostring(name)) % 5 + 1)
	return A.PERSONAS[(n - 1) % #A.PERSONAS + 1]
end
function A.setup_persona(name, override, seed)
	A.persona = A.persona_for(name, override)
	A.prof = A.PROFILE[A.persona]
	A.seed = tonumber(seed) or A.hash(tostring(name) .. ":" .. A.persona)
	A.rand = A.rng(A.seed)
	return A.persona
end
A.setup_persona("dev1")

--- weak hand = best pick is only high cards (no pair / flush)
local function weak(cards, picked)
	local ranks = {}
	for _, c in ipairs(cards) do ranks[c.rank] = (ranks[c.rank] or 0) + 1 end
	for _, r in pairs(ranks) do if r >= 2 then return false end end
	local suits = {}
	for _, c in ipairs(cards) do suits[c.suit] = (suits[c.suit] or 0) + 1; if suits[c.suit] >= 5 then return false end end
	return true
end
--- -> "play"|"discard", refs. Pure given the rng.
function A.choose(persona, cards, discards_left, rand)
	local P = A.PROFILE[persona] or A.PROFILE.aggressive
	rand = rand or A.rand
	local best = A.pick_cards(cards)
	if (discards_left or 0) > 0 and weak(cards) and rand() < P.discard then
		local s = {} for i, c in ipairs(cards) do s[i] = c end
		table.sort(s, function(a, b) return a.rank < b.rank end)
		local o, n = {}, math.min(5, #s - 1, persona == "conservative" and 5 or 3)
		for i = 1, n do o[i] = s[i].ref end
		if #o > 0 then return "discard", o end
	end
	if rand() < P.best then return "play", best end
	-- off-plan play: a random 1..5 cards (random persona always, others sometimes)
	local s = {} for i, c in ipairs(cards) do s[i] = c end
	for i = #s, 2, -1 do local j = math.floor(rand() * i) + 1; s[i], s[j] = s[j], s[i] end
	local o = {} for i = 1, math.min(#s, math.floor(rand() * 5) + 1) do o[i] = s[i].ref end
	return "play", o
end
--- items = { { cost, set, ref } }; -> list of refs to buy, in order
function A.shop_plan(persona, items, dollars, free_slots, rand)
	local P = A.PROFILE[persona] or A.PROFILE.aggressive
	rand = rand or A.rand
	local js = {}
	for _, it in ipairs(items) do if it.set == "Joker" then js[#js + 1] = it end end
	if persona == "aggressive" then table.sort(js, function(a, b) return a.cost > b.cost end)
	elseif persona == "random" then for i = #js, 2, -1 do local j = math.floor(rand() * i) + 1; js[i], js[j] = js[j], js[i] end
	else table.sort(js, function(a, b) return a.cost < b.cost end) end
	local out, money = {}, dollars or 0
	for _, it in ipairs(js) do
		if #out >= math.min(P.buy_max, free_slots or 0) then break end
		if it.cost <= money - P.keep and (persona ~= "random" or rand() < 0.6) then out[#out + 1] = it.ref; money = money - it.cost end
	end
	return out
end
function A.should_skip(persona, on_deck, is_pvp, rand)
	if is_pvp or on_deck == "Boss" then return false end
	return (rand or A.rand)() < (A.PROFILE[persona] or A.PROFILE.aggressive).skip
end

-- ---------------------------------------------------------------- game glue
local WANT = { "mp_return_to_lobby", "lobby_start_game", "lobby_ready_up", "skip_booster", "mp_toggle_ready", "select_blind",
	"play_cards_from_highlighted", "cash_out", "toggle_shop", "skip_blind", "discard_cards_from_highlighted" }

local function walk(node, found)
	if type(node) ~= "table" then return end
	local b = node.config and node.config.button
	if b and not found[b] and node.states and node.states.visible ~= false and not node.disable_button and not node.under_overlay then found[b] = node end
	for _, c in ipairs(node.children or {}) do walk(c, found) end
end
function A.buttons()
	local found = {}
	for _, box in ipairs(G.I and G.I.UIBOX or {}) do if box.UIRoot then walk(box.UIRoot, found) end end
	return found
end

local function state_name()
	for k, v in pairs(G.STATES or {}) do if v == G.STATE then return k end end
end

function A.snapshot(D, found)
	local present = {}
	for _, k in ipairs(WANT) do present[k] = found[k] ~= nil end
	local in_lobby = MP.LOBBY and MP.LOBBY.code and G.STAGE == G.STAGES.MAIN_MENU
	return {
		locked = G.CONTROLLER and G.CONTROLLER.locked or false,
		button_present = present,
		stage = in_lobby and "lobby" or (G.STAGE == G.STAGES.MAIN_MENU and "menu" or "run"),
		is_host = MP.LOBBY and MP.LOBBY.is_host,
		can_start = MP.LOBBY and MP.LOBBY.ready_to_start,
		players = MP.LOBBY and MP.LOBBY.player_list and #MP.LOBBY.player_list or 0,
		want_players = D.players,
		lobby_ready = MP.LOBBY and MP.LOBBY.ready_to_start,
		ready_allowed = (D.ready_after or 0) <= (D.t or 0),
		state = state_name(),
		blind_ready = MP.GAME and MP.GAME.ready_blind,
		highlighted = G.hand and G.hand.highlighted and #G.hand.highlighted or 0,
		hand_size = G.hand and G.hand.cards and #G.hand.cards or 0,
		shop_bought = A.shop_bought,
		intent = A.intent,
		skip_wanted = A.skip_wanted,
	}
end

local function pick_and_highlight()
	local cards = {}
	for _, c in ipairs(G.hand.cards) do
		local r = c.base and (c.base.id or c.base.nominal) or 2
		cards[#cards + 1] = { rank = r, suit = c.base and c.base.suit or "?", ref = c }
	end
	local dl = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
	local act, refs = A.choose(A.persona, cards, dl, A.rand)
	A.intent = act
	D_log("autoplay[" .. A.persona .. "]: " .. act .. " " .. #refs .. " card(s)")
	for _, c in ipairs(refs) do G.hand:add_to_highlighted(c, true) end
end

local function buy_cheap()
	A.shop_bought = true
	local area = G.shop_jokers
	if not (area and area.cards and G.jokers) then return end
	local free = (G.jokers.config.card_limit or 5) - #G.jokers.cards
	local items = {}
	for _, c in ipairs(area.cards) do items[#items + 1] = { cost = c.cost or 99, set = c.ability and c.ability.set, ref = c } end
	local plan = A.shop_plan(A.persona, items, G.GAME.dollars or 0, free, A.rand)
	for _, c in ipairs(plan) do
		G.FUNCS.buy_from_shop({ config = { ref_table = c, id = "buy" } })
		D_log("autoplay[" .. A.persona .. "]: bought " .. tostring(c.ability.name) .. " for $" .. tostring(c.cost))
	end
	if #plan == 0 then D_log("autoplay[" .. A.persona .. "]: shop, no buy ($" .. tostring(G.GAME.dollars) .. ")") end
	if A.prof.reroll > 0 and (G.GAME.dollars or 0) >= 10 and G.FUNCS.reroll_shop then
		pcall(G.FUNCS.reroll_shop, {}); D_log("autoplay[" .. A.persona .. "]: reroll")
	end
end

A.STATS_SHOT_DELAY = 2.5 -- after the match-stats overlay opens (let it animate in)
A.LOBBY_AFTER = 20       -- seconds after the match end before the bot goes back to the lobby
--- pure: what to do once this player's run is over. -> "play" | "idle" | "shot" | "lobby"
function A.over_decide(s)
	if not s.over then return "play" end
	if s.stats_open and not s.stats_shot and s.stats_open_for >= A.STATS_SHOT_DELAY then return "shot" end
	if s.match_done and s.over_for >= A.LOBBY_AFTER and not s.went_lobby then return "lobby" end
	return "idle"
end
function A.match_over_tick(D, t)
	local MS = MP.MATCH_STATS
	local in_run = G.STAGE == G.STAGES.RUN and MP.LOBBY and MP.LOBBY.code
	local over = in_run and MP.GAME and (MP.GAME.won or G.STATE == G.STATES.GAME_OVER or (MP.GAME.lives or 1) <= 0) or false
	if not over then A.over_t, A.stats_t, A.stats_shot, A.went_lobby = nil, nil, nil, nil; return false end
	A.over_t = A.over_t or t
	local stats_open = MS and MS.last and G.OVERLAY_MENU and not MS.show_at and true or false
	if stats_open then A.stats_t = A.stats_t or t else A.stats_t = nil end
	local act = A.over_decide({ over = true, stats_open = stats_open, stats_open_for = A.stats_t and (t - A.stats_t) or 0,
		stats_shot = A.stats_shot, match_done = (MP.GAME.won or (MS and MS.last)) and true or false,
		over_for = t - A.over_t, went_lobby = A.went_lobby })
	if act == "shot" then A.stats_shot = true; if D.shot then D.shot("match_stats") end
	elseif act == "lobby" then
		A.went_lobby = true; D.log("autoplay: match over -> back to lobby")
		if G.FUNCS.mp_return_to_lobby then pcall(G.FUNCS.mp_return_to_lobby) end
	elseif not A.idle_logged then A.idle_logged = true; D.log("autoplay: run over, bot idle (no more plays)") end
	return true
end

function A.tick(D, dt, t)
	D.t = t
	D_log = D.log or D_log
	if t < A.next_at then return end
	A.next_at = t + A.gap
	-- the patch-notes pop-up / other overlays on the main menu would block the bot: close them
	if G.OVERLAY_MENU and G.STAGE == G.STAGES.MAIN_MENU and not (MP.LOBBY and MP.LOBBY.code) then G.FUNCS.exit_overlay_menu(); return end
	if not A.persona_ready then A.persona_ready = true; A.setup_persona(D.name, D.persona, D.seed); D.log("autoplay: persona " .. A.persona .. " seed " .. A.seed) end
	if G.STATE ~= G.STATES.SHOP then A.shop_bought = false end
	if G.STATE ~= G.STATES.SELECTING_HAND then A.intent = nil end
	if G.STATE == G.STATES.BLIND_SELECT then
		local od = G.GAME and G.GAME.blind_on_deck
		if A.skip_for ~= od then
			A.skip_for = od
			local pvp = MP.is_pvp_boss and od == "Boss" and MP.is_pvp_boss() or false
			A.skip_wanted = A.should_skip(A.persona, od, pvp, A.rand)
		end
	else A.skip_for = nil; A.skip_wanted = false end
	if A.match_over_tick(D, t) then return end
	-- info pop-ups during the run ("X joined the running game!"): a player reads and closes them
	if G.OVERLAY_MENU and G.STAGE == G.STAGES.RUN then
		A.ov_t = A.ov_t or t
		if t - A.ov_t > 3 then A.ov_t = nil; D.log("autoplay: closing info pop-up"); G.FUNCS.exit_overlay_menu() end
		return
	end
	A.ov_t = nil
	local found = A.buttons()
	local act = A.decide(A.snapshot(D, found))
	if not act then return end
	if act == "@pick" then pick_and_highlight(); return end
	if act == "@buy" then pcall(buy_cheap); return end
	if act == "mp_return_to_lobby" then
		A.end_seen = A.end_seen or t
		if t - A.end_seen < A.END_SCREEN_WAIT then return end
		A.end_seen = nil
	end
	local node = found[act]
	if node then
		D.log("autoplay: " .. act)
		if act == "cash_out" then D.log("autoplay[" .. A.persona .. "]: round chips " .. tostring(G.GAME.chips) .. " $" .. tostring(G.GAME.dollars) .. " ante " .. tostring(G.GAME.round_resets.ante)) end
		if act == "discard_cards_from_highlighted" or act == "play_cards_from_highlighted" then A.intent = nil end
		if D.on_action then pcall(D.on_action, act) end
		node:click()
	end
end

return A
