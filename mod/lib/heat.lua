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
	if H.active() then H.started = H.now() end
end

--- Called when the blind is actually beaten.
function H.report(blind)
	if not (Client and Client.send and H.active()) then return end
	local round = G and G.GAME and G.GAME.current_round or {}
	local kind = "small"
	if blind and blind.boss then kind = "boss"
	elseif blind and ((blind.get_type and blind:get_type() == "Big") or blind.name == "Big Blind") then kind = "big" end
	local now = H.now()
	local par = H.PAR_SECONDS[kind] or 90
	local seconds = H.started and (now - H.started) or (par + 1)
	H.started = nil
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
	local gambel = MP.GAMBEL
	if gambel and gambel.badge then add(gambel.badge) end
	local chat = MP.CHAT
	if chat and chat.box then add(chat.box) end
	if G and G.MP3P_KOTH_UI then add(G.MP3P_KOTH_UI) end
	return list
end

--- Stop the bond from pulling the strip back down onto the cards.
function H.hold(box)
	if not box then return end
	if G and G.ROOM then box.container = G.ROOM end
	if box.alignment then
		box.alignment.type = "a"
		box.alignment.prev_type = "a"
		if box.alignment.type_list then box.alignment.type_list.a = true end
	end
end

function H.sync_visual(box)
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

function H.pin()
	local box = H.badge
	local area = G and G.jokers
	if not box or box.REMOVED or not area then return end
	local slot = H.layout_badge(area, area.cards, H.blockers(), H.room_rect())
	if not slot then return end
	H.hold(box)
	box.T.x, box.T.y, box.T.w, box.T.h = slot.x, slot.y, slot.w, slot.h
	if box.VT then box.VT.x, box.VT.y, box.VT.w, box.VT.h = slot.x, slot.y, slot.w, slot.h end
	if box.velocity then box.velocity.x, box.velocity.y = 0, 0 end
	H.sync_visual(box)
	H.slot = slot
end

--- The normal UI pass paints before the cards. Skip it and draw once afterwards.
function H.silence(box)
	if not box or box._mp_heat_draw or not box.draw then return end
	local orig = box.draw
	box._mp_heat_draw = orig
	function box.draw(self, ...)
		if not H._painting then return end
		return orig(self, ...)
	end
end

function H.draw_front()
	local box = H.badge
	if not box or box.REMOVED or not box.draw then return end
	if G and G.OVERLAY_MENU then return end
	H.pin()
	if box.FRAME then box.FRAME.DRAW = -1 end
	H._painting = true
	pcall(function()
		love.graphics.push()
		local drew, err = pcall(function()
			if box.translate_container then box:translate_container() end
			box:draw()
		end)
		love.graphics.pop()
		if not drew then error(err) end
	end)
	H._painting = false
end

function H.sync_badge()
	if not (G and UIBox and G.UIT and G.ROOM_ATTACH and G.STAGES) then return end
	local show = H.active() and G.STAGE == G.STAGES.RUN and G.jokers and G.jokers.T
	if not show then
		if H.badge and H.badge.remove then pcall(function() H.badge:remove() end) end
		H.badge, H.slot = nil, nil
		return
	end
	local g = MP.GAME or {}
	local now = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
	if not H.started then H.started = now end
	local text = string.format("HEAT %d/%d", tonumber(g.heat) or 0, H.MAX)
	local blind = G and G.GAME and G.GAME.blind
	if blind and blind.boss and H.started then
		text = text .. string.format("  BOSS %ds", math.max(0, math.floor(H.PAR_SECONDS.boss - (now - H.started))))
	end
	if g.heat_overdrive then text = text .. "  OVERDRIVE" end
	if (tonumber(g.heat_best) or 0) > 0 then text = text .. string.format("  Best %d", g.heat_best) end
	H.view.text = text
	if not H.badge or H.badge.REMOVED then
		H.badge = UIBox({
			definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR, minw = H.BADGE_W, minh = H.BADGE_H }, nodes = {
				{ n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05, minw = H.BADGE_W }, nodes = {
					{ n = G.UIT.T, config = { ref_table = H.view, ref_value = "text", scale = 0.32, colour = G.C.GOLD or G.C.WHITE, shadow = true } },
				} },
			} },
			config = { align = "tm", offset = { x = 0, y = -(H.BADGE_H + H.BADGE_GAP + H.HOVER) }, major = G.jokers, bond = "Weak" },
		})
		H.silence(H.badge)
	end
	H.pin()
end

function H.on_state(p)
	if type(p) ~= "table" then return end
	MP.GAME = MP.GAME or {}
	MP.GAME.heat = tonumber(p.heat) or 0
	MP.GAME.heat_total = tonumber(p.total) or MP.GAME.heat_total or 0
	MP.GAME.heat_best = tonumber(p.best) or MP.GAME.heat_best or 0
	MP.GAME.heat_overdrive = p.overdrive and true or false
	MP.GAME.heat_board = p.rows
	if p.reward == "cash" and ease_dollars and G and G.STAGE == G.STAGES.RUN then
		pcall(ease_dollars, H.CASH)
	elseif p.reward == "reroll" and G and G.GAME and G.GAME.current_round then
		G.GAME.current_round.reroll_cost = 0
	end
	if p.tag and add_tag and Tag and G and G.STAGE == G.STAGES.RUN then
		pcall(function() add_tag(Tag(p.tag)) end)
	end
	if H.sync_badge then H.sync_badge() end
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
		if H.active and H.active() and H.sync_badge then H.sync_badge() end
		return r
	end
end
