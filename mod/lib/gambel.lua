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

function R.bet(kind)
	if not R.active() or MP.GAME.gambel_bet_sent then return end
	if kind ~= "wheel" and kind ~= "double" then return end
	local money = dollars()
	if kind == "double" and money < 2 then return end
	local give, room = joker_flags()
	local ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
	local online = MP.STEAM_P2P and MP.LOBBY and MP.LOBBY.code and Client and Client.send
	if online then
		MP.GAME.gambel_bet_sent = true
		Client.send({ action = "gambelBet", kind = kind, money = money, ante = ante, give = give, room = room })
		R.clear_shop()
		return
	end
	local seed = (G and G.GAME and (G.GAME.pseudorandom_seed or G.GAME.seed)) or "house"
	local id = (MP.LOBBY and MP.LOBBY.my_id) or "solo"
	local res = kind == "wheel" and R.wheel(seed, id, ante, money) or R.flip(seed, id, ante, money)
	res.kind = kind
	R.apply_bet(res)
	R.clear_shop()
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

function R.play_wheel(msg)
	local plan = R.prize_plan(msg.id, {
		plain_joker = plain_joker() ~= nil,
		mortal_joker = mortal_joker() ~= nil,
		amount = msg.amount or msg.delta,
	})
	local seed = (G and G.GAME and (G.GAME.pseudorandom_seed or G.GAME.seed)) or "house"
	local ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1
	if plan.kind == "cash" then
		if msg.id ~= "cash" then R.apply_delta(plan.amount or 0) end
	R.flash("+$" .. tostring(plan.amount or msg.amount or 0))
	elseif plan.kind == "tax" then
		if msg.id ~= "tax" then R.apply_delta(-(plan.amount or 4)) end
		R.flash("-$" .. tostring(plan.amount or 4))
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
			R.flash(pick.label)
		else
			R.apply_delta(8)
			R.flash("+$8")
		end
	elseif plan.kind == "tag" then
		local key = WHEEL_TAGS[R.roll(seed, ante, "tag", #WHEEL_TAGS)]
		if add_tag and Tag and key then pcall(function() add_tag(Tag(key)) end) end
		R.flash(L("k_gambel_tag", "Tag"))
	elseif plan.kind == "discard" then
		R.arm_discard()
		R.flash(L("k_gambel_discard", "-1 discard next round"))
	elseif plan.kind == "perish" then
		local card = mortal_joker()
		local stuck = false
		if card and card.set_perishable then
			stuck = pcall(function() card:set_perishable(true) end)
		end
		if stuck then R.flash(L("k_gambel_perish", "Perishable"))
		else
			R.apply_delta(-math.min(4, dollars()))
			R.flash("-$4")
		end
	end
end

function R.apply_bet(msg)
	MP.GAME.gambel_bet_sent = false
	if not msg or msg.ok == false then
		if msg and msg.reason == "once" then MP.GAME.gambel_bet_sent = true end
		R.clear_shop()
		return
	end
	MP.GAME.gambel_bet_sent = true
	if msg.kind == "double" or msg.id == "cash" or msg.id == "tax" or msg.won ~= nil then
		R.apply_delta(msg.delta)
	end
	if msg.won == true then R.flash(L("b_gambel_double", "Double or Nothing") .. " +$" .. tostring(msg.stake or ""))
	elseif msg.won == false then R.flash(L("k_gambel_house", "The House holds") .. " -$" .. tostring(msg.stake or ""))
	elseif msg.id then R.play_wheel(msg) end
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
function R.shop_row()
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
		MP.GAMBEL.bet("double")
		if e and e.config then e.config.button = nil; e.config.colour = G.C.UI.BACKGROUND_INACTIVE end
	end
	function G.FUNCS.mp_gambel_wheel(e)
		if not MP.GAMBEL then return end
		MP.GAMBEL.bet("wheel")
		if e and e.config then e.config.button = nil; e.config.colour = G.C.UI.BACKGROUND_INACTIVE end
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
		end
		return r
	end
end

R.register_ui()
