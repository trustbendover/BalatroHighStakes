-- Heat Rush on the client: the meter, Overdrive, rewards, and the track.
local H = MP.load_mp_file and MP.load_mp_file("networking/heat_rules.lua") or nil
if not H then
	local ok, m = pcall(dofile, "networking/heat_rules.lua")
	if ok then H = m end
end
if not H then return end
MP.HEAT = H

H.view = H.view or { text = "" }

function H.active()
	local mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode
	return tostring(mode or ""):find(H.KEY, 1, true) and true or false
end

function H.register_music()
	if not (SMODS and SMODS.Sound and NFS and NFS.getInfo and MP.path) then return end
	if not NFS.getInfo(MP.path .. "/assets/sounds/music_heat_rush.ogg") then return end
	SMODS.Sound({
		key = "music_heat_rush",
		path = "music_heat_rush.ogg",
		sync = false,
		pitch = 1,
		volume = 1,
		select_music_track = function()
			local in_lobby = (MP.LOBBY and MP.LOBBY.code ~= nil) and true or false
			local stage = (G and G.STAGES and G.STATES and G.STAGE == G.STAGES.RUN and G.STATE ~= G.STATES.MENU) and "run" or "menu"
			local spec = MP.SPECTATE
			local seated = spec and spec.state and (spec.state.active or spec.state.joined)
			local watching = in_lobby and (seated or (stage == "run" and spec and spec.watching and spec.watching()))
			return H.music_priority({
				mode = MP.LOBBY and MP.LOBBY.config and MP.LOBBY.config.gamemode,
				in_lobby = in_lobby,
				watching = watching and true or false,
				stage = stage,
			})
		end,
	})
end

H.register_music()

function H.now()
	return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

--- The clock starts when a blind is chosen. Selecting a blind does not earn Heat.
function H.arm()
	H.reported = false
	if H.active() then H.started = H.now() end
end

--- Called when the blind is actually beaten. Once per blind, so end_round and
--- Blind:defeat can both call it.
function H.report(blind)
	if H.reported then return end
	if not (Client and Client.send and H.active()) then return end
	local round = G and G.GAME and G.GAME.current_round or {}
	local kind = "small"
	if blind and blind.boss then kind = "boss"
	elseif blind and ((blind.get_type and blind:get_type() == "Big") or blind.name == "Big Blind") then kind = "big" end
	local now = H.now()
	local par = H.PAR_SECONDS[kind] or 90
	local seconds = H.started and (now - H.started) or (par + 1)
	H.started = nil
	H.reported = true
	Client.send({
		action = "heatReport",
		blind = kind,
		hands = tonumber(round.hands_played) or 1,
		seconds = seconds,
	})
end

--- Window size in tiles. The playfield (G.ROOM) is inset inside this; consumables sit on the playfield.
function H.screen_rect()
	local scale = (G and G.TILESCALE and G.TILESIZE and (G.TILESCALE * G.TILESIZE)) or 0
	local wt = G and G.WINDOWTRANS
	local w, h
	if wt and scale > 0 and tonumber(wt.real_window_w) and wt.real_window_w > 0 then
		w = wt.real_window_w / scale
		if tonumber(wt.real_window_h) and wt.real_window_h > 0 then h = wt.real_window_h / scale end
	end
	if (not w or w <= 0) and scale > 0 and love and love.graphics and love.graphics.getWidth then
		local ok, pw, ph = pcall(function() return love.graphics.getWidth(), love.graphics.getHeight() end)
		if ok and type(pw) == "number" and pw > 0 then
			w = pw / scale
			if type(ph) == "number" and ph > 0 then h = ph / scale end
		end
	end
	if (not w or w <= 0) and G and G.ROOM and G.ROOM.T then
		local room = G.ROOM.T
		w = (room.x or 0) + (room.w or 0) + ((G and G.ROOM_PADDING_W) or 1)
		h = (room.y or 0) + (room.h or 0) + ((G and G.ROOM_PADDING_H) or 0.7)
	end
	if not w or w <= 0 then return nil end
	return { x = 0, y = 0, w = w, h = h or w }
end

function H.blockers()
	local list = {}
	local room = G and G.ROOM and G.ROOM.T
	local rx = (room and room.x) or 0
	local ry = (room and room.y) or 0
	-- Card areas and the chat box are room-local. The room offset is applied when they draw.
	local function add(box)
		local t = box and not box.REMOVED and box.T
		if t and t.w and t.w > 0 and t.h and t.h > 0 then
			list[#list + 1] = { x = (t.x or 0) + rx, y = (t.y or 0) + ry, w = t.w, h = t.h }
		end
	end
	local chat = MP.CHAT
	if chat and chat.box then add(chat.box) end
	if G and G.jokers then add(G.jokers) end
	if G and G.consumeables then add(G.consumeables) end
	if G and G.deck then add(G.deck) end
	if G and G.shop then add(G.shop) end
	return list
end

function H.place_meter()
	H.meter = H.layout_meter(H.screen_rect(), H.blockers())
	return H.meter
end

function H.in_run()
	return G and G.STAGES and G.STAGE == G.STAGES.RUN and true or false
end

function H.draw_front()
	if not (love and love.graphics and H.active and H.active()) then return end
	if G and (G.OVERLAY_MENU or not G.STAGES or G.STAGE ~= G.STAGES.RUN) then return end
	local box = H.place_meter()
	if not box then return end
	local g = MP.GAME or {}
	local heat = H.shown
	if heat == nil then heat = tonumber(g.heat) or 0 end
	local gpx = love.graphics
	local ts = (G and G.TILESIZE) or 20
	local sc = (G and G.TILESCALE) or 1
	local now = H.now()
	local function px(n) return n * ts end
	local function pill(x, y, w, h, col, mode)
		gpx.setColor(col[1], col[2], col[3], col[4] or 1)
		local rad = math.min(w, h) * 0.5
		gpx.rectangle(mode or "fill", x, y, math.max(1, w), math.max(1, h), rad, rad)
	end
	gpx.push()
	gpx.scale(sc, sc)
	local x, y, w, h = px(box.x), px(box.y), px(box.w), px(box.h)
	local pad = math.max(2, ts * 0.06)
	H.draw_flame(box)
	pill(x, y, w, h, { 0.04, 0.035, 0.04, 0.72 })
	local fill = H.meter_fill(box, heat, H.MAX)
	if fill and fill.h > 0.01 then
		local slices = 18
		local fh, fy = px(fill.h), px(fill.y)
		local sh = fh / slices
		local clipped = gpx.stencil and gpx.setStencilTest and pcall(function()
			gpx.stencil(function()
				local rad = math.min(w - pad * 2, fh) * 0.5
				gpx.rectangle("fill", x + pad, fy, math.max(1, w - pad * 2), math.max(1, fh), rad, rad)
			end, "replace", 1)
			gpx.setStencilTest("greater", 0)
		end)
		for i = 0, slices - 1 do
			local u = (i + 0.5) / slices
			local cr, cg, cb = H.meter_color(u * heat, H.MAX)
			gpx.setColor(cr, cg, cb, 0.95)
			gpx.rectangle("fill", x + pad, fy + fh - (i + 1) * sh, math.max(1, w - pad * 2), sh + 0.5)
		end
		local shine = (math.sin(now * 1.6) * 0.5 + 0.5) * fh
		gpx.setColor(1, 0.95, 0.8, 0.22)
		gpx.rectangle("fill", x + pad, fy + fh - shine - sh, math.max(1, (w - pad * 2) * 0.42), sh * 2)
		if clipped then pcall(function() gpx.setStencilTest() end) end
	end
	for _, tick in ipairs(H.meter_ticks(box)) do
		local ty = px(tick.y)
		gpx.setColor(1, 1, 1, 0.28)
		gpx.rectangle("fill", x + w * 0.22, ty, w * 0.56, math.max(1, ts * 0.035))
	end
	gpx.setColor(1, 0.96, 0.9, 0.55)
	gpx.setLineWidth(1)
	pill(x + 0.5, y + 0.5, w - 1, h - 1, { 1, 0.96, 0.9, 0.45 }, "line")
	local labels = H.meter_labels(box, heat, g.heat_best)
	-- Scale about the centre of each line. printf grows from the left of the
	-- box, which drew "0" to the right of "HEAT" on one row.
	local function line(node, col, scale)
		if not node or node.text == "" or node.text:find("\n", 1, true) then return end
		local font = gpx.getFont and gpx.getFont()
		local fh = (font and font.getHeight and font:getHeight()) or (ts * 0.8)
		local slot = px(node.h)
		local s = math.min(scale, (slot > 0) and (slot * 0.9 / math.max(1, fh)) or scale)
		gpx.setColor(col[1], col[2], col[3], col[4] or 1)
		gpx.push()
		gpx.translate(px(node.x + node.w / 2), px(node.y + node.h / 2))
		gpx.scale(s, s)
		local tw = (font and font.getWidth and font:getWidth(node.text)) or 0
		local th = (font and font.getHeight and font:getHeight()) or 0
		if gpx.print then gpx.print(node.text, -tw / 2, -th / 2) end
		gpx.pop()
	end
	line(labels.number, { 1, 0.97, 0.92, 1 }, 0.7)
	line(labels.caption, { 1, 0.78, 0.38, 0.95 }, 0.34)
	line(labels.best, { 0.92, 0.84, 0.62, 0.95 }, 0.32)
	local mx, my = H.pointer()
	if H.hit_meter(box, mx, my) then
		gpx.setColor(1, 0.86, 0.45, 1)
		local hint = "How to play"
		if localize then
			local okh, s = pcall(localize, "k_heat_how")
			if okh and type(s) == "string" and s ~= "k_heat_how" and s ~= "ERROR" then hint = s end
		end
		gpx.printf(hint, x - ts * 0.8, y - ts * 0.32, w + ts * 1.6, "center", 0, 0.4, 0.4)
	end
	gpx.setColor(1, 1, 1, 1)
	gpx.pop()
end

function H.sync_flame(heat, dt)
	G.ARGS = G.ARGS or {}
	local tab = H.flame_step(G.ARGS.heat_flames, H.flame_target(heat, H.MAX), dt)
	local chips = (G.C and G.C.UI_CHIPS) or { 1, 0.45, 0.15, 1 }
	local yellow = (G.C and G.C.YELLOW) or { 1, 0.9, 0.4, 1 }
	local lick = { 1, 1, 1, 1 }
	for i = 1, 3 do
		local a = chips[i] or 1
		local b = yellow[i] or 1
		lick[i] = math.min(math.max(((a * 0.5 + b * 0.5) + 0.1) ^ 2, 0.1), 1)
	end
	tab.colour_1 = { chips[1] or 1, chips[2] or 1, chips[3] or 1, chips[4] or 1 }
	tab.colour_2 = lick
	G.ARGS.heat_flames = tab
	return tab
end

function H.ensure_flame_sprite()
	if H.flame_sprite and not H.flame_sprite.REMOVED then return H.flame_sprite end
	if not (Sprite and G and G.ASSET_ATLAS and G.ASSET_ATLAS.ui_1 and G.SHADERS and G.SHADERS.flame) then return nil end
	local ok, sprite = pcall(Sprite, 0, 0, H.METER_W, H.METER_H, G.ASSET_ATLAS.ui_1, { x = 2, y = 0 })
	if not ok or type(sprite) ~= "table" or not sprite.define_draw_steps then return nil end
	sprite.container = sprite
	local tab = G.ARGS and G.ARGS.heat_flames
	if not tab then return nil end
	sprite:define_draw_steps({ {
		shader = "flame",
		send = {
			{ name = "time", ref_table = tab, ref_value = "timer" },
			{ name = "amount", ref_table = tab, ref_value = "real_intensity" },
			{ name = "image_details", ref_table = sprite, ref_value = "image_dims" },
			{ name = "texture_details", ref_table = sprite.RETS or sprite, ref_value = "get_pos_pixel" },
			{ name = "colour_1", ref_table = tab, ref_value = "colour_1" },
			{ name = "colour_2", ref_table = tab, ref_value = "colour_2" },
			{ name = "id", val = sprite.ID or 1 },
		},
	} })
	if sprite.get_pos_pixel then pcall(function() sprite:get_pos_pixel() end) end
	H.flame_sprite = sprite
	return sprite
end

function H.draw_flame(box)
	local tab = G and G.ARGS and G.ARGS.heat_flames
	if not box or not tab or (tab.real_intensity or 0) < 0.1 then return end
	local sprite = H.ensure_flame_sprite()
	if not sprite or not sprite.draw then return end
	local pad = 0.45
	local T = sprite.VT or sprite.T
	if not T then return end
	T.x, T.y = box.x - pad, box.y - pad * 0.15
	T.w, T.h = box.w + pad * 2, box.h + pad
	if sprite.T and sprite.VT and sprite.T ~= sprite.VT then
		sprite.T.x, sprite.T.y, sprite.T.w, sprite.T.h = T.x, T.y, T.w, T.h
	end
	sprite.container = sprite
	local g = love.graphics
	g.push()
	g.origin()
	pcall(function() sprite:draw() end)
	g.pop()
end

--- Raise the vanilla fire bed when Heat is burning, without lowering the chips/mult flame.
function H.bind_fire_sound()
	local sounds = G and G.ARGS and G.ARGS.ambient_sounds
	if not sounds or H._fire_bound then return end
	H._fire_orig = {}
	for _, name in ipairs({ "ambientFire1", "ambientFire2", "ambientFire3" }) do
		local spec = sounds[name]
		if type(spec) == "table" and spec.volfunc then
			local orig = spec.volfunc
			H._fire_orig[name] = orig
			spec.volfunc = function(prev)
				local base = orig(prev)
				local f = G and G.ARGS and G.ARGS.heat_flames
				local extra = f and H.flame_volume(name, f.real_intensity, f.change) or 0
				if extra > (tonumber(base) or 0) then return extra end
				return base
			end
		end
	end
	H._fire_bound = true
end

function H.drop_flame()
	if H.flame_sprite and H.flame_sprite.remove then pcall(function() H.flame_sprite:remove() end) end
	H.flame_sprite = nil
	local sounds = G and G.ARGS and G.ARGS.ambient_sounds
	if sounds and H._fire_orig then
		for name, orig in pairs(H._fire_orig) do
			if sounds[name] then sounds[name].volfunc = orig end
		end
	end
	H._fire_orig, H._fire_bound = nil, nil
	if G and G.ARGS then G.ARGS.heat_flames = nil end
end

function H.how_text()
	local key = "k_heat_rush_rules"
	if localize then
		local ok, s = pcall(localize, key)
		if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= key then return s end
	end
	return "Each clear pays +25 Heat. At 100 the next hand is Overdrive, x1.5."
end

function H.how_seen()
	if H.how_dismissed then return true end
	local cfg = SMODS and SMODS.Mods and SMODS.Mods["Multiplayer"] and SMODS.Mods["Multiplayer"].config
	return cfg and cfg.heat_how_seen and true or false
end

function H.mark_how()
	H.how_dismissed = true
	local mod = SMODS and SMODS.Mods and SMODS.Mods["Multiplayer"]
	local cfg = mod and mod.config
	if cfg then
		cfg.heat_how_seen = true
		if SMODS.save_mod_config then pcall(SMODS.save_mod_config, mod) end
	end
end

function H.show_how()
	if not (G and G.FUNCS and G.FUNCS.overlay_menu and create_UIBox_generic_options and UIBox_button) then return end
	if not (MP.UI and MP.UI.UTILS and G.UIT) then return end
	local U = MP.UI.UTILS
	local lines = { H.how_text() }
	if MP.UTILS and MP.UTILS.fit_lines then lines = MP.UTILS.fit_lines(H.how_text(), 0.36, 10, 12) end
	local rows = {}
	for _, line in ipairs(lines) do
		rows[#rows + 1] = U.create_row({ align = "cm", padding = 0.02 }, {
			U.create_text_node(line, { scale = 0.36, colour = G.C.UI.TEXT_LIGHT }),
		})
	end
	G.FUNCS.mp_heat_how_ok = function()
		H.mark_how()
		if G.FUNCS.exit_overlay_menu then pcall(G.FUNCS.exit_overlay_menu) end
	end
	local title = "How to play"
	if localize then
		local ok, s = pcall(localize, "k_heat_how")
		if ok and type(s) == "string" and s ~= "k_heat_how" and s ~= "ERROR" then title = s end
	end
	local ok_label = "Got it"
	if localize then
		local ok, s = pcall(localize, "b_heat_how_ok")
		if ok and type(s) == "string" and s ~= "b_heat_how_ok" and s ~= "ERROR" then ok_label = s end
	end
	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = {
				U.create_column({ align = "cm", padding = 0.08 }, {
					U.create_row({ align = "cm" }, {
						U.create_text_node(title, { scale = 0.55, colour = G.C.GOLD or G.C.WHITE }),
					}),
					U.create_column({ align = "cm", padding = 0.02 }, rows),
					U.create_row({ align = "cm", padding = 0.12 }, {
						UIBox_button({ button = "mp_heat_how_ok", label = { ok_label }, minw = 3.2, minh = 0.7, scale = 0.4, colour = G.C.ORANGE or G.C.RED }),
					}),
				}),
			},
		}),
	})
	H.how_shown = true
end

function H.on_match_start()
	if not (H.active and H.active()) then return end
	if H.how_seen() then return end
	H.show_how()
end

function H.pointer()
	if not (love and love.mouse and love.mouse.getPosition) then return nil end
	local ok, x, y = pcall(love.mouse.getPosition)
	if not ok or not x then return nil end
	local ts = (G and G.TILESIZE) or 20
	local sc = (G and G.TILESCALE) or 1
	if ts * sc == 0 then return nil end
	return x / (ts * sc), y / (ts * sc)
end

function H.on_state(p)
	if type(p) ~= "table" then return end
	MP.GAME = MP.GAME or {}
	local personal = p.heat ~= nil
	H.absorb(MP.GAME, p)
	if not personal then return end
	if p.reward == "cash" and ease_dollars and G and G.STAGE == G.STAGES.RUN then
		pcall(ease_dollars, H.CASH)
	elseif p.reward == "reroll" and G and G.GAME and G.GAME.current_round then
		G.GAME.current_round.reroll_cost = 0
	end
	if p.tag and add_tag and Tag and G and G.STAGE == G.STAGES.RUN then
		pcall(function() add_tag(Tag(p.tag)) end)
	end
end

if end_round and not H._round then
	H._round = true
	local end_ref = end_round
	function end_round(...)
		if H.report and G and G.GAME and G.GAME.blind then pcall(H.report, G.GAME.blind) end
		return end_ref(...)
	end
end

if love and love.draw and not H._draw then
	H._draw = true
	local draw = love.draw
	function love.draw(...)
		local r = draw(...)
		if H.draw_front then H.draw_front() end
		return r
	end
end

if Game and Game.update and not H._ui then
	H._ui = true
	local upd = Game.update
	function Game:update(dt)
		local r = upd(self, dt)
		if H.active and H.active() and H.in_run() then
			local target = tonumber(MP.GAME and MP.GAME.heat) or 0
			local prev = H.prev_heat or target
			local burst = H.meter_burst(prev, target, H.MAX)
			if burst > 0 then H.burst = burst end
			H.prev_heat = target
			if H.burst and H.burst > 0 then H.burst = H.burst - dt end
			H.shown = H.ease_heat(H.shown == nil and target or H.shown, target, dt)
			H.sync_flame(target, dt)
			H.bind_fire_sound()
			H.place_meter()
			local down = love and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
			local px, py = H.pointer()
			if down and not H.mouse_was_down and H.hit_meter(H.meter, px, py) then H.show_how() end
			H.mouse_was_down = down and true or false
			if H.drop_old then H.drop_old() end
		else
			H.drop_flame()
		end
		return r
	end
end

function H.drop_old()
	if H.badge and H.badge.remove then pcall(function() H.badge:remove() end) end
	H.badge = nil
end
