-- luajit tests/test_discord_relay.lua (run from mod/): Discord bug relay (payload, limits, rate limit,
-- privacy) + the 4-part version exemption in the sanitizer. Never prints the webhook URL.
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = { MOD_VERSION = "0.6.8.1", LOBBY = {} }
G = { FUNCS = {} }
local BR = dofile("lib/bug_report.lua")
local DR = dofile("lib/discord_relay.lua")

-- sanitizer: own version kept, real IPs still removed
local s = BR.sanitize("Mod 0.6.8.1 | v0.6.8.1~3P | host 10.0.0.12:5000 | 192.168.1.20")
ok(s:find("0.6.8.1", 1, true) and not s:find("10.0.0.12", 1, true) and not s:find("192.168", 1, true), "own 4-part version kept, IPs removed")

-- relay URL only, no webhook anywhere
local src = io.open("lib/discord_relay.lua"):read("*a")
ok(DR.URL == "https://hs-bug-relay.framewise.workers.dev" and not src:find("discord.com/api", 1, true), "relay URL, no webhook")

-- payload: sanitized, within Discord limits
local data = { title = "Crash with Kevin", desc = string.rep("é long text ", 400) .. " steam 76561198012345678 ip 192.168.1.2",
	log = string.rep("C:\\Users\\jdoe\\x.log line\n", 50) .. "rejoin_token=abc123def\nusername: Jane~1\n" }
local p = DR.payload(data, { names = { "Kevin" }, codes = {} }, { mode = "deathmatch", players = 5 })
local all = p.description .. p.version .. p.mode .. p.players .. p.log
ok(#p.log <= 900, "log <= 900")
for _, bad in ipairs({ "Kevin", "jdoe", "76561198012345678", "192.168", "abc123def", "Jane" }) do ok(not all:find(bad, 1, true), "no " .. bad .. " in payload") end
ok(p.version == "0.6.8.1" and p.mode == "deathmatch" and p.players == "5", "version/mode/players")
ok(p.description:sub(-3) == "...", "long description cut")

-- rate limit: 1 per 2 minutes, 5 per session; offline (no https) = silent false
ok(DR.allowed(1000), "first report allowed")
DR.sent.n, DR.sent.last = 1, 1000
ok(not DR.allowed(1060) and DR.allowed(1121), "max 1 per 2 minutes")
DR.sent.n = 5
ok(not DR.allowed(5000), "max 5 per session")
DR.sent.n, DR.sent.last = 0, nil
package.preload["SMODS.https"] = function() error("no https") end
ok(DR.send(data, {}) == false and DR.sent.n == 0, "offline: silent, nothing counted")
local posted
package.loaded["SMODS.https"] = { asyncRequest = function(url, o, cb) posted = { m = o.method, ct = o.headers["Content-Type"], hx = o.headers["x-hs-client"], u = url, n = #o.data } end }
package.preload["json"] = function() return dofile("tests/dkjson.lua") end
ok(DR.send(data, {}) == true and posted and posted.m == "POST" and posted.ct == "application/json" and posted.hx == "balatro-high-stakes" and posted.u == DR.URL, "online: one POST with JSON")
ok(DR.send(data, {}) == false, "second report right after: rate limited")
ok(type(G.FUNCS.mp_open_discord) == "function", "Discord button handler registered")
print("PASS: discord relay")
