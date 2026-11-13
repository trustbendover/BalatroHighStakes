-- In-lobby text chat. The host repeats each line, in order, to everyone in that lobby.
-- In the lobby the panel is part of the lobby menu, under the start row: 8.6 wide, text at 0.42.
-- In a match it is a bottom-left drawer, inset 0.45 by 0.6, 7.6 wide, and it can be closed.
-- It never shows a lobby code. Names are that player's blind color, then a colon, then light text.
MP.CHAT = MP.CHAT or {}
local CH = MP.CHAT

CH.RULES = CH.RULES or (MP.load_mp_file and MP.load_mp_file("networking/chat_rules.lua")) or nil
CH.state = CH.state or { view = "lobby", lobby = {}, match = {} }
CH.open = CH.open or false
CH.draft = CH.draft or { text = "" }
-- Lobby panel sits in the lobby menu, under the start row: 8.6 wide, text at 0.42.
-- The match drawer is a toggle at the bottom-left, inset from the corner, 7.6 wide.
-- A container maxw shrinks Balatro text permanently, so these panels use minw only.
CH.LOBBY_W = 8.2
CH.MATCH_W = 7.2
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
	scale = scale or 0.42
	wide = wide or CH.LOBBY_W
	local from = math.max(1, #all - CH.SHOW + 1)
	for i = from, #all do
		local m = all[i]
		local body = R and R.body(m, ui.watching) or tostring(m.text or "")
		local name = R and R.display_name(m.name) or tostring(m.name or "?")
		if MP.FIT and MP.FIT.ellipsize then name = MP.FIT.ellipsize(name, scale, wide - 0.4) end
		out[#out + 1] = { name = name, body = body, col = tonumber(m.col) or 1, watch = m.watch and true or false }
	end
	return out
end

function CH.wrap(text, scale, wide)
	if MP.UTILS and MP.UTILS.fit_lines then return MP.UTILS.fit_lines(text, scale, wide, 2) end
	return { tostring(text or "") }, scale
end

local function message_rows(row, scale, wide)
	local nodes = {}
	local name = row.name ~= "" and (row.name .. ":") or ""
	if name ~= "" then
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.02, minw = wide }, nodes = {
			{ n = G.UIT.T, config = { text = name, scale = scale, colour = CH.name_colour(row.col), shadow = true } },
		} }
	end
	local lines = CH.wrap(row.body or "", scale * 0.95, wide)
	if (row.body or "") == "" then lines = {} end
	for _, line in ipairs(lines) do
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.01, minw = wide }, nodes = {
			{ n = G.UIT.T, config = { text = line, scale = scale * 0.95, colour = CH.body_ink(), shadow = true } },
		} }
	end
	return nodes
end

--- The readable panel: title, messages, a text field, and Send. No maxw, so the text keeps its scale.
function CH.panel_nodes(wide, scale, input_w)
	local ui = CH.chrome()
	local nodes = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.04, minw = wide }, nodes = {
			{ n = G.UIT.T, config = { text = ui.title, scale = scale + 0.06, colour = G.C.GOLD or G.C.WHITE, shadow = true } },
		} },
	}
	local shown = CH.rows(scale, wide)
	if #shown == 0 then
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.08, minw = wide, minh = 0.45 }, nodes = {
			{ n = G.UIT.T, config = { text = ui.prompt, scale = scale, colour = G.C.UI.TEXT_INACTIVE or CH.body_ink() } },
		} }
	end
	for _, row in ipairs(shown) do
		for _, line in ipairs(message_rows(row, scale, wide)) do nodes[#nodes + 1] = line end
	end
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06, minw = wide }, nodes = {
		create_text_input({ w = input_w, h = 0.7, max_length = 80, prompt_text = ui.prompt,
			ref_table = CH.draft, ref_value = "text", extended_corpus = true, keyboard_offset = 1 }),
	} }
	nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04, minw = wide }, nodes = {
		UIBox_button({ id = "mp_chat_send", button = "mp_chat_send", label = { ui.send },
			minw = 2.6, minh = 0.6, scale = scale, colour = G.C.GREEN, col = true }),
	} }
	return nodes
end

--- Lobby: a full panel under the start row, centered with the lobby. Not a screen-corner box.
function CH.lobby_row()
	local wide = CH.LOBBY_W
	return { n = G.UIT.R, config = { align = "cm", padding = 0.15 }, nodes = {
		{ n = G.UIT.C, config = { id = "mp_chat_lobby", align = "cm", minw = wide + 0.4, padding = 0.14, r = 0.1,
			colour = G.C.BLACK, emboss = 0.05 }, nodes = CH.panel_nodes(wide, 0.42, 6.6) },
	} }
end

function CH.apply(msg)
	local R = rules()
	if R then CH.state = R.reduce(CH.state, msg) end
	CH.refresh()
end

function CH.send()
	local text = tostring(CH.draft.text or "")
	CH.draft.text = ""
	if not (MP.LOBBY and MP.LOBBY.code and Client and Client.send) then return end
	Client.send({ action = "chat", text = text })
end

function CH.toggle()
	CH.open = not CH.open
	CH.refresh(true)
end

function CH.close()
	CH.open = false
	CH.refresh(true)
end

--- In a match the panel is a drawer. Closed, it is one button. Open, it is wide enough to read and type.
function CH.definition()
	local ui = CH.chrome()
	local wide = CH.MATCH_W
	local nodes
	if not CH.open then
		nodes = { UIBox_button({ id = "mp_chat_open", button = "mp_chat_toggle", label = { ui.open },
			minw = 3.0, minh = 0.62, scale = 0.42, colour = G.C.BLUE, col = true }) }
	else
		nodes = CH.panel_nodes(wide, 0.38, 5.8)
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.02, minw = wide }, nodes = {
			UIBox_button({ id = "mp_chat_close", button = "mp_chat_close", label = { ui.close },
				minw = 2.6, minh = 0.55, scale = 0.38, colour = G.C.RED, col = true }),
		} }
	end
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.05, minw = wide + 0.5 }, nodes = {
		{ n = G.UIT.C, config = { align = "cm", padding = 0.12, r = 0.1, colour = G.C.BLACK, emboss = 0.05, minw = wide + 0.4 }, nodes = nodes },
	} }
end

function CH.in_lobby_menu()
	return G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and MP.LOBBY and MP.LOBBY.code
end

function CH.relayout_lobby()
	if CH._rebuilding or G.OVERLAY_MENU then return end
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
	if not force and CH._sig == CH.sig() and CH._stage == stage then return end
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
		CH.box = UIBox({
			definition = CH.definition(),
			config = { align = "bl", offset = { x = 0.45, y = 0.6 }, major = G.ROOM_ATTACH, bond = "Weak" },
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
