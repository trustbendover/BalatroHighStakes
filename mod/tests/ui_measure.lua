-- Test helper: width of a Balatro UI definition, the way UIBox:calculate_xywh adds it up
-- (engine/ui.lua): T = text width, R children stack (max width), other children sit side by side
-- (sum), each with the container's padding; result = max(content + padding, minw).
-- Text width comes from MP.FIT.width (m6x11 metrics). Reports every container whose content is
-- wider than its maxw (in-game that would shrink or overflow) and every T wider than its maxw.
local M = {}
local DEFAULT_PAD = 0 -- G.UIT.padding in globals.lua

function M.measure(node, issues, path)
	issues = issues or {}
	path = path or "root"
	if type(node) ~= "table" then return 0, issues end
	local U, cfg = G.UIT, node.config or {}
	if node.n == U.T then
		local text = cfg.text
		if cfg.ref_table and cfg.ref_value then text = cfg.ref_table[cfg.ref_value] end
		local w = MP.FIT.width(tostring(text or ""), cfg.scale or 1)
		if cfg.maxw and w > cfg.maxw + 1e-6 then issues[#issues + 1] = string.format("%s: text %q %.2f > maxw %.2f", path, tostring(text), w, cfg.maxw) end
		return w, issues
	elseif node.n == U.O then
		local o = cfg.object or {}
		local w = cfg.w or (o.text and MP.FIT.width(o.text, o.scale or 1)) or (o.T and o.T.w) or 0
		if o.maxw and w > o.maxw then w = o.maxw end -- DynaText shrinks itself
		return w, issues
	end
	local pad = cfg.padding or DEFAULT_PAD
	local cw = 0
	for i, c in ipairs(node.nodes or {}) do
		local tw = M.measure(c, issues, path .. "/" .. i)
		if c.n == U.R then cw = math.max(cw, tw + pad) else cw = cw + tw + pad end
	end
	local content = cw + pad
	if cfg.maxw and content > cfg.maxw + 1e-6 then
		issues[#issues + 1] = string.format("%s: content %.2f > maxw %.2f", path, content, cfg.maxw)
	end
	return math.max(content, cfg.minw or 0), issues
end

--- every node (depth first) matching pred
function M.find(node, pred, out)
	out = out or {}
	if type(node) ~= "table" then return out end
	if pred(node) then out[#out + 1] = node end
	for _, c in ipairs(node.nodes or {}) do M.find(c, pred, out) end
	return out
end

--- localize() stub from a localization file (misc.dictionary + misc.v_dictionary), #1# vars filled
function M.localizer(file)
	local t = dofile(file)
	local d = {}
	for _, k in ipairs({ "dictionary", "v_dictionary" }) do
		for key, val in pairs(t.misc and t.misc[k] or {}) do d[key] = val end
	end
	return function(a)
		local key = type(a) == "table" and a.key or a
		local s = d[key]
		if type(s) ~= "string" then return "ERROR" end
		if type(a) == "table" and a.vars then
			for i, v in ipairs(a.vars) do s = s:gsub("#" .. i .. "#", (tostring(v):gsub("%%", "%%%%"))) end
		end
		return s
	end
end

return M
