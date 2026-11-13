-- Small helpers shared by the Steamodded 26.829/26.1002 compatibility path and the
-- v1.0.5 bugfixes that apply to this fork. Pure enough to unit test.
MP.UTILS = MP.UTILS or {}

-- A shop spend from another player. A finite amount above the cap counts as the cap.
-- Anything that is not a finite number from 0 up counts as 0.
MP.UTILS.SHOP_SPEND_CAP = 1000000
function MP.UTILS.shop_spend(amount)
	local spent = tonumber(amount)
	if not spent or spent ~= spent or spent < 0 or spent == math.huge then return 0 end
	if spent > MP.UTILS.SHOP_SPEND_CAP then return MP.UTILS.SHOP_SPEND_CAP end
	return spent
end

-- How many new skips an enemyInfo should act on. A jump of more than one is a rejoin
-- sending the lifetime total, not that many new skips.
function MP.UTILS.live_skip_count(prev, skips)
	prev = tonumber(prev) or 0
	skips = tonumber(skips)
	if not skips or skips - prev ~= 1 then return 0 end
	return 1
end

-- True when this card is the opponent's (a phantom copy, or their jokers on the end screen).
function MP.UTILS.opponent_odds(trigger_obj)
	if type(trigger_obj) ~= "table" or trigger_obj.ability == nil then return false end
	if trigger_obj.edition and trigger_obj.edition.type == "mp_phantom" then return true end
	if MP.end_game_jokers and trigger_obj.area == MP.end_game_jokers then return true end
	return false
end

-- Keep this player's Oops! All 6s off the opponent's shown odds.
function MP.UTILS.wrap_probability_vars(get_vars)
	return function(trigger_obj, base_numerator, base_denominator, identifier, from_roll, no_mod)
		local bare = MP.UTILS.opponent_odds(trigger_obj)
		local n, d = get_vars(trigger_obj, base_numerator, base_denominator, identifier, from_roll, no_mod or bare or nil)
		if not bare and MP.GAME and MP.GAME.gambel_wild and type(n) == "number" and type(d) == "number" and d > 0 then
			n = math.min(d, n * 2)
		end
		return n, d
	end
end

-- Pressing Play twice on the same hand must not send two scores.
function MP.UTILS.duplicate_play(last, score, hands)
	return type(last) == "table" and last.score == score and last.hands == hands
end
