-- luajit tests/test_teams.lua (run from mod root): Teams + free-for-all PvP rules vs shared vectors
package.path = "tests/?.lua;" .. package.path
local json = require("dkjson")
local T = dofile("networking/teams_rules.lua")
local R = dofile("networking/pvp_rules.lua")
local Core = dofile("networking/p2p_server.lua")
local f = assert(io.open("tests/teams_vectors.json")); local V = json.decode(f:read("*a")); f:close()
local function null(v) if v == json.null then return nil end return v end
local n = 0
for _, c in ipairs(V.plans) do
	local size, count = T.plan(c.n, c.options)
	assert(size == null(c.size), "plan " .. c.n .. ": size " .. tostring(size))
	if size then assert(count == c.count, "plan " .. c.n .. ": count") end
	n = n + 1
end
for _, c in ipairs(V.assign) do
	local ids = {}
	for i = 1, c.n do ids[i] = "p" .. i end
	local t = assert(T.assign(ids, c.options))
	for i, want in ipairs(c.expect) do assert(t["p" .. i] == want, "assign seat " .. i .. " = " .. tostring(t["p" .. i])) end
	n = n + 1
end
for _, c in ipairs(V.cases) do
	local present = {}
	for team, list in pairs(c.teams) do
		present[team] = {}
		for i, s in ipairs(list) do present[team][i] = Core.parse_score(s) end
	end
	local got = T.resolve(present, c.size, Core.score_gt, Core.score_eq)
	assert(got == null(c.loser), c.name .. ": got " .. tostring(got))
	print("ok: " .. c.name); n = n + 1
end
for _, c in ipairs(V.ffa) do
	local entries = {}
	for i, s in ipairs(c.scores) do entries[i] = { id = i - 1, score = s } end
	local got = R.losers(entries, function(a, b) return a <= b end)
	table.sort(got)
	assert(#got == #c.losers, c.name .. ": " .. #got .. " losers")
	for i, v in ipairs(c.losers) do assert(got[i] == v, c.name) end
	print("ok: ffa " .. c.name); n = n + 1
end
Core.TEAMS = T
assert(Core.start_error("teams", 5, {}) == nil, "server allows 5")
assert(Core.start_error("teams", 7, {}) == nil, "server allows 7")
assert(Core.start_error("teams", 3, {}) ~= nil, "server rejects 3")
assert(Core.start_error("teams", 4, {}) == nil and Core.start_error("teams", 6, { teams_size = 3 }) == nil and Core.start_error("teams", 8, { teams_size = 4 }) == nil, "server still allows 4/6/8")
assert(Core.start_error("teams", 5, { teams_format = 2 }) ~= nil and Core.start_error("teams", 4, { teams_format = 2 }) == nil, "locked 2v2")
assert(Core.start_error("teams", 4, { teams_format = 3 }) ~= nil and Core.start_error("teams", 6, { teams_format = 3 }) == nil, "locked 3v3")
assert(Core.start_error("teams", 7, { teams_format = 4 }) ~= nil and Core.start_error("teams", 8, { teams_format = 4 }) == nil, "locked 4v4")
print("PASS test_teams (" .. n .. " vectors)")
