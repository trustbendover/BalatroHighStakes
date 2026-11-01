-- Balatro High Stakes 0.6.8: rejoin after a disconnect. GPL-3.0.
-- * While you play an MP run, a local checkpoint of your own run is written at every shop and
--   blind select (mp3p_rejoin.jkr in the save folder; your normal save.jkr is never touched).
--   The host only gets a small numeric summary (ante, money, jokers, ...): run data received
--   over the network is never loaded, only your own local file.
-- * After a crash / lost connection you rejoin with Steam (or the lobby code). The host held your
--   seat for the grace window (networking/p2p_server.lua: Core.rejoin_grace). If your checkpoint
--   matches the lobby, seed and the host's last known checkpoint, your run (deck, jokers, money,
--   ante) is restored; otherwise the run restarts at your ante with the money you had.
-- * Everyone else sees "X disconnected - waiting to rejoin 2:41" and "X rejoined".
MP.REJOIN = MP.REJOIN or {}
local RJ = MP.REJOIN

RJ.FILE = "mp3p_rejoin.jkr"
RJ.MAX_AGE = 6 * 3600
RJ.ckpt = RJ.ckpt or 0
RJ.away = RJ.away or {}
RJ.view = RJ.view or { bar = "" }

local function L(key, fallback, vars)
	if MP.SPECTATE and MP.SPECTATE.L then return MP.SPECTATE.L(key, fallback, vars) end
	if vars then for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", tostring(v)) end end
	return fallback
end
local function clean(n) return (tostring(n or "?"):gsub("~.*$", "")) end
local function now() return (love and love.timer and love.timer.getTime()) or os.clock() end

--- Pure: "m:ss"
function RJ.countdown(secs)
	secs = math.max(0, math.floor(tonumber(secs) or 0))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

--- Pure: the numeric run summary the host keeps (no cards, no strings).
function RJ.summary(game, jokers, deck, ckpt)
	game = game or {}
	local rr = game.round_resets or {}
	return { ante = tonumber(rr.ante), round = tonumber(game.round), dollars = tonumber(game.dollars),
		jokers = tonumber(jokers), deck = tonumber(deck), hands = tonumber(rr.hands),
		discards = tonumber(rr.discards), ckpt = tonumber(ckpt) }
end

--- Pure: can this local checkpoint be used for the resumeGame message p?
function RJ.usable(meta, p, t)
	if type(meta) ~= "table" or type(p) ~= "table" then return false, "none" end
	if meta.code ~= (MP.LOBBY and MP.LOBBY.code) then return false, "other lobby" end
	if p.seed ~= nil and meta.server_seed ~= p.seed then return false, "other seed" end
	if t and meta.time and t - meta.time > RJ.MAX_AGE then return false, "too old" end
	local host = p.runState and tonumber(p.runState.ckpt)
	if host and (tonumber(meta.ckpt) or -1) < host then return false, "older than host" end
	return true
end

--- Pure: the status bar text for the players we are waiting for.
-- 0.6.8: the bar has a fixed maximum width: at most RJ.BAR_NAMED players by name (names shortened
-- with ".."), the rest as "+N", and the whole line fitted to RJ.BAR_W at RJ.BAR_SCALE.
RJ.BAR_SCALE, RJ.BAR_W, RJ.BAR_NAMED, RJ.BAR_NAME_W = 0.35, 11, 2, 2.4
function RJ.bar_text(away, t)
	local list = {}
	for _, a in pairs(away or {}) do list[#list + 1] = a end
	table.sort(list, function(x, y)
		if (x.end_time or 0) ~= (y.end_time or 0) then return (x.end_time or 0) < (y.end_time or 0) end
		return tostring(x.name) < tostring(y.name)
	end)
	local F = MP.FIT
	local parts = {}
	for i, a in ipairs(list) do
		if i > RJ.BAR_NAMED then break end
		local left = a.end_time and RJ.countdown(a.end_time - t) or ""
		local name = F and F.ellipsize(a.name, RJ.BAR_SCALE, RJ.BAR_NAME_W) or tostring(a.name)
		parts[#parts + 1] = L("k_rj_waiting", "#1# disconnected - waiting to rejoin #2#", { name, left })
	end
	if #list > RJ.BAR_NAMED then parts[#parts + 1] = L("k_rj_more", "+#1# more", { #list - RJ.BAR_NAMED }) end
	local line = table.concat(parts, "  |  ")
	if F and F.width(line, RJ.BAR_SCALE) > RJ.BAR_W then
		-- two long waiting texts do not fit: keep the first one + "+N"
		line = parts[1] .. ((#list > 1) and ("  |  " .. L("k_rj_more", "+#1# more", { #list - 1 })) or "")
		line = F.ellipsize(line, RJ.BAR_SCALE, RJ.BAR_W)
	end
	return line
end

---------------------------------------------------------------------------------------------
-- checkpoint
function RJ.should_checkpoint()
	if not (MP.LOBBY and MP.LOBBY.code and G and G.STAGE == G.STAGES.RUN and G.GAME) then return false end
	if MP.GHOST and MP.GHOST.is_active and MP.GHOST.is_active() then return false end
	if not MP.GAME or (MP.GAME.lives or 0) <= 0 then return false end
	return G.STATE == G.STATES.SHOP or G.STATE == G.STATES.BLIND_SELECT
end

--- Build the save table with the game's own save_run (save_ref) without writing save.jkr.
function RJ.capture(save_ref)
	local prev_flag = G.F_NO_SAVING
	G.FILE_HANDLER = G.FILE_HANDLER or {}
	local had_run, had_queue = G.FILE_HANDLER.run, G.FILE_HANDLER.update_queued
	G.ARGS = G.ARGS or {}
	local prev_args = G.ARGS.save_run
	G.F_NO_SAVING = false
	local ok = pcall(save_ref)
	G.F_NO_SAVING = prev_flag
	local t = G.ARGS.save_run
	-- cancel the write to save.jkr that save_run just queued
	G.FILE_HANDLER.run, G.FILE_HANDLER.update_queued = had_run, had_queue
	G.ARGS.save_run = prev_args
	if ok and type(t) == "table" and t ~= prev_args then return t end
	return nil
end

function RJ.on_save_run(save_ref)
	if not RJ.should_checkpoint() then return end
	local t = RJ.capture(save_ref)
	if not t then return end
	RJ.ckpt = RJ.ckpt + 1
	local meta = { code = MP.LOBBY.code, server_seed = RJ.server_seed, ckpt = RJ.ckpt, time = os.time(),
		ante = G.GAME.round_resets and G.GAME.round_resets.ante }
	pcall(compress_and_save, RJ.FILE, { meta = meta, run = t })
	if MP.STEAM_P2P and Client and Client.send then
		local s = RJ.summary(G.GAME, G.jokers and G.jokers.cards and #G.jokers.cards,
			G.playing_cards and #G.playing_cards, RJ.ckpt)
		s.action = "runState"
		pcall(Client.send, s)
	end
end

function RJ.load()
	local ok, str = pcall(get_compressed, RJ.FILE)
	if not ok or type(str) ~= "string" then return nil end
	local ok2, t = pcall(STR_UNPACK, str)
	if ok2 and type(t) == "table" and type(t.meta) == "table" and type(t.run) == "table" then return t end
	return nil
end

function RJ.clear()
	RJ.ckpt = 0
	pcall(function() if love.filesystem.getInfo(RJ.FILE) then love.filesystem.remove(RJ.FILE) end end)
end

--- New match: forget the old checkpoint.
function RJ.on_start(p)
	RJ.clear()
	RJ.server_seed = p and p.seed
	RJ.away = {}
end

---------------------------------------------------------------------------------------------
-- restore (deferred until the lobby screen has settled after the rejoin)
function RJ.queue(p) RJ.pending = { p = p, at = now() } end

function RJ.ready()
	return RJ.pending and G.F_NO_SAVING and G.STAGE == G.STAGES.MAIN_MENU and now() - RJ.pending.at >= 1
end

function RJ.restore(p)
	local chk = RJ.load()
	local ok = not p.lateJoin and chk and RJ.usable(chk.meta, p, os.time())
	local lives = tonumber(p.lives) or (MP.GAME and MP.GAME.lives)
	if not ok then
		if MP.THREEP and MP.THREEP.restart_at_ante then MP.THREEP.restart_at_ante(p) end
		return "restarted"
	end
	MP.SP.practice = false
	if MP.GHOST and MP.GHOST.clear then MP.GHOST.clear() end
	MP.reset_game_states()
	if lives then MP.GAME.lives = lives end
	RJ.ckpt, RJ.server_seed = tonumber(chk.meta.ckpt) or 0, p.seed
	G.FUNCS.start_run(nil, { savetext = chk.run })
	if MP.MATCH_STATS then MP.MATCH_STATS.on_resume(p) end
	if lives then MP.GAME.lives = lives end
	local ante = tonumber(chk.meta.ante) or tonumber(p.ante) or 1
	MP.ACTIONS.set_ante(ante)
	Client.send({ action = "resumeRestarted" })
	pcall(MP.UI.UTILS.overlay_message, L("k_rj_restored", "Rejoined! Your run is restored (ante #1#)", { ante }))
	return "restored"
end

---------------------------------------------------------------------------------------------
-- other players' status
function RJ.on_away(p)
	if not p or not p.playerId then return end
	local name = clean((MP.LOBBY and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId]) or p.username)
	RJ.away[p.playerId] = { name = name, end_time = p.grace and (now() + p.grace) or nil }
	RJ.show_bar()
end

function RJ.on_back(p)
	if not p or not p.playerId then return end
	local a = RJ.away[p.playerId]
	RJ.away[p.playerId] = nil
	local known = a and a.name ~= "?" and a.name or nil -- the away entry may have been made without a name
	local name = clean(known or (MP.LOBBY and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId]) or p.username)
	RJ.notify(L("k_rj_rejoined", "#1# rejoined", { name }), G.C and G.C.GREEN)
	RJ.show_bar()
end

function RJ.on_expired(p)
	if not p or not p.playerId or not RJ.away[p.playerId] then return end
	local a = RJ.away[p.playerId]
	local known = a.name ~= "?" and a.name or nil
	local name = clean(known or (MP.LOBBY and MP.LOBBY.names_by_id and MP.LOBBY.names_by_id[p.playerId]) or p.username)
	RJ.away[p.playerId] = nil
	RJ.notify(L("k_rj_left", "#1# left", { name }), G.C and G.C.RED)
	RJ.show_bar()
end

function RJ.notify(msg, colour)
	pcall(sendWarnMessage, msg, "MULTIPLAYER")
	pcall(function()
		if G.STAGE == G.STAGES.RUN and G.ROOM_ATTACH then
			attention_text({ scale = 0.8, text = msg, hold = 4, align = "cm", offset = { x = 0, y = -2.6 },
				major = G.ROOM_ATTACH, colour = colour })
		end
	end)
end

function RJ.show_bar()
	RJ.view.bar = RJ.bar_text(RJ.away, now())
	local want = next(RJ.away) ~= nil
	pcall(function()
		if want and not RJ.bar_box and G.ROOM_ATTACH then
			RJ.bar_box = UIBox({
				definition = { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = {
					{ n = G.UIT.R, config = { align = "cm", padding = 0.08, r = 0.1, colour = G.C.BLACK, emboss = 0.05, maxw = RJ.BAR_W + 0.3 }, nodes = {
						{ n = G.UIT.T, config = { ref_table = RJ.view, ref_value = "bar", scale = RJ.BAR_SCALE, colour = G.C.ORANGE, shadow = true } },
					} },
				} },
				config = { align = "tm", offset = { x = 0, y = 0.15 }, major = G.ROOM_ATTACH, bond = "Weak" },
			})
			RJ.bar_stage = G.STAGE
		elseif not want and RJ.bar_box then
			RJ.bar_box:remove()
			RJ.bar_box = nil
		end
	end)
end

function RJ.register()
	if RJ.registered then return end
	RJ.registered = true
	local upd = Game.update
	local t = 0
	function Game:update(dt)
		local r = upd(self, dt)
		if RJ.ready() then
			local p = RJ.pending.p
			RJ.pending = nil
			local ok, err = pcall(RJ.restore, p)
			if not ok then
				-- broken checkpoint: never leave the player stuck in the menu, start on the lobby seed instead
				pcall(sendWarnMessage, "Rejoin restore failed: " .. tostring(err) .. " - restarting at the ante", "MULTIPLAYER")
				if MP.THREEP and MP.THREEP.restart_at_ante then
					local ok2, err2 = pcall(MP.THREEP.restart_at_ante, p)
					if not ok2 then pcall(sendWarnMessage, "Rejoin restart failed: " .. tostring(err2), "MULTIPLAYER") end
				end
			end
		end
		if next(RJ.away) then pcall(function()
			t = t - (dt or 0)
			if t <= 0 then
				t = 0.5
				RJ.view.bar = RJ.bar_text(RJ.away, now())
				if RJ.bar_box and (RJ.bar_box.REMOVED or RJ.bar_stage ~= G.STAGE) then
					pcall(function() RJ.bar_box:remove() end)
					RJ.bar_box = nil
				end
				if not RJ.bar_box then RJ.show_bar() end
			end
		end) end
		return r
	end
end

--- Match over / left the lobby: drop every status
function RJ.reset()
	RJ.away, RJ.pending = {}, nil
	RJ.show_bar()
end
