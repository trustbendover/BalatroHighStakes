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
CH.SHOW = 4

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

function CH.rows(scale, wide)
	local R = rules()
	local all = CH.current()
	local out, ui = {}, CH.chrome()
	scale = scale or 0.32
	wide = wide or CH.LOBBY_W
	local from = math.max(1, #all - CH.SHOW + 1)
	for i = from, #all do
		local m = all[i]
		local body = R and R.body(m, ui.watching) or tostring(m.text or "")
		local name = R and R.display_name(m.name) or tostring(m.name or "?")
		if MP.FIT and MP.FIT.ellipsize then
			name = MP.FIT.ellipsize(name, scale, 1.7)
			body = MP.FIT.ellipsize(body, scale, math.max(1.5, wide - 1.9))
		end
		out[#out + 1] = { name = name, body = body, col = tonumber(m.col) or 1, watch = m.watch and true or false }
	end
	return out
end

local function message_row(row, scale, wide)
	local name = row.name ~= "" and (row.name .. ":") or ""
	return { n = G.UIT.R, config = { align = "cl", padding = 0.03, minw = wide }, nodes = {
		{ n = G.UIT.C, config = { align = "cl", minw = 1.6 }, nodes = {
			{ n = G.UIT.T, config = { text = name, scale = scale, colour = CH.name_colour(row.col), shadow = true } },
		} },
		{ n = G.UIT.C, config = { align = "cl", minw = 0.08 } },
		{ n = G.UIT.C, config = { align = "cl" }, nodes = {
			{ n = G.UIT.T, config = { text = row.body or "", scale = scale, colour = CH.body_ink(), shadow = true } },
		} },
	} }
end

--- Title-free log plus one row: the message field and Send (and Close, in a match).
function CH.panel_nodes(wide, scale, input_w, with_close)
	local ui = CH.chrome()
	local nodes = {}
	local shown = CH.rows(scale, wide)
	if #shown == 0 then
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.04, minw = wide, minh = 0.32 }, nodes = {
			{ n = G.UIT.T, config = { text = ui.prompt, scale = scale, colour = G.C.UI.TEXT_INACTIVE or CH.body_ink() } },
		} }
	end
	for _, row in ipairs(shown) do nodes[#nodes + 1] = message_row(row, scale, wide) end
	local controls = {
		{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = {
			create_text_input({ w = input_w, h = 0.48, max_length = 80, prompt_text = ui.prompt,
				ref_table = CH.draft, ref_value = "text", extended_corpus = true, keyboard_offset = 1,
				callback = function() CH.send() end }),
		} },
		{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = {
			UIBox_button({ id = "mp_chat_send", button = "mp_chat_send", label = { ui.send },
				minw = 1.3, minh = 0.48, scale = scale, colour = G.C.GREEN, col = true }),
		} },
	}
	if with_close then
		controls[#controls + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = {
			UIBox_button({ id = "mp_chat_close", button = "mp_chat_close", label = { ui.close },
				minw = 1.15, minh = 0.48, scale = scale, colour = G.C.RED, col = true }),
		} }
	end
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04, minw = wide }, nodes = controls }
	return nodes
end

--- Lobby: compact panel under the start row. Input and Send share one row.
function CH.lobby_row()
	local wide = CH.LOBBY_W
	return { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = {
		{ n = G.UIT.C, config = { id = "mp_chat_lobby", align = "cm", minw = wide + 0.24, padding = 0.06, r = 0.1,
			colour = G.C.BLACK, emboss = 0.05 }, nodes = CH.panel_nodes(wide, 0.32, 4.2, false) },
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
	return CH.input_args() ~= nil
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
	CH.blank_letters()
	CH.release_input()
	-- A host echo can arrive inside Client.send. Rebuilding the box in that call
	-- frees the text field while Enter is still using it, so the redraw waits a frame.
	CH._sending = true
	if MP.LOBBY and MP.LOBBY.code and Client and Client.send then
		Client.send({ action = "chat", text = text })
	end
	CH._sending = false
	CH._pending = true
end

function CH.toggle()
	CH.open = not CH.open
	if CH.open then CH.seen = #CH.current() end
	CH.refresh(true)
end

function CH.close()
	CH.open = false
	CH.refresh(true)
end

function CH.unread()
	if CH.open then return 0 end
	return math.max(0, #CH.current() - (CH.seen or 0))
end

--- In a match the panel is a drawer inside the screen. "bl" without "i" sits below the room.
--- Closed: only the Chat button. Open: the log, with the field, Send, and Close on one row.
function CH.definition()
	local ui = CH.chrome()
	local wide = CH.MATCH_W
	if not CH.open then
		local n = CH.unread()
		local label = n > 0 and (ui.open .. " " .. n) or ui.open
		return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0 }, nodes = {
			UIBox_button({ id = "mp_chat_open", button = "mp_chat_toggle", label = { label },
				minw = 1.8, minh = 0.42, scale = 0.32, colour = G.C.BLUE, col = true }),
		} }
	end
	CH.seen = #CH.current()
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.04, minw = wide }, nodes = {
		{ n = G.UIT.R, config = { id = "mp_chat_drag", align = "cm", padding = 0.04, minh = 0.32, r = 0.06, colour = G.C.RED, hover = true }, nodes = {
			{ n = G.UIT.T, config = { text = ui.title, scale = 0.3, colour = G.C.WHITE, shadow = true } },
		} },
		{ n = G.UIT.C, config = { align = "cm", padding = 0.05, r = 0.1, colour = G.C.BLACK, emboss = 0.05, minw = wide + 0.16 }, nodes = CH.panel_nodes(wide, 0.32, 2.9, true) },
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
	if CH._sending or CH.typing() then
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
		CH.box._mp_chat = true
		CH.box_stage = G.STAGE
		CH.silence(CH.box)
		CH.raise()
		CH.apply_pos()
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
	CH.sync_visual(box)
	-- UIBox:draw skips a second pass in the same frame. This is the only pass.
	if box.FRAME then box.FRAME.DRAW = -1 end
	CH._painting = true
	pcall(function() box:draw() end)
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

function CH.over(id, x, y)
	local box = CH.box
	if not (box and box.get_UIE_by_ID and x) then return false end
	local el = box:get_UIE_by_ID(id)
	return el and el.collides_with_point and el:collides_with_point({ x = x, y = y }) or false
end

--- The playfield is inset. G.ROOM.T.w is TILE_W, while the window is TILE_W plus the padding on both sides.
--- Clamping to the room let the bubble reach x = 0 and stopped it short of the right and bottom edges.
function CH.screen_span()
	local right, bottom
	local scale = G and G.TILESCALE and G.TILESIZE and (G.TILESCALE * G.TILESIZE) or 0
	if scale > 0 and love and love.graphics and love.graphics.getWidth then
		local ok, w, h = pcall(function()
			return love.graphics.getWidth(), love.graphics.getHeight()
		end)
		if ok and w and h and w > 0 and h > 0 then
			right, bottom = w / scale, h / scale
		end
	end
	if G and G.WINDOWTRANS and G.WINDOWTRANS.w and G.WINDOWTRANS.w > 0 then
		if not right or G.WINDOWTRANS.w > right then right = G.WINDOWTRANS.w end
		if G.WINDOWTRANS.h and (not bottom or G.WINDOWTRANS.h > bottom) then bottom = G.WINDOWTRANS.h end
	end
	if not right and G and G.TILE_W then
		local padw = G.ROOM_PADDING_W or 1
		local padh = G.ROOM_PADDING_H or 0.7
		right = G.TILE_W + 2 * padw
		bottom = (G.TILE_H or 0) + 2 * padh
	end
	if not right and G and G.ROOM and G.ROOM.T then
		local room = G.ROOM.T
		right = (room.x or 0) + (room.w or 0) + ((G and G.ROOM_PADDING_W) or 1)
		bottom = (room.y or 0) + (room.h or 0) + ((G and G.ROOM_PADDING_H) or 0.7)
	end
	return 0, 0, right or 0, bottom or 0
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
	local left, top, right, bottom = CH.screen_span()
	local x0, y0, x1, y1 = CH.visible_extent(box)
	local minx, maxx = left - x0, right - x1
	local miny, maxy = top - y0, bottom - y1
	if maxx < minx then maxx = minx end
	if maxy < miny then maxy = miny end
	if pos.x < minx then pos.x = minx elseif pos.x > maxx then pos.x = maxx end
	if pos.y < miny then pos.y = miny elseif pos.y > maxy then pos.y = maxy end
end

--- A dragged panel is no longer welded to the room corner.
function CH.apply_pos()
	local box, pos = CH.box, CH.pos
	if not box or box.REMOVED or not pos or not box.T then return end
	if box.set_role then pcall(function() box:set_role({ role_type = "Major" }) end) end
	if box.alignment then
		box.alignment.type = "a"
		box.alignment.prev_type = "a"
		if box.alignment.type_list then box.alignment.type_list.a = true end
	end
	CH.clamp_pos()
	box.T.x, box.T.y = pos.x, pos.y
	if box.VT then box.VT.x, box.VT.y = pos.x, pos.y end
	if box.velocity then box.velocity.x, box.velocity.y = 0, 0 end
	CH.sync_visual(box)
end

--- Children keep the position calculated before the drag. Snap T and VT to the box.
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
		if node ~= box and node.move_with_major and node.role and node.role.major == box then
			pcall(function() node:move_with_major(0) end)
			if node.hard_set_VT then pcall(function() node:hard_set_VT() end) end
			if node.velocity then node.velocity.x, node.velocity.y = 0, 0 end
		end
		if node.children then
			for _, child in pairs(node.children) do snap(child) end
		end
	end
	snap(box)
end

function CH.tick_drag()
	if CH.typing() or not (CH.box and CH.box.T and love and love.mouse and love.mouse.isDown) then return end
	local x, y = CH.cursor()
	if not x then return end
	local down = love.mouse.isDown(1)
	if down and not CH.drag then
		local on_handle = CH.over("mp_chat_drag", x, y) or CH.over("mp_chat_open", x, y)
		local on_control = CH.over("mp_chat_send", x, y) or CH.over("mp_chat_close", x, y) or CH.over("text_input", x, y)
		if on_handle and not on_control then
			CH.drag = { x = x, y = y, bx = CH.box.T.x, by = CH.box.T.y, moved = false }
		end
	elseif down and CH.drag then
		local dx, dy = x - CH.drag.x, y - CH.drag.y
		if math.abs(dx) + math.abs(dy) > 0.12 then CH.drag.moved = true end
		if CH.drag.moved then
			CH.pos = { x = CH.drag.bx + dx, y = CH.drag.by + dy }
			CH.apply_pos()
		end
	elseif CH.drag then
		if CH.drag.moved then CH.suppress_click = true end
		CH.drag = nil
	end
	if CH.pos then CH.apply_pos() end
end

function CH.sig()
	local cur = CH.current()
	local last = cur[#cur]
	return tostring(CH.open) .. "|" .. tostring(CH.state.view) .. "|" .. tostring(#cur) .. "|" .. tostring(last and last.id)
end

function CH.register()
	if CH.registered then return end
	CH.registered = true
	G = G or {}
	G.FUNCS = G.FUNCS or {}
	G.FUNCS.mp_chat_toggle = function()
		-- The click is dispatched before this frame's drag tick, while the drag is still recorded.
		if (CH.drag and CH.drag.moved) or CH.suppress_click then CH.suppress_click = nil; return end
		CH.toggle()
	end
	G.FUNCS.mp_chat_close = function() CH.close() end
	G.FUNCS.mp_chat_send = function() CH.send() end
	if MP.register_action then
		MP.register_action("chat", function(p) CH.apply(p) end)
		MP.register_action("chatLog", function(p) CH.apply(p) end)
		MP.register_action("chatState", function(p) CH.apply(p) end)
		MP.register_action("chatReject", function() end)
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
				CH.tick_drag()
			elseif CH.box then
				CH.drop_box(CH.box)
				CH.box, CH._sig = nil, nil
			end
			return r
		end
	end
end

return CH
