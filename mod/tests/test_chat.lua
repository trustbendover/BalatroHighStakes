-- Lobby and match chat. Names are colored text, not chips. run from mod/: luajit tests/test_chat.lua
local function ok(c, m) assert(c, m); print("ok: " .. m) end
MP = {}
local C = dofile("networking/chat_rules.lua")
local Core = dofile("networking/p2p_server.lua")
ok(Core.CHAT and Core.CHAT.accept("hi") == "hi", "the host loads the chat rules")
ok(C.accept("   ") == nil and select(2, C.accept("  ")) == "empty", "empty is refused")
ok(C.accept(string.rep("a", 550)) == string.rep("a", 550), "550 characters are kept")
ok(select(2, C.accept(string.rep("a", 551))) == "long", "over 550 characters is refused")
ok(C.accept("  hello   there ") == "hello there", "a short line is kept, as one line")
ok(not C.body({ text = "hi" }, "(watching)"):find("ABCDE", 1, true), "a line has no lobby code")

local picked = C.colors({ { id = "a", username = "Ann~1" }, { id = "b", username = "Bob~2" } })
ok(picked.a == 1 and picked.b == 2, "chosen blind colors are kept")
local same = C.colors({ { id = "a", username = "Ann~4" }, { id = "b", username = "Bob~4" } })
ok(same.a ~= same.b, "two players who picked the same blind still get different name colors")
local plain = C.colors({ { id = "b", username = "Bob" }, { id = "a", username = "Ann" } })
ok(plain.a ~= plain.b and plain.a >= 1 and plain.b <= 25, "players without a color get distinct palette colors")
ok(C.name_color(picked.a) ~= C.name_color(picked.b) and C.name_color(1) == 1, "name text uses the blind color, with no chip")

local function dict(file)
	local t = dofile(file)
	return t.misc and t.misc.dictionary or {}
end
local en, nl = dict("localization/en-us.lua"), dict("localization/nl.lua")
ok(en.b_chat_send == "Send" and en.k_chat_prompt == "Message" and en.b_chat_close == "Close", "English chat chrome")
ok(nl.b_chat_send == "Stuur" and nl.k_chat_prompt == "Bericht" and nl.k_chat_watching == "(kijkt mee)", "Dutch chat chrome")
local core = io.open("core.lua"):read("*a")
ok(core:find('Core.CHAT = MP.load_mp_file("networking/chat_rules.lua")', 1, true), "Steamodded loads the chat rules onto the host")
local ui = io.open("lib/chat.lua"):read("*a")
ok(ui:find("function CH.pin()", 1, true) and ui:find("right - w - 0.15", 1, true) and ui:find("function CH.log_width()", 1, true)
	and ui:find("if love and not CH._text", 1, true) and ui:find("if love and not CH._wheel", 1, true)
	and ui:find("function CH.draw_front()", 1, true) and ui:find("love.draw", 1, true)
	and ui:find("if not CH._painting then return end", 1, true) and ui:find("CH._painting = true", 1, true)
	and ui:find("function CH.drop_box", 1, true) and ui:find("function CH.wrap_message", 1, true)
	and ui:find("CH.VIEW_LINES = 6", 1, true) and ui:find('id = "mp_chat_scroll"', 1, true)
	and ui:find("love.wheelmoved", 1, true) and ui:find("love.textinput", 1, true)
	and ui:find("love.graphics.getWidth", 1, true) and ui:find("G.TILE_W", 1, true)
	and ui:find("G.WINDOWTRANS", 1, true) and ui:find('get_UIE_by_ID("mp_chat_open")', 1, true)
	and ui:find("G.ROOM.T.x", 1, true) and ui:find("get_cursor_collision", 1, true)
	and ui:find("name_colour", 1, true) and not ui:find("chip_fill", 1, true) and not ui:find("r = 0.2", 1, true)
	and ui:find("CH.LOBBY_W = 5.6", 1, true) and ui:find("CH.MATCH_W = 5.4", 1, true)
	and ui:find("minh = 0.48", 1, true) and ui:find("minw = 1.3", 1, true)
	and ui:find("minw = 1.8, minh = 0.42", 1, true)
	and ui:find("panel_nodes(wide, 0.32, 3.6, false)", 1, true)
	and not ui:find("maxw = 3.2", 1, true) and not ui:find("mp_chat_drag", 1, true) and ui:find("lobby_row", 1, true),
	"match chat is a fixed top-right log with a scrollbar, and the field stays a fixed width")

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
ok(C.name_color(host_line.col) ~= C.name_color(guest_line.col), "those names use different colors")
ok(bob.lives == lives, "chat does not change lives")
local before = ann.count("chat")
S:receive(bob, { action = "chat", text = "   " })
S:receive(bob, { action = "chat", text = string.rep("b", 551) })
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

local CH = dofile("lib/chat.lua")
G = {
	ROOM = { T = { x = 1.47, y = 0.7, w = 20, h = 11.5 } },
	TILESCALE = 1, TILESIZE = 1, TILE_W = 20, TILE_H = 11.5,
	ROOM_PADDING_W = 1, ROOM_PADDING_H = 0.7,
	WINDOWTRANS = { w = 22.94, h = 12.9 },
	DRAW_HASH_BUFF = 2,
	CURSOR = { T = { x = 1, y = 1 } },
	FUNCS = {},
}
love = {
	graphics = { getWidth = function() return 22.94 end, getHeight = function() return 12.9 end },
	mouse = { isDown = function() return false end },
	timer = { getTime = function() return 10 end },
	draw = function() end,
}
local left, top, right = CH.screen_span()
ok(left == 0 and top == 0, "the draw span starts at the window corner")
ok(math.abs(right - 22.94) < 1e-6, "the right edge is the window width in tiles")
CH.box = { T = { x = 0, y = 0, w = 5.4, h = 3 }, VT = {}, states = { visible = true }, REMOVED = false }
CH.pin()
ok(math.abs(CH.box.T.x - (22.94 - 5.4 - 0.15)) < 1e-6, "the panel is pinned to the window's top-right")
ok(math.abs(CH.box.T.y - 0.15) < 1e-6, "the panel starts just under the top of the window")
local wrapped = CH.wrap_message("Ann", string.rep("word ", 20), 1, 12)
ok(#wrapped > 1 and wrapped[1].name == "Ann:" and wrapped[2].name == "", "a long line wraps under the coloured name")
ok(CH.scroll_max(10) == 4, "six visible lines leave four lines to scroll")
ok(CH.thumb_top(0, 10) > CH.thumb_top(4, 10), "scroll 0 puts the thumb at the newest end")
CH.draft = { text = "", caret = 0 }
CH.insert_text(string.rep("q", 600))
ok(#CH.draft.text == 550, "the field stops at 550 characters")
CH.focused = true
CH.on_key("backspace")
ok(#CH.draft.text == 549, "backspace edits the fixed-width field")
CH.draft = { text = "hello", caret = 0 }
ok(CH.field_slice():sub(1, 1) == "|", "a caret at zero sits in front of the first letter")
CH.on_key("end")
ok(CH.draft.caret == 5 and CH.field_slice():find("hello|", 1, true), "end moves the caret to the last letter")
CH.on_key("home")
ok(CH.draft.caret == 0, "home moves the caret to the start")
love.textinput = nil
love.wheelmoved = nil
Controller = { get_cursor_collision = function(self) self.collision_list = {} end }
CH.registered = nil
CH._cursor = nil
CH._draw = true
CH._text = nil
CH._keys = true
CH._wheel = nil
CH.register()
ok(type(love.textinput) == "function" and type(love.wheelmoved) == "function", "typing and the wheel hook install when Balatro left them empty")
CH.open = true
MP.LOBBY = MP.LOBBY or {}
MP.LOBBY.code = "ROOM"
CH.focused = true
CH._was_down = false
CH._pending = nil
love.mouse.isDown = function() return true end
CH.tick_focus()
ok(CH.focused == false, "a click outside the field releases the keyboard")
CH.box.collides_with_point = function(_, p) return p.x > 22.5 and p.x < 23.5 end
CH.box.get_UIE_by_ID = function(_, id)
	if id == "mp_chat_open" then
		return { id = id, states = { collide = {} }, collides_with_point = function(_, p) return p.x > 22.5 and p.x < 23.5 end }
	end
end
local ctrl = {}
Controller.get_cursor_collision(ctrl, { x = 23 + 1.47, y = 2 })
local found = false
for _, node in ipairs(ctrl.collision_list or {}) do
	if node.id == "mp_chat_open" then found = true end
end
ok(found, "a click in the widescreen margin still hits the chat button")

print("PASS: chat")
