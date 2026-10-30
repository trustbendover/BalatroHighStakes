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
function MP.UTILS.mode_desc(key, scale)
	scale = scale or 0.6
	local text = localize(key)
	local w = MP.UTILS.wrapText(text, 70)
	local _, n = w:gsub("\n", "")
	if n + 1 <= MP.UTILS.MODE_DESC_LINES then return w, scale end
	local width = math.ceil(70 * (n + 1) / MP.UTILS.MODE_DESC_LINES)
	return MP.UTILS.wrapText(text, width), scale * 70 / width
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