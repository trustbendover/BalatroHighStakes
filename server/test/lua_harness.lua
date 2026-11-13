-- stdin/stdout bridge so the Node tests can drive the Lua P2P server core.
package.path = arg[1] .. "/?.lua;" .. package.path
local json = require("dkjson")
local Core = dofile(arg[2])
Core.KOTH = dofile((arg[2]:gsub("p2p_server%.lua$", "koth_rules.lua")))
Core.TEAMS = dofile((arg[2]:gsub("p2p_server%.lua$", "teams_rules.lua")))
Core.PVP = dofile((arg[2]:gsub("p2p_server%.lua$", "pvp_rules.lua")))
math.randomseed(os.time())
local S = Core.new({ log = function(m) io.stderr:write(m .. "\n") end })
-- The bridge stamps Date.now()/1000 on every command. That clock matches the
-- test's timers and is sub-second, so a 1s grace is a real second. Fall back
-- to the server clock (love.timer / clock_gettime, not raw os.time()) if a
-- line arrives without a stamp.
local clock = nil
local builtin = S.now
S.now = function()
	if type(clock) == "number" then return clock end
	return builtin()
end
local conns = {}
local function out(t) io.stdout:write(json.encode(t) .. "\n"); io.stdout:flush() end
for line in io.lines() do
	local f = json.decode(line)
	if f then
		if type(f.now) == "number" then clock = f.now; S.coarse_clock = false end
		if f.t == "open" then
			local id = f.id
			conns[id] = S:connect(function(m) out({ id = id, m = m }) end, function() out({ id = id, close = true }) end)
		elseif f.t == "msg" and conns[f.id] then
			S:receive(conns[f.id], f.m)
		elseif f.t == "tick" then
			S:tick()
		elseif f.t == "close" and conns[f.id] then
			S:disconnect(conns[f.id]); conns[f.id] = nil
		end
	end
end
