-- Lobby and match chat, including name chips. run from mod/: luajit tests/test_chat.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = {}
local C = dofile("networking/chat_rules.lua")
local Core = dofile("networking/p2p_server.lua")
ok(Core.CHAT and Core.CHAT.accept("hi") == "hi", "the host loads the chat rules")
ok(C.accept("   ") == nil and select(2, C.accept("  ")) == "empty", "empty is refused")
ok(select(2, C.accept(string.rep("a", 81))) == "long", "over 80 characters is refused")
ok(C.accept("  hello   there ") == "hello there", "a short line is kept, as one line")
ok(not C.body({ text = "hi" }, "(watching)"):find("ABCDE", 1, true), "a line has no lobby code")

local picked = C.colors({ { id = "a", username = "Ann~1" }, { id = "b", username = "Bob~2" } })
ok(picked.a == 1 and picked.b == 2, "chosen blind colors are kept")
local same = C.colors({ { id = "a", username = "Ann~4" }, { id = "b", username = "Bob~4" } })
ok(same.a ~= same.b, "two players who picked the same blind still get different chips")
local plain = C.colors({ { id = "b", username = "Bob" }, { id = "a", username = "Ann" } })
ok(plain.a ~= plain.b and plain.a >= 1 and plain.b <= 25, "players without a color get distinct palette colors")
ok(C.chip(picked.a).text == "white" and C.chip(picked.b).text == "white" and C.chip(1).fill ~= C.chip(2).fill,
	"the name is white on a colored chip, and different colors stay different")

local function dict(file)
	local t = dofile(file)
	return t.misc and t.misc.dictionary or {}
end
local en, nl = dict("localization/en-us.lua"), dict("localization/nl.lua")
ok(en.b_chat_send == "Send" and en.k_chat_prompt == "Message" and en.b_chat_close == "Close", "English chat chrome")
ok(nl.b_chat_send == "Stuur" and nl.k_chat_prompt == "Bericht" and nl.k_chat_watching == "(kijkt mee)", "Dutch chat chrome")
local ui = io.open("lib/chat.lua"):read("*a")
ok(ui:find('align = "bl"', 1, true) and ui:find("TEXT_LIGHT", 1, true) and ui:find("chip_fill", 1, true),
	"the panel is bottom-left and the name chip uses light text")

local function client(S, name)
	local msgs = {}
	local c = S:connect(function(t) msgs[#msgs + 1] = t end)
	c.box = msgs
	function c.last(a, pred) for i = #msgs, 1, -1 do if msgs[i].action == a and (not pred or pred(msgs[i])) then return msgs[i] end end end
	function c.count(a) local n = 0 for _, m in ipairs(msgs) do if m.action == a then n = n + 1 end end return n end
	S:receive(c, { action = "version", version = Core.SERVER_VERSION })
	S:receive(c, { action = "username", username = name })
	return c
end
local function view(box)
	local state = C.blank()
	for _, m in ipairs(box) do
		if m.action == "chat" or m.action == "chatState" or m.action == "chatLog" then state = C.reduce(state, m) end
	end
	return state
end
local function texts(box)
	local out = {}
	for _, m in ipairs(C.current(view(box))) do out[#out + 1] = m.text end
	return table.concat(out, "|")
end

local S = Core.new({ now = function() return 1000 end, log = function() end })
local ann, bob = client(S, "Ann~1"), client(S, "Bob~2")
S:receive(ann, { action = "createLobby", gameMode = "attrition" })
local joined = ann.last("joinedLobby")
S:receive(bob, { action = "joinLobby", code = joined.code })
local lives = bob.lives
S:receive(ann, { action = "chat", text = "hello from the host" })
S:receive(bob, { action = "chat", text = "hello from the guest" })
ok(texts(ann.box) == "hello from the host|hello from the guest", "host sees lobby chat in order")
ok(texts(bob.box) == "hello from the host|hello from the guest", "guest sees the same lobby chat")
local host_line = ann.last("chat", function(m) return m.text == "hello from the host" end)
local guest_line = ann.last("chat", function(m) return m.text == "hello from the guest" end)
ok(host_line.col == 1 and guest_line.col == 2 and host_line.name == "Ann" and guest_line.name == "Bob",
	"the host sends each player's own blind color and plain name")
ok(C.chip(host_line.col).text == "white" and C.chip(guest_line.col).fill ~= C.chip(host_line.col).fill, "those chips contrast")
ok(bob.lives == lives, "chat does not change lives")
local before = ann.count("chat")
S:receive(bob, { action = "chat", text = "   " })
S:receive(bob, { action = "chat", text = string.rep("b", 81) })
ok(bob.last("chatReject").reason == "long", "too long is rejected")
ok(ann.count("chat") == before, "empty and too-long lines are not sent on")
local rejected = 0
for _, m in ipairs(bob.box) do if m.action == "chatReject" then rejected = rejected + 1 end end
ok(rejected == 2, "the sender is told both were rejected")

S:receive(bob, { action = "readyLobby" })
S:receive(ann, { action = "startGame" })
ok(texts(ann.box) == "" and texts(bob.box) == "", "a new match starts with an empty match log")
ok(view(ann.box).lobby[1].text == "hello from the host", "the lobby lines are still stored")
S:receive(ann, { action = "chat", text = "during the match" })
ok(texts(bob.box) == "during the match" and bob.last("chat").scope == "match", "guest sees the match line")

local dee = client(S, "Dee~9")
S:receive(dee, { action = "joinLobby", code = joined.code, spectate = true })
local snap = dee.last("chatLog")
ok(snap and snap.view == "match" and snap.lines[1].text == "during the match", "a watcher receives the match log")
S:receive(dee, { action = "chat", text = "watching this", name = "Ann", col = 1 })
local said = ann.last("chat")
ok(said and said.watch == true and said.name == "Dee" and said.col == 9 and said.text == "watching this",
	"a watcher is labeled watching, under their own name and color")
ok(texts(dee.box):find("during the match", 1, true) and texts(dee.box):find("watching this", 1, true), "the watcher sees the same match lines")

ann.lobby.isInGame = false
S:receive(ann, { action = "rematch" })
ok(texts(ann.box) == "hello from the host|hello from the guest", "after rematch the current log is the lobby chat")
ok(not texts(ann.box):find("during the match", 1, true), "the previous match line is not the current log")
for _, p in ipairs(ann.lobby.players) do if p ~= ann then S:receive(p, { action = "readyLobby" }) end end
S:receive(ann, { action = "startGame" })
ok(texts(ann.box) == "" and texts(bob.box) == "", "the next match does not reuse the previous match log")
S:receive(bob, { action = "chat", text = "only this game" })
ok(texts(ann.box) == "only this game" and texts(bob.box) == "only this game", "host and guest see only the new match")

print("PASS: chat")
