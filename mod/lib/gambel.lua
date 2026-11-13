-- Gambel Time on the client: show the host's spin, apply the local half of a bet,
-- and play the party track while this run (or a watch of it) is on screen.
-- The ogg is added separately. A missing file, or a headless test, skips the sound.
local R = MP.load_mp_file and MP.load_mp_file("networking/gambel_rules.lua") or nil
if not R then return end
MP.GAMBEL = R
R.state = {}

local function L(key, fallback)
	local ok, s = pcall(localize, key)
	if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= key then return s end
	return fallback
end

function R.active()
	local mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode
	return R.is_mode(mode)
end

--- A Gambel overlay is on screen. A notice must not pause the game or replace that menu.
function R.notice_blocked()
	if not (G and G.OVERLAY_MENU) then return false end
	if R.double_view or R.wheel_view then return true end
	return false
end

function R.show_notice(text)
	pcall(function()
		if not attention_text or text == "" then return end
		attention_text({
			scale = 0.65, text = text, hold = 2.4, align = "cm", offset = { x = 0, y = -2.6 }, maxw = 10,
			major = (G and (G.ROOM_ATTACH or G.play)) or nil,
		})
	end)
end

function R.toast(text)
	if type(text) ~= "string" or text == "" then return end
	if MP.GAME then MP.GAME.gambel_notice = text end
	if R.notice_blocked() then return end
	R.show_notice(text)
end

local SPIN_NAME = {
	double_interest = { "k_gambel_spin_double_interest", "Double Interest" },
	inflation = { "k_gambel_spin_inflation", "Inflation" },
	golden_hour = { "k_gambel_spin_golden_hour", "Golden Hour" },
	wild_odds = { "k_gambel_spin_wild_odds", "Wild Odds" },
	high_roller = { "k_gambel_spin_high_roller", "High Roller" },
	slim_hands = { "k_gambel_spin_slim_hands", "Slim Hands" },
}
local TWIST_NAME = {
	reverse = { "k_gambel_twist_reverse", "Reverse Stakes" },
	double = { "k_gambel_twist_double", "Double Trouble" },
	pot = { "k_gambel_twist_pot", "Joker Pot" },
	house = { "k_gambel_twist_house", "House Twist" },
	sabotage = { "k_gambel_twist_sabotage", "Hot Potato" },
	allin = { "k_gambel_twist_allin", "All-In" },
}

function R.spin_name(id)
	local row = SPIN_NAME[id]
	if not row then return tostring(id or "") end
	return L(row[1], row[2])
end
function R.twist_name(id)
	local row = TWIST_NAME[id]
	if not row then return tostring(id or "") end
	return L(row[1], row[2])
end

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

--- Hands and discards that survive vanilla new_round live on round_resets, not the current counters.
local function bump_rounds(hands, discards)
	local game = G and G.GAME
	local rr = game and game.round_resets
	local cr = game and game.current_round
	local applied_h, applied_d = 0, 0
	if hands ~= 0 and rr and type(rr.hands) == "number" then
		local next_h = rr.hands + hands
		if next_h >= 1 then
			rr.hands = next_h
			if cr and type(cr.hands_left) == "number" then cr.hands_left = math.max(0, cr.hands_left + hands) end
			applied_h = hands
		end
	end
	if discards ~= 0 and rr and type(rr.discards) == "number" then
		local next_d = math.max(0, rr.discards + discards)
		applied_d = next_d - rr.discards
		rr.discards = next_d
		if applied_d ~= 0 and cr and type(cr.discards_left) == "number" then
			cr.discards_left = math.max(0, cr.discards_left + applied_d)
		end
	end
	return applied_h, applied_d
end

function R.undo_table()
	local game = MP and MP.GAME
	local delta = game and game.gambel_spin_delta
	if game then game.gambel_spin_delta = nil end
	if not delta or not (G and G.GAME) then return end
	if delta.interest_amount ~= nil and type(G.GAME.interest_amount) == "number" then
		G.GAME.interest_amount = delta.interest_amount
	end
	if delta.interest_cap ~= nil and type(G.GAME.interest_cap) == "number" then
		G.GAME.interest_cap = delta.interest_cap
	end
	if delta.inflation and type(G.GAME.inflation) == "number" then
		G.GAME.inflation = G.GAME.inflation - delta.inflation
	end
	if delta.hands or delta.discards then
		bump_rounds(-(delta.hands or 0), -(delta.discards or 0))
	end
end

function R.sync_state()
	local g = MP and MP.GAME or {}
	R.state = {
		table_spin = g.gambel_table,
		ante = g.gambel_applied_ante,
		twist = g.gambel_twist,
		wild = g.gambel_wild and true or false,
		gold_paid = g.gambel_gold_paid and true or false,
		bet_sent = g.gambel_bet_sent and true or false,
		bet_for = g.gambel_bet_for,
		discard_pending = g.gambel_discard_pending and true or false,
		discard_restore = g.gambel_discard_restore,
	}
end

--- Put a temporary -1 Discard back, then forget it. Used when the penalty round ends and when a match resets.
function R.clear_discard_penalty()
	if not (MP and MP.GAME) then return end
	local n = tonumber(MP.GAME.gambel_discard_restore) or 0
	if n > 0 and (MP.GAME.gambel_discard_pending or MP.GAME.gambel_discard_armed)
		and G and G.GAME and G.GAME.round_resets and type(G.GAME.round_resets.discards) == "number" then
		G.GAME.round_resets.discards = G.GAME.round_resets.discards + n
	end
	MP.GAME.gambel_discard_pending = false
	MP.GAME.gambel_discard_restore = nil
	MP.GAME.gambel_discard_armed = false
end

function R.reset()
	if R.undo_table then R.undo_table() end
	if R.clear_discard_penalty then R.clear_discard_penalty() end
	if MP and MP.GAME then
		MP.GAME.gambel_table = nil
		MP.GAME.gambel_wild = false
		MP.GAME.gambel_gold_paid = false
		MP.GAME.gambel_bet_sent = false
		MP.GAME.gambel_bet_for = nil
		MP.GAME.gambel_phase_mark = nil
		MP.GAME.gambel_twist = nil
		MP.GAME.gambel_notice = nil
		MP.GAME.gambel_applied_spin = nil
		MP.GAME.gambel_applied_ante = nil
		MP.GAME.gambel_spin_delta = nil
	end
	if R.drop_cards then R.drop_cards(R.double_view) end
	R.double_view = nil
	R.wheel_view = nil
	if G and G.GAME then G.GAME.mp_gambel_shop_used = nil end
	R.state = {}
end

function R.apply_table(spin, ante)
	if not spin or not (G and G.GAME) then return end
	MP.GAME = MP.GAME or {}
	ante = tonumber(ante) or tonumber(G.GAME.round_resets and G.GAME.round_resets.ante)
	if MP.GAME.gambel_applied_spin == spin and MP.GAME.gambel_applied_ante == ante then
		R.sync_state()
		return
	end
	-- The same rule on the next ante keeps its numbers. Re-applying would stack interest, inflation, and hands.
	if MP.GAME.gambel_applied_spin == spin then
		MP.GAME.gambel_applied_ante = ante
		MP.GAME.gambel_table = spin
		MP.GAME.gambel_gold_paid = false
		R.sync_state()
		R.toast(R.spin_name(spin))
		return
	end
	R.undo_table()
	MP.GAME.gambel_table = spin
	MP.GAME.gambel_wild = spin == "wild_odds"
	MP.GAME.gambel_gold_paid = false
	MP.GAME.gambel_applied_spin = spin
	MP.GAME.gambel_applied_ante = ante
	local delta = {}
	if spin == "double_interest" then
		if type(G.GAME.interest_amount) == "number" then
			delta.interest_amount = G.GAME.interest_amount
			G.GAME.interest_amount = G.GAME.interest_amount * 2
		end
		if type(G.GAME.interest_cap) == "number" then
			delta.interest_cap = G.GAME.interest_cap
			G.GAME.interest_cap = G.GAME.interest_cap * 2
		end
	elseif spin == "inflation" and type(G.GAME.inflation) == "number" then
		delta.inflation = 1
		G.GAME.inflation = G.GAME.inflation + 1
	elseif spin == "high_roller" then
		local hands, discards = bump_rounds(1, 1)
		delta.hands, delta.discards = hands, discards
	elseif spin == "slim_hands" then
		local hands = bump_rounds(-1, 0)
		delta.hands = hands
		R.apply_delta(5)
	end
	MP.GAME.gambel_spin_delta = delta
	R.sync_state()
	R.toast(R.spin_name(spin))
end

function R.on_new_round()
	if MP.GAME and G and G.GAME and G.GAME.round_resets then
		if MP.GAME.gambel_discard_armed then
			local n = tonumber(MP.GAME.gambel_discard_restore) or 1
			if type(G.GAME.round_resets.discards) == "number" then
				G.GAME.round_resets.discards = G.GAME.round_resets.discards + n
			end
			MP.GAME.gambel_discard_pending = false
			MP.GAME.gambel_discard_restore = nil
			MP.GAME.gambel_discard_armed = false
		elseif MP.GAME.gambel_discard_pending then
			-- This round is the one that plays with one fewer discard. The round after gives it back.
			MP.GAME.gambel_discard_armed = true
		end
	end
	if not (MP.GAME and R.active()) or MP.GAME.gambel_table ~= "golden_hour" or MP.GAME.gambel_gold_paid then return end
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

function R.joker_flags()
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
	local give, room = R.joker_flags()
	local ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
	local online = MP.STEAM_P2P and MP.LOBBY and MP.LOBBY.code and Client and Client.send
	if online then
		MP.GAME.gambel_bet_sent = true
		MP.GAME.gambel_bet_for = ante
		R.mirror_shop_used()
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
	{ foil = true, key = "k_gambel_foil", label = "Foil" },
	{ holo = true, key = "k_gambel_holo", label = "Holographic" },
	{ polychrome = true, key = "k_gambel_polychrome", label = "Polychrome" },
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
	MP.GAME = MP.GAME or {}
	if MP.GAME.gambel_discard_pending or MP.GAME.gambel_discard_armed then return end
	MP.GAME.gambel_discard_pending = true
	MP.GAME.gambel_discard_restore = 0
	if G and G.GAME and G.GAME.round_resets and type(G.GAME.round_resets.discards) == "number" then
		local before = G.GAME.round_resets.discards
		G.GAME.round_resets.discards = math.max(0, before - 1)
		MP.GAME.gambel_discard_restore = before - G.GAME.round_resets.discards
	end
	R.sync_state()
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
			return say(L(pick.key, pick.label))
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
		R.mirror_shop_used()
		if R.double_view and R.double_view.picked then R.finish_double(nil) end
		if R.wheel_view and R.wheel_view.spinning then R.finish_wheel(nil) end
		R.clear_shop()
		return
	end
	MP.GAME.gambel_bet_sent = true
	MP.GAME.gambel_bet_for = G and G.GAME and G.GAME.round_resets and tonumber(G.GAME.round_resets.ante) or MP.GAME.gambel_bet_for
	R.mirror_shop_used()
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
	elseif msg.id and not showing then
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
	-- Joker Pot moves cash only when a card did not change hands. Losers pay, the winner is paid.
	if msg.kind == "pot" and not msg.joker then
		local cash = tonumber(msg.amount) or 0
		if msg.role == "give" then R.apply_delta(-cash)
		elseif msg.role == "take" then R.apply_delta(cash) end
	end
	-- All-In doubles the boss reward for the winner only. A loss or a tie pays nothing.
	if msg.kind == "allin" and msg.role == "take" and G.GAME and G.GAME.blind and type(G.GAME.blind.dollars) == "number" then
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

--- The ante's bet is spent. Either flag is enough: the run copy can outlive a menu rebuild.
function R.shop_used()
	if MP.GAME and MP.GAME.gambel_bet_sent then return true end
	return (G and G.GAME and G.GAME.mp_gambel_shop_used) and true or false
end

function R.mirror_shop_used()
	if G and G.GAME then
		G.GAME.mp_gambel_shop_used = (MP.GAME and MP.GAME.gambel_bet_sent) and true or nil
	end
end

--- Shop click opens this. Backing out before Red or Black does not spend the ante's bet.
function R.can_double()
	if not R.active() or R.shop_used() then return false end
	return R.stake(dollars()) >= 1
end

function R.open_double()
	if R.double_view or R.shop_used() or not R.active() then return end
	if R.stake(dollars()) < 1 then
		R.toast(L("k_gambel_need_cash", "Need at least $2"))
		return
	end
	if R.wheel_view and not R.wheel_view.spinning then R.close_wheel() end
	if not (G and G.FUNCS and G.FUNCS.overlay_menu) then return end
	local stake = R.stake(dollars())
	R.double_view = {
		stake = stake, picked = false, show_close = false,
		result = "", outcome = nil, face = "back",
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
	local view = R.double_view
	local flip = view and view.flip
	if flip and not flip.done and flip.line and flip.line ~= "" then
		R.flash(flip.line)
	end
	R.drop_cards(view)
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
	local drawn = R.ace_name(suit)
	view.result = ""
	view.outcome = nil
	view.show_close = false
	view.flip = {
		t = 0, flip_dur = 0.70, hold_dur = 0.55, swapped = false, opened = false, done = false,
		suit = suit, key = key, drawn = drawn, line = line or "",
		outcome = R.outcome_from(msg, line),
	}
end

local function set_card_width(card, w)
	if not card then return end
	if card.VT then card.VT.w = w end
	if card.children then
		for _, part in pairs(card.children) do
			if type(part) == "table" and part.VT then part.VT.w = w end
		end
	end
end

function R.tick_double(dt)
	local view = R.double_view
	local flip = view and view.flip
	if not flip or flip.done then return end
	local turn = flip.flip_dur or 0.70
	local hold = flip.hold_dur or 0.55
	flip.t = math.min(turn + hold, (flip.t or 0) + (tonumber(dt) or 0))
	local card = view.card
	local full = card and card.T and card.T.w or 0
	-- pinch.x stays false. Moveable:move_wh shrinks the card whenever pinch.x is true,
	-- which fought the opening half and snapped the face into the payout.
	if card and card.pinch then card.pinch.x = false end
	if card and full > 0 then
		local span = 1
		if flip.t < turn * 0.5 then
			span = 1 - flip.t / (turn * 0.5)
		elseif flip.t < turn then
			span = (flip.t - turn * 0.5) / (turn * 0.5)
		end
		set_card_width(card, full * span)
	end
	if not flip.swapped and flip.t >= turn * 0.5 then
		flip.swapped = true
		view.face = "front"
		view.pip = "A"
		view.suit_mark = flip.suit
		local def = G and G.P_CARDS and G.P_CARDS[flip.key]
		if card and def then
			pcall(function()
				R.with_classic_suits(function()
					if card.set_base then card:set_base(def) end
					if card.set_sprites then card:set_sprites(nil, def) end
				end)
				R.force_classic_front(card, def)
				card.facing = "front"
				card.sprite_facing = "front"
				card.flipping = nil
				if card.pinch then card.pinch.x = false end
				if card.states then card.states.visible = true end
				R.mute_ace(card, view.area)
			end)
		end
		if play_sound then pcall(play_sound, "card1") end
	end
	if not flip.opened and flip.t >= turn then
		flip.opened = true
		if card and card.T then
			if card.pinch then card.pinch.x = false end
			set_card_width(card, card.T.w)
		end
	end
	if flip.t >= turn + hold then
		flip.done = true
		view.outcome = flip.outcome
		view.result = flip.line or ""
		view.show_close = true
		if card then
			card.facing = "front"
			card.sprite_facing = "front"
			if card.pinch then card.pinch.x = false end
			R.mute_ace(card, view.area)
		end
		view.flip = nil
		if flip.line and flip.line ~= "" then R.toast(flip.line) end
		-- Rebuild once. Hiding a sibling row leaves a blank gap in Balatro's UIBox.
		R.reshow_double()
	end
end

function R.tick(dt)
	R.tick_double(dt)
	R.tick_wheel(dt)
end

function R.outcome_from(msg, line)
	if msg and msg.won == true then return "win" end
	if msg and msg.won == false then return "loss" end
	if type(line) == "string" then
		if line:sub(1, 1) == "+" then return "win" end
		if line:sub(1, 1) == "-" then return "loss" end
	end
	return "house"
end

function R.finish_double(line)
	local view = R.double_view
	if not view then return end
	view.flip = nil
	view.result = line or L("k_gambel_house", "The House holds")
	view.outcome = (line == nil) and "house" or R.outcome_from(nil, line)
	view.show_close = true
	R.reshow_double()
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

--- The Ace is a prop. Hover must not open the chips/mult card tooltip.
function R.mute_ace(card, area)
	if area and area.states and area.states.hover then area.states.hover.can = false end
	if not card then return end
	card.no_ui = true
	if card.states then
		if card.states.hover then card.states.hover.can = false end
		if card.states.drag then card.states.drag.can = false end
		if card.states.click then card.states.click.can = false end
	end
	card.hover = function() end
	if card.config then card.config.h_popup = nil end
	if card.children and card.children.h_popup then
		pcall(function() card.children.h_popup:remove() end)
		card.children.h_popup = nil
	end
end

--- High Contrast uses cards_2 (orange diamonds, blue clubs). The Ace stays on classic cards_1.
function R.with_classic_suits(fn)
	local settings = G and G.SETTINGS
	local prev = settings and settings.colourblind_option
	if settings then settings.colourblind_option = false end
	local ok, err = pcall(fn)
	if settings then settings.colourblind_option = prev end
	if not ok then error(err, 0) end
end

function R.force_classic_front(card, def)
	if not (card and card.children and card.children.front and G and G.ASSET_ATLAS and G.ASSET_ATLAS.cards_1) then return end
	local front = card.children.front
	front.atlas = G.ASSET_ATLAS.cards_1
	if def and def.pos and front.set_sprite_pos then front:set_sprite_pos(def.pos) end
end

--- Face down until reveal_double. emplace flips a face-down card up unless stay_flipped is set.
function R.make_double_card(view)
	if view and view.card and not view.card.REMOVED and view.area and not view.area.REMOVED then
		if view.face == "front" then R.hold_ace(view) else R.mute_ace(view.card, view.area) end
		return view.card
	end
	if not (view and Card and CardArea and G and G.P_CARDS and G.P_CENTERS and G.P_CENTERS.c_base and G.CARD_W and G.CARD_H) then
		return nil
	end
	local card, area
	local ok = pcall(function()
		area = CardArea(0, 0, G.CARD_W * 1.5, G.CARD_H * 1.35, {
			card_limit = 1, type = "title_2", highlight_limit = 0, card_w = G.CARD_W * 0.95,
		})
		local hidden = G.P_CARDS.H_A or G.P_CARDS["H_A"]
		R.with_classic_suits(function()
			card = Card(0, 0, G.CARD_W * 0.95, G.CARD_H * 0.95, hidden, G.P_CENTERS.c_base)
		end)
		R.force_classic_front(card, hidden)
		card.facing = "back"
		card.sprite_facing = "back"
		card.flipping = nil
		if card.pinch then card.pinch.x = false end
		if card.states then card.states.visible = true end
		area:emplace(card, nil, true)
		card.facing = "back"
		card.sprite_facing = "back"
		card.flipping = nil
		if card.pinch then card.pinch.x = false end
		if card.T and card.children and card.children.back and card.children.back.VT then
			card.children.back.VT.w = card.T.w
			card.children.back.VT.h = card.T.h
		end
		R.mute_ace(card, area)
	end)
	if not ok or not area or not card then
		if area and area.remove then pcall(function() area:remove() end) end
		if card and card.remove and not card.REMOVED then pcall(function() card:remove() end) end
		return nil
	end
	view.area, view.card = area, card
	if view.face == "front" then R.hold_ace(view) else view.face = "back" end
	return card
end

--- The revealed Ace is shown face up. Hover stays muted, and pinch stays off so the width holds.
function R.hold_ace(view)
	local card = view and view.card
	if not card or card.REMOVED then return end
	if view.face == "front" then
		card.facing = "front"
		card.sprite_facing = "front"
		card.flipping = nil
		if card.pinch then card.pinch.x = false end
		if card.states then card.states.visible = true end
		local key = (view.suit_mark and view.suit_mark ~= "") and (view.suit_mark .. "_A") or nil
		local def = key and G and G.P_CARDS and G.P_CARDS[key]
		if def then
			pcall(function()
				R.with_classic_suits(function()
					if card.set_base then card:set_base(def) end
					if card.set_sprites then card:set_sprites(nil, def) end
				end)
				R.force_classic_front(card, def)
				card.facing = "front"
				card.sprite_facing = "front"
				if card.pinch then card.pinch.x = false end
			end)
		end
	end
	R.mute_ace(card, view.area)
end

local function ace_node()
	local view = R.double_view
	view.face = view.face or "back"
	view.pip = view.pip or "?"
	view.suit_mark = view.suit_mark or ""
	local card = R.make_double_card(view)
	local cw = (G and G.CARD_W) or 1
	local ch = (G and G.CARD_H) or 1
	local row = (not card or not view.area) and ace_fallback(view)
		or { n = G.UIT.R, config = { align = "cm", minw = cw * 1.6, minh = ch * 1.45 }, nodes = {
			{ n = G.UIT.O, config = { object = view.area } },
		} }
	return { n = G.UIT.C, config = { align = "cm", minw = 2.4, minh = 3.15 }, nodes = { row } }
end

local FELT = { 0.05, 0.22, 0.14, 1 }
local CRIMSON = { 0.62, 0.10, 0.14, 1 }
local GOLD_INK = { 0.96, 0.80, 0.32, 1 }
local WIN_BAR = { 0.96, 0.62, 0.08, 1 }
local HOUSE_BAR = { 0.16, 0.17, 0.22, 1 }
local STAKE_FILL = { 0.07, 0.09, 0.14, 1 }
local STAKE_RIM = { 0.95, 0.74, 0.28, 1 }

--- Shared card-table frame: green felt, crimson title, gold lettering, Balatro emboss.
local function ink(c) return { c[1], c[2], c[3], c[4] } end

function R.casino_frame(title, minw, nodes, opts)
	opts = opts or {}
	local body = {}
	if opts.promo then
		local head, tail = tostring(title or ""), nil
		local at = head:lower():find(" or ", 1, true)
		if at then
			tail = head:sub(at + 1):upper()
			head = head:sub(1, at - 1):upper()
		end
		body[#body + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.01 }, nodes = {
			{ n = G.UIT.T, config = { text = head, scale = 0.64, colour = ink(GOLD_INK), shadow = true } },
		} }
		if tail then
			body[#body + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.01 }, nodes = {
				{ n = G.UIT.T, config = { text = tail, scale = 0.56, colour = G.C.WHITE, shadow = true } },
			} }
		end
	else
		body[#body + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.07, r = 0.08, colour = ink(CRIMSON), minw = (minw or 7.2) - 0.5 }, nodes = {
			{ n = G.UIT.T, config = { text = title, scale = 0.46, colour = ink(GOLD_INK), shadow = true } },
		} }
	end
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

function R.payout_line(view)
	view = view or {}
	local stake = tostring(view.stake or 0)
	if view.outcome == "win" then return L("k_gambel_win", "WIN +$") .. stake, ink(WIN_BAR) end
	if view.outcome == "loss" then return L("k_gambel_lose", "LOSE -$") .. stake, (G and G.C and G.C.RED) or { 0.86, 0.16, 0.18, 1 } end
	local text = view.result
	if type(text) ~= "string" or text == "" then text = L("k_gambel_house", "The House holds") end
	return text, ink(HOUSE_BAR)
end

--- The live menu owns the Ace. Unhook it before overlay_menu removes that menu.
local function detach_ace(view)
	local area = view and view.area
	if not area then return end
	local seen = {}
	local function walk(node)
		if type(node) ~= "table" or node == area or seen[node] then return end
		seen[node] = true
		if node.config and node.config.object == area then node.config.object = nil end
		if node.children then
			for k, child in pairs(node.children) do
				if child == area then node.children[k] = nil else walk(child) end
			end
		end
		if node.nodes then
			for _, child in pairs(node.nodes) do walk(child) end
		end
		if node.UIRoot then walk(node.UIRoot) end
	end
	if G and G.OVERLAY_MENU then walk(G.OVERLAY_MENU) end
	local parent = area.parent
	if type(parent) == "table" and type(parent.children) == "table" then
		for k, child in pairs(parent.children) do
			if child == area then parent.children[k] = nil end
		end
	end
	area.parent = nil
	if area.role then area.role.major = nil end
end

--- Rebuild the modal once the hold ends, keeping the Ace that is already face up.
function R.reshow_double()
	local view = R.double_view
	if not (view and G and G.OVERLAY_MENU and G.FUNCS and G.FUNCS.overlay_menu) then return end
	if view.face == "front" then R.hold_ace(view) end
	local area, card = view.area, view.card
	local area_remove = area and area.remove
	local card_remove = card and card.remove
	if area then area.remove = function() end end
	if card then card.remove = function() end end
	detach_ace(view)
	local shown = pcall(function()
		G.FUNCS.overlay_menu({ definition = R.double_definition() })
	end)
	if area then area.remove = area_remove end
	if card then card.remove = card_remove end
	if not shown and G.FUNCS.exit_overlay_menu and G.OVERLAY_MENU then
		pcall(function() G.FUNCS.exit_overlay_menu() end)
	end
end

function R.double_definition()
	local view = R.double_view or { stake = 0, result = "", show_close = false }
	local stake = tostring(view.stake or 0)
	local nodes = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { text = L("k_gambel_ace_ask", "RED OR BLACK ACE?"), scale = 0.36, colour = G.C.WHITE, shadow = true } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = {
			{ n = G.UIT.C, config = {
				id = "mp_gambel_stake", align = "cm", padding = 0.08, minw = 3.4, minh = 0.48,
				r = 0.12, colour = ink(STAKE_FILL), emboss = 0.08, outline = 1.5, outline_colour = ink(STAKE_RIM),
			}, nodes = {
				{ n = G.UIT.T, config = { text = L("k_gambel_stake", "STAKE: $") .. stake, scale = 0.38, colour = ink(GOLD_INK), shadow = true } },
			} },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { ace_node() } },
	}
	if view.show_close then
		local label, bar = R.payout_line(view)
		local edge = view.outcome == "loss" and { 1, 0.72, 0.7, 1 }
			or (view.outcome == "win" and { 1, 0.88, 0.55, 1 } or { 0.45, 0.48, 0.55, 1 })
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
			{ n = G.UIT.C, config = {
				id = "mp_gambel_result", align = "cm", padding = 0.1, minw = 5.6, minh = 0.76,
				r = 0.14, colour = bar, emboss = 0.1, outline = 2, outline_colour = edge,
			}, nodes = {
				{ n = G.UIT.T, config = { text = label, scale = 0.52, colour = G.C.WHITE, shadow = true } },
			} },
		} }
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.03, maxw = 6.6 }, nodes = {
			{ n = G.UIT.T, config = { text = L("k_gambel_half", "BET HALF YOUR CASH - WIN IT OR LOSE IT"), scale = 0.26, colour = G.C.WHITE, shadow = true } },
		} }
		nodes[#nodes + 1] = { n = G.UIT.R, config = { id = "mp_gambel_continue", align = "cm", padding = 0.06 }, nodes = {
			casino_btn("mp_gambel_continue", "mp_gambel_double_close", L("b_gambel_continue", "Continue"), G.C.BLUE, 2.4),
		} }
	else
		nodes[#nodes + 1] = { n = G.UIT.R, config = { id = "mp_gambel_choices", align = "cm", padding = 0.06 }, nodes = {
			casino_btn("mp_gambel_red", "mp_gambel_pick_red", L("b_gambel_red", "Red Ace"), G.C.RED, 2.2),
			casino_btn("mp_gambel_black", "mp_gambel_pick_black", L("b_gambel_black", "Black Ace"), G.C.BLACK, 2.2),
			casino_btn("mp_gambel_back", "mp_gambel_double_back", L("b_gambel_back", "Back"), G.C.GREY, 1.6),
		} }
	end
	return R.casino_frame(L("b_gambel_double", "Double or Nothing"), 7.2, nodes, { promo = true })
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
			local radius = (half - 0.88) * ts
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
			local bulbs = 28
			local now = 0
			if love.timer and love.timer.getTime then
				local ok_t, t = pcall(love.timer.getTime)
				if ok_t and type(t) == "number" then now = t end
			end
			local won = view and view.landed
			local chase = math.floor(now * (won and 18 or 10))
			local pulse = won and (0.55 + 0.45 * math.abs(math.sin(now * 16))) or 1
			local bulb_at = rim + 0.09 * ts
			for b = 0, bulbs - 1 do
				local a = -math.pi / 2 + b * (2 * math.pi / bulbs)
				local bx, by = math.cos(a) * bulb_at, math.sin(a) * bulb_at
				local lit = won or ((b + chase) % 3 == 0)
				if lit then
					g.setColor(1, 0.82, 0.35, 0.3 * pulse)
					g.circle("fill", bx, by, 0.07 * ts)
					g.setColor(1, 0.98, 0.84, 1 * pulse)
					g.circle("fill", bx, by, 0.038 * ts)
					g.setColor(1, 1, 1, pulse)
					g.circle("fill", bx - 0.01 * ts, by - 0.01 * ts, 0.012 * ts)
				else
					g.setColor(0.22, 0.12, 0.04, 1)
					g.circle("fill", bx, by, 0.042 * ts)
					g.setColor(0.42, 0.24, 0.08, 1)
					g.circle("fill", bx, by, 0.032 * ts)
				end
			end
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
			-- Love2D y grows downward. The sharp tip sits on the rim; the wide base is above it.
			local tip = -(rim + 0.02 * ts)
			local base = tip - 0.28 * ts
			g.setColor(0.75, 0.62, 0.2, 1)
			g.polygon("fill", 0, tip, -0.16 * ts, base, 0.16 * ts, base)
			g.setColor(CRIMSON[1], CRIMSON[2], CRIMSON[3], 1)
			g.polygon("fill", 0, tip + 0.04 * ts, -0.11 * ts, base + 0.04 * ts, 0.11 * ts, base + 0.04 * ts)
			g.setColor(1, 0.85, 0.85, 1)
			g.polygon("fill", 0, tip + 0.02 * ts, -0.035 * ts, tip - 0.08 * ts, 0.035 * ts, tip - 0.08 * ts)
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
	return { n = G.UIT.C, config = { align = "tm", padding = 0.1, r = 0.08, minw = 2.7, colour = { 0.03, 0.08, 0.06, 0.45 }, emboss = 0.05 }, nodes = rows }
end

function R.can_wheel()
	return R.active() and not R.shop_used()
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
	local current = tonumber(view.angle) or 0
	local dest = R.wheel_rotation(view.index, 4)
	-- The wheel is already turning while the host answers. Keep that angle; do not snap it back to 0.
	if view.spinning and current ~= 0 then
		local land = R.wheel_rotation(view.index, 0)
		dest = land - 4 * 2 * math.pi
		while dest > current - (2 * math.pi) do dest = dest - 2 * math.pi end
		view.start_angle = current
	else
		view.start_angle = 0
	end
	view.target_angle = dest
	view.pending_label = label
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
	local from = view.start_angle or 0
	view.angle = from + (view.target_angle - from) * R.wheel_ease(view.t)
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
	return R.casino_frame(L("b_gambel_wheel", "Gambel Wheel"), 13.0, {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = {
			{ n = G.UIT.T, config = { ref_table = view, ref_value = "prompt", scale = 0.32, colour = G.C.WHITE } },
		} },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = {
			wheel_face(),
			{ n = G.UIT.C, config = { align = "cm", minw = 1.25 } },
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
end

-- Compact enough that the booster OPEN tag stays on screen. Vanilla shop is top-anchored,
-- so this row's height is also how far G.shop must move up (R.shop_row_height).
local SHOP_ROW_PAD = 0.05
local SHOP_BTN_PAD = 0.04
local SHOP_BTN_H = 0.56

function R.shop_row_height()
	return SHOP_ROW_PAD * 2 + SHOP_BTN_PAD * 2 + SHOP_BTN_H
end

--- Vanilla Game:update_shop and the pack-return paths set this. A more negative value moves the shop up.
R.SHOP_VANILLA_Y = -5.3

function R.shop_offset_y()
	if not R.active() then return R.SHOP_VANILLA_Y end
	return R.SHOP_VANILLA_Y - R.shop_row_height()
end

--- If a shop open or a pack return just wrote the vanilla -5.3, lift by the gambel row.
--- Any other y (the pack sliding the shop off screen) is left alone. py is the value
--- toggle_shop copies back, so it has to be lifted too or the shop snaps down on return.
function R.place_shop()
	if not R.active() then return end
	local off = G and G.shop and G.shop.alignment and G.shop.alignment.offset
	if type(off) ~= "table" then return end
	local want = R.shop_offset_y()
	local vanilla = R.SHOP_VANILLA_Y
	if type(off.y) == "number" and math.abs(off.y - vanilla) < 1e-4 then off.y = want end
	if type(off.py) == "number" and math.abs(off.py - vanilla) < 1e-4 then off.py = want end
end

function R.queue_shop_place()
	R.place_shop()
	if not (G and G.E_MANAGER and G.E_MANAGER.add_event and Event) then return end
	G.E_MANAGER:add_event(Event({
		trigger = "immediate",
		blockable = false,
		func = function()
			if MP.GAMBEL and MP.GAMBEL.place_shop then MP.GAMBEL.place_shop() end
			return true
		end,
	}))
end

local function shop_button(id, click, update, label, colour, enabled)
	return { n = G.UIT.C, config = { align = "cm", padding = SHOP_BTN_PAD }, nodes = {
		UIBox_button({
			id = id,
			button = enabled and click or nil,
			func = update,
			label = { label },
			minw = 3.6,
			minh = SHOP_BTN_H,
			scale = 0.36,
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
	R.mirror_shop_used()
end

function R.shop_row()
	R.sync_bet_ante()
	MP.GAME.gambel_shop_note = MP.GAME.gambel_shop_note or ""
	return { n = G.UIT.R, config = { align = "cm", padding = SHOP_ROW_PAD, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
		shop_button("mp_gambel_double", "mp_gambel_double", "mp_gambel_double_btn", L("b_gambel_double", "Double or Nothing"), G.C.ORANGE, R.can_double()),
		shop_button("mp_gambel_wheel", "mp_gambel_wheel", "mp_gambel_wheel_btn", L("b_gambel_wheel", "Gambel Wheel"), G.C.PURPLE, R.can_wheel()),
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
	R.sync_bet_ante()
	-- A leftover overlay from the previous run must not block the first shop.
	if not (G and G.OVERLAY_MENU) then
		if R.double_view then R.drop_cards(R.double_view) end
		R.double_view = nil
		R.wheel_view = nil
	end
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
			local in_lobby = (MP.LOBBY and MP.LOBBY.code ~= nil) and true or false
			local stage = (G and G.STAGES and G.STATES and G.STAGE == G.STAGES.RUN and G.STATE ~= G.STATES.MENU) and "run" or "menu"
			local spec = MP.SPECTATE
			local seated = spec and spec.state and (spec.state.active or spec.state.joined)
			local watching = in_lobby and (seated or (stage == "run" and spec and spec.watching and spec.watching()))
			return R.music_priority({
				mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode,
				in_lobby = in_lobby,
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
	function G.FUNCS.mp_gambel_double_btn(e)
		if not (e and e.config and MP.GAMBEL) then return end
		if MP.GAMBEL.can_double() then
			e.config.colour = G.C.ORANGE
			e.config.button = "mp_gambel_double"
		else
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		end
	end
	function G.FUNCS.mp_gambel_wheel_btn(e)
		if not (e and e.config and MP.GAMBEL) then return end
		if MP.GAMBEL.can_wheel() then
			e.config.colour = G.C.PURPLE
			e.config.button = "mp_gambel_wheel"
		else
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		end
	end
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
				if view.flip and not view.flip.done and view.flip.line and view.flip.line ~= "" then
					MP.GAMBEL.flash(view.flip.line)
				end
				MP.GAMBEL.drop_cards(view)
				MP.GAMBEL.double_view = nil
			end
			MP.GAMBEL.tick(dt)
			if G.STATE == G.STATES.SHOP and MP.GAMBEL.place_shop then MP.GAMBEL.place_shop() end
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
