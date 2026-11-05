-- luajit tests/test_version_string.lua (run from mod/): 0.6.8 drops "~3P" from the version; every consumer copes
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local ver = io.open("Multiplayer.json"):read("*a"):match('"version"%s*:%s*"([^"]+)"')
ok(ver == "0.6.9.1", "Multiplayer.json version is plain 0.6.9.1 (got " .. tostring(ver) .. ")")
ok(not io.open("networking/p2p_server.lua"):read("*a"):find("MULTIPLAYER3P", 1, true), "lobby host SERVER_VERSION has no MULTIPLAYER3P suffix")
MP = { UTILS = {} }
SMODS = { Mods = { Multiplayer = { version = ver }, Steamodded = { version = "1.0.0~BETA-1620a-STEAMODDED" } } }
-- the version helpers of lib/matchmaking.lua (version_prefix .. version_mismatches_with), loaded on their own
local src = io.open("lib/matchmaking.lua"):read("*a")
local a = src:find("function MP.UTILS.version_prefix", 1, true)
local b = src:find("function MP.UTILS.version_mismatches_with", 1, true)
local e = select(2, src:find("\nend\n", b))
assert(loadstring(src:sub(a, e)))()
local U = MP.UTILS
ok(U.version_prefix("0.6.8") == "0.6.8" and U.version_prefix("0.6.8~3P") == "0.6.8" and U.version_prefix("0.6.7~3P") == "0.6.7", "lobby compares X.Y.Z: 0.6.8 == 0.6.8~3P, 0.6.7~3P differs")
local function peer(v) return { username = "p", hash_str = "Multiplayer-" .. v .. ";Steamodded-1.0.0~BETA-1620a-STEAMODDED" } end
ok(#U.version_mismatches_with(peer("0.6.9.1")) == 0, "two 0.6.9.1 players: no mismatch")
local mm = U.version_mismatches_with(peer("0.6.7~3P"))
ok(#mm == 1 and mm[1].our == "0.6.9.1" and mm[1].their == "0.6.7~3P", "0.6.9.1 vs 0.6.7~3P: one clear mismatch")
print("all version string tests passed")
