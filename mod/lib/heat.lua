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

function H.sync_badge()
	if not (G and UIBox and G.UIT and G.ROOM_ATTACH and G.STAGES) then return end
	local show = H.active() and G.STAGE == G.STAGES.RUN
	if not show then
		if H.badge and H.badge.remove then pcall(function() H.badge:remove() end) end
		H.badge = nil
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
	if H.badge and H.view.text == text then return end
	if H.badge and H.badge.remove then pcall(function() H.badge:remove() end) end
	H.view.text = text
	H.badge = UIBox({
		definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
			{ n = G.UIT.R, config = { align = "cm", padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
				{ n = G.UIT.T, config = { ref_table = H.view, ref_value = "text", scale = 0.35, colour = G.C.GOLD or G.C.WHITE, shadow = true } },
			} },
		} },
		config = { align = "tm", offset = { x = 0, y = 1.05 }, major = G.ROOM_ATTACH, bond = "Weak" },
	})
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

if Game and Game.update and not H._ui then
	H._ui = true
	local upd = Game.update
	function Game:update(dt)
		local r = upd(self, dt)
		if H.active and H.active() and H.sync_badge then H.sync_badge() end
		return r
	end
end
