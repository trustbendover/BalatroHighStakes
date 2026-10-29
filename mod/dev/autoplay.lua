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
		if s.button_present.select_blind then return "select_blind" end
	elseif s.state == "SELECTING_HAND" then
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

-- ---------------------------------------------------------------- game glue
local WANT = { "mp_return_to_lobby", "lobby_start_game", "lobby_ready_up", "skip_booster", "mp_toggle_ready", "select_blind",
	"play_cards_from_highlighted", "cash_out", "toggle_shop" }

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
	}
end

local function pick_and_highlight()
	local cards = {}
	for _, c in ipairs(G.hand.cards) do
		local r = c.base and (c.base.id or c.base.nominal) or 2
		cards[#cards + 1] = { rank = r, suit = c.base and c.base.suit or "?", ref = c }
	end
	for _, c in ipairs(A.pick_cards(cards)) do G.hand:add_to_highlighted(c, true) end
end

local function buy_cheap()
	A.shop_bought = true
	local area = G.shop_jokers
	if not (area and area.cards and G.jokers) then return end
	if #G.jokers.cards >= (G.jokers.config.card_limit or 5) then return end
	for _, c in ipairs(area.cards) do
		if c.cost and c.cost <= (G.GAME.dollars or 0) - 4 and c.ability and c.ability.set == "Joker" then
			G.FUNCS.buy_from_shop({ config = { ref_table = c, id = "buy" } })
			D_log("bought " .. tostring(c.ability.name) .. " for $" .. tostring(c.cost))
			return
		end
	end
end

function A.tick(D, dt, t)
	D.t = t
	D_log = D.log or D_log
	if t < A.next_at then return end
	A.next_at = t + A.gap
	-- the patch-notes pop-up / other overlays on the main menu would block the bot: close them
	if G.OVERLAY_MENU and G.STAGE == G.STAGES.MAIN_MENU and not (MP.LOBBY and MP.LOBBY.code) then G.FUNCS.exit_overlay_menu(); return end
	if G.STATE ~= G.STATES.SHOP then A.shop_bought = false end
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
		if D.on_action then pcall(D.on_action, act) end
		node:click()
	end
end

return A
