-- luajit tests/test_heat_hud.lua (run from mod/)
-- The Heat strip sits above the joker row and stays clear of the other top HUD.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local H = dofile("networking/heat_rules.lua")

local function overlaps(a, b)
	return H.overlap(a, b, 0)
end

local function scene(px_w, px_h, n)
	local units_h = 11
	local units_w = units_h * (px_w / px_h)
	local jw = math.min(1.15 * n, units_w * 0.5)
	local jx = units_w * 0.52 - jw / 2
	local jy, jh = 2.35, 1.15
	local area = { T = { x = jx, y = jy, w = jw, h = jh } }
	local cards = {}
	for i = 1, n do
		cards[i] = {
			T = { x = jx + (i - 1), y = jy - (i == 2 and 0.2 or 0), w = 1, h = 1.27 },
			highlighted = i == 2,
		}
	end
	local chat = { x = units_w - 4.0, y = 0.25, w = 3.7, h = 2.4 }
	local chaos = { x = units_w / 2 - 4, y = 0.55, w = 8, h = 0.48 }
	local room = { x = 0, y = 0, w = units_w, h = units_h }
	return area, cards, { chaos, chat }, room
end

local function clears(box, area, cards)
	if box.y + box.h > area.T.y - H.HOVER - H.BADGE_GAP + 1e-9 then return false end
	for _, c in ipairs(cards) do
		local limit = c.T.y - ((c.highlighted and H.HOVER) or 0) - H.BADGE_GAP
		if box.y + box.h > limit + 1e-9 then return false end
	end
	return true
end

local screens = {
	{ "1080p", 1920, 1080 },
	{ "1440p", 2560, 1440 },
	{ "4K", 3840, 2160 },
	{ "ultrawide", 3440, 1440 },
}
local first = nil
for _, s in ipairs(screens) do
	local area, cards, blockers, room = scene(s[2], s[3], 6)
	local box = H.layout_badge(area, cards, blockers, room)
	ok(box and clears(box, area, cards), s[1] .. ": the strip is above the joker row, including a raised joker")
	ok(not overlaps(box, blockers[1]), s[1] .. ": it does not cover the Chaos badge")
	ok(not overlaps(box, blockers[2]), s[1] .. ": it does not cover the chat")
	ok(box.x >= room.x - 1e-9 and box.x + box.w <= room.x + room.w + 1e-9, s[1] .. ": it stays inside the room")
	ok(box.y + box.h <= area.T.y - 0.2, s[1] .. ": it is just above the cards, not up in the top bar")
	if s[1] == "1080p" then first = box end
	if s[1] == "4K" or s[1] == "1440p" then
		ok(math.abs(box.x - first.x) < 1e-6 and math.abs(box.y - first.y) < 1e-6, s[1] .. ": same game-unit place as 1080p")
	end
	if s[1] == "ultrawide" then
		ok(math.abs(box.x - first.x) > 0.5, "ultrawide follows the joker row as it moves sideways")
	end
end

local area, cards = scene(1920, 1080, 5)
local five = H.layout_badge(area, cards, {}, { x = 0, y = 0, w = 19.5, h = 11 })
ok(#cards == 5 and clears(five, area, cards), "five jokers, one of them raised, still leave the strip clear")

local src = io.open("lib/heat.lua"):read("*a")
ok(not src:find("y = 1.05", 1, true) and not src:find("major = G.jokers", 1, true), "the old top strip is gone")
ok(src:find("function H.draw_front()", 1, true) and src:find("love.draw", 1, true), "the meter is drawn after the cards")
ok(src:find("H.layout_meter", 1, true) and src:find("H.meter_labels", 1, true), "the vertical meter carries the stacked labels")
local rules = io.open("networking/heat_rules.lua"):read("*a")
ok(rules:find('text = "Best "', 1, true) or rules:find('"Best "', 1, true), "Best is its own centered line")
-- The screen is wider than the playfield. Consumables, the 0/2 counter and the deck
-- sit on the playfield's right edge. The pill is pinned to the screen edge instead.
local function screen_of(px_w, px_h)
	local orig = 16 / 9
	local base_scale, tile, base_h = 3.6, 20, 1080
	local tilescale = (px_w / px_h < orig) and (base_scale * px_w / 1920) or (base_scale * px_h / base_h)
	return { x = 0, y = 0, w = px_w / (tile * tilescale), h = px_h / (tile * tilescale) }
end
local function field(screen)
	local room_right = screen.w - 2.4
	return {
		jokers = { x = screen.w * 0.28, y = 0.55, w = 8.2, h = 1.45 },
		cons = { x = room_right - 2.7, y = 2.5, w = 2.55, h = 3.3 },
		counter = { x = room_right - 1.15, y = 2.15, w = 1.0, h = 0.42 },
		deck = { x = room_right - 2.3, y = screen.h - 3.1, w = 2.15, h = 2.5 },
	}
end
local screens_px = {
	{ "1080p", 1920, 1080 },
	{ "1440p", 2560, 1440 },
	{ "ultrawide", 3440, 1440 },
	{ "window", 1600, 900 },
}
local anchor = nil
for _, s in ipairs(screens_px) do
	local screen = screen_of(s[2], s[3])
	local f = field(screen)
	local blockers = { f.jokers, f.cons, f.counter, f.deck }
	local meter = H.layout_meter(screen, blockers)
	ok(meter and meter.anchor == "screen", s[1] .. ": the meter is anchored to the screen, not the consumable row")
	local right = H.meter_right(meter)
	ok(right <= screen.w - H.METER_INSET + 1e-6, s[1] .. ": pill, flame and caption stay inside the margin")
	ok(screen.w - right >= 0.3 and screen.w - right <= 0.5, s[1] .. ": the right margin is 0.3 to 0.5")
	ok(meter.x > f.cons.x + f.cons.w and meter.x > f.deck.x + f.deck.w, s[1] .. ": it sits to the right of the consumables and the deck")
	ok(not H.meter_overlaps(meter, blockers, 0.02), s[1] .. ": the pill and its caption clear consumables, deck and jokers")
	local mid = screen.y + screen.h / 2
	ok(math.abs((meter.y + meter.h / 2) - mid) < screen.h * 0.28, s[1] .. ": it stays around the middle of the screen")
	if s[1] == "1080p" then anchor = meter.x end
	if s[1] == "1440p" then
		ok(math.abs(meter.x - anchor) < 1e-6, "1440p keeps the same tile position as 1080p")
	end
	if s[1] == "ultrawide" then
		ok(meter.x > anchor + 1, "ultrawide follows the wider screen, not the playfield")
	end
end
local covered = H.layout_meter({ x = 0, y = 0, w = 20, h = 12 }, {
	{ x = 16, y = 0, w = 4, h = 12 },
})
ok(covered and math.abs(H.meter_right(covered) - (20 - H.METER_INSET)) < 1e-6, "a blocker covering the right column does not pull the assembly off the margin")
local px = H.screen_tiles(1920, 1080, 3.6, 20)
ok(px and math.abs(px.w - (1920 / (3.6 * 20))) < 1e-6 and px.w < 100, "real_window_w is pixels and is divided by TILESCALE * TILESIZE")
local meter = H.layout_meter(screen_of(1920, 1080), {})
local labels = H.meter_labels(meter, 0, 12)
ok(labels.number.text == "0" and labels.caption.text == "HEAT" and not labels.caption.text:find("\n", 1, true), "the number and HEAT are each one line")
ok(labels.caption.y >= labels.number.y + labels.number.h - 1e-6, "HEAT sits under the number, not on it")
ok(labels.best and labels.best.y >= labels.caption.y + labels.caption.h - 1e-6, "Best sits under HEAT")
local cx = meter.x + meter.w / 2
ok(math.abs(labels.number.x + labels.number.w / 2 - cx) < 1e-6, "the number is centered on the pill")
ok(math.abs(labels.caption.x + labels.caption.w / 2 - cx) < 1e-6, "HEAT is centered on the pill")
ok(math.abs(labels.best.x + labels.best.w / 2 - cx) < 1e-6, "Best is centered on the pill")
ok(labels.number.w == labels.caption.w and labels.caption.w == labels.best.w, "the three lines share one centered column")
ok(labels.caption.y >= labels.number.y + labels.number.h, "HEAT starts only after the number's line")
ok(labels.best.y >= labels.caption.y + labels.caption.h, "Best starts only after HEAT")
ok(src:find("real_window_w", 1, true) and src:find("getWidth", 1, true), "the meter measures the screen, not the consumable area")
ok(not src:find("major = G.consumeables", 1, true), "the meter is not parented to the consumables")
ok(src:find("gpx.translate", 1, true) and not src:find('printf(node.text', 1, true), "caption scale is about the line centre, so the number cannot sit beside HEAT")
ok(H.flame_target(0, 100) == 0 and H.flame_target(50, 100) == 0, "the flame stays out until Heat nears 100")
ok(H.flame_target(90, 100) > 0 and H.flame_target(100, 100) > H.flame_target(90, 100), "the flame grows as Heat nears 100")
ok(math.abs(H.flame_target(100, 100) - H.FLAME_FULL) < 1e-9, "Heat 100 is a full vanilla flame")
local stepped = H.flame_step({ real_intensity = 0, intensity_vel = 0, timer = 0, change = 0 }, H.FLAME_FULL, 0.05)
ok(stepped.real_intensity > 0 and stepped.real_intensity < H.FLAME_FULL, "the flame eases up the way the chips flame does")
local chips = { real_intensity = 3, change = 1 }
local kept = chips.real_intensity
H.flame_step(stepped, H.FLAME_FULL, 0.05)
ok(chips.real_intensity == kept, "the Heat flame does not write the chips flame")
ok(H.flame_volume("ambientFire2", H.FLAME_FULL, 0) > 0.5 and H.flame_volume("ambientFire2", 0, 0) == 0, "full Heat uses the vanilla fire bed, and zero Heat is silent")
ok(src:find("heat_flames", 1, true) and src:find('shader = "flame"', 1, true) and src:find("ambientFire1", 1, true), "the meter hooks the vanilla flame shader and its fire sounds")
ok(src:find("function H.drop_flame()", 1, true), "leaving the match removes the Heat flame")
local fill = H.meter_fill(meter, 50, 100)
ok(fill and math.abs((fill.y + fill.h) - (meter.y + meter.h)) < 1e-9 and fill.h < meter.h, "the bar fills from the bottom")
local _, gy, _ = H.meter_color(0, 100)
local _, gr, _ = H.meter_color(100, 100)
ok(gy > gr, "empty is yellow and full is red")
local flames = H.flame_tick({}, 0.05, true, 1)
ok(#flames > 0, "Overdrive lights the flame")
flames = H.flame_tick(flames, 2, false, 2)
ok(#flames == 0, "spending Overdrive puts the flame out")
ok(H.hit_meter(meter, meter.x + 0.1, meter.y + 0.2) and not H.hit_meter(meter, meter.x - 1, meter.y), "the meter is the hover target for How to play")
local ticks = H.meter_ticks(meter)
local y25, y75
for _, t in ipairs(ticks) do
	if t.mark == 25 then y25 = t.y elseif t.mark == 75 then y75 = t.y end
end
ok(#ticks == 3 and y25 and y75 and y25 > y75, "tick marks sit at 25, 50 and 75, rising with the fill")
local eased = H.ease_heat(0, 100, 0.016)
ok(eased > 0 and eased < 25, "the fill eases toward the new Heat")
ok(H.meter_burst(80, 100, 100) > 0 and H.meter_burst(100, 100, 100) == 0, "reaching 100 flashes once")
local both = H.flame_tick({}, 0.016, true, 1)
local left, right, low, high = false, false, false, false
for _, p in ipairs(both) do
	if p.side == -1 then left = true elseif p.side == 1 then right = true end
	if (p.y or 1) < 0.35 then low = true end
	if (p.y or 0) > 0.6 then high = true end
end
ok(left and right and low and high, "flames run both edges from the bottom to the top")
local pile = both
for i = 1, 40 do pile = H.flame_tick(pile, 0.001, true, i) end
ok(#pile <= 36, "the flame stays within a small particle cap")

print("PASS: heat hud")
