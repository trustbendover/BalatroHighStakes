-- In-lobby text chat. The host repeats each line, in order, to everyone in that lobby.
-- Lobby: a compact panel under the start row, 5.6 wide, text at 0.32.
-- Match: a bottom-left drawer inside the screen ("bli"), pulled up from the bottom edge.
-- It never shows a lobby code. Names are that player's blind color, then a colon, then light text.
MP.CHAT = MP.CHAT or {}
local CH = MP.CHAT

CH.RULES = CH.RULES or (MP.load_mp_file and MP.load_mp_file("networking/chat_rules.lua")) or nil
CH.state = CH.state or { view = "lobby", lobby = {}, match = {} }
CH.open = CH.open or false
CH.draft = CH.draft or { text = "" }
CH.seen = CH.seen or 0
-- Compact sizes. A container maxw shrinks Balatro text, so these panels use minw only.
CH.LOBBY_W = 5.6
CH.MATCH_W = 5.4
CH.VIEW_LINES = 6
CH.INPUT_W = 3.6
CH.scroll = CH.scroll or 0
CH.field = CH.field or { show = "" }
CH.draft.caret = CH.draft.caret or 0

local function rules()
	if CH.RULES then return CH.RULES end
	local ok, m = pcall(dofile, "networking/chat_rules.lua")
	if ok and type(m) == "table" then CH.RULES = m end
	return CH.RULES
end

local function L(key, fallback)
	local ok, s = pcall(localize, key)
	if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= key then return s end
	return fallback
end

function CH.chrome()
	return {
		open = L("b_chat_open", "Chat"),
		close = L("b_chat_close", "Close"),
		send = L("b_chat_send", "Send"),
		prompt = L("k_chat_prompt", "Message"),
		title = L("k_chat", "Chat"),
		watching = L("k_chat_watching", "(watching)"),
	}
end

--- The player's blind color, used for the name text. Falls back to that blind's boss colour.
function CH.name_colour(col)
	col = tonumber(col) or 1
	if MP.UTILS and MP.UTILS.blind_col_numtokey and G and G.P_BLINDS then
		local blind = G.P_BLINDS[MP.UTILS.blind_col_numtokey(col)]
		if blind and blind.boss_colour then return blind.boss_colour end
	end
	local names = { "RED", "BLUE", "GREEN", "PURPLE", "ORANGE", "GOLD", "CHIPS", "MULT" }
	local key = names[((col - 1) % #names) + 1]
	if G and G.C and G.C[key] then return G.C[key] end
	return key
end

function CH.body_ink()
	if G and G.C and G.C.UI and G.C.UI.TEXT_LIGHT then return G.C.UI.TEXT_LIGHT end
	return "plain"
end

function CH.current()
	local R = rules()
	if not R then return {} end
	return R.current(CH.state)
end

function CH.cols_for(wide, scale)
	scale = scale or 0.32
	return math.max(12, math.floor(((wide or CH.MATCH_W) - 0.35) / math.max(0.12, scale * 0.5)))
end

--- Name stays on the first line. The body wraps onto following lines instead of ending in "...".
function CH.wrap_message(name, body, col, cols)
	cols = math.max(8, tonumber(cols) or 24)
	name = tostring(name or "")
	if name ~= "" and not name:find(":$") then name = name .. ":" end
	body = tostring(body or "")
	local lines = {}
	local function push(n, b, first)
		lines[#lines + 1] = { name = n, body = b, col = col or 1, first = first and true or false }
	end
	local function take(text, width)
		if text == "" then return "", "" end
		local n = math.max(1, width)
		return text:sub(1, n), text:sub(n + 1)
	end
	local room = math.max(4, cols - #name - 1)
	local head, rest = take(body, room)
	push(name, head, true)
	while rest ~= "" do
		local piece
		piece, rest = take(rest, cols)
		push("", piece, false)
	end
	return lines
end

function CH.wrapped(wide, scale)
	local R = rules()
	local ui = CH.chrome()
	local cols = CH.cols_for(wide, scale)
	local lines = {}
	for _, m in ipairs(CH.current()) do
		local body = R and R.body(m, ui.watching) or tostring(m.text or "")
		local name = R and R.display_name(m.name) or tostring(m.name or "?")
		for _, line in ipairs(CH.wrap_message(name, body, tonumber(m.col) or 1, cols)) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

function CH.scroll_max(total)
	return math.max(0, (tonumber(total) or 0) - CH.VIEW_LINES)
end

function CH.clamp_scroll(total)
	local maxs = CH.scroll_max(total)
	CH.scroll = tonumber(CH.scroll) or 0
	if CH.scroll < 0 then CH.scroll = 0 elseif CH.scroll > maxs then CH.scroll = maxs end
	return maxs
end

--- 0 means the thumb sits on the newest line. 1 means it sits on the oldest.
function CH.thumb_top(scroll, total)
	local view = CH.VIEW_LINES
	total = tonumber(total) or 0
	scroll = tonumber(scroll) or 0
	local maxs = math.max(0, total - view)
	local thumb = (total <= view or total == 0) and 1 or (view / total)
	if maxs == 0 then return 0, thumb end
	return (1 - scroll / maxs) * (1 - thumb), thumb
end

function CH.window_lines(wide, scale)
	local lines = CH.wrapped(wide, scale)
	CH.clamp_scroll(#lines)
	local start = math.max(1, #lines - CH.VIEW_LINES - CH.scroll + 1)
	local out = {}
	for i = 0, CH.VIEW_LINES - 1 do
		out[#out + 1] = lines[start + i] or { name = "", body = "", col = 1, first = false }
	end
	return out, #lines
end

function CH.ensure_slots()
	CH.slots = CH.slots or {}
	CH.slot_ink = CH.slot_ink or {}
	for i = 1, CH.VIEW_LINES do
		CH.slots[i] = CH.slots[i] or { name = "", body = "" }
		CH.slot_ink[i] = CH.slot_ink[i] or {}
	end
	CH.field = CH.field or { show = "" }
end

function CH.log_width()
	if CH.in_lobby_menu and CH.in_lobby_menu() then return CH.LOBBY_W - 0.4 end
	return CH.MATCH_W - 0.4
end

function CH.paint_slots(wide, scale)
	CH.ensure_slots()
	wide = wide or CH.log_width()
	local shown = CH.window_lines(wide, scale)
	for i = 1, CH.VIEW_LINES do
		local line = shown[i]
		local slot = CH.slots[i]
		slot.name = line.name or ""
		slot.body = line.body or ""
		local ink = CH.slot_ink[i]
		if ink then ink.colour = (line.first and CH.name_colour(line.col)) or CH.body_ink() end
	end
end

function CH.field_slice()
	local text = CH.draft.text or ""
	local caret = tonumber(CH.draft.caret) or #text
	if caret < 0 then caret = 0 elseif caret > #text then caret = #text end
	CH.draft.caret = caret
	if text == "" and not CH.focused then return CH.chrome().prompt end
	local extra = #text >= 100 and (" " .. #text .. "/550") or ""
	local cols = extra ~= "" and 12 or 18
	local win_start = caret - math.floor(cols / 2) + 1
	if win_start < 1 then win_start = 1 end
	if win_start + cols - 1 > #text then win_start = math.max(1, #text - cols + 1) end
	local win_end = math.min(#text, win_start + cols - 1)
	local window = text:sub(win_start, win_end)
	local before_n = caret - win_start + 1
	if before_n < 0 then before_n = 0 elseif before_n > #window then before_n = #window end
	local mark = ""
	if CH.focused then
		local t = 0
		if love and love.timer and love.timer.getTime then
			local ok, n = pcall(love.timer.getTime)
			if ok and type(n) == "number" then t = n end
		end
		if math.floor(t * 2) % 2 == 0 then mark = "|" end
	end
	return window:sub(1, before_n) .. mark .. window:sub(before_n + 1) .. extra
end

function CH.paint_field()
	CH.field = CH.field or { show = "" }
	CH.field.show = CH.field_slice()
end

function CH.insert_text(s)
	local R = rules()
	local maxn = (R and R.MAX) or 550
	s = tostring(s or ""):gsub("%c", "")
	if s == "" then return end
	local text = CH.draft.text or ""
	local caret = tonumber(CH.draft.caret) or #text
	local room = maxn - #text
	if room <= 0 then return end
	if #s > room then s = s:sub(1, room) end
	CH.draft.text = text:sub(1, caret) .. s .. text:sub(caret + 1)
	CH.draft.caret = caret + #s
	CH.scroll = 0
	CH.paint_field()
end

function CH.backspace()
	local text = CH.draft.text or ""
	local caret = tonumber(CH.draft.caret) or #text
	if caret <= 0 then return end
	CH.draft.text = text:sub(1, caret - 1) .. text:sub(caret + 1)
	CH.draft.caret = caret - 1
	CH.paint_field()
end

local function log_rows(wide, scale)
	CH.ensure_slots()
	local nodes = {}
	for i = 1, CH.VIEW_LINES do
		local slot = CH.slots[i]
		local ink = { ref_table = slot, ref_value = "name", scale = scale, colour = CH.body_ink(), shadow = true }
		CH.slot_ink[i] = ink
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.015, minw = wide, minh = 0.28 }, nodes = {
			{ n = G.UIT.T, config = ink },
			{ n = G.UIT.T, config = { text = " ", scale = scale, colour = CH.body_ink() } },
			{ n = G.UIT.T, config = { ref_table = slot, ref_value = "body", scale = scale, colour = CH.body_ink() } },
		} }
	end
	CH.paint_slots(wide, scale)
	return nodes
end

local function input_row(wide, scale, input_w, with_close)
	CH.paint_field()
	local ui = CH.chrome()
	local controls = {
		{ n = G.UIT.C, config = { id = "mp_chat_field", align = "cl", padding = 0.04, minw = input_w, minh = 0.48, r = 0.06, colour = G.C.WHITE, button = "mp_chat_focus", hover = true, func = "mp_chat_arm" }, nodes = {
			{ n = G.UIT.T, config = { ref_table = CH.field, ref_value = "show", scale = scale, colour = G.C.BLACK } },
		} },
		{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = {
			UIBox_button({ id = "mp_chat_send", button = "mp_chat_send", func = "mp_chat_arm", label = { ui.send },
				minw = 1.3, minh = 0.48, scale = scale, colour = G.C.GREEN, col = true }),
		} },
	}
	if with_close then
		controls[#controls + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = {
			UIBox_button({ id = "mp_chat_close", button = "mp_chat_close", func = "mp_chat_arm", label = { ui.close },
				minw = 1.15, minh = 0.48, scale = scale, colour = G.C.RED, col = true }),
		} }
	end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.04, minw = wide }, nodes = controls }
end

function CH.panel_nodes(wide, scale, input_w, with_close)
	local lw = wide - 0.4
	local log = { n = G.UIT.C, config = { align = "tm", minw = lw }, nodes = log_rows(lw, scale) }
	local row_nodes = { log }
	local bar = CH.make_bar and CH.make_bar()
	if bar then
		row_nodes[#row_nodes + 1] = { n = G.UIT.C, config = { id = "mp_chat_scroll", align = "cm", minw = 0.32, minh = 1.8 }, nodes = {
			{ n = G.UIT.O, config = { object = bar } },
		} }
	end
	return {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = row_nodes },
		input_row(wide, scale, input_w, with_close),
	}
end

--- Lobby: compact panel under the start row. Input and Send share one row.
function CH.lobby_row()
	local wide = CH.LOBBY_W
	return { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = {
		{ n = G.UIT.C, config = { id = "mp_chat_lobby", align = "cm", minw = wide + 0.24, padding = 0.06, r = 0.1,
			colour = G.C.BLACK, emboss = 0.05 }, nodes = CH.panel_nodes(wide, 0.32, 3.6, false) },
	} }
end

function CH.apply(msg)
	local R = rules()
	if R then CH.state = R.reduce(CH.state, msg) end
	CH.refresh()
end

--- The hooked field's config is the create_text_input args, which point at CH.draft.
function CH.input_args(hook)
	hook = hook or (G and G.CONTROLLER and G.CONTROLLER.text_input_hook)
	local args = hook and hook.config and hook.config.ref_table
	if type(args) ~= "table" then return nil end
	if args == CH.draft or args.ref_table == CH.draft then return args end
	return nil
end

function CH.typing()
	return CH.focused and true or false
end

function CH.release_input()
	if CH.typing() then G.CONTROLLER.text_input_hook = nil end
end

--- Letter nodes keep their own copies. Clearing CH.draft.text alone leaves "test" on screen.
function CH.blank_letters()
	local args = CH.input_args()
	if not args or not args.text or not args.text.letters then return end
	for i = 1, #args.text.letters do args.text.letters[i] = "" end
	args.text.current_position = 0
	args.current_prompt_text = args.prompt_text or ""
end

function CH.send()
	local text = tostring(CH.draft.text or "")
	CH.draft.text = ""
	CH.draft.caret = 0
	CH.scroll = 0
	CH.focused = false
	CH.blank_letters()
	CH.paint_field()
	-- A host echo can arrive inside Client.send. Rebuilding the box in that call
	-- frees the text field while Enter is still using it, so the redraw waits a frame.
	CH._sending = true
	if MP.LOBBY and MP.LOBBY.code and Client and Client.send then
		Client.send({ action = "chat", text = text })
	end
	CH._sending = false
	CH._pending = true
	CH.paint_slots()
end

function CH.toggle()
	CH.open = not CH.open
	CH.focused = false
	if CH.open then CH.seen = #CH.current(); CH.scroll = 0 end
	CH.refresh(true)
end

function CH.close()
	CH.seen = #CH.current()
	CH.open = false
	CH.refresh(true)
end

function CH.unread()
	if CH.open then return 0 end
	return math.max(0, #CH.current() - (CH.seen or 0))
end

--- Closed: the Chat button, pinned to the top-right. Open: the log grows downward from that corner.
function CH.definition()
	local ui = CH.chrome()
	local wide = CH.MATCH_W
	if not CH.open then
		local n = CH.unread()
		local label = n > 0 and (ui.open .. " " .. n) or ui.open
		return { n = G.UIT.ROOT, config = { align = "tr", colour = G.C.CLEAR, padding = 0 }, nodes = {
			UIBox_button({ id = "mp_chat_open", button = "mp_chat_toggle", func = "mp_chat_arm", label = { label },
				minw = 1.8, minh = 0.42, scale = 0.32, colour = G.C.BLUE, col = true }),
		} }
	end
	CH.seen = #CH.current()
	local body = CH.panel_nodes(wide, 0.32, CH.INPUT_W, false)
	local nodes = {
		{ n = G.UIT.R, config = { align = "cr", padding = 0.04, minh = 0.36 }, nodes = {
			{ n = G.UIT.T, config = { text = ui.title, scale = 0.3, colour = G.C.WHITE, shadow = true } },
			{ n = G.UIT.C, config = { align = "cm", minw = 0.15 } },
			UIBox_button({ id = "mp_chat_close", button = "mp_chat_close", func = "mp_chat_arm", label = { ui.close },
				minw = 1.15, minh = 0.36, scale = 0.28, colour = G.C.RED, col = true }),
		} },
	}
	for _, node in ipairs(body) do nodes[#nodes + 1] = node end
	return { n = G.UIT.ROOT, config = { align = "tr", colour = G.C.CLEAR, padding = 0.04, minw = wide }, nodes = {
		{ n = G.UIT.C, config = { align = "tm", padding = 0.05, r = 0.1, colour = G.C.BLACK, emboss = 0.05, minw = wide }, nodes = nodes },
	} }
end

function CH.in_lobby_menu()
	return G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and MP.LOBBY and MP.LOBBY.code
end

function CH.relayout_lobby()
	if CH._rebuilding then return end
	if (G and G.OVERLAY_MENU) or CH.typing() then
		CH._pending = true
		return
	end
	if not (G.MAIN_MENU_UI and G.MAIN_MENU_UI.get_UIE_by_ID and G.MAIN_MENU_UI:get_UIE_by_ID("lobby_menu_start")) then return end
	if not (G.FUNCS and G.FUNCS.get_lobby_main_menu_UI) then return end
	CH._rebuilding = true
	pcall(function()
		G.MAIN_MENU_UI:remove()
		G.MAIN_MENU_UI = G.FUNCS.get_lobby_main_menu_UI()
		G.MAIN_MENU_UI.alignment.offset.y = 0
		G.MAIN_MENU_UI:align_to_major()
	end)
	CH._rebuilding = false
end

function CH.refresh(force)
	local stage = G and G.STAGE
	if CH.focused and not force then
		CH.paint_slots()
		CH.paint_field()
		return
	end
	if CH._sending then
		CH._pending = true
		return
	end
	if not force and not CH._pending and CH._sig == CH.sig() and CH._stage == stage then return end
	CH._pending = nil
	CH._sig = CH.sig()
	CH._stage = stage
	pcall(function()
		if CH.box then CH.drop_box(CH.box); CH.box = nil end
		-- The lobby menu draws the chat itself. A second box in the screen corner is what
		-- left only a sliver you could not read or click.
		if CH.in_lobby_menu() then
			CH.relayout_lobby()
			return
		end
		if not (MP.LOBBY and MP.LOBBY.code and G and G.ROOM_ATTACH and UIBox) then return end
		-- Top and right, inside the room, with the top below the consumables row.
		-- y = 0.35 put the open drawer on the 0/2 slot. The deck is the bottom-right.
		CH.release_input()
		CH.box = UIBox({
			definition = CH.definition(),
			config = { align = "tri", offset = { x = -0.2, y = 2.7 }, major = G.ROOM_ATTACH, bond = "Weak" },
		})
		if G.ROOM then CH.box.container = G.ROOM end
		CH.box._mp_chat = true
		CH.box_stage = G.STAGE
		CH.silence(CH.box)
		CH.raise()
		CH.pin()
	end)
end

--- Later boxes are drawn later and are tested first for the cursor.
function CH.raise()
	local list = G and G.I and G.I.UIBOX
	local box = CH.box
	if type(list) ~= "table" or not box then return end
	for i, v in ipairs(list) do
		if v == box then
			table.remove(list, i)
			list[#list + 1] = box
			return
		end
	end
end

--- The normal UI pass would paint this box, and a second paint landed on a different VT.
--- Skip that pass. love.draw calls draw_front once, after cards, the shop, and the HUD.
function CH.silence(box)
	if not box or box._mp_chat_draw or not box.draw then return end
	local orig = box.draw
	box._mp_chat_draw = orig
	box._mp_chat = true
	function box.draw(self, ...)
		if not CH._painting then return end
		return orig(self, ...)
	end
end

function CH.draw_front()
	local box = CH.box
	if not box or box.REMOVED or not box.draw then return end
	-- Pause, settings, and Double or Nothing must keep the clicks and the screen.
	if G and G.OVERLAY_MENU then return end
	CH.sync_visual(box)
	-- UIBox:draw skips a second pass in the same frame. This is the only pass.
	if box.FRAME then box.FRAME.DRAW = -1 end
	CH._painting = true
	pcall(function()
		love.graphics.push()
		local drew, err = pcall(function()
			box:translate_container()
			box:draw()
		end)
		love.graphics.pop()
		if not drew then error(err) end
	end)
	CH._painting = false
end

--- Remove this box and any earlier chat box still sitting in the UI list.
function CH.drop_box(box)
	local list = G and G.I and G.I.UIBOX
	local doomed = {}
	if type(list) == "table" then
		for _, v in ipairs(list) do
			if v == box or (type(v) == "table" and v._mp_chat) then doomed[#doomed + 1] = v end
		end
	elseif box then
		doomed[1] = box
	end
	for _, v in ipairs(doomed) do
		pcall(function() if v.remove then v:remove() end end)
	end
	if type(list) ~= "table" then return end
	for i = #list, 1, -1 do
		local v = list[i]
		if v == box or (type(v) == "table" and v._mp_chat) then table.remove(list, i) end
	end
end

function CH.cursor()
	local c = G and G.CURSOR and G.CURSOR.T
	if c and c.x and c.y then return c.x, c.y end
	return nil
end

function CH.find(id)
	local box = CH.box
	if box and box.get_UIE_by_ID then
		local el = box:get_UIE_by_ID(id)
		if el then return el end
	end
	local menu = G and G.MAIN_MENU_UI
	if menu and menu.get_UIE_by_ID then return menu:get_UIE_by_ID(id) end
	return nil
end

function CH.over(id, x, y)
	if x == nil or y == nil then return false end
	local el = CH.find(id)
	if not el then return false end
	return CH.hits_point(el, { x = x, y = y })
end

--- Window size in tiles. real_window_* is pixels; WINDOWTRANS.w is already tiles.
function CH.window_wh()
	local scale = (G and G.TILESCALE and G.TILESIZE and (G.TILESCALE * G.TILESIZE)) or 0
	local wt = G and G.WINDOWTRANS
	local w, h
	if wt and scale > 0 and tonumber(wt.real_window_w) and wt.real_window_w > 0 then
		w = wt.real_window_w / scale
		if tonumber(wt.real_window_h) and wt.real_window_h > 0 then h = wt.real_window_h / scale end
	end
	if (not w or w <= 0) and scale > 0 and love and love.graphics and love.graphics.getWidth then
		local ok, pw, ph = pcall(function()
			return love.graphics.getWidth(), love.graphics.getHeight()
		end)
		if ok and type(pw) == "number" and pw > 0 then
			w = pw / scale
			if type(ph) == "number" and ph > 0 then h = ph / scale end
		end
	end
	if (not w or w <= 0) and wt and tonumber(wt.w) and wt.w > 0 then
		w, h = wt.w, wt.h
	end
	if (not w or w <= 0) and G and G.TILE_W then
		local padw = G.ROOM_PADDING_W or 1
		local padh = G.ROOM_PADDING_H or 0.7
		w = G.TILE_W + 2 * padw
		h = (G.TILE_H or 0) + 2 * padh
	end
	if (not w or w <= 0) and G and G.ROOM and G.ROOM.T then
		local room = G.ROOM.T
		w = (room.x or 0) + (room.w or 0) + ((G and G.ROOM_PADDING_W) or 1)
		h = (room.y or 0) + (room.h or 0) + ((G and G.ROOM_PADDING_H) or 0.7)
	end
	return w or 0, h or 0
end

--- The draw span is the window, starting at the window corner. The box itself is G.ROOM-local.
function CH.screen_span()
	local w, h = CH.window_wh()
	return 0, 0, w, h
end

--- Closed, the root can be wider than the Chat button. Measure that button. Open, use the panel.
function CH.visible_extent(box)
	local w, h = box.T.w or 0, box.T.h or 0
	local x0, y0 = 0, 0
	if not CH.open and box.get_UIE_by_ID then
		local el = box:get_UIE_by_ID("mp_chat_open")
		if el and el.T and el.T.w and el.T.w > 0 and box.T.x and el.T.x then
			x0 = el.T.x - box.T.x
			y0 = (el.T.y or 0) - (box.T.y or 0)
			w = x0 + el.T.w
			h = y0 + (el.T.h or 0)
		end
	end
	return x0, y0, w, h
end

function CH.clamp_pos()
	local pos, box = CH.pos, CH.box
	if not pos or not box or not box.T then return end
	local win_w, win_h = CH.window_wh()
	local rx = (G and G.ROOM and G.ROOM.T and G.ROOM.T.x) or 0
	local ry = (G and G.ROOM and G.ROOM.T and G.ROOM.T.y) or 0
	local room_right = win_w - rx
	local room_top = -ry
	local room_bottom = win_h - ry
	local room_left = -rx
	local x0, y0, x1, y1 = CH.visible_extent(box)
	local minx, maxx = room_left - x0, room_right - x1
	local miny, maxy = room_top - y0, room_bottom - y1
	if maxx < minx then maxx = minx end
	if maxy < miny then maxy = miny end
	if pos.x < minx then pos.x = minx elseif pos.x > maxx then pos.x = maxx end
	if pos.y < miny then pos.y = miny elseif pos.y > maxy then pos.y = maxy end
end

--- Pin in G.ROOM space, inset from the visible top-right so the pill is never clipped.
function CH.pin()
	local box = CH.box
	if not box or box.REMOVED or not box.T then return end
	if G and G.ROOM then box.container = G.ROOM end
	if box.set_role then pcall(function() box:set_role({ role_type = "Major" }) end) end
	if box.alignment then
		box.alignment.type = "a"
		box.alignment.prev_type = "a"
		if box.alignment.type_list then box.alignment.type_list.a = true end
	end
	local win_w, win_h = CH.window_wh()
	local rx = (G and G.ROOM and G.ROOM.T and G.ROOM.T.x) or 0
	local ry = (G and G.ROOM and G.ROOM.T and G.ROOM.T.y) or 0
	local room_right = win_w - rx
	local room_top = -ry
	local room_bottom = win_h - ry
	local room_left = -rx
	local _, _, x1, y1 = CH.visible_extent(box)
	local w = (x1 and x1 > 0) and x1 or (box.T.w or CH.MATCH_W)
	local h = (y1 and y1 > 0) and y1 or (box.T.h or 0.42)
	local x = room_right - w - 0.25
	local y = room_top + 0.30
	if x < room_left then x = room_left end
	if x + w > room_right then x = math.max(room_left, room_right - w) end
	if y < room_top then y = room_top end
	if h > 0 and y + h > room_bottom then y = math.max(room_top, room_bottom - h) end
	box.T.x, box.T.y = x, y
	if box.VT then box.VT.x, box.VT.y = x, y end
	if box.velocity then box.velocity.x, box.velocity.y = 0, 0 end
	if CH.arm_box then CH.arm_box(box) end
end

function CH.make_bar()
	if not (Moveable and love and love.graphics and love.graphics.rectangle) then return nil end
	local obj = Moveable(0, 0, 0.28, 1.8)
	function obj:draw()
		if not (love and love.graphics and love.graphics.rectangle) then return end
		pcall(function()
			local g = love.graphics
			local T = self.VT or self.T
			if not T then return end
			local lines = CH.wrapped(CH.log_width(), 0.32)
			local top, thumb = CH.thumb_top(CH.scroll, #lines)
			local ts = G.TILESIZE or 20
			local sc = G.TILESCALE or 1
			g.push()
			g.scale(sc, sc)
			g.translate(T.x * ts, T.y * ts)
			g.setColor(0.15, 0.12, 0.1, 0.9)
			g.rectangle("fill", 0, 0, T.w * ts, T.h * ts, 3, 3)
			local th = math.max(0.18, thumb) * T.h * ts
			local ty = top * (T.h * ts - th)
			g.setColor(0.95, 0.78, 0.35, 1)
			g.rectangle("fill", 1, ty, T.w * ts - 2, th, 3, 3)
			g.setColor(1, 1, 1, 1)
			g.pop()
		end)
	end
	return obj
end

function CH.jump_scroll(y)
	local el = CH.find("mp_chat_scroll")
	local lines = CH.wrapped(CH.log_width(), 0.32)
	local maxs = CH.scroll_max(#lines)
	if not el or not el.T or not el.T.h or el.T.h <= 0 or maxs == 0 then
		CH.scroll = 0
		return
	end
	local ry = (G and G.ROOM and G.ROOM.T and G.ROOM.T.y) or 0
	local rel = ((y - ry) - el.T.y) / el.T.h
	if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
	CH.scroll = (1 - rel) * maxs
	CH.paint_slots(CH.log_width(), 0.32)
end

function CH.tick_scroll()
	if not (love and love.mouse and love.mouse.isDown) then
		CH.scroll_drag = nil
		return
	end
	local down = love.mouse.isDown(1)
	local x, y = CH.cursor()
	if not down or not y then CH.scroll_drag = nil; return end
	if not CH.scroll_drag then
		if CH.over("mp_chat_scroll", x, y) then
			CH.scroll_drag = { y = y }
			CH.jump_scroll(y)
		end
		return
	end
	local lines = CH.wrapped(CH.log_width(), 0.32)
	local maxs = CH.scroll_max(#lines)
	local dy = y - CH.scroll_drag.y
	CH.scroll_drag.y = y
	if maxs > 0 then
		CH.scroll = math.max(0, math.min(maxs, (CH.scroll or 0) - dy / 1.8 * maxs))
		CH.paint_slots(CH.log_width(), 0.32)
	end
end

--- Children keep the position calculated before the pin. Walk top-down, including the scrollbar.
function CH.sync_visual(box)
	if not box or not box.T then return end
	if box.hard_set_VT then
		pcall(function() box:hard_set_VT() end)
	elseif box.VT then
		box.VT.x, box.VT.y, box.VT.w, box.VT.h = box.T.x, box.T.y, box.T.w, box.T.h
	end
	local seen = {}
	local function snap(node)
		if type(node) ~= "table" or seen[node] then return end
		seen[node] = true
		if node ~= box and node.move_with_major and node.role and node.role.major then
			pcall(function() node:move_with_major(0) end)
			if node.velocity then node.velocity.x, node.velocity.y = 0, 0 end
		end
		if node.hard_set_VT then
			pcall(function() node:hard_set_VT() end)
		elseif node ~= box and node.VT and node.T then
			node.VT.x, node.VT.y, node.VT.w, node.VT.h = node.T.x, node.T.y, node.T.w, node.T.h
		end
		local obj = node.config and node.config.object
		if type(obj) == "table" then snap(obj) end
		if node.children then
			for _, child in ipairs(node.children) do snap(child) end
		end
	end
	snap(box)
	if box.UIRoot then snap(box.UIRoot) end
end

--- Box and cursor are both in the space collides_with_point already understands.
function CH.hits_point(node, cursor)
	if not (node and node.collides_with_point and cursor) then return false end
	local ok, hit = pcall(function() return node:collides_with_point(cursor) end)
	return ok and hit and true or false
end

function CH.note_hit(list, node)
	if not node then return end
	for _, have in ipairs(list) do
		if have == node then return end
	end
	if node.states and node.states.collide then node.states.collide.is = true end
	table.insert(list, 1, node)
end

--- The engine drops every click once the cursor leaves the playfield hash.
--- Put the chat controls back on the list so a bubble in the margin still receives them.
function CH.hook_cursor()
	if CH._cursor or not (Controller and Controller.get_cursor_collision) then return end
	CH._cursor = true
	local orig = Controller.get_cursor_collision
	function Controller:get_cursor_collision(cursor_trans)
		orig(self, cursor_trans)
		local box = CH.box
		if G and G.OVERLAY_MENU then return end
		if not box or box.REMOVED or not cursor_trans then return end
		if box.states and box.states.visible == false then return end
		self.collision_list = self.collision_list or {}
		local ids = { "mp_chat_open", "mp_chat_send", "mp_chat_close", "mp_chat_field", "mp_chat_scroll" }
		if box.get_UIE_by_ID then
			for _, id in ipairs(ids) do
				local el = box:get_UIE_by_ID(id)
				if CH.hits_point(el, cursor_trans) then CH.note_hit(self.collision_list, el) end
			end
		end
		if CH.hits_point(box, cursor_trans) then CH.note_hit(self.collision_list, box) end
	end
end

function CH.expire_suppress()
	if not CH.suppress_click then return end
	local now = love and love.timer and love.timer.getTime and love.timer.getTime()
	if type(CH.suppress_click) ~= "number" or not now or (now - CH.suppress_click) > 0.05 then
		CH.suppress_click = nil
	end
end

function CH.on_key(key)
	if not CH.focused then return false end
	local text = CH.draft.text or ""
	local caret = tonumber(CH.draft.caret) or #text
	if key == "return" or key == "kpenter" then CH.send(); return true end
	if key == "escape" then CH.focused = false; CH.paint_field(); return true end
	if key == "backspace" then CH.backspace(); return true end
	if key == "delete" then
		if caret < #text then
			CH.draft.text = text:sub(1, caret) .. text:sub(caret + 2)
			CH.paint_field()
		end
		return true
	end
	if key == "left" then CH.draft.caret = math.max(0, caret - 1); CH.paint_field(); return true end
	if key == "right" then CH.draft.caret = math.min(#text, caret + 1); CH.paint_field(); return true end
	if key == "home" then CH.draft.caret = 0; CH.paint_field(); return true end
	if key == "end" then CH.draft.caret = #text; CH.paint_field(); return true end
	if key == "v" and love and love.keyboard and love.keyboard.isDown and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") or love.keyboard.isDown("lgui")) then
		local clip = ""
		if love.system and love.system.getClipboardText then
			local ok, s = pcall(love.system.getClipboardText)
			if ok and type(s) == "string" then clip = s end
		end
		CH.insert_text(clip)
		return true
	end
	return true
end

function CH.on_wheel(dy)
	if G and G.OVERLAY_MENU then return false end
	if not CH.over_panel() then return false end
	local lines = CH.wrapped(CH.log_width(), 0.32)
	local maxs = CH.scroll_max(#lines)
	local step = (tonumber(dy) or 0) > 0 and 1 or -1
	CH.scroll = math.max(0, math.min(maxs, (CH.scroll or 0) + step))
	CH.paint_slots(CH.log_width(), 0.32)
	return true
end

function CH.over_panel()
	local x, y = CH.cursor()
	if x == nil then return false end
	local box = CH.box
	if box and CH.hits_point(box, { x = x, y = y }) then return true end
	return CH.over("mp_chat_lobby", x, y)
end

function CH.tick_focus()
	if not (MP.LOBBY and MP.LOBBY.code) or (not CH.in_lobby_menu() and not CH.open) then
		if CH.focused then CH.focused = false; CH.paint_field() end
	end
	if CH.focused then CH.paint_field() end
	if not (love and love.mouse and love.mouse.isDown) then return end
	local down = love.mouse.isDown(1) and true or false
	if down and not CH._was_down and CH.focused then
		local x, y = CH.cursor()
		if not CH.over("mp_chat_field", x, y) and not CH.over("mp_chat_send", x, y) then
			CH.focused = false
			CH.paint_field()
			if CH._pending then CH.refresh() end
		end
	end
	CH._was_down = down
end

function CH.sig()
	local cur = CH.current()
	local last = cur[#cur]
	return tostring(CH.open) .. "|" .. tostring(CH.state.view) .. "|" .. tostring(#cur) .. "|" .. tostring(last and last.id)
end

function CH.arm(node)
	if type(node) ~= "table" then return end
	node.states = node.states or {}
	node.states.hover = node.states.hover or {}
	node.states.click = node.states.click or {}
	node.states.collide = node.states.collide or {}
	node.states.hover.can = true
	node.states.click.can = true
	node.states.collide.can = true
end

function CH.arm_box(box)
	if not (box and box.get_UIE_by_ID) then return end
	for _, id in ipairs({ "mp_chat_open", "mp_chat_close", "mp_chat_send", "mp_chat_field" }) do
		local el = box:get_UIE_by_ID(id)
		if el then CH.arm(el) end
	end
end

function CH.register()
	if CH.registered then return end
	CH.registered = true
	G = G or {}
	G.FUNCS = G.FUNCS or {}
	G.FUNCS.mp_chat_toggle = function() CH.toggle() end
	G.FUNCS.mp_chat_arm = function(e) CH.arm(e) end
	G.FUNCS.mp_chat_focus = function()
		CH.focused = true
		CH.draft.caret = #(CH.draft.text or "")
		CH.paint_field()
	end
	G.FUNCS.mp_chat_close = function() CH.focused = false; CH.close() end
	G.FUNCS.mp_chat_send = function() CH.send() end
	if MP.register_action then
		MP.register_action("chat", function(p) CH.apply(p) end)
		MP.register_action("chatLog", function(p) CH.apply(p) end)
		MP.register_action("chatState", function(p) CH.apply(p) end)
		MP.register_action("chatReject", function() end)
	end
	CH.hook_cursor()
	if love and not CH._text then
		CH._text = true
		local textin = love.textinput
		function love.textinput(t)
			if CH.focused then CH.insert_text(t); return end
			if textin then return textin(t) end
		end
	end
	if love and love.keypressed and not CH._keys then
		CH._keys = true
		local keyp = love.keypressed
		function love.keypressed(key, scancode, rep)
			if CH.on_key(key) then return end
			if keyp then return keyp(key, scancode, rep) end
		end
	end
	if love and not CH._wheel then
		CH._wheel = true
		local wheel = love.wheelmoved
		function love.wheelmoved(x, y)
			if CH.on_wheel(y) then return end
			if wheel then return wheel(x, y) end
		end
	end
	if love and love.draw and not CH._draw then
		CH._draw = true
		local draw = love.draw
		function love.draw(...)
			local r = draw(...)
			if MP.CHAT and MP.CHAT.draw_front then MP.CHAT.draw_front() end
			return r
		end
	end
	if Game and Game.update then
		local upd = Game.update
		function Game:update(dt)
			local r = upd(self, dt)
			if MP.LOBBY and MP.LOBBY.code then
				if CH.box and (CH.box.REMOVED or CH.box_stage ~= G.STAGE) then
					CH.drop_box(CH.box)
					CH.box, CH._sig = nil, nil
				end
				CH.refresh()
				CH.raise()
				CH.pin()
				CH.tick_scroll()
			elseif CH.box then
				CH.focused = false
				CH.drop_box(CH.box)
				CH.box, CH._sig = nil, nil
			end
			CH.tick_focus()
			return r
		end
	end
end

return CH
