-- Host-controlled lobby visibility. Private is the default and is not marked for a lobby browser.
-- The Steam type is Invisible (3), not Private (0): code search and invites still work.
-- run from mod/: luajit tests/test_lobby_visibility.lua
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local P2P = dofile("networking/steam_p2p.lua")
local Core = dofile("networking/p2p_server.lua")
local Match = dofile("networking/match_settings.lua")
local HMmod = dofile("networking/host_migration.lua")
Core.TEAMS = dofile("networking/teams_rules.lua")
Core.PVP = dofile("networking/pvp_rules.lua")
Core.KOTH = dofile("networking/koth_rules.lua")

local function ok(c, m) assert(c, m); print("ok: " .. m) end

ok(P2P.STEAM_LOBBY_PUBLIC == 2, "public uses Steam type Public")
ok(P2P.STEAM_LOBBY_PRIVATE == 3, "private uses Steam type Invisible so a code search can still find it")
ok(P2P.STEAM_LOBBY_PRIVATE ~= 0 and P2P.STEAM_LOBBY_PRIVATE ~= 1, "not Steam Private or Friends-only (those are invisible to code search)")
local function vis(flag, public, typ, disc)
	local v = P2P.visibility(flag)
	ok(v.public == public and v.lobby_type == typ and v.discover == disc, "visibility " .. tostring(flag))
end
vis(nil, false, 3, "0")
vis(false, false, 3, "0")
vis("false", false, 3, "0")
vis(0, false, 3, "0")
vis(true, true, 2, "1")
vis("true", true, 2, "1")
vis(1, true, 2, "1")
ok(not P2P.discoverable(nil) and not P2P.discoverable("") and not P2P.discoverable("0"), "absent or 0 is not listed")
ok(P2P.discoverable("1"), "discover=1 is the browser flag")

local fresh = Match.fresh()
ok(fresh.lobby_public == false, "new lobby config defaults to private")
local guest = { lobby_public = true, weekly = "keep" }
Match.apply(guest, Match.wire(fresh))
ok(guest.lobby_public == false and guest.weekly == "keep", "guest public leftover is cleared; personal weekly stays")
local host_on = Match.fresh(); host_on.lobby_public = true
Match.apply(guest, Match.wire(host_on))
ok(guest.lobby_public == true, "guest follows the host when the lobby is public")

local T = 1000
local now = function() return T end
local NET
local function remove(t, x) for i = #t, 1, -1 do if t[i] == x then table.remove(t, i) end end end
local function steam_leave(l, me)
	local L = NET.lobbies[l]; if not L then return end
	remove(L.members, me)
	if L.owner == me then
		if #L.members == 0 then NET.lobbies[l] = nil else L.owner = L.members[1] end
	end
end

local function backend(me, opts)
	opts = opts or {}
	local B, pend = {}, {}
	NET.inbox[me] = {}
	local function later(f) pend[#pend + 1] = f end
	function B.poll() local p = pend; pend = {}; for _, f in ipairs(p) do f() end end
	function B.my_id() return me end
	function B.create_lobby(cb, typ) later(function()
		local id = tostring(8000 + NET.next); NET.next = NET.next + 1
		NET.lobbies[id] = { owner = me, members = { me }, data = {}, typ = typ, type_sets = 0 }
		NET.created = { id = id, typ = typ }
		cb(id)
	end) end
	function B.find_lobby(code, cb) later(function()
		for id, l in pairs(NET.lobbies) do if l.data.mp3p_code == code then return cb(id) end end
		cb(nil)
	end) end
	function B.join_lobby(id, cb) later(function()
		local l = NET.lobbies[id]
		if not l or (NET.dead and NET.dead[me]) then return cb(false) end
		NET.joins = (NET.joins or 0) + 1
		remove(l.members, me); table.insert(l.members, me); cb(true)
	end) end
	function B.leave_lobby(id) steam_leave(id, me) end
	function B.set_data(id, k, v)
		local l = NET.lobbies[id]
		if l and l.owner == me then l.data[k] = v end
	end
	function B.get_data(id, k) local l = NET.lobbies[id]; return l and l.data[k] or "" end
	function B.owner(id) local l = NET.lobbies[id]; return l and l.owner or "0" end
	if opts.types ~= false then
		function B.set_lobby_type(id, t)
			local l = NET.lobbies[id]
			if not l or l.owner ~= me then return false end
			l.typ = t; l.type_sets = (l.type_sets or 0) + 1
			return true
		end
	end
	function B.set_member_data() end
	function B.get_member_data() return "" end
	function B.set_owner(id, new)
		local l = NET.lobbies[id]
		if l and l.owner == me then l.owner = new; return true end
		return false
	end
	function B.members(id) local l = NET.lobbies[id]; local r = {}; for i, m in ipairs(l and l.members or {}) do r[i] = m end return r end
	function B.invite_dialog(id) NET.invited = id end
	B.rp = {}
	function B.set_presence(k, v) B.rp[k] = v end
	function B.clear_presence() B.rp = {} end
	function B.accept() end
	function B.close() end
	function B.send(peer, data)
		if NET.dead and (NET.dead[peer] or NET.dead[me]) then return true end
		local q = NET.inbox[peer]; if q then q[#q + 1] = { peer = me, data = data } end return true
	end
	function B.receive() local q = NET.inbox[me]; NET.inbox[me] = {}; return q or {} end
	return B
end

local all
local function player(name, types)
	local P = { name = name, msgs = {}, alive = true }
	P.b = backend(name, { types = types })
	P.r = P2P.new_router({ backend = P.b, Core = Core, json = json, now = now, version = "0.7.0", Migration = HMmod,
		push = function(s) P.msgs[#P.msgs + 1] = json.decode(s) end })
	P.send = function(t) P.r.send(t) end
	P.last = function(a) for i = #P.msgs, 1, -1 do if P.msgs[i].action == a then return P.msgs[i] end end end
	return P
end
local function pump(n) for _ = 1, n or 8 do for _, p in ipairs(all) do if p.alive then p.r.update() end end end end
local function run(secs) for _ = 1, secs do T = T + 1; pump(3) end end

local function boot(types)
	NET = { lobbies = {}, inbox = {}, next = 1, dead = {} }
	local A, B = player("ann", types), player("ben", types)
	all = { A, B }
	for _, p in ipairs(all) do
		p.send({ action = "connect" }); p.send({ action = "username", username = p.name, modHash = "t" })
		p.send({ action = "version", version = "0.7.0" })
	end
	A.send({ action = "createLobby", gameMode = "attrition" }); pump()
	return A, B
end

local A, B = boot(true)
local lob = NET.lobbies[A.r.lobby]
ok(NET.created.typ == P2P.STEAM_LOBBY_PRIVATE and lob.typ == P2P.STEAM_LOBBY_PRIVATE, "new lobby is created private")
ok(lob.data.mp3p_discover == "0", "private is not marked discoverable")
ok(A.b.rp.connect == nil, "private host does not publish friends-list Join game")
local code = A.last("joinedLobby").code
B.send({ action = "joinLobby", code = code }); pump(6)
ok(B.r.mode == "guest" and B.last("joinedLobby"), "code join still finds a private lobby")
ok(B.last("lobbyOptions") and B.last("lobbyOptions").lobby_public == false, "guest is told the lobby is private")
ok(A.r.invite() and NET.invited == A.r.lobby, "Steam invite dialog still opens for a private lobby")
ok((NET.joins or 0) >= 1, "joining the lobby id still calls JoinLobby")

A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true }); pump()
lob = NET.lobbies[A.r.lobby]
ok(lob.typ == P2P.STEAM_LOBBY_PUBLIC and lob.data.mp3p_discover == "1", "host can switch to public")
ok(A.b.rp.connect == "+connect_lobby " .. A.r.lobby, "public host publishes friends-list Join game")
local told = nil
for i = #B.msgs, 1, -1 do if B.msgs[i].action == "lobbyOptions" and B.msgs[i].lobby_public == true then told = B.msgs[i] end end
ok(told, "guest receives public=true")
local dirty = { lobby_public = false }
Match.apply(dirty, told)
ok(dirty.lobby_public == true, "guest local private is replaced by the host's public")

local before = lob.type_sets
B.send({ action = "lobbyOptions", match_settings = 1, lobby_public = false }); pump()
ok(NET.lobbies[A.r.lobby].typ == P2P.STEAM_LOBBY_PUBLIC and NET.lobbies[A.r.lobby].type_sets == before, "guest cannot change visibility")

A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = false }); pump()
lob = NET.lobbies[A.r.lobby]
ok(lob.typ == P2P.STEAM_LOBBY_PRIVATE and lob.data.mp3p_discover == "0" and A.b.rp.connect == nil, "host can switch back to private")
B.send({ action = "leaveLobby" }); pump()
B.send({ action = "joinLobby", code = code }); pump(6)
ok(B.last("joinedLobby"), "code join still works after toggling private again")

-- missing SetLobbyType: metadata still updates, nothing throws
local C, D = boot(false)
C.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true }); pump()
local bare = NET.lobbies[C.r.lobby]
ok(bare.data.mp3p_discover == "1" and bare.typ == P2P.STEAM_LOBBY_PRIVATE, "without SetLobbyType the create-time type stays private and discover is still set")
D.send({ action = "joinLobby", code = C.last("joinedLobby").code }); pump(4)
ok(D.r.mode == "guest", "code join works when SetLobbyType is missing")

-- public survives host migration
A, B = boot(true)
A.send({ action = "lobbyOptions", match_settings = 1, lobby_public = true, normal_bosses = true }); pump()
B.send({ action = "joinLobby", code = A.last("joinedLobby").code }); pump(8)
run(2) -- guest must see the host in the Steam lobby before the host disappears
A.alive = false
NET.dead[A.name] = true
steam_leave(A.r.lobby, A.name)
run(4)
ok(B.r.mode == "host", "guest became host")
local moved = NET.lobbies[B.r.lobby]
ok(moved and moved.owner == B.name, "Steam owner followed the new host")
ok(moved.data.mp3p_discover == "1" and moved.typ == P2P.STEAM_LOBBY_PUBLIC, "public listing survived host migration")
ok(B.last("lobbyOptions") and B.last("lobbyOptions").lobby_public == true and B.last("lobbyOptions").normal_bosses == true, "new host still has the match settings")

print("PASS: lobby visibility")
