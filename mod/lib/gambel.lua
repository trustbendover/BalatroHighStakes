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
	local boss = (G and G.GAME and G.GAME.blind_on_deck == "Boss") or tostring(key or ""):find("nemesis", 1, true)
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
	MP.GAME.gambel_bet_sent = true
	local give, room = joker_flags()
	if Client and Client.send then
		Client.send({
			action = "gambelBet",
			kind = kind,
			money = dollars(),
			ante = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 1,
			give = give,
			room = room,
		})
	end
end

function R.apply_bet(msg)
	MP.GAME.gambel_bet_sent = false
	if not msg or msg.ok == false then
		if msg and msg.reason == "once" then MP.GAME.gambel_bet_sent = true end
		return
	end
	MP.GAME.gambel_bet_sent = true
	R.apply_delta(msg.delta)
	if msg.id == "discard" and ease_discard then pcall(ease_discard, -1) end
	if msg.won == true then R.toast("Double or Nothing")
	elseif msg.won == false then R.toast(L("k_gambel_house", "The House holds"))
	elseif msg.id then R.toast(tostring(msg.id)) end
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

function R.on_shop()
	if not R.active() or not (UIBox and G and G.UIT and G.ROOM_ATTACH) then return end
	if G.STATES and G.STATE ~= G.STATES.SHOP then
		MP.GAME.gambel_shop_box = nil
		return
	end
	if MP.GAME.gambel_shop_box then return end
	local ok, box = pcall(function()
		return UIBox({
			definition = {
				n = G.UIT.ROOT,
				config = { align = "cm", colour = G.C.CLEAR, padding = 0.1 },
				nodes = {
					UIBox_button({
						id = "mp_gambel_double", button = "mp_gambel_double",
						label = { L("b_gambel_double", "Double or Nothing") },
						minw = 2.4, minh = 0.5, scale = 0.3, col = true, colour = G.C.ORANGE,
					}),
					UIBox_button({
						id = "mp_gambel_wheel", button = "mp_gambel_wheel",
						label = { L("b_gambel_wheel", "Gambel Wheel") },
						minw = 2.4, minh = 0.5, scale = 0.3, col = true, colour = G.C.PURPLE,
					}),
				},
			},
			config = { align = "cr", offset = { x = -0.4, y = 1.2 }, major = G.ROOM_ATTACH },
		})
	end)
	if ok then MP.GAME.gambel_shop_box = box end
end

function R.register_music()
	if not (SMODS and SMODS.Sound and NFS and NFS.getInfo and MP.path) then return end
	if not NFS.getInfo(MP.path .. "/assets/sounds/music_gambel_time.ogg") then return end
	SMODS.Sound({
		key = "music_gambel_time",
		path = "music_gambel_time.ogg",
		sync = false,
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

if G and G.FUNCS then
	function G.FUNCS.mp_gambel_double() if MP.GAMBEL then MP.GAMBEL.bet("double") end end
	function G.FUNCS.mp_gambel_wheel() if MP.GAMBEL then MP.GAMBEL.bet("wheel") end end
end
