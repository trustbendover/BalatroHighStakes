-- Balatro High Stakes: Steam P2P host migration (router side). GPL-3.0, see FORK_NOTICE.md.
--
-- How it works (see docs/HOST_MIGRATIE_NL.md):
--  * The host sends every guest a snapshot frame "S" whenever its lobby state changes (and at
--    least once per second while it changes): the full lobby/game state (Server:snapshot), the
--    succession order (Steam ids of the other players in seat order) and, per guest, the last
--    message sequence number it has processed ("acks").
--  * Guests number the game messages they send ("Q<seq>|json") and keep them in an outbox until
--    a snapshot acknowledges them, so nothing sent to a host that dies is lost.
--  * Host gone = "L" frame (host left on purpose), or the host dropped out of the Steam lobby
--    member list, or the host is frozen: a host that stays in the Steam lobby but sends nothing.
--    Guests share "host silent" votes ("V" frames, every VOTE_EVERY s) with each other; once the
--    host has been silent SILENT s for a strict majority of the connected guests, they migrate
--    without waiting for Steam. With one guest (2 players) the silence alone counts after
--    SOLO_TIMEOUT s. A guest that is silent alone (its own connection is bad) never reaches a
--    majority and falls back after FALLBACK_AT s instead. Every guest then walks the same succession
--    list: the first candidate still in the Steam lobby promotes itself; the others wait up to
--    WAIT seconds for its announcement "A" before trying the next candidate.
--  * The successor rebuilds the server from the snapshot (Core.restore), reconnects its own
--    player, replays its outbox and announces itself ("A", with an epoch counter). Guests then
--    rejoin the new host with their reconnect token and replay their outbox. The Steam lobby
--    owner (if it is somebody else) hands Steam ownership to the new host.
--  * Split brain guard: an announcement only counts with a higher epoch, or the same epoch from
--    a better-ranked candidate; a host that hears a better announcement steps down and rejoins.
--  * If there is no snapshot or nobody can take over, the guest falls back to the old behaviour
--    (back to the menu with a message).
local M = {}
M.WAIT = 6          -- seconds to wait for a candidate's announcement before trying the next one
M.ANNOUNCE_FOR = 20 -- the new host repeats its announcement to members that haven't rejoined yet
M.MAX_OUTBOX = 400
M.SILENT = 10       -- host silent this long (s) -> this guest votes "host frozen"
M.SOLO_TIMEOUT = 13 -- only one guest (2 players): migrate after this much host silence
M.VOTE_EVERY = 2    -- guests share their vote this often (and at once when it changes)
M.VOTE_FRESH = 6    -- a vote older than this does not count
M.FALLBACK_AT = 30  -- silent host, no majority (we are the one cut off): back to the menu here
M.WATCH_EVERY = 3   -- the new host keeps telling a frozen old host (still in Steam) to step down
M.REJOIN_FOR = 180 -- a host that was cut off keeps trying to rejoin the new host this long
-- messages that are not replayed to a new host (identity / lobby control)
M.NO_REPLAY = { connect = true, version = true, username = true, joinLobby = true, rejoinLobby = true,
	leaveLobby = true, createLobby = true, keepAlive = true, keepAliveAck = true, lobbyInfo = true }

local function contains(t, x) for _, v in ipairs(t or {}) do if v == x then return true end end return false end
local function index_of(t, x) for i, v in ipairs(t or {}) do if v == x then return i end end return nil end

--- ctx (from the router): R, B, json, now, log, push, peer, drop_peer, to_local, start_join,
--- get_core(), new_core(), local_conn(), conn_peer(conn) -> steam id, Core
function M.attach(ctx)
	local R, B, json, now, log = ctx.R, ctx.B, ctx.json, ctx.now, ctx.log
	local H = { last_snap = nil, last_snap_t = -1, dirty = false }
	R.epoch, R.seq, R.outbox, R.votes = 0, 0, {}, {}

	local function members()
		if not R.lobby then return {} end
		local ok, m = pcall(B.members, R.lobby)
		return ok and m or {}
	end
	local function owner()
		if not R.lobby then return nil end
		local ok, o = pcall(B.owner, R.lobby)
		if ok and o and o ~= "" and o ~= "0" then return o end
		return nil
	end
	local function send(id, tag, t) return B.send(id, tag .. json.encode(t)) end

	function H.reset()
		R.snap, R.mig, R.epoch, R.seq, R.outbox = nil, nil, 0, 0, {}
		R.host_seen_member, R.announce, R.timeout_since = false, nil, nil
		R.votes, R.watch_old, H.vote_t, H.vote_last = {}, nil, nil, nil
		H.last_snap, H.dirty, H.had_guests, H.was_member = nil, false, false, false
	end

	local fail
	----------------------------------------------------------------- guest side
	--- Frame for a guest -> host message (numbered unless it is lobby control).
	function H.guest_frame(msg)
		if M.NO_REPLAY[msg.action] then return "J" .. json.encode(msg) end
		R.seq = R.seq + 1
		R.outbox[#R.outbox + 1] = { seq = R.seq, msg = msg }
		if #R.outbox > M.MAX_OUTBOX then table.remove(R.outbox, 1) end
		return "Q" .. R.seq .. "|" .. json.encode(msg)
	end
	local function replay_to(id)
		local ack = R.snap and R.snap.acks and tonumber(R.snap.acks[B.my_id()]) or 0
		for _, e in ipairs(R.outbox) do
			if e.seq > ack then B.send(id, "Q" .. e.seq .. "|" .. json.encode(e.msg)) end
		end
	end
	local function on_snapshot(s)
		R.snap = s
		R.epoch = math.max(R.epoch or 0, tonumber(s.epoch) or 0)
		local ack = s.acks and tonumber(s.acks[B.my_id()]) or nil
		if ack then
			local keep = {}
			for _, e in ipairs(R.outbox) do if e.seq > ack then keep[#keep + 1] = e end end
			R.outbox = keep
		end
	end

	function H.fail(why, message) return fail(why, message) end
	function fail(why, message)
		log("host migration failed: " .. tostring(why))
		local had_game = R.snap and R.snap.state and R.snap.state.isInGame
		ctx.to_local()
		ctx.push({ action = "hostMigrationFailed", inGame = had_game or false, lost = message ~= nil,
			message = message or "The host left and nobody could take over the lobby. Back to the menu." })
		ctx.push({ action = "disconnected" })
	end

	local function my_player_id()
		for _, p in ipairs((R.snap and R.snap.state and R.snap.state.players) or {}) do
			if p.reconnectToken == R.token then return p.id end
		end
		return nil
	end

	--- The new host: rebuild the server from the snapshot, reconnect our own player, announce.
	local function promote()
		local s, mig = R.snap, R.mig
		local state = s.state
		local core = ctx.new_core(function(opts)
			return ctx.Core.restore(state, { now = now, log = log, oldHostId = state.hostId, newHostId = my_player_id(),
				reason = mig.reason })
		end)
		log("host migration: promoting myself (epoch " .. mig.epoch .. ", reason " .. mig.reason .. ")")
		R.mode, R.host, R.epoch, R.mig = "host", nil, mig.epoch, nil
		if mig.old then ctx.drop_peer(mig.old) end
		local lc = ctx.local_conn()
		for _, k in ipairs({ "version", "username" }) do if R.cached[k] then core:receive(lc, R.cached[k]) end end
		core:receive(lc, { action = "rejoinLobby", code = state.code, reconnectToken = R.token })
		local ack = s.acks and tonumber(s.acks[B.my_id()]) or 0
		for _, e in ipairs(R.outbox) do if e.seq > ack then core:receive(lc, e.msg) end end
		R.outbox, R.seq, R.snap = {}, 0, nil
		R.announce = { until_t = now() + M.ANNOUNCE_FOR, last = -1, code = state.code }
		-- a frozen old host is still in the Steam lobby: keep telling it to step down once it wakes up
		R.watch_old = mig.old and { id = mig.old, code = state.code, last = -1 } or nil
		R.votes = {}
		pcall(B.set_data, R.lobby, "mp3p_host", B.my_id())
		-- Steam lobby data can only be written by the owner (maybe the frozen old host): also tag
		-- ourselves in our own member data so players joining by code find the real host
		if B.set_member_data then pcall(B.set_member_data, R.lobby, "mp3p_host", tostring(R.epoch)) end
		H.announce(true)
		H.dirty = true
	end

	function H.announce(force)
		local a = R.announce
		if not a or R.mode ~= "host" then return end
		local t = now()
		if t > a.until_t then R.announce = nil; return end
		if not force and t - a.last < 2 then return end
		a.last = t
		local me = B.my_id()
		for _, id in ipairs(members()) do
			local p = R.peers[id]
			if id ~= me and not (p and p.conn) then
				ctx.peer(id)
				send(id, "A", { epoch = R.epoch, host = me, code = a.code })
			end
		end
	end

	local function advance()
		local mig = R.mig
		local me = B.my_id()
		local mem = members()
		while true do
			local cand = mig.cands[mig.idx]
			if not cand then return fail("no successor left") end
			if cand == me then return promote() end
			if #mem == 0 or contains(mem, cand) then
				mig.deadline = now() + M.WAIT
				ctx.peer(cand)
				log("host migration: waiting for " .. cand .. " to take over")
				return
			end
			mig.idx = mig.idx + 1
		end
	end

	--- The host is gone (reason "left" or "disconnected").
	function H.host_lost(reason)
		if R.mode ~= "guest" then return false end
		local s = R.snap
		if not s or not s.state or not R.token or not s.succession then return false end
		local old = R.host
		local cands = {}
		for _, id in ipairs(s.succession) do if id ~= old then cands[#cands + 1] = id end end
		R.mode, R.host = "migrating", nil
		R.mig = { reason = reason, old = old, epoch = (tonumber(s.epoch) or 0) + 1, cands = cands, idx = 1, t0 = now() }
		log("host migration: host " .. tostring(old) .. " " .. reason)
		ctx.push({ action = "hostMigrating", reason = reason })
		if old then ctx.drop_peer(old) end
		advance()
		return true
	end

	--- The P2P heartbeat to the host timed out. Returns true while handled (migrating or waiting),
	--- false when the caller should fall back.
	function H.host_timeout()
		if R.mode ~= "guest" then return false end
		local mem, me = members(), B.my_id()
		if #mem > 0 and contains(mem, R.host) then
			-- Steam still lists the host and the other guests did not confirm the silence (no
			-- majority), so WE are probably the one who is cut off: don't take over. Give Steam
			-- until FALLBACK_AT seconds of silence to drop whoever is gone, then fall back.
			if not contains(mem, me) then return false end
			local hp = R.peers[R.host]
			local silent = hp and (now() - hp.seen) or M.FALLBACK_AT
			return silent < M.FALLBACK_AT
		end
		return H.host_lost("disconnected")
	end

	--- Quorum check for a frozen host (once per second while we are a guest).
	local function frozen_check(t, mem)
		local s, hp, me = R.snap, R.peers[R.host], B.my_id()
		if not (s and s.succession and hp) then return end
		local silent_for = t - hp.seen
		local silent = silent_for >= M.SILENT
		local others = {}
		for _, id in ipairs(s.succession) do if id ~= me and id ~= R.host then others[#others + 1] = id end end
		if not H.vote_t or t - H.vote_t >= M.VOTE_EVERY or silent ~= H.vote_last then
			H.vote_t, H.vote_last = t, silent
			for _, id in ipairs(others) do send(id, "V", { host = R.host, silent = silent, epoch = R.epoch }) end
		end
		if not silent or (#mem > 0 and not contains(mem, me)) then return end
		local total, votes = #others + 1, 1
		if total == 1 then
			if silent_for < M.SOLO_TIMEOUT then return end
		else
			for _, id in ipairs(others) do
				local v = (R.votes or {})[id]
				if v and v.silent and v.host == R.host and t - v.t <= M.VOTE_FRESH then votes = votes + 1 end
			end
			if votes * 2 <= total then return end
		end
		log("host migration: host " .. tostring(R.host) .. " silent " .. silent_for .. "s, " .. votes .. "/" .. total .. " guests agree")
		if not H.host_lost("frozen") then H.fail("no snapshot from the frozen host", "Lost connection to the Steam host. Back to the menu.") end
	end

	--- Follow a new host (from its announcement).
	local function follow(id, a)
		local me = B.my_id()
		local old = R.host
		if R.mode == "host" then
			-- we were (or thought we were) host: step down, our own server is discarded
			log("host migration: stepping down for " .. id)
			ctx.new_core(nil)
			for pid, p in pairs(R.peers) do if pid ~= id then ctx.drop_peer(pid) end end
			if B.set_member_data then pcall(B.set_member_data, R.lobby, "mp3p_host", "") end
			R.watch_old = nil
		end
		R.votes, H.vote_t = {}, nil
		R.mode, R.host, R.epoch, R.mig, R.announce = "guest", id, tonumber(a.epoch) or (R.epoch + 1), nil, nil
		R.host_seen_member = false
		if old and old ~= id then ctx.drop_peer(old) end
		ctx.peer(id)
		for _, k in ipairs({ "version", "username" }) do if R.cached[k] then B.send(id, "J" .. json.encode(R.cached[k])) end end
		B.send(id, "J" .. json.encode({ action = "rejoinLobby", code = a.code or (R.snap and R.snap.state and R.snap.state.code) or R.code,
			reconnectToken = R.token }))
		replay_to(id)
		if owner() == me and id ~= me and B.set_owner then pcall(B.set_owner, R.lobby, id) end
		log("host migration: following new host " .. id .. " (epoch " .. tostring(R.epoch) .. ")")
	end

	local function rank(id)
		local s = R.snap
		return (s and index_of(s.succession, id)) or (R.succession_cache and index_of(R.succession_cache, id)) or 99
	end

	--- Frames "S" / "A" / "L". Returns true when handled.
	function H.on_frame(from, data)
		local tag = data:sub(1, 1)
		if tag == "S" then
			if R.mode == "guest" and from == R.host then
				local ok, s = pcall(json.decode, data:sub(2))
				if ok and type(s) == "table" then on_snapshot(s) end
			end
			return true
		elseif tag == "L" then
			if R.mode == "guest" and from == R.host then
				if not H.host_lost("left") then fail("host left before sending a snapshot") end
			end
			return true
		elseif tag == "V" then
			local ok, v = pcall(json.decode, data:sub(2))
			if ok and type(v) == "table" and R.mode == "guest" then
				R.votes = R.votes or {}
				R.votes[from] = { silent = v.silent == true, host = v.host, t = now() }
			end
			return true
		elseif tag == "A" then
			local ok, a = pcall(json.decode, data:sub(2))
			if not ok or type(a) ~= "table" then return true end
			local e = tonumber(a.epoch) or 0
			if R.mode == "migrating" then
				if e >= R.mig.epoch or contains(R.mig.cands, from) then follow(from, a) end
			elseif R.mode == "guest" then
				if from ~= R.host and e > (R.epoch or 0) then follow(from, a) end
			elseif R.mode == "host" then
				if e > R.epoch or (e == R.epoch and rank(from) < rank(B.my_id())) then
					-- our snapshot is no newer than theirs: the better candidate wins
					follow(from, a)
				end
			end
			return true
		end
		return false
	end

	----------------------------------------------------------------- host side
	function H.mark_dirty() H.dirty = true end

	--- Seat order of the other players (Steam ids): the succession list.
	--- 0.6.8: spectators can take over too (they get the same snapshots and run the same server
	--- code), but only after every seated player (alive or eliminated), so a player keeps priority.
	local function succession(L, lc)
		local list = {}
		for pass = 1, 2 do
			for _, pl in ipairs(L.players) do
				if pl ~= lc and ((pass == 1) == (not pl.spectator)) then
					local id = ctx.conn_peer(pl)
					if id then list[#list + 1] = id end
				end
			end
		end
		return list
	end

	function H.host_tick(force)
		if R.mode ~= "host" then return end
		H.announce(false)
		local core, lc = ctx.get_core(), ctx.local_conn()
		local L = lc.lobby
		if not L then return end
		local t = now()
		if not (force or H.dirty or t - H.last_snap_t >= 1) then return end
		H.dirty, H.last_snap_t = false, t
		local acks, any = {}, false
		for id, p in pairs(R.peers) do if p.conn then any = true; acks[id] = p.ack or 0 end end
		if not any then return end
		local state = core:snapshot(L.code, lc.id)
		if not state then return end
		local succ = succession(L, lc)
		R.succession_cache = succ
		local ok, str = pcall(json.encode, { epoch = R.epoch, succession = succ, acks = acks, state = state })
		if not ok then log("snapshot encode failed: " .. tostring(str)); return end
		if str == H.last_snap and not force then return end
		H.last_snap = str
		for id, p in pairs(R.peers) do if p.conn then B.send(id, "S" .. str) end end
	end

	--- The host's own player leaves: hand the lobby over instead of closing it. Returns true if
	--- the guests were told to migrate.
	function H.host_leaving()
		if R.mode ~= "host" then return false end
		local any = false
		for _, p in pairs(R.peers) do if p.conn then any = true end end
		if not any then return false end
		H.host_tick(true)
		for id, p in pairs(R.peers) do if p.conn then B.send(id, "L") end end
		log("host migration: leaving, guests take over")
		return true
	end

	----------------------------------------------------------------- per frame
	local last_check = -1
	function H.update()
		local t = now()
		if R.mode == "migrating" and R.mig and R.mig.deadline and t >= R.mig.deadline then
			R.mig.idx = R.mig.idx + 1
			R.mig.deadline = nil
			advance()
		end
		if t == last_check then return end
		last_check = t
		local rj = H.rejoin
		if rj then
			if R.mode ~= "local" or t > rj.until_t or ctx.local_conn().lobby then
				H.rejoin, R.quiet_join = nil, nil
			elseif t >= rj.next_t and not R.joining then
				rj.next_t = t + 5
				R.quiet_join = true
				ctx.start_join(rj.code, { action = "rejoinLobby", code = rj.code, reconnectToken = rj.token })
			end
		end
		local w = R.watch_old
		if w and R.mode == "host" and R.lobby and t - w.last >= M.WATCH_EVERY then
			w.last = t
			local p = R.peers[w.id]
			if not contains(members(), w.id) or (p and p.conn) then R.watch_old = nil -- gone, or rejoined as guest
			else send(w.id, "A", { epoch = R.epoch, host = B.my_id(), code = w.code }) end
		end
		if R.mode == "host" and R.lobby then
			-- we lost everyone and Steam gave the lobby to somebody else: we were cut off and the
			-- others migrated. Step down and rejoin the new host as a guest (seat held by token).
			local any = false
			for _, p in pairs(R.peers) do if p.conn then any = true end end
			if any then H.had_guests = true end
			local mem = members()
			local in_lobby = contains(mem, B.my_id())
			if in_lobby then H.was_member = true end
			local cut = (H.was_member and #mem > 0 and not in_lobby) -- Steam dropped us from our own lobby
			if not cut and not any and H.had_guests then
				local o = owner()
				cut = o ~= nil and o ~= B.my_id()
			end
			if cut then
				do
					H.had_guests = false
					local code, token = R.code, R.token
					log("host migration: cut off from the Steam lobby; rejoining as a guest")
					ctx.new_core(nil)
					for _, k in ipairs({ "version", "username" }) do if R.cached[k] then ctx.get_core():receive(ctx.local_conn(), R.cached[k]) end end
					ctx.to_local()
					ctx.push({ action = "hostMigrating", reason = "cut_off" })
					-- the connection may still be down: keep trying for a while
					if code and token then H.rejoin = { code = code, token = token, next_t = t, until_t = t + M.REJOIN_FOR } end
					return
				end
			end
		end
		if R.mode == "guest" and R.host and R.lobby then
			local hp = R.peers[R.host]
			if hp and t - hp.seen < 5 then R.timeout_since = nil end
			local mem = members()
			if contains(mem, R.host) then
				R.host_seen_member = true
			elseif R.host_seen_member and contains(mem, B.my_id()) then
				-- Steam says the host has left the lobby (quit / crash / lost connection)
				if not H.host_lost("disconnected") then H.fail("no snapshot from the host") end
			end
			if R.mode == "guest" then frozen_check(t, mem) end
		end
	end
	return H
end

return M
