-- luajit tests/test_brand.lua (run from mod/): the repo slug / zip prefix / folder agree everywhere (0.6.8 repo rename)
local function ok(c, m) assert(c, m); print("ok: " .. m) end
local json = dofile("tests/dkjson.lua")
local function read(p) local f = assert(io.open(p, "rb"), p); local s = f:read("*a"); f:close(); return s end
local B = json.decode(read("brand.json"))
ok(B.repo == "trustbendover/BalatroHighStakes" and B.repo_old == "trustbendover/BalatroMultiplayer3P", "brand.json: new repo name + old fallback")
ok(B.asset_prefix == "BalatroMultiplayer3P" and B.folder == "BalatroMultiplayer3P" and B.mod_id == "Multiplayer", "brand.json: zip prefix, folder and mod id unchanged (old updaters)")
ok(not (B.id or B.name or B.main_file or B.prefix), "brand.json is not mistaken for SMODS mod metadata")
local core = read("core.lua")
for _, k in ipairs({ "repo", "repo_old", "asset_prefix", "folder" }) do
	ok(core:find("\n\t" .. k .. ' = "' .. B[k]:gsub("%p", "%%%0") .. '"', 1) ~= nil, "core.lua MP.BRAND." .. k .. " = brand.json")
end
local ps = read("updater/update.ps1")
ok(ps:find("repo = '" .. B.repo .. "'", 1, true) and ps:find("repo_old = '" .. B.repo_old .. "'", 1, true)
	and ps:find("asset_prefix = '" .. B.asset_prefix .. "'", 1, true), "update.ps1 built-in defaults = brand.json")
ok(ps:find("brand.json", 1, true) and ps:find("$FallbackRepo", 1, true), "update.ps1 reads brand.json and has a fallback repo")
ok(read("../installer/install.ps1"):find("$OurModName = '" .. B.folder .. "'", 1, true), "installer folder = brand.json folder")
ok(read("../tools/build_release.py"):find('BRAND["asset_prefix"]', 1, true), "build_release.py takes the zip prefix from brand.json")
-- links point to the new name (GitHub redirects the old one)
for _, p in ipairs({ "../README.md", "CREDITS.md", "FORK_NOTICE.md", "../installer/README.txt", "../installer/LEES_MIJ.txt", "../installer/CREDITS.txt" }) do
	local s = read(p)
	ok(s:find("github.com/" .. B.repo, 1, true) and not s:find("github.com/" .. B.repo_old, 1, true), p .. ": GitHub links use the new repo name")
end
print("PASS test_brand")
