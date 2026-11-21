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
ok(not src:find("y = 1.05", 1, true), "the strip is no longer pinned down into the joker row")
ok(src:find("major = G.jokers", 1, true), "it is attached to the joker area")
ok(src:find("function H.draw_front()", 1, true) and src:find("love.draw", 1, true), "it is drawn after the cards")
ok(src:find("function H.silence(", 1, true), "the early UI pass does not paint it under the cards")

print("PASS: heat hud")
