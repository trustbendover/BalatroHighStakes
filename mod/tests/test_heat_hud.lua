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
local room = { x = 0, y = 0, w = 19.5556, h = 11 }
local chat = { x = 15.2, y = 0.3, w = 3.9, h = 1.3 }
local deck = { x = 16.6, y = 8.3, w = 2.4, h = 2.2 }
local meter = H.layout_meter(room, { chat, deck })
ok(meter and meter.x > room.w * 0.7, "the meter sits on the right")
ok(meter.x + meter.w > room.w - 0.08, "the pill sits close to the right edge")
ok(meter.y >= chat.y + chat.h + 0.6, "the pill starts below the chat and the consumable row")
ok(not H.meter_overlaps(meter, { chat, deck }, 0), "it clears the chat and the deck")
local counter = { x = 17.6, y = 3.2, w = 0.9, h = 0.4 }
ok(not H.overlap(meter, counter, 0.05), "the pill clears the vanilla consumable counter (0/2)")
local labels = H.meter_labels(meter, 0, 12)
ok(labels.number.text == "0" and labels.caption.text == "HEAT" and not labels.caption.text:find("\n", 1, true), "the number and HEAT are each one line")
ok(labels.caption.y >= labels.number.y + labels.number.h - 1e-6, "HEAT sits under the number, not on it")
ok(labels.best and labels.best.y >= labels.caption.y + labels.caption.h - 1e-6, "Best sits under HEAT")
local cx = meter.x + meter.w / 2
ok(math.abs(labels.number.x + labels.number.w / 2 - cx) < 1e-6, "the number is centered on the pill")
ok(math.abs(labels.caption.x + labels.caption.w / 2 - cx) < 1e-6, "HEAT is centered on the pill")
ok(math.abs(labels.best.x + labels.best.w / 2 - cx) < 1e-6, "Best is centered on the pill")
ok(labels.caption.w >= 2.4, "HEAT has enough width that it does not wrap")
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
