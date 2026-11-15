-- Compact, read-only view of one player's table.
-- The followed client builds a snapshot. The host relays it only to people who
-- are watching that player (spectators and eliminated players). Active opponents
-- are never on the recipient list.
local P = {}

P.MIN_GAP = 0.4
P.HEARTBEAT = 2.0
P.MAX = { hand = 12, jokers = 10, cons = 5, played = 8, shop = 6 }
P.PHASES = { select = true, play = true, shop = true, round = true, pack = true, idle = true, gone = true }

function P.edition(card)
	local e = type(card) == "table" and card.edition or nil
	if type(e) ~= "table" then return "" end
	if e.negative then return "neg" end
	if e.polychrome then return "poly" end
	if e.holo then return "holo" end
	if e.foil then return "foil" end
	return ""
end

function P.sticker(card)
	local a = type(card) == "table" and card.ability or nil
	if type(a) ~= "table" then return "" end
	if a.eternal then return "eternal" end
	if a.perishable then return "perish" end
	if a.rental then return "rental" end
	return ""
end

function P.card(card)
	if type(card) ~= "table" then return nil end
	local base = type(card.base) == "table" and card.base or nil
	local center = type(card.config) == "table" and type(card.config.center) == "table" and card.config.center or nil
	local rank = (base and base.value) or card.rank or card.r or ""
	local suit = (base and base.suit) or card.suit or card.s or ""
	local key = (center and center.key) or card.key or card.k or ""
	local cost = tonumber(card.cost)
	return {
		k = tostring(key) ~= "" and tostring(key):sub(1, 40) or nil,
		r = tostring(rank) ~= "" and tostring(rank):sub(1, 4) or nil,
		s = tostring(suit) ~= "" and tostring(suit):sub(1, 1) or nil,
		e = P.edition(card) ~= "" and P.edition(card) or (type(card.e) == "string" and card.e:sub(1, 8) or ""),
		st = P.sticker(card) ~= "" and P.sticker(card) or (type(card.st) == "string" and card.st:sub(1, 8) or ""),
		cost = cost and math.floor(cost) or nil,
	}
end

function P.list(cards, n)
	local out = {}
	if type(cards) ~= "table" then return out end
	local limit = math.min(tonumber(n) or 8, #cards)
	for i = 1, limit do
		local c = P.card(cards[i])
		if c then out[#out + 1] = c end
	end
	return out
end

--- Balatro G.STATE numbers, or a phase name already chosen by the caller.
function P.phase(g, states)
	g = g or {}
	if type(g.phase) == "string" and P.PHASES[g.phase] then return g.phase end
	local s, st = g.state, states or g.states or {}
	if s == st.SHOP or s == "shop" then return "shop" end
	if s == st.BLIND_SELECT or s == "select" or s == "blind_select" then return "select" end
	if s == st.SELECTING_HAND or s == st.HAND_PLAYED or s == st.DRAW_TO_HAND or s == "play" then return "play" end
	if s == st.ROUND_EVAL or s == st.NEW_ROUND or s == "round" then return "round" end
	if s == st.PLAY_TAROT or s == st.TAROT_PACK or s == st.PLANET_PACK or s == st.SPECTRAL_PACK
		or s == st.STANDARD_PACK or s == st.BUFFOON_PACK or s == "pack" then return "pack" end
	return "idle"
end

function P.capture(g)
	g = g or {}
	local phase = P.phase(g)
	local snap = {
		phase = phase,
		ante = math.max(1, math.floor(tonumber(g.ante) or 1)),
		blind = tostring(g.blind or ""):sub(1, 32),
		money = math.floor(tonumber(g.money) or 0),
		hands = math.max(0, math.floor(tonumber(g.hands) or 0)),
		discards = math.max(0, math.floor(tonumber(g.discards) or 0)),
		score = tostring(g.score or "0"):sub(1, 24),
		chips = tostring(g.chips or "0"):sub(1, 24),
		mult = tostring(g.mult or "0"):sub(1, 24),
		hand = P.list(g.hand, P.MAX.hand),
		jokers = P.list(g.jokers, P.MAX.jokers),
		cons = P.list(g.cons, P.MAX.cons),
		played = P.list(g.played, P.MAX.played),
	}
	if phase == "shop" then snap.shop = P.list(g.shop, P.MAX.shop) end
	snap.sig = P.signature(snap)
	return snap
end

local function piece(card)
	local extra = ""
	if card.e and card.e ~= "" then extra = extra .. " " .. card.e end
	if card.st and card.st ~= "" then extra = extra .. " " .. card.st end
	if card.r and card.r ~= "" then return tostring(card.r) .. tostring(card.s or "") .. extra end
	local k = tostring(card.k or "?"):gsub("^j_", ""):gsub("^c_", ""):gsub("_", " ")
	if card.cost then k = k .. " $" .. tostring(card.cost) end
	return k .. extra
end

local function join_cards(list, n)
	local bits, shown = {}, math.min(n or 8, #(list or {}))
	for i = 1, shown do bits[#bits + 1] = piece(list[i]) end
	if #(list or {}) > shown then bits[#bits + 1] = "+" .. (#list - shown) end
	if #bits == 0 then return "-" end
	return table.concat(bits, "  ")
end

function P.signature(snap)
	snap = snap or {}
	return table.concat({
		tostring(snap.phase), tostring(snap.ante), tostring(snap.blind), tostring(snap.money),
		tostring(snap.hands), tostring(snap.discards), tostring(snap.score), tostring(snap.chips), tostring(snap.mult),
		join_cards(snap.hand, 12), join_cards(snap.jokers, 10), join_cards(snap.cons, 5),
		join_cards(snap.played, 8), join_cards(snap.shop, 6),
	}, "|")
end

--- True when a snapshot is worth sending. Identical boards wait for the heartbeat.
--- A gap shorter than MIN_GAP is never sent, so a modified client cannot flood the relay.
function P.due(prev_sig, sig, now, last)
	now, last = tonumber(now) or 0, tonumber(last) or 0
	if last > 0 and now - last < P.MIN_GAP then return false end
	if sig ~= prev_sig then return true end
	if last == 0 or now - last >= P.HEARTBEAT then return true end
	return false
end

function P.subscribers(watch, target)
	local ids = {}
	for sid, tid in pairs(watch or {}) do
		if tid == target and sid ~= target then ids[#ids + 1] = sid end
	end
	table.sort(ids)
	return ids
end

--- Active opponents are omitted even if a bad client put them in the watch map.
function P.recipients(players, watch, target)
	local allow = {}
	for _, id in ipairs(P.subscribers(watch, target)) do allow[id] = true end
	local out = {}
	for _, p in ipairs(players or {}) do
		if type(p) == "table" and allow[p.id] and (p.spectator or p.eliminated) then
			out[#out + 1] = p.id
		end
	end
	return out
end

function P.wanted(watch, target)
	if not target or target == "" then return false end
	for _, tid in pairs(watch or {}) do if tid == target then return true end end
	return false
end

local PHASE_LABEL = {
	select = "Blind select", play = "Playing", shop = "Shop", round = "Scoring",
	pack = "Pack", idle = "Between", gone = "Gone",
}

function P.lines(snap)
	snap = snap or {}
	local phase = PHASE_LABEL[snap.phase] or "Waiting"
	local blind = snap.blind and snap.blind ~= "" and snap.blind or ""
	return {
		string.format("%s   ante %s   %s", phase, tostring(snap.ante or "-"), blind),
		string.format("$%s   hands %s   discards %s", tostring(snap.money or 0), tostring(snap.hands or 0), tostring(snap.discards or 0)),
		string.format("Score %s    %s x %s", tostring(snap.score or "0"), tostring(snap.chips or "0"), tostring(snap.mult or "0")),
		"Hand  " .. join_cards(snap.hand, 8),
		"Jokers  " .. join_cards(snap.jokers, 6),
		"Played  " .. join_cards(snap.played, 6) .. "   Cons  " .. join_cards(snap.cons, 4),
		snap.phase == "shop" and ("Shop  " .. join_cards(snap.shop, 5)) or "",
	}
end

return P
