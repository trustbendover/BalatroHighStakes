-- Runs Steamodded's real preflight loader (loadMods) on a Mods folder, prints can_load / load issues per mod,
-- and (with a 3rd arg = path of our mod/) the clash list of the compat guard. Box/CI helper, needs luajit + a Steamodded checkout.
-- usage: luajit tools/smods_loader_check.lua <smods_dir> <mods_dir> [mod_dir]
local SM, MODS = arg[1], arg[2]
package.path = SM.."/libs/json/?.lua;"..package.path
json = require("json"); JSON = json
local function sh(c) local p=io.popen(c); local s=p:read("*a"); p:close(); return s end
local function isdir(p) return sh('[ -d "'..p..'" ] && echo d || ([ -f "'..p..'" ] && echo f)'):match("%a") end
NFS = {
 getInfo=function(p) local t=isdir(p); if t=="d" then return {type="directory"} elseif t=="f" then return {type="file", size=1} end end,
 getDirectoryItems=function(p) local t={} for l in sh('ls -A "'..p..'" 2>/dev/null'):gmatch("[^\n]+") do t[#t+1]=l end return t end,
 read=function(p) local f=io.open(p,"rb"); if not f then return nil end local s=f:read("*a"); f:close(); return s end,
 lines=function(p) local f=io.open(p); if not f then return function() end end return f:lines() end,
 write=function() return true end, append=function() return true end, mount=function() return true end, smodsAddRedirect=function() end,
}
love={filesystem={read=function(p) if p=="version.jkr" then return "1.0.1o-FULL\n" end end, getInfo=function() end, getDirectoryItems=function() return {} end}}
function sendDebugMessage() end function sendInfoMessage() end function sendWarnMessage(m) end function sendErrorMessage(m) print("ERR",m) end function sendTraceMessage() end
function boot_print_stage() end
package.preload["lovely"]=function() return {version="0.10.0", mod_dir=MODS} end
package.preload["SMODS.preflight.sharedUtil"]=function() return dofile(SM.."/src/preflight/sharedUtil.lua") end
local vs = dofile(SM.."/version.lua")
SMODS = {id="Steamodded", version=vs, can_load=true, meta_mod=true, NFS=NFS, MODS_DIR=MODS, path=SM.."/", compat_0_9_8={}}
dofile(SM.."/src/preflight/loader.lua")
local ok, e = pcall(loadMods, MODS)
if not ok then print("loadMods error:", e) end
local ids={} for k in pairs(SMODS.Mods) do ids[#ids+1]=k end table.sort(ids)
for _,k in ipairs(ids) do local m=SMODS.Mods[k]; if not m.meta_mod then
 local li=m.load_issues or {}
 local function j(t) return t and table.concat(t,",") or "" end
 print(string.format("%-18s can_load=%-5s prefix=%-8s deps=[%s] conflicts=[%s] prefix_conflicts=[%s] path=%s", k, tostring(m.can_load), tostring(m.prefix), j(li.dependencies), j(li.conflicts), j(li.prefix_conflicts), tostring(m.path))) end end
if arg[3] then
 MP = { path = arg[3], LOAD_ERRORS = {} }; G = { SETTINGS = { language = "en-us" }, C = {}, UIT = {}, FUNCS = {} }
 dofile(arg[3] .. "/lib/compat_guard.lua")
 for _, c in ipairs(MP.COMPAT_GUARD.find_clashes(SMODS.Mods, SMODS.Mods.Multiplayer)) do print("CLASH", c.id, c.folder, "loaded=" .. tostring(c.loaded)) end
end
