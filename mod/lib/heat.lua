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

function H.room_rect()
	local t = G and G.ROOM and G.ROOM.T
	if not t then return nil end
	return { x = t.x or 0, y = t.y or 0, w = t.w or 0, h = t.h or 0 }
end

function H.blockers()
	local list = {}
	local function add(box)
		local t = box and not box.REMOVED and box.T
		if t and t.w and t.w > 0 and t.h and t.h > 0 then
			list[#list + 1] = { x = t.x or 0, y = t.y or 0, w = t.w, h = t.h }
		end
	end
	local chat = MP.CHAT
	if chat and chat.box then add(chat.box) end
	if G and G.deck then add(G.deck) end
	if G and G.shop then add(G.shop) end
	return list
end

function H.place_meter()
	H.meter = H.layout_meter(H.room_rect(), H.blockers())
	return H.meter
end

function H.draw_front()
	if not (love and love.graphics and H.active and H.active()) then return end
	if G and (G.OVERLAY_MENU or not G.STAGES or G.STAGE ~= G.STAGES.RUN) then return end
	local box = H.place_meter()
	if not box then return end
	local g = MP.GAME or {}
	local heat = H.shown
	if heat == nil then heat = tonumber(g.heat) or 0 end
	local fire = g.heat_overdrive and true or false
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
	if fire then
		local pulse = 0.22 + 0.14 * math.sin(now * 7)
		local burst = math.max(0, H.burst or 0) / 0.42
		pill(x - 3, y - 3, w + 6, h + 6, { 1, 0.45, 0.08, pulse + burst * 0.45 })
	end
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
	if fire then
		local edge = math.max(1.5, ts * 0.045)
		local pulse = 0.45 + 0.35 * math.sin(now * 11)
		local burst = math.max(0, H.burst or 0) / 0.42
		gpx.setColor(1, 0.72, 0.25, math.min(1, pulse + burst))
		gpx.rectangle("fill", x - edge, y, edge, h)
		gpx.rectangle("fill", x + w, y, edge, h)
		for _, p in ipairs(H.flames or {}) do
			local a = math.max(0, math.min(1, (p.life or 0) / 0.62))
			local along = math.max(0, math.min(1, p.y or 0))
			local py = y + h - along * h
			local side = (p.side == 1) and 1 or -1
			local outward = (0.02 + (1 - a) * 0.07) * ts
			local fx = (side < 0) and (x - outward) or (x + w + outward)
			if p.kind == "ember" then
				gpx.setColor(1, 0.82, 0.35, a * 0.85)
				gpx.circle("fill", fx, py, (0.045 + 0.03 * a) * ts)
			else
				gpx.setColor(1, 0.42 + 0.25 * a, 0.06, a * 0.9)
				gpx.rectangle("fill", fx - ts * 0.03, py - ts * 0.1, ts * 0.07, ts * 0.16)
			end
		end
		if burst > 0 then
			gpx.setColor(1, 0.95, 0.75, burst * 0.4)
			pill(x, y, w, h, { 1, 0.95, 0.75, burst * 0.4 })
		end
	end
	local shown = math.floor((heat or 0) + 0.5)
	gpx.setColor(1, 0.97, 0.92, 1)
	gpx.printf(tostring(shown), x - ts * 0.35, y + h + ts * 0.04, w + ts * 0.7, "center", 0, 0.72, 0.72)
	gpx.setColor(1, 0.78, 0.38, 0.9)
	gpx.printf("HEAT", x - ts * 0.35, y + h + ts * 0.28, w + ts * 0.7, "center", 0, 0.38, 0.38)
	local best = tonumber(g.heat_best) or 0
	if best > 0 then
		gpx.setColor(0.92, 0.84, 0.62, 0.9)
		gpx.printf("Best " .. tostring(math.floor(best)), x - ts * 0.45, y + h + ts * 0.48, w + ts * 0.9, "center", 0, 0.36, 0.36)
	end
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
		if H.active and H.active() then
			local target = tonumber(MP.GAME and MP.GAME.heat) or 0
			local prev = H.prev_heat or target
			local burst = H.meter_burst(prev, target, H.MAX)
			if burst > 0 then H.burst = burst end
			H.prev_heat = target
			if H.burst and H.burst > 0 then H.burst = H.burst - dt end
			H.shown = H.ease_heat(H.shown == nil and target or H.shown, target, dt)
			H.flames = H.flame_tick(H.flames, dt, MP.GAME and MP.GAME.heat_overdrive, H.now())
			H.place_meter()
			local down = love and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
			local px, py = H.pointer()
			if down and not H.mouse_was_down and H.hit_meter(H.meter, px, py) then H.show_how() end
			H.mouse_was_down = down and true or false
			if H.drop_old then H.drop_old() end
		end
		return r
	end
end

function H.drop_old()
	if H.badge and H.badge.remove then pcall(function() H.badge:remove() end) end
	H.badge = nil
end
