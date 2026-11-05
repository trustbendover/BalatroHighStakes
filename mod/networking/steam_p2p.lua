-- Balatro High Stakes (fork of Balatro Multiplayer): Steam peer-to-peer transport (GPL-3.0, see FORK_NOTICE.md)
--
-- Balatro's bundled luasteam.dll has no networking/matchmaking bindings, so this
-- talks to the steam_api64.dll that ships with Balatro through LuaJIT FFI (flat API).
-- Appid = Balatro's own (whatever SteamAPI was initialised with by the game).
--
-- Roles:
--   host  : runs the full server logic (2-8 players) in-process (networking/p2p_server.lua),
--           publishes a Steam lobby tagged with the lobby code, accepts peers.
--   guest : finds the Steam lobby by code, joins it and relays the normal JSON
--           actions to the host over ISteamNetworkingMessages.
--   local : before hosting/joining, the in-process core answers (username, version...).
-- Async calls are polled with ISteamUtils::IsAPICallCompleted/GetAPICallResult.
-- Balatro itself never calls luasteam's runCallbacks(), so Steam callbacks (invite
-- accepted, friends-list "Join game", P2P session requests) are never dispatched
-- unless we pump them: B.pump() calls G.STEAM.runCallbacks() once per frame (0.6.4 fix).

local M = {}

M.CHANNEL = 7
M.HEARTBEAT = 3
M.TIMEOUT = 20
M.SELF_STALL = 8 -- our own update gap this long counts as "we were frozen"
M.JOIN_ACTIONS = { version = true, username = true, joinLobby = true, rejoinLobby = true, connected = true, keepAlive = true }
M.LOBBY_KEY = "mp3p_code" -- protocol key, kept for compatibility with earlier builds
-- Steam ELobbyType (ISteamMatchmaking). RequestLobbyList only returns Public (2) and
-- Invisible (3). Private (0) and Friends-only (1) are not searchable, so a 5-letter code
-- could not find them. "Private" here is Invisible: hidden from the Steam friends list,
-- still found by code search and by a direct invite. "Public" is type Public.
-- mp3p_discover is "1" only for public. A future lobby browser must filter on that key.
-- Absent or "0" (older lobbies, or the host never chose) means not listed. The code is
-- not a password: anyone who has it can still join a private lobby.
M.STEAM_LOBBY_PUBLIC = 2
M.STEAM_LOBBY_PRIVATE = 3
M.DISCOVER_KEY = "mp3p_discover"

function M.visibility(flag)
	local public = flag == true or flag == "true" or flag == 1 or flag == "1"
	return {
		public = public,
		lobby_type = public and M.STEAM_LOBBY_PUBLIC or M.STEAM_LOBBY_PRIVATE,
		discover = public and "1" or "0",
	}
end

function M.discoverable(value)
	return value == "1" or value == 1 or value == true
end
-- Steam lobby member limit. Star topology: every guest talks only to the host, which runs the
-- server core and relays, so traffic grows linearly with players (8 is light).
M.MAX_MEMBERS = 16 -- 0.6.8: up to 8 players + room for spectators and rejoining players
M.SEARCH_TRIES = 4
M.SEARCH_DELAY = 3
M.INVITE_TRIES = 4

------------------------------------------------------------------------------
-- FFI backend
------------------------------------------------------------------------------
function M.new_ffi_backend()
	local ok_ffi, ffi = pcall(require, "ffi")
	if not ok_ffi then return nil, "LuaJIT FFI not available" end
	pcall(ffi.cdef, [[
		typedef struct { int32_t m_eType; int32_t m_cbSize; uint8_t m_data[128]; } MP3P_SteamNetworkingIdentity;
		typedef struct {
			void *m_pData; int32_t m_cbSize; int32_t m_conn;
			MP3P_SteamNetworkingIdentity m_identityPeer;
		} MP3P_SteamNetworkingMessage;
		void *SteamAPI_SteamMatchmaking_v009();
		void *SteamAPI_SteamUtils_v010();
		void *SteamAPI_SteamUser_v022();
		void *SteamAPI_SteamFriends_v017();
		void *SteamAPI_SteamNetworkingMessages_SteamAPI_v002();
		uint64_t SteamAPI_ISteamMatchmaking_CreateLobby(void *self, int eLobbyType, int cMaxMembers);
		uint64_t SteamAPI_ISteamMatchmaking_JoinLobby(void *self, uint64_t lobby);
		void SteamAPI_ISteamMatchmaking_LeaveLobby(void *self, uint64_t lobby);
		bool SteamAPI_ISteamMatchmaking_SetLobbyData(void *self, uint64_t lobby, const char *k, const char *v);
		const char *SteamAPI_ISteamMatchmaking_GetLobbyData(void *self, uint64_t lobby, const char *k);
		uint64_t SteamAPI_ISteamMatchmaking_GetLobbyOwner(void *self, uint64_t lobby);
		void SteamAPI_ISteamMatchmaking_SetLobbyMemberData(void *self, uint64_t lobby, const char *k, const char *v);
		const char *SteamAPI_ISteamMatchmaking_GetLobbyMemberData(void *self, uint64_t lobby, uint64_t user, const char *k);
		bool SteamAPI_ISteamMatchmaking_SetLobbyOwner(void *self, uint64_t lobby, uint64_t owner);
		int SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(void *self, uint64_t lobby);
		uint64_t SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(void *self, uint64_t lobby, int i);
		bool SteamAPI_ISteamMatchmaking_SetLobbyJoinable(void *self, uint64_t lobby, bool joinable);
		bool SteamAPI_ISteamMatchmaking_SetLobbyType(void *self, uint64_t lobby, int eLobbyType);
		void SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter(void *self, const char *k, const char *v, int cmp);
		void SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter(void *self, int f);
		uint64_t SteamAPI_ISteamMatchmaking_RequestLobbyList(void *self);
		uint64_t SteamAPI_ISteamMatchmaking_GetLobbyByIndex(void *self, int i);
		bool SteamAPI_ISteamUtils_IsAPICallCompleted(void *self, uint64_t call, bool *failed);
		bool SteamAPI_ISteamUtils_GetAPICallResult(void *self, uint64_t call, void *buf, int cb, int expected, bool *failed);
		uint64_t SteamAPI_ISteamUser_GetSteamID(void *self);
		void SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog(void *self, uint64_t lobby);
		int SteamAPI_ISteamNetworkingMessages_SendMessageToUser(void *self, const MP3P_SteamNetworkingIdentity *id, const void *data, uint32_t cb, int flags, int channel);
		int SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(void *self, int channel, MP3P_SteamNetworkingMessage **out, int max);
		bool SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(void *self, const MP3P_SteamNetworkingIdentity *id);
		bool SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(void *self, const MP3P_SteamNetworkingIdentity *id);
		void SteamAPI_SteamNetworkingMessage_t_Release(MP3P_SteamNetworkingMessage *msg);
		void SteamAPI_SteamNetworkingIdentity_SetSteamID64(MP3P_SteamNetworkingIdentity *self, uint64_t id);
		void *SteamAPI_SteamApps_v008();
		int SteamAPI_ISteamApps_GetLaunchCommandLine(void *self, char *buf, int cb);
		bool SteamAPI_ISteamFriends_SetRichPresence(void *self, const char *k, const char *v);
		void SteamAPI_ISteamFriends_ClearRichPresence(void *self);
		void SteamAPI_RegisterCallback(void *cb, int id);
		const char *GetCommandLineA(void);
		typedef struct MP3P_CallbackVT {
			void (*RunCallResult)(void *self, void *param, bool io, uint64_t call);
			void (*RunCallback)(void *self, void *param);
			int (*GetSize)(void *self);
		} MP3P_CallbackVT;
		typedef struct { MP3P_CallbackVT *vt; uint8_t flags; int32_t id; } MP3P_CallbackBase;
	]])
	assert(ffi.sizeof("MP3P_SteamNetworkingIdentity") == 136)
	local ok_lib, lib = pcall(ffi.load, "steam_api64")
	if not ok_lib then return nil, "steam_api64.dll not loadable: " .. tostring(lib) end
	local mm = lib.SteamAPI_SteamMatchmaking_v009()
	local utils = lib.SteamAPI_SteamUtils_v010()
	local user = lib.SteamAPI_SteamUser_v022()
	local friends = lib.SteamAPI_SteamFriends_v017()
	local net = lib.SteamAPI_SteamNetworkingMessages_SteamAPI_v002()
	if mm == nil or utils == nil or user == nil or net == nil then
		return nil, string.format("SteamAPI not initialised (mm=%s utils=%s user=%s net=%s)",
			tostring(mm ~= nil), tostring(utils ~= nil), tostring(user ~= nil), tostring(net ~= nil))
	end

	local function id2s(u) return (tostring(ffi.cast("uint64_t", u)):gsub("ULL$", "")) end
	local function s2id(s)
		local v = ffi.new("uint64_t", 0)
		for d in tostring(s):gmatch("%d") do v = v * 10 + tonumber(d) end
		return v
	end
	local function ident(s)
		local id = ffi.new("MP3P_SteamNetworkingIdentity")
		lib.SteamAPI_SteamNetworkingIdentity_SetSteamID64(id, s2id(s))
		return id
	end

	local B = { pending = {} }
	local failed = ffi.new("bool[1]")
	-- async call polling
	local function await(call, size, cbid, done)
		B.pending[#B.pending + 1] = { call = call, size = size, cbid = cbid, done = done }
	end
	function B.poll()
		for i = #B.pending, 1, -1 do
			local p = B.pending[i]
			if lib.SteamAPI_ISteamUtils_IsAPICallCompleted(utils, p.call, failed) then
				table.remove(B.pending, i)
				local buf = ffi.new("uint8_t[?]", p.size)
				local ok = lib.SteamAPI_ISteamUtils_GetAPICallResult(utils, p.call, buf, p.size, p.cbid, failed)
				p.done((ok and not failed[0]) and buf or nil)
			end
		end
	end
	function B.my_id() return id2s(lib.SteamAPI_ISteamUser_GetSteamID(user)) end
	-- LobbyCreated_t (513): int32 result; [pad]; uint64 lobby
	function B.create_lobby(cb, lobby_type)
		local typ = tonumber(lobby_type) or M.STEAM_LOBBY_PRIVATE
		await(lib.SteamAPI_ISteamMatchmaking_CreateLobby(mm, typ, M.MAX_MEMBERS), 16, 513, function(buf)
			if not buf then return cb(nil, "CreateLobby failed") end
			local res = ffi.cast("int32_t*", buf)[0]
			if res ~= 1 then return cb(nil, "CreateLobby result " .. res) end
			cb(id2s(ffi.cast("uint64_t*", buf + 8)[0]))
		end)
	end
	-- LobbyMatchList_t (510): uint32 count
	function B.find_lobby(code, cb)
		lib.SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter(mm, M.LOBBY_KEY, code, 0)
		lib.SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter(mm, 3 --[[worldwide]])
		local call = lib.SteamAPI_ISteamMatchmaking_RequestLobbyList(mm)
		if B.log then B.log("RequestLobbyList call=" .. id2s(call)) end
		await(call, 4, 510, function(buf)
			if not buf then if B.log then B.log("RequestLobbyList failed") end return cb(nil) end
			local n = ffi.cast("uint32_t*", buf)[0]
			if B.log then B.log("RequestLobbyList matches=" .. tostring(n)) end
			if n < 1 then return cb(nil) end
			cb(id2s(lib.SteamAPI_ISteamMatchmaking_GetLobbyByIndex(mm, 0)))
		end)
	end
	-- LobbyEnter_t (504): uint64 lobby; uint32 perms; bool locked; uint32 response (1 = success)
	function B.join_lobby(lobby, cb)
		await(lib.SteamAPI_ISteamMatchmaking_JoinLobby(mm, s2id(lobby)), 24, 504, function(buf)
			if not buf then return cb(false, "JoinLobby call failed") end
			local resp = ffi.cast("uint32_t*", buf + 16)[0]
			cb(resp == 1, "EChatRoomEnterResponse=" .. tostring(resp))
		end)
	end
	function B.leave_lobby(lobby) lib.SteamAPI_ISteamMatchmaking_LeaveLobby(mm, s2id(lobby)) end
	function B.set_data(lobby, k, v) lib.SteamAPI_ISteamMatchmaking_SetLobbyData(mm, s2id(lobby), k, tostring(v)) end
	function B.get_data(lobby, k)
		local r = lib.SteamAPI_ISteamMatchmaking_GetLobbyData(mm, s2id(lobby), k)
		return r ~= nil and ffi.string(r) or ""
	end
	function B.set_joinable(lobby, j) lib.SteamAPI_ISteamMatchmaking_SetLobbyJoinable(mm, s2id(lobby), j) end
	function B.set_lobby_type(lobby, t)
		local ok, res = pcall(lib.SteamAPI_ISteamMatchmaking_SetLobbyType, mm, s2id(lobby), tonumber(t) or M.STEAM_LOBBY_PRIVATE)
		if not ok and B.log then B.log("SetLobbyType unavailable: " .. tostring(res)) end
		return ok and res and true or false
	end
	function B.owner(lobby) return id2s(lib.SteamAPI_ISteamMatchmaking_GetLobbyOwner(mm, s2id(lobby))) end
	-- host migration: only the current owner can hand the lobby over
	-- every member may tag itself (host migration: the real host while the owner is frozen)
	function B.set_member_data(lobby, k, v) lib.SteamAPI_ISteamMatchmaking_SetLobbyMemberData(mm, s2id(lobby), k, tostring(v)) end
	function B.get_member_data(lobby, id, k)
		local r = lib.SteamAPI_ISteamMatchmaking_GetLobbyMemberData(mm, s2id(lobby), s2id(id), k)
		return r ~= nil and ffi.string(r) or ""
	end
	function B.set_owner(lobby, id) return lib.SteamAPI_ISteamMatchmaking_SetLobbyOwner(mm, s2id(lobby), s2id(id)) end
	function B.members(lobby)
		local out, L = {}, s2id(lobby)
		for i = 0, lib.SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(mm, L) - 1 do
			out[#out + 1] = id2s(lib.SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(mm, L, i))
		end
		return out
	end
	function B.invite_dialog(lobby)
		if friends ~= nil then lib.SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog(friends, s2id(lobby)) end
	end
	function B.set_presence(k, v)
		if friends ~= nil then
			local okp = lib.SteamAPI_ISteamFriends_SetRichPresence(friends, k, v)
			if B.log then B.log("rich presence " .. k .. "=" .. v .. " -> " .. tostring(okp)) end
		end
	end
	function B.clear_presence()
		if friends ~= nil then lib.SteamAPI_ISteamFriends_ClearRichPresence(friends) end
	end
	-- launch options: Steam passes "+connect_lobby <id>" (lobby invite) or our rich-presence
	-- "connect" string on the process command line when the game is started from an invite.
	function B.launch_args()
		local parts = {}
		if type(arg) == "table" then for _, a in ipairs(arg) do parts[#parts + 1] = tostring(a) end end
		pcall(function() -- full process command line (Steam appends +connect_lobby <id> here)
			local c = ffi.C.GetCommandLineA()
			if c ~= nil then parts[#parts + 1] = ffi.string(c) end
		end)
		local ok = pcall(function()
			local apps = lib.SteamAPI_SteamApps_v008()
			if apps ~= nil then
				local buf = ffi.new("char[1024]")
				local n = lib.SteamAPI_ISteamApps_GetLaunchCommandLine(apps, buf, 1024)
				if n > 0 then parts[#parts + 1] = ffi.string(buf) end
			end
		end)
		return table.concat(parts, " ")
	end
	-- Join requests while the game runs. luasteam owns SteamAPI_RunCallbacks, so we
	-- register our own CCallbackBase objects (MSVC x64 vtable order: RunCallResult,
	-- RunCallback, GetSize) and let luasteam's RunCallbacks dispatch them.
	B.events = {}
	B.cb_keep = {}
	local function register(id, size, handler)
		local vt = ffi.new("MP3P_CallbackVT")
		local f1 = ffi.cast("void (*)(void *, void *, bool, uint64_t)", function(_, param) pcall(handler, param) end)
		local f2 = ffi.cast("void (*)(void *, void *)", function(_, param) pcall(handler, param) end)
		local f3 = ffi.cast("int (*)(void *)", function() return size end)
		vt.RunCallResult, vt.RunCallback, vt.GetSize = f1, f2, f3
		local obj = ffi.new("MP3P_CallbackBase")
		obj.vt, obj.flags, obj.id = vt, 0, id
		lib.SteamAPI_RegisterCallback(obj, id)
		B.cb_keep[#B.cb_keep + 1] = { vt, f1, f2, f3, obj } -- never GC'd
	end
	function B.enable_join_callbacks()
		if B.cb_on then return true end
		B.cb_on = pcall(function()
			-- GameLobbyJoinRequested_t (333): CSteamID lobby; CSteamID friend
			register(333, 16, function(p)
				B.events[#B.events + 1] = { lobby = id2s(ffi.cast("uint64_t*", p)[0]) }
			end)
			-- GameRichPresenceJoinRequested_t (337): CSteamID friend; char connect[256]
			register(337, 264, function(p)
				B.events[#B.events + 1] = { connect = ffi.string(ffi.cast("char*", p) + 8) }
			end)
			-- SteamNetworkingMessagesSessionRequest_t (1251): SteamNetworkingIdentity remote (steamid at +8)
			register(1251, 136, function(p)
				B.events[#B.events + 1] = { session = id2s(ffi.cast("uint64_t*", ffi.cast("uint8_t*", p) + 8)[0]) }
			end)
		end)
		return B.cb_on
	end
	function B.join_events() local e = B.events; B.events = {}; return e end
	-- dispatch Steam callbacks (Balatro never does this itself)
	B.pump_state = "unknown"
	function B.pump()
		local st = rawget(_G, "G") and G.STEAM
		if not (st and st.runCallbacks) then
			if B.pump_state ~= "missing" and B.log then B.log("callback pump: G.STEAM.runCallbacks not available yet") end
			B.pump_state = "missing"
			return false
		end
		local ok, err = pcall(st.runCallbacks)
		if ok and B.pump_state ~= "ok" then
			B.pump_state = "ok"
			if B.log then B.log("callback pump active (G.STEAM.runCallbacks each frame)") end
		elseif not ok and B.pump_state ~= "error" then
			B.pump_state = "error"
			if B.log then B.log("callback pump error: " .. tostring(err)) end
		end
		return ok
	end
	function B.accept(peer) lib.SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(net, ident(peer)) end
	function B.close(peer) lib.SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(net, ident(peer)) end
	-- Reliable (8) + AutoRestartBrokenSession (32)
	function B.send(peer, data)
		return lib.SteamAPI_ISteamNetworkingMessages_SendMessageToUser(net, ident(peer), data, #data, 40, M.CHANNEL) == 1
	end
	local msgs = ffi.new("MP3P_SteamNetworkingMessage*[32]")
	function B.receive()
		local out = {}
		while true do
			local n = lib.SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(net, M.CHANNEL, msgs, 32)
			if n <= 0 then break end
			for i = 0, n - 1 do
				local m = msgs[i]
				local sid = ffi.cast("uint64_t*", m.m_identityPeer.m_data)[0]
				out[#out + 1] = { peer = id2s(sid), data = ffi.string(m.m_pData, m.m_cbSize) }
				lib.SteamAPI_SteamNetworkingMessage_t_Release(m)
			end
			if n < 32 then break end
		end
		return out
	end
	return B
end

------------------------------------------------------------------------------
-- Router (pure Lua; unit-tested with a fake backend)
------------------------------------------------------------------------------
-- opts: backend, Core (p2p_server module), json {encode, decode}, push(str) -> UI,
--       log(str), now() -> seconds, version (lobby data tag)
function M.new_router(o)
	local R = { backend = o.backend, mode = "local", peers = {}, cached = {}, lobby = nil, host = nil, joining = false }
	local B, json, now = o.backend, o.json, o.now or os.time
	local log = o.log or function() end
	local core = o.Core.new({ log = log, now = now })
	B.log = log
	R.core = core
	R.gen = 0 -- bumped whenever the in-process server is replaced (old connections go silent)
	local TOKEN_ACTIONS = { joinedLobby = true, rejoinedLobby = true, hostMigrated = true }
	local function push(t)
		if type(t) == "table" and TOKEN_ACTIONS[t.action] then
			R.token = t.reconnectToken or R.token
			R.code = t.code or R.code
		end
		o.push(type(t) == "string" and t or json.encode(t))
	end
	-- the UI's own {"action":"connect"} produces the "connected"; drop the core's automatic one
	local localConn
	local function connect_local(silent)
		local gen, first = R.gen, true
		localConn = core:connect(function(t)
			if R.gen ~= gen then return end
			if first and t.action == "connected" then first = false; return end
			if silent and t.action == "version" then silent = false; return end
			push(t)
		end, function() end)
	end
	connect_local(false)
	local conn_peer = setmetatable({}, { __mode = "k" }) -- core connection -> Steam id
	local HM -- host migration (networking/host_migration.lua), optional

	local function peer(id)
		local p = R.peers[id]
		if not p then
			log("P2P peer added " .. tostring(id) .. " (mode " .. R.mode .. ")")
			p = { id = id, seen = now(), sent = 0 }
			R.peers[id] = p
			B.accept(id)
			B.send(id, "H")
		end
		return p
	end
	local function drop_peer(id)
		local p = R.peers[id]
		if not p then return end
		R.peers[id] = nil
		if p.conn then core:disconnect(p.conn) end
		B.close(id)
	end
	local function presence(lobby, public)
		if not B.set_presence then return end
		-- Private: do not publish a friends-list "Join game" string. Steam invites still
		-- carry the lobby id, and the code search still finds an Invisible lobby.
		if lobby and public then
			B.set_presence("connect", "+connect_lobby " .. lobby)
			B.set_presence("steam_player_group", lobby)
			B.set_presence("steam_player_group_size", "3")
			B.set_presence("status", "Balatro High Stakes lobby")
		elseif B.clear_presence then
			B.clear_presence()
		end
	end
	R.want_public = false
	local function publish_visibility()
		if R.mode ~= "host" or not R.lobby then return end
		local v = M.visibility(R.want_public)
		if B.set_data then pcall(B.set_data, R.lobby, M.DISCOVER_KEY, v.discover) end
		local owned = not B.owner
		if B.owner then
			local ok_o, o = pcall(B.owner, R.lobby)
			owned = ok_o and o == B.my_id()
		end
		if owned and B.set_lobby_type then pcall(B.set_lobby_type, R.lobby, v.lobby_type) end
		if owned then R.applied_public = v.public end
		presence(R.lobby, v.public)
	end
	function R.apply_visibility(flag)
		R.want_public = M.visibility(flag).public
		R.applied_public = nil
		publish_visibility()
	end
	local function to_local()
		if R.lobby then B.leave_lobby(R.lobby) end
		presence(nil)
		for id in pairs(R.peers) do drop_peer(id) end
		R.mode, R.lobby, R.host, R.joining, R.retry, R.invite_retry = "local", nil, nil, false, nil, nil
		if HM then HM.reset() end
	end
	R.to_local = to_local
	--- Replace the in-process server (host migration). make(opts) -> new server, or nil for a fresh one.
	local function new_core(make)
		R.gen = R.gen + 1
		core = make and make() or o.Core.new({ log = log, now = now })
		R.core = core
		for _, p in pairs(R.peers) do p.conn = nil end
		connect_local(true)
		return core
	end

	local function host_lobby_code()
		return localConn.lobby and localConn.lobby.code or nil
	end

	local function start_hosting()
		R.mode = "host"
		local created_as = M.visibility(R.want_public).lobby_type
		B.create_lobby(function(lobby, err)
			if not lobby then
				log("Steam lobby creation failed: " .. tostring(err))
				push({ action = "error", message = "Steam lobby could not be created (" .. tostring(err) .. ")" })
				return
			end
			if R.mode ~= "host" or not host_lobby_code() then B.leave_lobby(lobby); return end
			R.lobby = lobby
			B.set_data(lobby, M.LOBBY_KEY, host_lobby_code())
			B.set_data(lobby, "mp3p_version", o.version or "")
			publish_visibility()
			log("Steam lobby " .. lobby .. " type " .. tostring(created_as)
				.. " discover=" .. M.visibility(R.want_public).discover
				.. " for code " .. host_lobby_code())
		end, created_as)
	end

	-- join a known Steam lobby id; first_msg nil => joinLobby with the lobby's published code
	local function join_by_id(lobby, first_msg, attempt)
		attempt = attempt or 1
		log("invite: JoinLobby " .. lobby .. " (attempt " .. attempt .. ")")
		B.join_lobby(lobby, function(ok, why)
			log("invite: JoinLobby " .. lobby .. " -> " .. tostring(ok) .. " " .. tostring(why or ""))
			if not ok then
				if not first_msg and attempt < M.INVITE_TRIES then
					R.invite_retry = { at = now() + M.SEARCH_DELAY, lobby = lobby, attempt = attempt + 1 }
					return
				end
				R.joining = false
				if not R.quiet_join then push({ action = "error", message = "Could not join the Steam lobby (" .. tostring(why) .. ")" }) end
				return
			end
			local owner = B.owner(lobby)
			-- after a host migration the Steam owner may be a frozen old host: the member with the
			-- highest "mp3p_host" epoch in its member data is the real host
			if B.get_member_data then
				local best = 0
				for _, id in ipairs(B.members(lobby)) do
					local okd, v = pcall(B.get_member_data, lobby, id, "mp3p_host")
					local e = okd and tonumber(v) or nil
					if e and e > best and id ~= B.my_id() then best, owner = e, id end
				end
			end
			local msg = first_msg
			if not msg then
				local code = B.get_data and B.get_data(lobby, M.LOBBY_KEY) or ""
				log("invite: lobby " .. lobby .. " code='" .. code .. "' owner=" .. tostring(owner))
				if code == "" then
					R.joining = false; B.leave_lobby(lobby)
					push({ action = "error", message = "That Steam lobby is not a Balatro High Stakes lobby (or it closed)" })
					return
				end
				msg = { action = "joinLobby", code = code }
			end
			R.mode, R.lobby, R.host, R.joining = "guest", lobby, owner, false
			presence(lobby, false)
			peer(owner)
			-- the remote core needs our identity first, then the join itself
			for _, k in ipairs({ "version", "username" }) do
				if R.cached[k] then B.send(owner, "J" .. json.encode(R.cached[k])) end
			end
			local sent = B.send(owner, "J" .. json.encode(msg))
			log("invite/code join: sent " .. tostring(msg.action) .. " to host " .. owner .. " -> " .. tostring(sent))
		end)
	end

	-- Steam's lobby search index lags a few seconds behind a new lobby: retry a few times
	local function start_join(code, first_msg, attempt)
		if R.joining and not attempt then return end
		R.joining = true
		attempt = attempt or 1
		B.find_lobby(code, function(lobby)
			if not lobby then
				if attempt < M.SEARCH_TRIES then
					R.retry = { at = now() + M.SEARCH_DELAY, code = code, msg = first_msg, attempt = attempt + 1 }
					return
				end
				R.joining = false
				if first_msg and first_msg.action == "rejoinLobby" then
					log("Steam rejoin: lobby " .. code .. " no longer exists")
				else
					push({ action = "error", message = "No Steam lobby found with code " .. code })
				end
				return
			end
			join_by_id(lobby, first_msg)
		end)
	end

	-- invite / friends-list "Join game" / +connect_lobby: no code typing needed
	R.pending_invite = nil
	local ready = o.ready or function() return true end
	function R.accept_invite(lobby, source)
		lobby = tostring(lobby or ""):match("(%d+)")
		if not lobby or #lobby < 3 then return false end
		if lobby == R.lobby then log("invite: already in lobby " .. lobby); return false end
		R.pending_invite, R.last_invite = lobby, lobby
		R.pending_since = now()
		log("invite: pending lobby " .. lobby .. " (" .. tostring(source or "?") .. ")")
		return true
	end
	local waited_log = nil
	local function run_pending_invite()
		local lobby = R.pending_invite
		if not lobby or R.joining then return end
		local why = (not R.cached.username and "username not sent yet") or (not ready() and "main menu not ready") or nil
		if why then
			if waited_log ~= why then log("invite: waiting (" .. why .. ")"); waited_log = why end
			return
		end
		waited_log = nil
		R.pending_invite = nil
		if R.mode == "guest" then
			B.send(R.host, "J" .. json.encode({ action = "leaveLobby" }))
			to_local()
		elseif R.mode == "host" or localConn.lobby then
			core:receive(localConn, { action = "leaveLobby" })
			to_local()
		end
		R.joining = true
		join_by_id(lobby, nil)
	end
	function M.parse_connect(s)
		s = tostring(s or "")
		return s:match("%+connect_lobby%s+(%d+)") or s:match("connect_lobby=(%d+)") or s:match("joinlobby/%d+/(%d+)")
	end

	function R.send(msg)
		local a = msg.action
		if a == "version" or a == "username" then R.cached[a] = msg end
		if a == "connect" then -- the in-process core is always reachable
			if R.mode ~= "guest" then push({ action = "connected" }) end
			return
		end
		if R.mode == "guest" then
			B.send(R.host, HM and HM.guest_frame(msg) or ("J" .. json.encode(msg)))
			if a == "leaveLobby" then to_local() end
			return
		end
		if R.mode == "migrating" then
			-- no host right now: keep game messages for the new host, leaving cancels
			if a == "leaveLobby" then to_local(); return end
			HM.guest_frame(msg)
			return
		end
		if a == "leaveLobby" and R.mode == "host" and HM and HM.host_leaving() then
			-- the guests continue with a new host; our own server goes quiet
			new_core(nil)
			for _, k in ipairs({ "version", "username" }) do if R.cached[k] then core:receive(localConn, R.cached[k]) end end
			to_local()
			return
		end
		if (a == "joinLobby" or a == "rejoinLobby") and msg.code and not core.lobbies[msg.code] then
			if R.mode == "host" then to_local() end
			return start_join(msg.code, msg)
		end
		core:receive(localConn, msg)
		if HM then HM.mark_dirty() end
		if R.mode == "host" and a == "lobbyOptions"
			and (msg.lobby_public ~= nil or msg.match_settings == 1 or msg.match_settings == "1" or msg.match_settings == true) then
			R.apply_visibility(msg.lobby_public)
		end
		if a == "createLobby" and host_lobby_code() then
			start_hosting()
		elseif R.mode == "host" and not host_lobby_code() then
			to_local() -- host left / lobby gone
		end
	end

	-- fallback UI: join by pasted lobby id / steam link / 5-letter code, or retry the last invite
	function R.join_text(text)
		text = tostring(text or "")
		local l = M.parse_connect(text) or text:match("(%d%d%d%d%d%d%d%d%d%d+)")
		if l then return R.accept_invite(l, "pasted lobby id") and "invite" or false end
		local code = text:upper():gsub("[^%a]", ""):sub(1, 5)
		if #code == 5 then R.send({ action = "joinLobby", code = code }); return "code" end
		return false
	end
	function R.retry_invite()
		if not R.last_invite then return false end
		R.joining = false
		return R.accept_invite(R.last_invite, "retry button")
	end

	function R.invite()
		if not R.lobby then return false end
		B.invite_dialog(R.lobby)
		return true
	end

	if B.enable_join_callbacks then log("Steam callbacks registered: " .. tostring(B.enable_join_callbacks())) end
	if B.launch_args then
		local args = tostring(B.launch_args())
		log("launch command line: " .. args)
		local l = M.parse_connect(args)
		if l then log("Started from a Steam invite, lobby " .. l); R.accept_invite(l, "launch +connect_lobby") end
	end

	local last_members, last_hb = -1, -1
	function R.update()
		if B.pump then B.pump() end
		B.poll()
		if B.join_events then
			for _, e in ipairs(B.join_events()) do
				if e.session then
					log("P2P session request from " .. e.session .. " (mode " .. R.mode .. ")")
					if R.mode == "host" or (R.mode == "guest" and e.session == R.host) or R.mode == "migrating"
						or (HM and R.lobby and R.mode == "guest") then
						B.accept(e.session)
						if R.mode == "host" then peer(e.session) end
					end
				else
					local l = e.lobby or M.parse_connect(e.connect)
					log("Steam join request: lobby=" .. tostring(e.lobby) .. " connect=" .. tostring(e.connect))
					if l then R.accept_invite(l, e.lobby and "overlay invite" or "friends list Join game") end
				end
			end
		end
		run_pending_invite()
		if R.invite_retry and now() >= R.invite_retry.at then
			local r = R.invite_retry; R.invite_retry = nil
			join_by_id(r.lobby, nil, r.attempt)
		end
		if R.retry and now() >= R.retry.at then
			local r = R.retry; R.retry = nil
			start_join(r.code, r.msg, r.attempt)
		end
		local t = now()
		-- 0.6.8 final: WE were frozen (game hitch, alt-tab, slow PC): silence that piled up while we
		-- were not running is not the peers' fault. Restart their timeout clocks instead of
		-- dropping them / abandoning the host on the first frame after waking up.
		if R.last_tick and t - R.last_tick >= M.SELF_STALL then
			log(string.format("we were frozen for %.0f s: peer timeouts restarted", t - R.last_tick))
			for _, p in pairs(R.peers) do p.seen = math.max(p.seen or t, t) end
			if HM and HM.self_stalled then HM.self_stalled(t) end
		end
		R.last_tick = t
		local fr = R.follow_retry
		if fr then
			if R.mode ~= "guest" or R.host ~= fr.id or t > fr.until_t then R.follow_retry = nil
			elseif t >= fr.next_t then
				fr.next_t = t + 4
				log("rejoin to the new host " .. tostring(fr.id) .. " not answered yet: retrying")
				for _, k in ipairs({ "version", "username" }) do if R.cached and R.cached[k] then B.send(fr.id, "J" .. json.encode(R.cached[k])) end end
				B.send(fr.id, "J" .. json.encode({ action = "rejoinLobby", code = fr.code, reconnectToken = R.token }))
			end
		end
		for _, m in ipairs(B.receive()) do
			local p = R.peers[m.peer]
			if R.mode == "host" and not p then p = peer(m.peer) end
			if p then p.seen = t end
			local tag = m.data:sub(1, 1)
			-- 0.6.8 final: any sign of life (also plain heartbeats) from a guest we timed out: ask it to
			-- rejoin with its token (an idle guest would otherwise never be re-attached)
			if R.mode == "host" and R.dropped and R.dropped[m.peer] and p and not p.conn and tag ~= "J" and tag ~= "Q"
				and t - R.dropped[m.peer] >= 2 then R.dropped[m.peer] = t; B.send(m.peer, "R") end
			if HM and (tag == "S" or tag == "A" or tag == "L" or tag == "V") then
				HM.on_frame(m.peer, m.data)
			elseif p then
				local body, seq = nil, nil
				if tag == "J" then
					body = m.data:sub(2)
				elseif tag == "Q" then
					local n, rest = m.data:match("^Q(%d+)|(.*)$")
					seq, body = tonumber(n), rest
				end
				if body then
					local ok, msg = pcall(json.decode, body)
					if ok and type(msg) == "table" then
						local resync = R.mode == "host" and not p.conn and R.dropped and R.dropped[m.peer]
							and not M.JOIN_ACTIONS[msg.action]
						if resync then
							-- 0.6.8 final: a guest we timed out (seat held) is alive again and still
							-- playing: ask it to rejoin with its token instead of dropping its messages
							if t - (R.dropped[m.peer] or 0) >= 2 then R.dropped[m.peer] = t; B.send(m.peer, "R") end
						elseif R.mode == "host" then
							if msg.action == "rejoinLobby" and R.dropped then R.dropped[m.peer] = nil end
							if not p.conn then
								local id, gen = m.peer, R.gen
								p.conn = core:connect(function(x) if R.gen == gen then B.send(id, "J" .. json.encode(x)) end end,
									function() if R.gen == gen then B.send(id, "K") end end)
								conn_peer[p.conn] = id
							end
							core:receive(p.conn, msg)
							if seq then p.ack = math.max(p.ack or 0, seq) end
							if HM then HM.mark_dirty() end
						elseif R.mode == "guest" and m.peer == R.host and msg.action ~= "connected" then
							if msg.action == "rejoinedLobby" or msg.action == "joinedLobby" or msg.action == "hostMigrated" then R.follow_retry = nil end
							if msg.action == "lobbyOptions" or msg.action == "rematch" or msg.action == "startGame" then
								local flag = msg.lobby_public
								if flag == nil and type(msg.config) == "table" then flag = msg.config.lobby_public end
								if flag ~= nil or msg.action == "lobbyOptions" then presence(R.lobby, M.visibility(flag).public) end
							end
							push(msg)
						end
					end
				elseif m.data == "R" and R.mode == "guest" and m.peer == R.host then
					log("host asked us to rejoin (we timed out); rejoining with our token")
					for _, k in ipairs({ "version", "username" }) do if R.cached and R.cached[k] then B.send(m.peer, "J" .. json.encode(R.cached[k])) end end
					B.send(m.peer, "J" .. json.encode({ action = "rejoinLobby", code = R.code, reconnectToken = R.token }))
				elseif m.data == "K" and R.mode == "guest" and m.peer == R.host then
					to_local(); push({ action = "disconnected" })
				end
			end
		end
		if R.mode == "host" and R.lobby and R.applied_public ~= R.want_public then publish_visibility() end
		if R.mode == "host" and R.lobby and t ~= last_members then
			last_members = t
			local me = B.my_id()
			for _, id in ipairs(B.members(R.lobby)) do
				if id ~= me and not R.peers[id] then peer(id) end
			end
		end
		if t - last_hb >= M.HEARTBEAT then
			last_hb = t
			for id in pairs(R.peers) do B.send(id, "H") end
		end
		for id, p in pairs(R.peers) do
			if t - p.seen > M.TIMEOUT then
				if not p.timeout_logged then log("Steam peer " .. id .. " timed out"); p.timeout_logged = true end
				if R.mode == "guest" and id == R.host then
					if HM then
						if not HM.host_timeout() then HM.fail("host timed out", "Lost connection to the Steam host. Back to the menu.") end
					else
						to_local()
						push({ action = "error", message = "Lost connection to the Steam host" })
						push({ action = "disconnected" })
					end
				elseif R.mode == "migrating" then
					R.peers[id] = nil
				else
					if R.mode == "host" then R.dropped = R.dropped or {}; R.dropped[id] = 0 end
					drop_peer(id)
				end
			end
		end
		core:tick()
		if HM then HM.update(); HM.host_tick(false) end
	end

	if o.Migration then
		HM = o.Migration.attach({
			R = R, B = B, json = json, now = now, log = log, push = push, Core = o.Core,
			peer = peer, drop_peer = drop_peer, to_local = to_local, start_join = function(...) return start_join(...) end,
			get_core = function() return core end, local_conn = function() return localConn end,
			conn_peer = function(c) return conn_peer[c] end,
			new_core = function(make) return new_core(make) end,
		})
		R.migration = HM
	end
	return R
end

return M
