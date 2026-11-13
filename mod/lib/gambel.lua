-- Gambel Time on the client: show the host's spin, apply the local half of a bet,
-- and play the party track while this run (or a watch of it) is on screen.
-- The ogg is added separately. A missing file, or a headless test, skips the sound.
local R = MP.load_mp_file and MP.load_mp_file("networking/gambel_rules.lua") or nil
if not R then return end
MP.GAMBEL = R

local function L(key, fallback)
	local ok, s = pcall(localize, key)
	if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= key then return s end
	return fallback
end

function R.active()
	local mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode
	return R.is_mode(mode)
end

function R.toast(text)
	if type(text) ~= "string" or text == "" then return end
	MP.GAME.gambel_notice = text
	if MP.UI and MP.UI.UTILS and MP.UI.UTILS.overlay_message then
		pcall(MP.UI.UTILS.overlay_message, text)
	end
end

local SPIN_NAME = {
	double_interest = "Double Interest",
	inflation = "Inflation",
	golden_hour = "Golden Hour",
	wild_odds = "Wild Odds",
	high_roller = "High Roller",
	slim_hands = "Slim Hands",
}
local TWIST_NAME = {
	reverse = "Reverse Stakes",
	double = "Double Trouble",
	pot = "Joker Pot",
	house = "House Twist",
	sabotage = "Hot Potato",
	allin = "All-In",
}

function R.spin_name(id) return SPIN_NAME[id] or tostring(id or "") end
function R.twist_name(id) return TWIST_NAME[id] or tostring(id or "") end

local function dollars()
	if G and G.GAME and G.GAME.dollars ~= nil and to_big then
		local ok, n = pcall(function() return to_number(to_big(G.GAME.dollars)) end)
		if ok and type(n) == "number" then return n end
	end
	return tonumber(G and G.GAME and G.GAME.dollars) or 0
end

function R.apply_delta(delta)
	delta = tonumber(delta) or 0
	if delta == 0 or not ease_dollars then return end
	if delta < 0 then delta = -math.min(-delta, math.max(0, dollars())) end
	pcall(ease_dollars, delta)
end

function R.apply_table(spin)
	if not spin or not (G and G.GAME) then return end
	MP.GAME.gambel_table = spin
	MP.GAME.gambel_wild = spin == "wild_odds"
	MP.GAME.gambel_gold_paid = false
	MP.GAME.gambel_bet_sent = false
	MP.GAME.gambel_bet_for = nil
	if spin == "double_interest" then
		if type(G.GAME.interest_amount) == "number" then G.GAME.interest_amount = G.GAME.interest_amount * 2 end
		if type(G.GAME.interest_cap) == "number" then G.GAME.interest_cap = G.GAME.interest_cap * 2 end
	elseif spin == "inflation" and type(G.GAME.inflation) == "number" then
		G.GAME.inflation = G.GAME.inflation + 1
	elseif spin == "high_roller" then
		if ease_hands then pcall(ease_hands, 1) end
		if ease_discard then pcall(ease_discard, 1) end
	elseif spin == "slim_hands" then
		if G.hand and G.hand.config and type(G.hand.config.card_limit) == "number" then
			G.hand.config.card_limit = math.max(1, G.hand.config.card_limit - 1)
		end
		R.apply_delta(5)
	end
	R.toast(R.spin_name(spin))
end

function R.on_new_round()
	if MP.GAME and MP.GAME.gambel_discard_pending and G and G.GAME and G.GAME.current_round and G.GAME.round_resets then
		local cap = G.GAME.round_resets.discards
		if type(cap) == "number" and type(G.GAME.current_round.discards_left) == "number" and G.GAME.current_round.discards_left > cap then
			G.GAME.current_round.discards_left = cap
		end
		MP.GAME.gambel_discard_pending = false
	end
	if not R.active() or MP.GAME.gambel_table ~= "golden_hour" or MP.GAME.gambel_gold_paid then return end
	if not (G and G.GAME and G.GAME.blind and G.GAME.chips and to_big) then return end
	local ok, cleared = pcall(function()
		return to_big(G.GAME.chips) >= to_big(G.GAME.blind.chips) and to_big(G.GAME.blind.chips) > to_big(0)
	end)
	if ok and cleared then
		MP.GAME.gambel_gold_paid = true
		R.apply_delta(3)
	end
end

function R.on_blind(key)
	if not R.active() then return end
	local deck = (G and G.GAME and G.GAME.blind_on_deck) or key
	local phase = R.blind_phase and R.blind_phase(deck) or "build"
	local mark = tostring(G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) .. ":" .. phase
	if MP.GAME.gambel_phase_mark ~= mark then
		MP.GAME.gambel_phase_mark = mark
		local names = { build = L("k_gambel_build", "BUILD-UP"), drop = L("k_gambel_drop", "DROP!"), final = L("k_gambel_final", "FINAL DROP") }
		R.toast(names[phase] or names.build)
		local bonus = R.phase_bonus and R.phase_bonus(phase) or 0
		if bonus > 0 then R.apply_delta(bonus) end
	end
	local boss = phase == "final"
	if boss and MP.ACTIONS and MP.ACTIONS.gambel_boss then MP.ACTIONS.gambel_boss() end
end

local function joker_flags()
	local give, room = false, false
	if G and G.jokers and G.jokers.cards and G.jokers.config then
		local limit = tonumber(G.jokers.config.card_limit) or #G.jokers.cards
		room = #G.jokers.cards < limit
		for _, c in ipairs(G.jokers.cards) do
			if not (c.ability and c.ability.eternal) then give = true end
		end
	end
	return give, room
end

function R.bet(kind, choice)
	if not R.active() or MP.GAME.gambel_bet_sent then return false end
	if kind ~= "wheel" and kind ~= "double" then return false end
	local money = dollars()
	if kind == "double" and money < 2 then return false end
	if kind == "double" and choice ~= "red" and choice ~= "black" then choice = nil end
	local give, room = joker_flags()
	local ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
	local online = MP.STEAM_P2P and MP.LOBBY and MP.LOBBY.code and Client and Client.send
	if online then
		MP.GAME.gambel_bet_sent = true
		MP.GAME.gambel_bet_for = ante
		local msg = { action = "gambelBet", kind = kind, money = money, ante = ante, give = give, room = room }
		if kind == "double" then msg.choice = choice end
		Client.send(msg)
		R.mute_shop_buttons()
		R.clear_shop()
		return true
	end
	local seed = (G and G.GAME and (G.GAME.pseudorandom_seed or G.GAME.seed)) or "house"
	local id = (MP.LOBBY and MP.LOBBY.my_id) or "solo"
	local res = kind == "wheel" and R.wheel(seed, id, ante, money) or R.flip(seed, id, ante, money, choice)
	res.kind = kind
	R.apply_bet(res)
	R.clear_shop()
	return true
end

local WHEEL_TAGS = { "tag_uncommon", "tag_holo", "tag_foil", "tag_investment", "tag_charm", "tag_meteor", "tag_standard", "tag_economy", "tag_ethereal", "tag_juggle" }
local WHEEL_EDITIONS = {
	{ foil = true, label = "Foil" },
	{ holo = true, label = "Holographic" },
	{ polychrome = true, label = "Polychrome" },
}

local function plain_joker()
	if not (G and G.jokers and G.jokers.cards) then return nil end
	for _, c in ipairs(G.jokers.cards) do
		if c and not c.edition and not (c.ability and c.ability.eternal) then return c end
	end
	return nil
end

local function mortal_joker()
	if not (G and G.jokers and G.jokers.cards) then return nil end
	for _, c in ipairs(G.jokers.cards) do
		if c and not (c.ability and c.ability.eternal) then return c end
	end
	return nil
end

function R.arm_discard()
	MP.GAME.gambel_discard_pending = true
	if G and G.GAME and G.GAME.round_resets and type(G.GAME.round_resets.discards) == "number" then
		G.GAME.round_resets.discards = math.max(0, G.GAME.round_resets.discards - 1)
	end
end

function R.play_wheel(msg, quiet)
	local plan = R.prize_plan(msg.id, {
		plain_joker = plain_joker() ~= nil,
		mortal_joker = mortal_joker() ~= nil,
		amount = msg.amount or msg.delta,
	})
	local seed = (G and G.GAME and (G.GAME.pseudorandom_seed or G.GAME.seed)) or "house"
	local ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
	local function say(text)
		if not quiet then R.flash(text) end
		return text
	end
	if plan.kind == "cash" then
		if msg.id ~= "cash" then R.apply_delta(plan.amount or 0) end
		return say("+$" .. tostring(plan.amount or msg.amount or 0))
	elseif plan.kind == "tax" then
		if msg.id ~= "tax" then R.apply_delta(-(plan.amount or 4)) end
		return say("-$" .. tostring(plan.amount or 4))
	elseif plan.kind == "edition" then
		local card = plain_joker()
		local pick = WHEEL_EDITIONS[R.roll(seed, ante, "edition", #WHEEL_EDITIONS)]
		if card and card.set_edition and pick then
			pcall(function()
				local edition = {}
				if pick.foil then edition.foil = true
				elseif pick.holo then edition.holo = true
				else edition.polychrome = true end
				G.CONTROLLER.locks.edition = false
				card:set_edition(edition, true, true)
			end)
			return say(pick.label)
		end
		R.apply_delta(8)
		return say("+$8")
	elseif plan.kind == "tag" then
		local key = WHEEL_TAGS[R.roll(seed, ante, "tag", #WHEEL_TAGS)]
		if add_tag and Tag and key then pcall(function() add_tag(Tag(key)) end) end
		return say(L("k_gambel_tag", "Tag"))
	elseif plan.kind == "discard" then
		R.arm_discard()
		return say(L("k_gambel_discard", "-1 discard next round"))
	elseif plan.kind == "perish" then
		local card = mortal_joker()
		local stuck = false
		if card and card.set_perishable then
			stuck = pcall(function() card:set_perishable(true) end)
		end
		if stuck then return say(L("k_gambel_perish", "Perishable")) end
		R.apply_delta(-math.min(4, dollars()))
		return say("-$4")
	end
end

function R.apply_bet(msg)
	MP.GAME.gambel_bet_sent = false
	if not msg or msg.ok == false then
		if msg and msg.reason == "once" then
			MP.GAME.gambel_bet_sent = true
			MP.GAME.gambel_bet_for = G and G.GAME and G.GAME.round_resets and tonumber(G.GAME.round_resets.ante) or MP.GAME.gambel_bet_for
		end
		if R.double_view and R.double_view.picked then R.finish_double(nil) end
		if R.wheel_view and R.wheel_view.spinning then R.finish_wheel(nil) end
		R.clear_shop()
		return
	end
	MP.GAME.gambel_bet_sent = true
	MP.GAME.gambel_bet_for = G and G.GAME and G.GAME.round_resets and tonumber(G.GAME.round_resets.ante) or MP.GAME.gambel_bet_for
	R.mute_shop_buttons()
	if msg.kind == "double" or msg.id == "cash" or msg.id == "tax" or msg.won ~= nil then
		R.apply_delta(msg.delta)
	end
	local line
	if msg.won == true then line = "+$" .. tostring(msg.stake or "")
	elseif msg.won == false then line = "-$" .. tostring(msg.stake or "") end
	local showing = R.double_view and R.double_view.picked and (msg.kind == "double" or msg.drawn) and G and G.OVERLAY_MENU
	if line and not showing then
		local title = msg.won and L("b_gambel_double", "Double or Nothing") or L("k_gambel_house", "The House holds")
		R.flash(title .. " " .. line)
	elseif line then
		if MP.GAME then MP.GAME.gambel_shop_note = line end
		R.toast(line)
	elseif msg.id then
		local spinning = R.wheel_view and R.wheel_view.spinning and G and G.OVERLAY_MENU
		if spinning then R.arm_wheel(msg, R.play_wheel(msg, true))
		else R.play_wheel(msg) end
	end
	if showing then R.reveal_double(msg, line)
	elseif R.double_view and R.double_view.picked then R.double_view = nil end
	R.clear_shop()
end

function R.apply_hit(msg)
	if not msg or not G then return end
	if msg.kind == "tax" then R.apply_delta(-(tonumber(msg.amount) or 4)) end
	if msg.kind == "allin" and G.GAME and G.GAME.blind and type(G.GAME.blind.dollars) == "number" then
		G.GAME.blind.dollars = G.GAME.blind.dollars * (tonumber(msg.payout) or 2)
	end
	if msg.joker and G.jokers and G.jokers.cards then
		if msg.role == "give" then
			for i, c in ipairs(G.jokers.cards) do
				if not (c.ability and c.ability.eternal) then
					pcall(function() c:remove() end)
					table.remove(G.jokers.cards, i)
					break
				end
			end
		elseif msg.role == "take" and create_card and G.jokers.config then
			local limit = tonumber(G.jokers.config.card_limit) or #G.jokers.cards
			if #G.jokers.cards < limit then
				pcall(function()
					local card = create_card("Joker", G.jokers, nil, nil, nil, nil, nil, "gambel")
					card:add_to_deck()
					G.jokers:emplace(card)
				end)
			end
		end
	end
end

function R.mute_shop_buttons()
	local boxes = G and G.I and G.I.UIBOX
	if type(boxes) ~= "table" then return end
	for _, box in pairs(boxes) do
		if box and box.get_UIE_by_ID then
			for _, id in ipairs({ "mp_gambel_double", "mp_gambel_wheel" }) do
				local el = box:get_UIE_by_ID(id)
				if el and el.config then
					el.config.button = nil
					el.config.colour = (G.C.UI and G.C.UI.BACKGROUND_INACTIVE) or G.C.GREY
				end
			end
		end
	end
end

--- Shop click opens this. Backing out before Red or Black does not spend the ante's bet.
function R.can_double()
	if not R.active() or (MP.GAME and MP.GAME.gambel_bet_sent) then return false end
	return R.stake(dollars()) >= 1
end

function R.open_double()
	if R.double_view or not R.can_double() then return end
	if R.wheel_view and not R.wheel_view.spinning then R.close_wheel() end
	if not (G and G.FUNCS and G.FUNCS.overlay_menu) then return end
	local stake = R.stake(dollars())
	R.double_view = {
		stake = stake, picked = false, show_close = false,
		prompt = L("k_gambel_pick", "Pick Red or Black"),
		result = "", card_name = "",
	}
	G.FUNCS.overlay_menu({ definition = R.double_definition() })
end

function R.drop_cards(view)
	if not view then return end
	local area, card = view.area, view.card
	view.area, view.card = nil, nil
	if area and area.remove then pcall(function() area:remove() end) end
	if card and card.remove and not card.REMOVED then pcall(function() card:remove() end) end
end

function R.close_double()
	R.drop_cards(R.double_view)
	R.double_view = nil
	if G and G.FUNCS and G.FUNCS.exit_overlay_menu and G.OVERLAY_MENU then
		pcall(function() G.FUNCS.exit_overlay_menu() end)
	end
end

function R.pick_double(choice)
	local view = R.double_view
	if not view or view.picked or view.show_close then return end
	if choice ~= "red" and choice ~= "black" then return end
	if not R.can_double() then
		R.close_double()
		return
	end
	view.picked = choice
	local menu = G and G.OVERLAY_MENU
	if menu and menu.get_UIE_by_ID then
		for _, id in ipairs({ "mp_gambel_red", "mp_gambel_black", "mp_gambel_back" }) do
			local el = menu:get_UIE_by_ID(id)
			if el and el.config then
				el.config.button = nil
				el.config.colour = (G.C.UI and G.C.UI.BACKGROUND_INACTIVE) or G.C.GREY
			end
		end
	end
	if not R.bet("double", choice) then
		view.picked = false
		R.close_double()
	end
end

function R.reveal_double(msg, line)
	local view = R.double_view
	if not view then return end
	local suit = msg and msg.suit
	if suit ~= "H" and suit ~= "D" and suit ~= "S" and suit ~= "C" then
		suit = (msg and msg.drawn == "black") and "S" or "H"
	end
	local key = suit .. "_A"
	local picked = (view.picked == "black") and L("b_gambel_black", "Black Ace") or L("b_gambel_red", "Red Ace")
	local drawn = R.ace_name(suit)
	view.card_name = drawn
	view.face = "front"
	view.pip = "A"
	view.suit_mark = suit
	view.prompt = L("k_gambel_you_picked", "You picked ") .. picked .. L("k_gambel_drawn_mid", " — Drawn: ") .. drawn
	view.result = line or ""
	view.show_close = true
	local card = view.card
	local def = G and G.P_CARDS and G.P_CARDS[key]
	if card and def then
		pcall(function()
			if card.set_base then card:set_base(def) end
			if card.set_sprites then card:set_sprites(nil, def) end
			card.facing = "front"
			card.sprite_facing = "front"
			card.flipping = nil
			if card.pinch then card.pinch.x = false; card.pinch.y = false end
			if card.states then card.states.visible = true end
		end)
	end
end

function R.finish_double(line)
	local view = R.double_view
	if not view then return end
	view.result = line or L("k_gambel_house", "The House holds")
	view.show_close = true
end

function R.ace_name(suit)
	local keys = { H = "k_gambel_ace_h", D = "k_gambel_ace_d", S = "k_gambel_ace_s", C = "k_gambel_ace_c" }
	local fb = { H = "Ace of Hearts", D = "Ace of Diamonds", S = "Ace of Spades", C = "Ace of Clubs" }
	return L(keys[suit] or "", fb[suit] or "")
end

local function ace_fallback(view)
	local front = view.face == "front"
	local red = view.suit_mark == "H" or view.suit_mark == "D"
	local ink = front and (red and { 0.86, 0.16, 0.18, 1 } or { 0.08, 0.08, 0.1, 1 }) or { 0.95, 0.95, 0.98, 1 }
	local paper = front and { 0.96, 0.94, 0.88, 1 } or { 0.12, 0.28, 0.62, 1 }
	return { n = G.UIT.C, config = { align = "cm", minw = 1.7, minh = 2.35, r = 0.08, colour = paper, emboss = 0.08 }, nodes = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "pip", scale = 0.7, colour = ink, shadow = true } },
		} },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "suit_mark", scale = 0.42, colour = ink } },
		} },
	} }
end

local function ace_node()
	local view = R.double_view
	view.face = view.face or "back"
	view.pip = view.pip or "?"
	view.suit_mark = view.suit_mark or ""
	local caption = { n = G.UIT.R, config = { align = "cm", padding = 0.04, minh = 0.4 }, nodes = {
		{ n = G.UIT.T, config = { ref_table = view, ref_value = "card_name", scale = 0.38, colour = G.C.WHITE, shadow = true } },
	} }
	local function shown(card_row)
		return { n = G.UIT.C, config = { align = "cm" }, nodes = { card_row, caption } }
	end
	if not (Card and CardArea and G and G.P_CARDS and G.P_CENTERS and G.P_CENTERS.c_base and G.CARD_W and G.CARD_H) then
		return shown(ace_fallback(view))
	end
	local card, area
	local ok = pcall(function()
		area = CardArea(0, 0, G.CARD_W * 1.5, G.CARD_H * 1.35, {
			card_limit = 1, type = "title_2", highlight_limit = 0, card_w = G.CARD_W * 0.95,
		})
		local def = G.P_CARDS.H_A or G.P_CARDS["H_A"]
		card = Card(0, 0, G.CARD_W * 0.95, G.CARD_H * 0.95, def, G.P_CENTERS.c_base)
		card.facing = "back"
		card.sprite_facing = "back"
		if card.states then card.states.visible = true end
		area:emplace(card)
	end)
	if not ok or not area then
		if area and area.remove then pcall(function() area:remove() end) end
		if card and card.remove and not card.REMOVED then pcall(function() card:remove() end) end
		return shown(ace_fallback(view))
	end
	view.area, view.card = area, card
	return shown({ n = G.UIT.R, config = { align = "cm", minw = G.CARD_W * 1.6, minh = G.CARD_H * 1.45 }, nodes = {
		{ n = G.UIT.O, config = { object = area } },
	} })
end

local FELT = { 0.05, 0.22, 0.14, 1 }
local CRIMSON = { 0.62, 0.10, 0.14, 1 }
local GOLD_INK = { 0.96, 0.80, 0.32, 1 }

--- Shared card-table frame: green felt, crimson title, gold lettering, Balatro emboss.
local function ink(c) return { c[1], c[2], c[3], c[4] } end

function R.casino_frame(title, minw, nodes)
	local body = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.07, r = 0.08, colour = ink(CRIMSON), minw = (minw or 7.2) - 0.5 }, nodes = {
			{ n = G.UIT.T, config = { text = title, scale = 0.46, colour = ink(GOLD_INK), shadow = true } },
		} },
	}
	for _, node in ipairs(nodes or {}) do body[#body + 1] = node end
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.06 }, nodes = {
		{ n = G.UIT.C, config = { id = "mp_gambel_felt", align = "cm", padding = 0.12, r = 0.12, colour = ink(FELT), emboss = 0.08, minw = minw or 7.2 }, nodes = body },
	} }
end

local function casino_btn(id, func, label, colour, minw)
	return { n = G.UIT.C, config = { align = "cm", padding = 0.05 }, nodes = {
		UIBox_button({ id = id, button = func, label = { label }, minw = minw or 2.15, minh = 0.55, scale = 0.36, colour = colour, col = true }),
	} }
end

function R.double_definition()
	local view = R.double_view or { stake = 0, prompt = "", result = "", card_name = "" }
	local stake = tostring(view.stake or 0)
	local stake_txt = L("k_gambel_stake", "Stake: $") .. stake
	local odds = L("k_gambel_win", "Win +$") .. stake .. " / " .. L("k_gambel_lose", "Lose -$") .. stake
	return R.casino_frame(L("b_gambel_double", "Double or Nothing"), 7.2, {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { text = stake_txt, scale = 0.36, colour = GOLD_INK } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { text = odds, scale = 0.32, colour = G.C.UI and G.C.UI.TEXT_LIGHT or G.C.WHITE } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "prompt", scale = 0.34, colour = G.C.WHITE } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { ace_node() } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.04, minh = 0.4 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "result", scale = 0.46, colour = GOLD_INK, shadow = true } },
		} },
		{ n = G.UIT.R, config = { id = "mp_gambel_choices", align = "cm", padding = 0.04, func = "mp_gambel_choices_vis" }, nodes = {
			casino_btn("mp_gambel_red", "mp_gambel_pick_red", L("b_gambel_red", "Red Ace"), G.C.RED, 2.2),
			casino_btn("mp_gambel_black", "mp_gambel_pick_black", L("b_gambel_black", "Black Ace"), G.C.BLACK, 2.2),
			casino_btn("mp_gambel_back", "mp_gambel_double_back", L("b_gambel_back", "Back"), G.C.GREY, 1.6),
		} },
		{ n = G.UIT.R, config = { id = "mp_gambel_continue", align = "cm", padding = 0.04, func = "mp_gambel_continue_vis" }, nodes = {
			casino_btn("mp_gambel_continue", "mp_gambel_double_close", L("b_gambel_continue", "Continue"), G.C.BLUE, 2.4),
		} },
	})
end

function R.wheel_labels()
	return {
		"+$8",
		"+$20",
		L("k_gambel_tag", "Tag"),
		L("k_gambel_edition", "Edition"),
		L("k_gambel_wheel_tax", "-$4 Tax"),
		L("k_gambel_wheel_discard", "-1 Discard"),
		L("k_gambel_perish", "Perishable"),
	}
end

--- Short marks that fit inside a wedge. The full names stay in the legend.
function R.wheel_slices()
	return { "+$8", "+$20", "TAG", "EDIT", "-$4", "-1D", "PERISH" }
end

function R.wheel_colours()
	return {
		{ 0.95, 0.78, 0.28, 1 },
		{ 1.00, 0.90, 0.48, 1 },
		{ 0.28, 0.55, 0.95, 1 },
		{ 0.68, 0.38, 0.95, 1 },
		{ 0.86, 0.18, 0.20, 1 },
		{ 0.95, 0.52, 0.16, 1 },
		{ 0.32, 0.68, 0.36, 1 },
	}
end

--- Draw is a no-op unless Love2D is present, so headless tests never touch the canvas.
R.WHEEL_BOX = 5.0
function R.make_wheel()
	if not (Moveable and love and love.graphics and love.graphics.polygon) then return nil end
	local size = R.WHEEL_BOX
	local obj = Moveable(0, 0, size, size)
	obj.config = obj.config or {}
	if obj.states then
		obj.states.drag.can = false
		obj.states.click.can = false
		obj.states.collide.can = false
	end
	function obj:draw()
		if not (love and love.graphics and love.graphics.polygon and G and G.TILESIZE) then return end
		pcall(function()
			local g = love.graphics
			local T = self.VT or self.T
			if not T then return end
			local ts = G.TILESIZE
			local sc = G.TILESCALE or 1
			local view = R.wheel_view
			local rot = view and view.angle or 0
			local n = (R.WHEEL and #R.WHEEL) or 7
			local slice = (2 * math.pi) / n
			local colours = R.wheel_colours()
			local labels = R.wheel_slices()
			-- Rim, pegs, and the pointer all stay inside this box. The legend is a later column.
			local half = math.min(T.w, T.h) / 2
			local radius = (half - 0.72) * ts
			local rim = radius + 0.11 * ts
			g.push()
			if self.translate_container then self:translate_container() end
			g.scale(sc, sc)
			g.translate((T.x + T.w / 2) * ts, (T.y + T.h / 2) * ts)
			g.setColor(0.28, 0.18, 0.05, 1)
			g.circle("fill", 0, 0, rim + 0.07 * ts)
			g.setColor(GOLD_INK[1], GOLD_INK[2], GOLD_INK[3], 1)
			g.circle("fill", 0, 0, rim + 0.035 * ts)
			g.setColor(0.45, 0.28, 0.06, 1)
			g.circle("fill", 0, 0, rim)
			g.setLineWidth(2)
			g.setColor(1, 0.92, 0.55, 1)
			g.circle("line", 0, 0, rim + 0.035 * ts)
			for i = 1, n do
				local a0 = -math.pi / 2 + (i - 1) * slice + rot
				local a1 = a0 + slice
				local col = colours[i] or GOLD_INK
				local mid = (a0 + a1) / 2
				local poly = { 0, 0 }
				for s = 0, 12 do
					local a = a0 + (a1 - a0) * (s / 12)
					poly[#poly + 1] = math.cos(a) * radius
					poly[#poly + 1] = math.sin(a) * radius
				end
				g.setColor(col[1] * 0.55, col[2] * 0.55, col[3] * 0.55, 1)
				g.polygon("fill", poly)
				local face = { math.cos(mid) * radius * 0.22, math.sin(mid) * radius * 0.22 }
				for s = 0, 12 do
					local a = a0 + (a1 - a0) * (s / 12)
					face[#face + 1] = math.cos(a) * radius
					face[#face + 1] = math.sin(a) * radius
				end
				g.setColor(col[1], col[2], col[3], 1)
				g.polygon("fill", face)
				local landed = view and view.landed and view.index == i
				g.setColor(landed and 1 or 0.15, landed and 0.9 or 0.1, landed and 0.4 or 0.05, 1)
				g.setLineWidth(landed and 3 or 1.2)
				g.polygon("line", poly)
				local peg = rim + 0.01 * ts
				g.setColor(1, 0.82, 0.35, 1)
				g.circle("fill", math.cos(a0) * peg, math.sin(a0) * peg, 0.055 * ts)
				g.setColor(1, 0.95, 0.7, 1)
				g.circle("fill", math.cos(a0) * peg - 0.012 * ts, math.sin(a0) * peg - 0.012 * ts, 0.022 * ts)
				local font = g.getFont and g.getFont()
				if font and labels[i] then
					local fh = font:getHeight()
					local spin = mid + math.pi / 2
					if math.sin(mid) > 0 then spin = spin + math.pi end
					g.push()
					g.translate(math.cos(mid) * radius * 0.64, math.sin(mid) * radius * 0.64)
					g.rotate(spin)
					g.scale(0.26, 0.26)
					g.setColor(0, 0, 0, 0.9)
					g.printf(labels[i], -71, -fh / 2, 140, "center")
					g.printf(labels[i], -69, -fh / 2, 140, "center")
					g.setColor(1, 0.98, 0.9, 1)
					g.printf(labels[i], -70, -fh / 2 - 1, 140, "center")
					g.pop()
				end
			end
			g.setColor(0.55, 0.38, 0.08, 1)
			g.circle("fill", 0, 0, radius * 0.24)
			g.setColor(GOLD_INK[1], GOLD_INK[2], GOLD_INK[3], 1)
			g.circle("fill", 0, 0, radius * 0.18)
			g.setColor(0.35, 0.18, 0.04, 1)
			g.circle("fill", 0, 0, radius * 0.09)
			g.setColor(1, 0.9, 0.45, 1)
			local star = {}
			for s = 0, 9 do
				local a = -math.pi / 2 + s * math.pi / 5
				local rr = (s % 2 == 0) and radius * 0.07 or radius * 0.03
				star[#star + 1] = math.cos(a) * rr
				star[#star + 1] = math.sin(a) * rr
			end
			g.polygon("fill", star)
			local tip = -(rim + 0.02 * ts)
			g.setColor(0.75, 0.62, 0.2, 1)
			g.polygon("fill", 0, tip - 0.28 * ts, -0.16 * ts, tip + 0.02 * ts, 0.16 * ts, tip + 0.02 * ts)
			g.setColor(CRIMSON[1], CRIMSON[2], CRIMSON[3], 1)
			g.polygon("fill", 0, tip - 0.24 * ts, -0.11 * ts, tip, 0.11 * ts, tip)
			g.setColor(1, 0.85, 0.85, 1)
			g.polygon("fill", 0, tip - 0.2 * ts, -0.035 * ts, tip - 0.04 * ts, 0.035 * ts, tip - 0.04 * ts)
			g.setColor(1, 1, 1, 1)
			g.pop()
		end)
		pcall(function() love.graphics.setColor(1, 1, 1, 1) end)
	end
	return obj
end

local function wheel_face()
	local obj = R.make_wheel()
	if obj and R.wheel_view then R.wheel_view.wheel = obj end
	local inner = obj and { n = G.UIT.O, config = { object = obj } }
		or { n = G.UIT.T, config = { text = L("b_gambel_wheel", "Gambel Wheel"), scale = 0.36, colour = GOLD_INK } }
	return { n = G.UIT.C, config = { align = "cm", minw = R.WHEEL_BOX, minh = R.WHEEL_BOX, padding = 0.08 }, nodes = { inner } }
end

local function wheel_legend()
	local rows = {}
	local labels, colours = R.wheel_labels(), R.wheel_colours()
	for i, text in ipairs(labels) do
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.025 }, nodes = {
			{ n = G.UIT.C, config = { align = "cm", minw = 0.24, minh = 0.24, r = 0.04, colour = colours[i] } },
			{ n = G.UIT.C, config = { minw = 0.08 } },
			{ n = G.UIT.T, config = { text = text, scale = 0.28, colour = G.C.WHITE } },
		} }
	end
	return { n = G.UIT.C, config = { align = "cm", padding = 0.06, r = 0.1, minw = 3.05, colour = GOLD_INK, emboss = 0.05 }, nodes = {
		{ n = G.UIT.C, config = { align = "tm", padding = 0.1, r = 0.08, minw = 2.85, colour = { 0.06, 0.04, 0.03, 1 } }, nodes = rows },
	} }
end

function R.can_wheel()
	return R.active() and not (MP.GAME and MP.GAME.gambel_bet_sent)
end

function R.open_wheel()
	if R.wheel_view or not R.can_wheel() then return end
	if R.double_view and not R.double_view.picked then R.close_double() end
	if not (G and G.FUNCS and G.FUNCS.overlay_menu) then return end
	R.wheel_view = {
		spinning = false, show_close = false, landed = false, angle = 0, result = "",
		prompt = L("k_gambel_wheel_prompt", "Seven prizes. One spin."),
	}
	G.FUNCS.overlay_menu({ definition = R.wheel_definition() })
end

function R.close_wheel()
	local view = R.wheel_view
	if view and view.pending_label and not view.announced then
		view.announced = true
		R.flash(view.pending_label)
	end
	R.wheel_view = nil
	if G and G.FUNCS and G.FUNCS.exit_overlay_menu and G.OVERLAY_MENU then
		pcall(function() G.FUNCS.exit_overlay_menu() end)
	end
end

function R.spin_wheel()
	local view = R.wheel_view
	if not view or view.spinning or view.show_close then return end
	if not R.can_wheel() then
		R.close_wheel()
		return
	end
	view.spinning = true
	local menu = G and G.OVERLAY_MENU
	if menu and menu.get_UIE_by_ID then
		for _, id in ipairs({ "mp_gambel_spin", "mp_gambel_wheel_back" }) do
			local el = menu:get_UIE_by_ID(id)
			if el and el.config then
				el.config.button = nil
				el.config.colour = (G.C.UI and G.C.UI.BACKGROUND_INACTIVE) or G.C.GREY
			end
		end
	end
	if not R.bet("wheel") then
		view.spinning = false
		R.close_wheel()
	end
end

function R.arm_wheel(msg, label)
	local view = R.wheel_view
	if not view then
		if label then R.flash(label) end
		return
	end
	view.index = R.wheel_index(msg)
	view.target_angle = R.wheel_rotation(view.index, 4)
	view.pending_label = label
	view.angle = 0
	view.t = 0
	view.duration = 2.4
	view.spinning = true
	if not (love and love.graphics and love.graphics.polygon) then
		view.t = 1
		view.angle = view.target_angle
		view.landed = true
		view.spinning = false
		view.show_close = true
		view.result = label or ""
		view.announced = true
		if label then R.flash(label) end
	end
end

function R.finish_wheel(line)
	local view = R.wheel_view
	if not view then return end
	view.spinning = false
	view.landed = true
	view.show_close = true
	view.result = line or L("k_gambel_house", "The House holds")
end

function R.tick_wheel(dt)
	local view = R.wheel_view
	if not view then return end
	if view.spinning and not view.target_angle then
		view.angle = (view.angle or 0) - (tonumber(dt) or 0) * 1.4
		return
	end
	if not view.spinning or view.landed or not view.target_angle then return end
	local step = (tonumber(dt) or 0.016) / (view.duration or 2.4)
	view.t = math.min(1, (view.t or 0) + step)
	view.angle = view.target_angle * R.wheel_ease(view.t)
	if view.t >= 1 then
		view.angle = view.target_angle
		view.landed = true
		view.spinning = false
		view.show_close = true
		view.result = view.pending_label or ""
		if view.pending_label and not view.announced then
			view.announced = true
			R.flash(view.pending_label)
		end
	end
end

function R.wheel_definition()
	local view = R.wheel_view or { prompt = "", result = "" }
	return R.casino_frame(L("b_gambel_wheel", "Gambel Wheel"), 12.4, {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "prompt", scale = 0.32, colour = G.C.WHITE } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = {
			wheel_face(),
			{ n = G.UIT.C, config = { align = "cm", minw = 0.7 } },
			wheel_legend(),
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.04, minh = 0.4 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "result", scale = 0.46, colour = GOLD_INK, shadow = true } },
		} },
		{ n = G.UIT.R, config = { id = "mp_gambel_spin_row", align = "cm", padding = 0.04, func = "mp_gambel_spin_vis" }, nodes = {
			casino_btn("mp_gambel_spin", "mp_gambel_spin", L("b_gambel_spin", "Spin!"), G.C.ORANGE, 2.2),
			casino_btn("mp_gambel_wheel_back", "mp_gambel_wheel_back", L("b_gambel_back", "Back"), G.C.GREY, 1.6),
		} },
		{ n = G.UIT.R, config = { id = "mp_gambel_wheel_continue", align = "cm", padding = 0.04, func = "mp_gambel_wheel_continue_vis" }, nodes = {
			casino_btn("mp_gambel_wheel_continue", "mp_gambel_wheel_close", L("b_gambel_continue", "Continue"), G.C.BLUE, 2.4),
		} },
	})
end

function R.clear_shop()
	local box = MP.GAME and MP.GAME.gambel_shop_box
	if box then pcall(function() box:remove() end) end
	if MP.GAME then MP.GAME.gambel_shop_box = nil end
end

function R.flash(text)
	text = tostring(text or "")
	if MP.GAME then MP.GAME.gambel_shop_note = text end
	R.toast(text)
	if attention_text and text ~= "" then
		pcall(attention_text, {
			text = text, scale = 0.9, hold = 1.3,
			major = (G and (G.shop or G.play)) or nil,
			align = "cm", backdrop_colour = G and G.C and G.C.GOLD or nil,
		})
	end
end

local function shop_button(id, func, label, colour, enabled)
	return { n = G.UIT.C, config = { align = "cm", padding = 0.08 }, nodes = {
		UIBox_button({
			id = id,
			button = enabled and func or nil,
			label = { label },
			minw = 3.6,
			minh = 0.74,
			scale = 0.42,
			col = true,
			shadow = true,
			colour = enabled and colour or (G.C.UI and G.C.UI.BACKGROUND_INACTIVE or G.C.GREY),
		}),
	} }
end

--- One row inside the shop UI itself: Double or Nothing, then Gambel Wheel, then the last result.
function R.sync_bet_ante()
	if not (MP.GAME and R.keep_bet) then return end
	local ante = G and G.GAME and G.GAME.round_resets and tonumber(G.GAME.round_resets.ante)
	MP.GAME.gambel_bet_sent = R.keep_bet(MP.GAME.gambel_bet_for, ante, MP.GAME.gambel_bet_sent)
	if not MP.GAME.gambel_bet_sent then MP.GAME.gambel_bet_for = nil end
end

function R.shop_row()
	R.sync_bet_ante()
	MP.GAME.gambel_shop_note = MP.GAME.gambel_shop_note or ""
	local used = MP.GAME.gambel_bet_sent and true or false
	local cash = dollars()
	return { n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
		shop_button("mp_gambel_double", "mp_gambel_double", L("b_gambel_double", "Double or Nothing"), G.C.ORANGE, (not used) and cash >= 2),
		shop_button("mp_gambel_wheel", "mp_gambel_wheel", L("b_gambel_wheel", "Gambel Wheel"), G.C.PURPLE, not used),
		{ n = G.UIT.C, config = { align = "cm", minw = 2.2, padding = 0.06 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = MP.GAME, ref_value = "gambel_shop_note", scale = 0.4, colour = G.C.GOLD or G.C.WHITE } },
		} },
	} }
end

function R.hook_shop()
	if R._shop or not (G and G.UIDEF and G.UIDEF.shop) then return false end
	R._shop = true
	local ref = G.UIDEF.shop
	function G.UIDEF.shop()
		local t = ref()
		if R.active() and type(t) == "table" and type(t.nodes) == "table" then
			table.insert(t.nodes, 1, R.shop_row())
		end
		return t
	end
	return true
end

function R.on_shop()
	R.hook_shop()
	R.clear_shop()
end

function R.register_music()
	if not (SMODS and SMODS.Sound and NFS and NFS.getInfo and MP.path) then return end
	if not NFS.getInfo(MP.path .. "/assets/sounds/music_gambel_time.ogg") then return end
	SMODS.Sound({
		key = "music_gambel_time",
		path = "music_gambel_time.ogg",
		sync = false,
		pitch = 1,
		volume = 1,
		select_music_track = function()
			local watching = MP.SPECTATE and MP.SPECTATE.watching and MP.SPECTATE.watching()
			local stage = (G and G.STAGES and G.STAGE == G.STAGES.RUN) and "run" or "menu"
			return R.music_priority({
				mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode,
				watching = watching and true or false,
				stage = stage,
			})
		end,
	})
end

R.register_music()

function R.register_ui()
	G = G or {}
	G.FUNCS = G.FUNCS or {}
	function G.FUNCS.mp_gambel_double(e)
		if not MP.GAMBEL then return end
		MP.GAMBEL.open_double()
	end
	function G.FUNCS.mp_gambel_pick_red()
		if MP.GAMBEL then MP.GAMBEL.pick_double("red") end
	end
	function G.FUNCS.mp_gambel_pick_black()
		if MP.GAMBEL then MP.GAMBEL.pick_double("black") end
	end
	function G.FUNCS.mp_gambel_double_back()
		if not (MP.GAMBEL and MP.GAMBEL.double_view) or MP.GAMBEL.double_view.picked then return end
		MP.GAMBEL.close_double()
	end
	function G.FUNCS.mp_gambel_double_close()
		if MP.GAMBEL then MP.GAMBEL.close_double() end
	end
	function G.FUNCS.mp_gambel_choices_vis(e)
		local view = MP.GAMBEL and MP.GAMBEL.double_view
		if e and e.states then e.states.visible = not (view and view.show_close) end
	end
	function G.FUNCS.mp_gambel_continue_vis(e)
		local view = MP.GAMBEL and MP.GAMBEL.double_view
		if e and e.states then e.states.visible = view and view.show_close and true or false end
	end
	function G.FUNCS.mp_gambel_wheel(e)
		if not MP.GAMBEL then return end
		MP.GAMBEL.open_wheel()
	end
	function G.FUNCS.mp_gambel_spin()
		if MP.GAMBEL then MP.GAMBEL.spin_wheel() end
	end
	function G.FUNCS.mp_gambel_wheel_back()
		if not (MP.GAMBEL and MP.GAMBEL.wheel_view) or MP.GAMBEL.wheel_view.spinning then return end
		MP.GAMBEL.close_wheel()
	end
	function G.FUNCS.mp_gambel_wheel_close()
		if MP.GAMBEL then MP.GAMBEL.close_wheel() end
	end
	function G.FUNCS.mp_gambel_spin_vis(e)
		local view = MP.GAMBEL and MP.GAMBEL.wheel_view
		if e and e.states then e.states.visible = not (view and view.show_close) end
	end
	function G.FUNCS.mp_gambel_wheel_continue_vis(e)
		local view = MP.GAMBEL and MP.GAMBEL.wheel_view
		if e and e.states then e.states.visible = view and view.show_close and true or false end
	end
	R.hook_shop()
	if R._ui or not (Game and Game.update) then return end
	R._ui = true
	local upd = Game.update
	function Game:update(dt)
		local r = upd(self, dt)
		if MP.GAMBEL and MP.GAMBEL.active and MP.GAMBEL.active() and G and G.STATES then
			MP.GAMBEL.hook_shop()
			if G.STATE ~= G.STATES.SHOP then MP.GAMBEL.clear_shop() end
			local view = MP.GAMBEL.double_view
			if view and not G.OVERLAY_MENU then
				MP.GAMBEL.drop_cards(view)
				if not view.picked then MP.GAMBEL.double_view = nil end
			end
			MP.GAMBEL.tick_wheel(dt)
			local wheel = MP.GAMBEL.wheel_view
			if wheel and not G.OVERLAY_MENU then
				if wheel.pending_label and not wheel.announced then
					wheel.announced = true
					MP.GAMBEL.flash(wheel.pending_label)
				end
				if not wheel.spinning or wheel.announced or not wheel.pending_label then MP.GAMBEL.wheel_view = nil end
			end
		end
		return r
	end
end

R.register_ui()
