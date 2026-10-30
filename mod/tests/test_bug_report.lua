-- luajit tests/test_bug_report.lua (run from mod/): bug report sanitizer + GitHub URL builder
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = {}
G = { FUNCS = {} }
local BR = dofile("lib/bug_report.lua")
local raw = table.concat({
	[[C:\Users\jdoe\AppData\Roaming\Balatro\Mods\lovely\log\x.log]],
	"C:/Users/Some One/GrokBot/file.lua",
	"/home/alice/.local/share/love/Balatro",
	"/Users/bob/Library/Application Support/Balatro",
	"steam id 76561198012345678 joined, [U:1:123456]",
	"connect 192.168.1.20:5000",
	"rejoin_token=abc123def, token: zzz999, encryptID=154031384470.61; hostHash: preview=false",
	"Steam lobby Ldev1_24c910_1793389938 published for code HOWBP",
	"(username: Jane~1) (playerId: p1-x)",
	"Kevin wins the match",
}, "\n")
local s = BR.sanitize(raw, { names = { "Kevin" }, codes = { "QWERT" } })
for _, bad in ipairs({ "jdoe", "Some One", "alice", "bob", "76561198012345678", "123456]", "192.168", "abc123def", "zzz999", "154031384470", "HOWBP", "Ldev1_24c910", "Jane", "Kevin" }) do
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
local file, body = BR.render({ title = "T", desc = "at C:\\Users\\jdoe\\x", info = "Mod: x", log = string.rep("l\n", 500) .. "last C:\\Users\\jdoe\\y" }, { names = {} }, "bug_report_1.txt")
ok(not file:find("jdoe") and not body:find("jdoe"), "render sanitizes everything")
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
-- multi-line description box
local st = { text = "", cursor = 0 }
BR.ml_insert(st, "Hello"); BR.ml_key(st, "return"); BR.ml_insert(st, "wörld")
ok(st.text == "Hello\nwörld" and st.cursor == #st.text, "typing + Enter = new line")
BR.ml_key(st, "backspace"); ok(st.text == "Hello\nwörl", "backspace")
BR.ml_key(st, "left"); BR.ml_key(st, "left"); BR.ml_key(st, "backspace"); ok(st.text == "Hello\nwrl" and st.cursor == 7, "backspace removes a whole UTF-8 char (ö)")
BR.ml_key(st, "home"); ok(st.cursor == 6, "Home = start of the line"); BR.ml_key(st, "end"); ok(st.cursor == #st.text, "End = end of the line")
BR.ml_key(st, "home"); BR.ml_key(st, "delete"); ok(st.text == "Hello\nrl", "delete")
love = { system = { getClipboardText = function() return "pasted\r\ntext" end } }
st.cursor = #st.text; BR.ml_key(st, "v", true); ok(st.text == "Hello\nrlpasted\ntext", "Ctrl+V pastes (CRLF -> LF)")
local big = { text = "", cursor = 0 }
BR.ml_insert(big, string.rep("é", 600)); ok(#big.text <= BR.DESC_MAX and #big.text % 2 == 0, "1000-byte cap, never splits a UTF-8 char")
ok(BR.DESC_MAX == 1000, "about 1000 characters")
local rows = BR.ml_lines(string.rep("word ", 40) .. "\nlast", 205, 30, 4, true)
ok(#rows == 4 and rows[4]:find("|", 1, true), "wraps and scrolls to the cursor row")
for _, r in ipairs(BR.ml_lines(string.rep("abc ", 50), 0, 30, 7, false)) do ok(#r <= 30, "row fits " .. #r) break end
ok(not BR.ml_key(st, "a"), "plain letters come via textinput, not keypressed")
-- input fields: placeholder, single-line title, focus
local tl = { text = "", cursor = 0, active = false, max = 60, single = true }
BR.field_refresh(tl, 64, 1, "Type a short title...", true)
ok(tl.ph == "Type a short title..." and tl.rows.r1 == "", "placeholder shown when empty and unfocused")
tl.active = true; BR.field_refresh(tl, 64, 1, "Type a short title...", true)
ok(tl.ph == "" and tl.rows.r1 == "|", "focused+empty: no placeholder, cursor visible")
BR.ml_insert(tl, "a\nb"); ok(tl.text == "a b", "title is single-line")
ok(not BR.ml_key(tl, "return"), "Enter in title is not inserted")
BR.ml_insert(tl, string.rep("x", 100)); ok(#tl.text == 60, "title capped at 60")
BR.field_refresh(tl, 64, 1, "ph", true); ok(tl.ph == "", "no placeholder with text")
ok(BR.TEXT.nl.ph_title == "Typ een korte titel..." and BR.TEXT.en.ph_desc == "Describe what happened..." and BR.TEXT.nl.hint, "EN/NL placeholders")
print("PASS: bug report")
