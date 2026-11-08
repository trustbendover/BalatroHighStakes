-- In-lobby text chat. The host repeats each line, in order, to everyone in that lobby.
-- The panel sits at the bottom left: a Chat button when closed, a short log when open.
-- It does not sit on the score or lives HUD, and it never shows a lobby code.
--
-- Each name is white text on a chip of that player's blind color (the ~N they already
-- use in the lobby). The message itself stays ordinary Balatro text.
MP.CHAT = MP.CHAT or {}
local CH = MP.CHAT

CH.RULES = CH.RULES or (MP.load_mp_file and MP.load_mp_file("networking/chat_rules.lua")) or nil
CH.state = CH.state or { view = "lobby", lobby = {}, match = {} }
CH.open = CH.open or false
CH.draft = CH.draft or { text = "" }
CH.SHOW = 4
CH.BOX_W = 5.2

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

--- White name on the player's blind color. Falls back to that blind's boss colour in-game.
function CH.chip_fill(col)
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

function CH.name_ink()
	if G and G.C and G.C.UI and G.C.UI.TEXT_LIGHT then return G.C.UI.TEXT_LIGHT end
	return "white"
end

function CH.current()
	local R = rules()
	if not R then return {} end
	return R.current(CH.state)
end

function CH.rows()
	local R = rules()
	local all = CH.current()
	local out, ui = {}, CH.chrome()
	local from = math.max(1, #all - CH.SHOW + 1)
	for i = from, #all do
		local m = all[i]
		local body = R and R.body(m, ui.watching) or tostring(m.text or "")
		if MP.FIT and MP.FIT.ellipsize then body = MP.FIT.ellipsize(body, 0.28, 3.2) end
		local name = R and R.display_name(m.name) or tostring(m.name or "?")
		if MP.FIT and MP.FIT.ellipsize then name = MP.FIT.ellipsize(name, 0.28, 1.6) end
		out[#out + 1] = { name = name, body = body, col = tonumber(m.col) or 1, watch = m.watch and true or false }
	end
	return out
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

local function chip(row)
	return { n = G.UIT.C, config = { align = "cm", padding = 0.04, r = 0.2, colour = CH.chip_fill(row.col), minw = 0.8, maxw = 1.7 }, nodes = {
		{ n = G.UIT.T, config = { text = row.name, scale = 0.28, colour = CH.name_ink(), shadow = true } },
	} }
end

--- Bottom-left panel. A closed button stays out of the score and lives row.
function CH.definition()
	local ui = CH.chrome()
	local nodes = {}
	if not CH.open then
		nodes[1] = UIBox_button({ id = "mp_chat_open", button = "mp_chat_toggle", label = { ui.open },
			minw = 2.2, minh = 0.45, scale = 0.32, colour = G.C.BLUE, col = true })
	else
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = {
			{ n = G.UIT.T, config = { text = ui.title, scale = 0.4, colour = G.C.GOLD or G.C.WHITE, shadow = true } },
		} }
		local shown = CH.rows()
		if #shown == 0 then shown[1] = { name = "", body = "", col = 1 } end
		for _, row in ipairs(shown) do
			nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cl", padding = 0.02, minw = CH.BOX_W, maxw = CH.BOX_W }, nodes = {
				chip(row),
				{ n = G.UIT.C, config = { minw = 0.08 } },
				{ n = G.UIT.C, config = { align = "cl", maxw = 3.2 }, nodes = {
					{ n = G.UIT.T, config = { text = row.body, scale = 0.28, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
				} },
			} }
		end
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
			create_text_input({ w = 3.4, h = 0.5, max_length = 80, prompt_text = ui.prompt,
				ref_table = CH.draft, ref_value = "text", extended_corpus = true, keyboard_offset = 1 }),
		} }
		nodes[#nodes + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
			UIBox_button({ id = "mp_chat_send", button = "mp_chat_send", label = { ui.send },
				minw = 1.6, minh = 0.42, scale = 0.32, colour = G.C.GREEN, col = true }),
			{ n = G.UIT.C, config = { minw = 0.15 } },
			UIBox_button({ id = "mp_chat_close", button = "mp_chat_close", label = { ui.close },
				minw = 1.6, minh = 0.42, scale = 0.32, colour = G.C.RED, col = true }),
		} }
	end
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, padding = 0.04 }, nodes = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = nodes },
	} }
end

function CH.refresh(force)
	if not force and CH._sig == CH.sig() then return end
	CH._sig = CH.sig()
	pcall(function()
		if not (MP.LOBBY and MP.LOBBY.code and G and G.ROOM_ATTACH and UIBox) then
			if CH.box then pcall(function() CH.box:remove() end); CH.box = nil end
			return
		end
		if CH.box then pcall(function() CH.box:remove() end); CH.box = nil end
		CH.box = UIBox({
			definition = CH.definition(),
			config = { align = "bl", offset = { x = 0.15, y = -0.15 }, major = G.ROOM_ATTACH, bond = "Weak" },
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
