-- Balatro High Stakes - DEV ONLY. GPL-3.0.
-- Local test transport: the same backend interface as the Steam FFI backend in networking/steam_p2p.lua,
-- but lobbies and messages are small files in one shared folder, so 2-8 Balatro instances on one PC can
-- play through the normal router + authoritative host (networking/p2p_server.lua). Needs only Lua io:
-- no sockets, no hub process, survives any instance quitting (host-migration tests).
--
-- Layout under dir (created by tools/dev_local_match.ps1 or fs.mkdir):
--   peers/<peer>                      session token + heartbeat time ("<session> <time>")
--   inbox/<to>__<from>__<session>__<seq>.msg   one message (written to tmp/ then renamed: never half read)
--   lobby/<id>__owner                 owner peer
--   lobby/<id>__m__<peer>             member heartbeat "<join_order> <time>"
--   lobby/<id>__d__<key>              lobby data
--   lobby/<id>__md__<peer>__<key>     member data
--   lobby/code__<CODE>                lobby id for a lobby code (find_lobby)
local M = {}
M.STALE = 15      -- seconds without heartbeat -> a member/peer counts as gone (Steam drops crashed members too)
M.BEAT = 2

local function safe(s) return (tostring(s):gsub("[^%w_%-]", "_")) end

function M.default_fs()
	local fs = {}
	function fs.read(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
	function fs.write(p, s) local f = io.open(p, "wb"); if not f then return false end f:write(s); f:close(); return true end
	function fs.remove(p) return os.remove(p) end
	function fs.rename(a, b) return os.rename(a, b) end
	function fs.exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end return false end
	function fs.mkdir(p)
		if NFS and NFS.createDirectory then return NFS.createDirectory(p) end
		if package.config:sub(1, 1) == "\\" then return os.execute('mkdir "' .. p:gsub("/", "\\") .. '" 2>NUL') end
		return os.execute('mkdir -p "' .. p .. '"')
	end
	return fs
end

--- o = { dir, me, peers = {list}, now = fn (seconds, may be fractional), fs, log, session }
function M.new(o)
	assert(o and o.dir and o.me and o.peers, "dir, me and peers are required")
	local fs, now, dir, me = o.fs or M.default_fs(), o.now or os.time, o.dir:gsub("[/\\]$", ""), safe(o.me)
	local B = { log = o.log, dev = true }
	-- unique per process even if several instances start in the same second with the same unseeded RNG
	local session = safe(o.session or (tostring(os.time()) .. string.format("%x", math.floor((os.clock() * 1e6) % 1e9)) .. tostring(o.me):gsub("%W", "")
		.. tostring({}):gsub("%W", "")))
	local seq, msgseq, rx, later, last_beat = 0, {}, {}, {}, -1e9
	local my_lobbies = {}
	for _, d in ipairs({ "", "/peers", "/inbox", "/lobby", "/tmp" }) do if not fs.exists(dir .. d .. "/.keep") then fs.mkdir(dir .. d); fs.write(dir .. d .. "/.keep", "") end end
	local function P(...) return dir .. "/" .. table.concat({ ... }) end
	local function atomic(path, s)
		seq = seq + 1
		local tmp = P("tmp/", me, "_", session, "_", seq, ".tmp")
		if not fs.write(tmp, s) then return false end
		fs.remove(path)
		if fs.rename(tmp, path) then return true end
		fs.remove(tmp); return false
	end
	local function alive_stamp(s)
		local t = s and tonumber(s:match("(%S+)$"))
		return t and (now() - t) <= M.STALE
	end
	local function beat(force)
		if not force and now() - last_beat < M.BEAT then return end
		last_beat = now()
		atomic(P("peers/", me), session .. " " .. now())
		for id, order in pairs(my_lobbies) do atomic(P("lobby/", id, "__m__", me), order .. " " .. now()) end
	end
	beat(true)

	function B.my_id() return me end
	function B.poll()
		local q = later; later = {}
		for _, f in ipairs(q) do f() end
		beat()
	end
	function B.pump() end
	local function defer(f) later[#later + 1] = f end

	function B.create_lobby(cb)
		defer(function()
			local id = "L" .. me .. "_" .. session:sub(-6) .. "_" .. math.floor(now())
			atomic(P("lobby/", id, "__owner"), me)
			my_lobbies[id] = 1
			beat(true)
			cb(id)
		end)
	end
	function B.find_lobby(code, cb)
		defer(function()
			local id = fs.read(P("lobby/code__", safe(code)))
			if id and B.owner(id) then return cb(id) end
			cb(nil)
		end)
	end
	function B.join_lobby(id, cb)
		defer(function()
			if not B.owner(id) then return cb(false, "lobby gone") end
			if #B.members(id) >= (o.max_members or 16) then return cb(false, "EChatRoomEnterResponse=4") end
			local order = 1
			for _, p in ipairs(o.peers) do
				local s = fs.read(P("lobby/", id, "__m__", safe(p)))
				local n = s and tonumber(s:match("^(%S+)"))
				if n and n >= order then order = n + 1 end
			end
			my_lobbies[id] = order
			beat(true)
			cb(true)
		end)
	end
	function B.leave_lobby(id)
		my_lobbies[id] = nil
		fs.remove(P("lobby/", id, "__m__", me))
	end
	function B.set_data(id, k, v)
		atomic(P("lobby/", id, "__d__", safe(k)), tostring(v))
		if k == "mp3p_code" and v and v ~= "" then atomic(P("lobby/code__", safe(v)), id) end
	end
	function B.get_data(id, k) return fs.read(P("lobby/", id, "__d__", safe(k))) or "" end
	function B.set_joinable() return true end
	function B.set_member_data(id, k, v) atomic(P("lobby/", id, "__md__", me, "__", safe(k)), tostring(v)) end
	function B.get_member_data(id, peer, k) return fs.read(P("lobby/", id, "__md__", safe(peer), "__", safe(k))) or "" end
	function B.set_owner(id, peer) return atomic(P("lobby/", id, "__owner"), safe(peer)) end
	--- live members, in join order
	function B.members(id)
		local list = {}
		for _, p in ipairs(o.peers) do
			local sp = safe(p)
			local s = sp == me and my_lobbies[id] and (my_lobbies[id] .. " " .. now()) or fs.read(P("lobby/", id, "__m__", sp))
			if s and alive_stamp(s) then list[#list + 1] = { id = sp, order = tonumber(s:match("^(%S+)")) or 99 } end
		end
		table.sort(list, function(a, b) return a.order < b.order end)
		local out = {}
		for i, m in ipairs(list) do out[i] = m.id end
		return out
	end
	--- like Steam: when the owner is gone, the longest-standing remaining member becomes owner
	function B.owner(id)
		local o_ = fs.read(P("lobby/", id, "__owner"))
		if not o_ then return nil end
		local mem = B.members(id)
		for _, m in ipairs(mem) do if m == o_ then return o_ end end
		if mem[1] then return mem[1] end
		return nil
	end
	function B.invite_dialog() return false end
	function B.set_presence() end
	function B.clear_presence() end
	function B.launch_args() return "" end
	function B.enable_join_callbacks() return false end
	function B.join_events() return {} end
	function B.accept() end
	function B.close() end
	function B.send(peer, data)
		local to = safe(peer)
		msgseq[to] = (msgseq[to] or 0) + 1 -- contiguous per (sender session, receiver)
		local name = table.concat({ to, me, session, string.format("%09d", msgseq[to]) }, "__") .. ".msg"
		local tmp = P("tmp/", name)
		if not fs.write(tmp, data) then return false end
		return fs.rename(tmp, P("inbox/", name)) and true or false
	end
	--- messages from every known peer, each in send order; a restarted peer (new session) starts at seq 1 again
	local clock = o.clock or (love and love.timer and love.timer.getTime) or os.clock
	local last_rx = -1e9
	function B.receive()
		local out = {}
		if clock() - last_rx < (o.rx_interval or 0.05) then return out end -- ~20 scans/s, plenty for a card game
		last_rx = clock()
		for _, p in ipairs(o.peers) do
			local sp = safe(p)
			if sp ~= me then
				local s = fs.read(P("peers/", sp))
				local sess = s and s:match("^(%S+)")
				if sess then
					local r = rx[sp]
					if not r or r.session ~= sess then r = { session = sess, next = nil }; rx[sp] = r end
					-- in order; skip at most a few missing numbers (a failed write) so one lost file cannot stall the peer
					local n, miss = r.next or 1, 0
					while miss <= 2 do
						local f = P("inbox/", me, "__", sp, "__", sess, "__", string.format("%09d", n), ".msg")
						local d = fs.read(f)
						if d then
							fs.remove(f)
							out[#out + 1] = { peer = sp, data = d }
							r.next, miss = n + 1, 0
						else
							miss = miss + 1
						end
						n = n + 1
					end
				end
			end
		end
		return out
	end
	return B
end

return M
