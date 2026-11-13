-- Credit to Steamo (https://github.com/Steamopollys/Steamodded/blob/main/core/core.lua)
function MP.UTILS.wrapText(text, maxChars)
	local wrappedText = ""
	local currentLineLength = 0

	for word in text:gmatch("%S+") do
		if currentLineLength + #word <= maxChars then
			wrappedText = wrappedText .. word .. " "
			currentLineLength = currentLineLength + #word + 1
		else
			wrappedText = wrappedText .. "\n" .. word .. " "
			currentLineLength = #word + 1
		end
	end

	return wrappedText
end

--- 0.6.8: gamemode info text. At most MODE_DESC_LINES lines fit above the blind chips; longer text (e.g. a
--- long translation) is wrapped wider at a smaller scale instead of overlapping the graphic.
MP.UTILS.MODE_DESC_LINES = 4
function MP.UTILS.mode_desc(key, scale, max_lines)
	scale = scale or 0.6
	max_lines = max_lines or MP.UTILS.MODE_DESC_LINES
	local text = localize(key)
	local w = MP.UTILS.wrapText(text, 70)
	local _, n = w:gsub("\n", "")
	if n + 1 <= max_lines then return w, scale end
	local width = math.ceil(70 * (n + 1) / max_lines)
	return MP.UTILS.wrapText(text, width), scale * 70 / width
end

--- Lines that fit a card width. A newline inside one text node has no extra height, so the
--- next row (the orange win line) is drawn on top of the last word of the line above it.
function MP.UTILS.fit_lines(text, scale, maxw, max_lines)
	scale = scale or 0.45
	maxw = maxw or 10.2
	max_lines = max_lines or 12
	local function width(s, sc)
		if MP.FIT and MP.FIT.width then return MP.FIT.width(s, sc) end
		return #tostring(s) * 0.4375 * sc
	end
	local function wrap(sc)
		local lines, cur = {}, ""
		for word in tostring(text or ""):gmatch("%S+") do
			local trial = cur == "" and word or (cur .. " " .. word)
			if cur ~= "" and width(trial, sc) > maxw then
				lines[#lines + 1] = cur
				cur = word
			else
				cur = trial
			end
		end
		if cur ~= "" then lines[#lines + 1] = cur end
		if #lines == 0 then lines[1] = "" end
		return lines
	end
	local lines = wrap(scale)
	local guard = 0
	while #lines > max_lines and scale > 0.26 and guard < 6 do
		scale = math.max(0.26, scale * max_lines / #lines)
		lines = wrap(scale)
		guard = guard + 1
	end
	return lines, scale
end

function MP.UTILS.string_split(inputstr, sep)
	if sep == nil then sep = "%s" end
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

function MP.UTILS.string_starts(str, prefix)
    return str:sub(1, #prefix) == prefix
end