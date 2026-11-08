-- Lobby and match text chat. Pure rules, no LOVE and no Steam.
-- The host repeats each accepted line, in order, to the people in that lobby.
-- Empty lines and lines over MAX characters are refused. The displayed name,
-- the watching flag, and the name color come from the host.
--
-- Name color is the player's existing blind color (the ~N on their username,
-- the same color shown beside them in the lobby). The name is drawn as white
-- text on that color. If they have no color, or it is already taken, they get
-- the next free color in that same 1..25 blind palette, stable by player id.
local C = {}

C.MAX = 80
C.KEEP = 30
C.PALETTE = 25

function C.display_name(u)
	local s = tostring(u or ""):match("^([^~]*)") or ""
	s = s:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #s > 24 then s = s:sub(1, 24) end
	if s == "" then return "?" end
	return s
end

--- The blind color they already chose, or nil.
function C.chosen(username)
	local n = tonumber(tostring(username or ""):match("~(%d+)%s*$"))
	if n and n >= 1 and n <= C.PALETTE and n == math.floor(n) then return n end
	return nil
end

--- id -> color index. Unique chosen colors are kept. Everyone else gets a free one.
function C.colors(people)
	local used, out, rest = {}, {}, {}
	for _, p in ipairs(people or {}) do
		if type(p) == "table" and p.id ~= nil then
			local c = C.chosen(p.username)
			if c and not used[c] then
				out[p.id] = c
				used[c] = true
			else
				rest[#rest + 1] = p
			end
		end
	end
	table.sort(rest, function(a, b) return tostring(a.id) < tostring(b.id) end)
	local n = 1
	for _, p in ipairs(rest) do
		local guard = 0
		while used[n] and guard < C.PALETTE do
			n = (n % C.PALETTE) + 1
			guard = guard + 1
		end
		out[p.id] = n
		used[n] = true
		n = (n % C.PALETTE) + 1
	end
	return out
end

--- Chip: colored fill, white name text. The message body is not part of the chip.
function C.chip(col)
	col = tonumber(col) or 1
	if col < 1 or col > C.PALETTE or col ~= math.floor(col) then col = 1 end
	return { fill = col, text = "white" }
end

--- Cleaned text, or nil, "empty" | "long".
function C.accept(text)
	if type(text) ~= "string" then return nil, "empty" end
	local s = text:gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil, "empty" end
	if #s > C.MAX then return nil, "long" end
	return s
end

function C.push(log, msg)
	log = log or {}
	log[#log + 1] = msg
	while #log > C.KEEP do table.remove(log, 1) end
	return log
end

function C.blank()
	return { view = "lobby", lobby = {}, match = {} }
end

function C.reduce(state, msg)
	state = state or C.blank()
	if type(msg) ~= "table" then return state end
	if msg.action == "chatState" then
		if msg.view == "match" or msg.view == "lobby" then state.view = msg.view end
		if msg.clear and msg.view == "match" then state.match = {} end
	elseif msg.action == "chatLog" then
		local lines = {}
		for i, m in ipairs(msg.lines or {}) do
			if type(m) == "table" and (m.scope == "lobby" or m.scope == "match") then lines[i] = m end
		end
		if msg.view == "match" then
			state.view, state.match = "match", lines
		else
			state.view, state.lobby = "lobby", lines
		end
	elseif msg.action == "chat" and (msg.scope == "lobby" or msg.scope == "match") and type(msg.text) == "string" then
		local bucket = msg.scope == "match" and state.match or state.lobby
		for _, old in ipairs(bucket) do if old.id == msg.id then return state end end
		C.push(bucket, { id = msg.id, scope = msg.scope, name = msg.name, watch = msg.watch and true or false,
			text = msg.text, col = tonumber(msg.col) or 1 })
	end
	return state
end

function C.current(state)
	state = state or C.blank()
	if state.view == "match" then return state.match end
	return state.lobby
end

--- Body after the name chip. Watching stays in this normal text. No lobby code.
function C.body(m, watch_word)
	m = m or {}
	local tag = m.watch and ((watch_word or "(watching)") .. " ") or ""
	return tag .. tostring(m.text or "")
end

return C
