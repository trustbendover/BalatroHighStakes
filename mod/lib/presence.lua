-- Per-player connection status. The host already knows these states (connected socket,
-- seat held during the rejoin window, socket back but the run not restored yet, watching,
-- eliminated after the grace). This file only names them. It does not change lives,
-- seats, or who wins. A lobby code is never part of a status.
MP.PRESENCE = MP.PRESENCE or {}
local P = MP.PRESENCE

--- "connected" | "held" | "rejoining" | "watching" | "gone"
function P.kind(f)
	f = f or {}
	if f.rejoining then return "rejoining" end
	if f.spectator then return "watching" end
	if f.held or f.away then
		if f.eliminated or f.gone then return "gone" end
		return "held"
	end
	if f.connected == false then return "gone" end
	return "connected"
end

local TEXT = {
	connected = { "k_pr_connected", "Connected" },
	held = { "k_pr_held", "Waiting to rejoin" },
	rejoining = { "k_pr_rejoining", "Rejoining" },
	watching = { "k_pr_watching", "Watching" },
	gone = { "k_pr_gone", "Gone" },
}

--- English fallback, or the localized word when `loc` returns a real string.
function P.label(kind, loc, secs)
	local row = TEXT[kind] or TEXT.connected
	local s = row[2]
	if loc then
		local ok, got = pcall(loc, row[1])
		if ok and type(got) == "string" and got ~= "" and got ~= "ERROR" and got ~= row[1] then s = got end
	end
	secs = tonumber(secs)
	if kind == "held" and secs and secs >= 0 then
		secs = math.floor(secs)
		s = s .. string.format(" %d:%02d", math.floor(secs / 60), secs % 60)
	end
	return s
end

local function clean(n)
	return (tostring(n or "?"):gsub("~.*$", ""))
end

--- One row per connected player and per held seat, from a lobbyInfo-shaped table.
--- The lobby code is ignored even if the table carries one.
function P.roster(info, loc)
	local out = {}
	for _, pl in ipairs((info and info.players) or {}) do
		if type(pl) == "table" then
			local kind = P.kind({ spectator = pl.spectator, rejoining = pl.rejoining, connected = true })
			out[#out + 1] = { id = pl.id, name = clean(pl.username), kind = kind, label = P.label(kind, loc), team = pl.team }
		end
	end
	for _, a in ipairs((info and info.away) or {}) do
		if type(a) == "table" then
			local kind = P.kind({ held = true, away = true, eliminated = a.eliminated })
			out[#out + 1] = { id = a.id, name = clean(a.username), kind = kind, label = P.label(kind, loc, a.left), team = a.team }
		end
	end
	return out
end

return P
