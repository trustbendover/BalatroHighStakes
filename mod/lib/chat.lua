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
		if CH.box then pcall(function() CH.box:remove() end); CH.box = nil end
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
		CH.box_stage = G.STAGE
	end)
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
	G.FUNCS.mp_chat_toggle = function() CH.toggle() end
	G.FUNCS.mp_chat_close = function() CH.close() end
	G.FUNCS.mp_chat_send = function() CH.send() end
	if MP.register_action then
		MP.register_action("chat", function(p) CH.apply(p) end)
		MP.register_action("chatLog", function(p) CH.apply(p) end)
		MP.register_action("chatState", function(p) CH.apply(p) end)
		MP.register_action("chatReject", function() end)
	end
	if Game and Game.update then
		local upd = Game.update
		function Game:update(dt)
			local r = upd(self, dt)
			if MP.LOBBY and MP.LOBBY.code then
				if CH.box and (CH.box.REMOVED or CH.box_stage ~= G.STAGE) then CH.box = nil; CH._sig = nil end
				CH.refresh()
			elseif CH.box then
				pcall(function() CH.box:remove() end)
				CH.box, CH._sig = nil, nil
			end
			return r
		end
	end
end

return CH
