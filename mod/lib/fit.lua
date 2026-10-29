-- Balatro High Stakes 0.6.8: make text fit a fixed width, the Balatro way. GPL-3.0.
-- Balatro's G.UIT.T nodes have no maxw (only containers and DynaText do), and a container's maxw
-- shrinks its children's scale permanently. So dynamic texts are measured and shortened up front:
-- names get "..", numbers get compact, lines drop spacing - before they reach the UI.
-- Width in UI units = font width at size 1 (em) * scale, exactly as UIBox:calculate_xywh measures it.
MP.FIT = MP.FIT or {}
local F = MP.FIT

-- m6x11plus advance widths in em (ASCII); everything else counts as 0.5. Used when no font is loaded (tests).
local NARROW, WIDE = "!',.:;|il`", { M = 0.5625, W = 0.5625, m = 0.5625, w = 0.5625, ["&"] = 0.625, ["@"] = 0.625,
	X = 0.5, x = 0.5, Q = 0.5, ["#"] = 0.5, ["("] = 0.3125, [")"] = 0.3125, ["["] = 0.3125, ["]"] = 0.3125, j = 0.3125,
	['"'] = 0.375, ["*"] = 0.375, ["<"] = 0.375, [">"] = 0.375, ["{"] = 0.375, ["}"] = 0.375 }
local function em(ch)
	if WIDE[ch] then return WIDE[ch] end
	if #ch == 1 and NARROW:find(ch, 1, true) then return ch == "`" and 0.0625 or 0.1875 end
	if #ch == 1 then return 0.4375 end
	return 0.5
end
F.em = em

local function chars(s)
	local t = {}
	for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
	return t
end

--- width of `s` at text scale `scale`, in UI units
function F.width(s, scale)
	s = tostring(s or "")
	scale = scale or 1
	local font = G and G.LANG and G.LANG.font
	if font and font.FONT and font.FONT.getWidth and G.TILESIZE then
		local ok, w = pcall(function() return font.FONT:getWidth(s) * (font.squish or 1) * scale * (font.FONTSCALE or 0.1) / G.TILESIZE end)
		if ok and type(w) == "number" then return w end
	end
	local w = 0
	for _, ch in ipairs(chars(s)) do w = w + em(ch) end
	return w * scale
end

--- `s` shortened with ".." so it fits `maxw` at `scale`
function F.ellipsize(s, scale, maxw)
	s = tostring(s or "")
	if F.width(s, scale) <= maxw then return s end
	local t = chars(s)
	while #t > 0 do
		t[#t] = nil
		local cand = table.concat(t):gsub("%s+$", "") .. ".."
		if F.width(cand, scale) <= maxw then return cand end
	end
	return ".."
end

--- compact a score text so it fits: "123,456,789,012" -> "1.23e14"; non-numbers are ellipsized
function F.number(s, scale, maxw)
	s = tostring(s or "")
	if F.width(s, scale) <= maxw then return s end
	local n = tonumber((s:gsub(",", "")))
	if n then
		for d = 3, 0, -1 do
			local c = string.format("%." .. d .. "e", n):gsub("e%+0*", "e"):gsub("e%-0*", "e-")
			if F.width(c, scale) <= maxw then return c end
		end
	end
	return F.ellipsize(s, scale, maxw)
end

--- join `parts` with the widest separator that fits, else ellipsize
function F.join(parts, scale, maxw, seps)
	seps = seps or { "   ", "  ", " " }
	local line
	for _, sep in ipairs(seps) do
		line = table.concat(parts, sep)
		if F.width(line, scale) <= maxw then return line end
	end
	return F.ellipsize(line, scale, maxw)
end

--- the scale at which `s` fits `maxw` (never above `scale`)
function F.scale(s, scale, maxw)
	local w = F.width(s, scale)
	if w <= maxw or w == 0 then return scale end
	return scale * maxw / w
end

--- re-fit a DynaText after its string changed (DynaText applies maxw only when created)
function F.refit_dynatext(obj)
	if not (obj and obj.config and obj.config.maxw and obj.update_text) then return end
	pcall(function()
		obj.scale = obj.config.scale or obj.scale
		obj:update_text(true)
		if obj.config.W and obj.config.W > obj.config.maxw then
			obj.scale = obj.scale * obj.config.maxw / obj.config.W
			obj:update_text(true)
		end
	end)
end

--- copy colour `src` into the table `dst` (T nodes keep a reference to their colour table)
function F.set_colour(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then return dst end
	for i = 1, 4 do dst[i] = src[i] or dst[i] or 1 end
	return dst
end

return F
