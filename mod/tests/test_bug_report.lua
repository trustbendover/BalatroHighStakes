-- luajit tests/test_bug_report.lua (run from mod/): bug report sanitizer + GitHub URL builder
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = {}
G = { FUNCS = {} }
local BR = dofile("lib/bug_report.lua")
local raw = table.concat({
	[[C:\Users\sverr\AppData\Roaming\Balatro\Mods\lovely\log\x.log]],
	"C:/Users/Some One/GrokBot/file.lua",
	"/home/alice/.local/share/love/Balatro",
	"/Users/bob/Library/Application Support/Balatro",
	"steam id 76561198012345678 joined, [U:1:123456]",
	"connect 192.168.1.20:5000",
	"rejoin_token=abc123def, token: zzz999, encryptID=154031384470.61; hostHash: preview=false",
	"Steam lobby Ldev1_24c910_1793389938 published for code HOWBP",
	"(username: Sverre~1) (playerId: p1-x)",
	"Kevin wins the match",
}, "\n")
local s = BR.sanitize(raw, { names = { "Kevin" }, codes = { "QWERT" } })
for _, bad in ipairs({ "sverr", "Some One", "alice", "bob", "76561198012345678", "123456]", "192.168", "abc123def", "zzz999", "154031384470", "HOWBP", "Ldev1_24c910", "Sverre", "Kevin" }) do
	ok(not s:find(bad, 1, true), "removed " .. bad)
end
ok(s:find([[C:\Users\USER\AppData]], 1, true) and s:find("/home/USER/", 1, true), "paths keep their shape")
ok(s:find("Player1 wins", 1, true), "player names become PlayerN")
ok(BR.url_encode("a b&c\n#") == "a+b%26c%0D%0A%23", "url encoding")
local long = string.rep("line of log text with ü and &\n", 800)
local url = BR.build_url("Crash in lobby", long, 6000, "owner/repo")
ok(#url <= 6000, "url under 6000 chars (" .. #url .. ")")
ok(url:find("^https://github.com/owner/repo/issues/new%?labels=bug&title=Crash%+in%+lobby&body="), "prefilled title + body")
ok(url:find("cut", 1, true), "cut note when the body is shortened")
ok(#BR.build_url("t", "short body") < 300, "short body stays whole")
local file, body = BR.render({ title = "T", desc = "at C:\\Users\\sverr\\x", info = "Mod: x", log = string.rep("l\n", 500) .. "last C:\\Users\\sverr\\y" }, { names = {} }, "bug_report_1.txt")
ok(not file:find("sverr") and not body:find("sverr"), "render sanitizes everything")
ok(body:find("bug_report_1.txt", 1, true) and body:find("drag", 1, true), "body tells to drag in the report file")
local _, n = body:gsub("\nl", "")
ok(n <= BR.LOG_LINES_URL, "issue body only has a short log tail")
ok(BR.ISSUE_REPO:match("^trustbendover/"), "single repo constant")
ok(BR.TEXT.nl.button == "Bug melden" and BR.TEXT.en.button == "Report a bug", "EN + NL texts")
G.STAGES = { MAIN_MENU = 1, RUN = 2 }; G.STAGE = 2
ok(not BR.allowed(), "not available during a match")
G.STAGE = 1; ok(BR.allowed(), "available in main menu / lobby")
local src = io.open("lib/bug_report.lua"):read("*a")
ok(not src:find("https.request", 1, true) and not src:find("socket", 1, true), "no automatic network sends")
print("PASS: bug report")
