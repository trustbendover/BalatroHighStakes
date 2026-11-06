-- Public lobby list. Native Balatro UI (same overlay as the other multiplayer menus).
-- Rows come from MP.STEAM_P2P.browse. Names and modes are already validated there.

MP.BROWSER = MP.BROWSER or {
	phase = "idle",
	rows = {},
	page = 1,
	note_key = nil,
}

local function loc(key, fallback)
	local s = localize(key)
	if type(s) == "string" and s ~= "" and s ~= "ERROR" and s ~= key then return s end
	return fallback
end

local function fill(key, a, b, fallback)
	local s = loc(key, fallback)
	return (s:gsub("#1#", tostring(a)):gsub("#2#", tostring(b)))
end

local function detail_line(row)
	local bits = {}
	if row.fmt == "2" or row.fmt == "3" or row.fmt == "4" then bits[#bits + 1] = row.fmt .. "v" .. row.fmt end
	if row.boss == true then bits[#bits + 1] = loc("k_browser_boss_on", "Boss effects on")
	elseif row.boss == false then bits[#bits + 1] = loc("k_browser_boss_off", "Boss effects off")
	else bits[#bits + 1] = loc("k_browser_boss_unknown", "Boss effects unknown") end
	if type(row.lives) == "number" then bits[#bits + 1] = tostring(row.lives) .. " " .. loc("k_browser_lives", "lives") end
	if type(row.pvp_at) == "number" then bits[#bits + 1] = loc("k_browser_pvp_ante", "PvP ante") .. " " .. tostring(row.pvp_at) end
	if type(row.show_at) == "number" then bits[#bits + 1] = loc("k_browser_show_ante", "Showdown ante") .. " " .. tostring(row.show_at) end
	if row.timer == true then bits[#bits + 1] = loc("k_browser_timer_on", "Timer on")
	elseif row.timer == false then bits[#bits + 1] = loc("k_browser_timer_off", "Timer off") end
	return table.concat(bits, " | ")
end

local function clip(text, scale, maxw)
	text = tostring(text or "")
	if MP.FIT and MP.FIT.ellipsize then return MP.FIT.ellipsize(text, scale, maxw) end
	if #text > 22 then return text:sub(1, 20) .. ".." end
	return text
end

local NOTE_KEYS = {
	private = { "k_browser_stale", "That lobby is no longer public." },
	full = { "k_browser_full", "Full" },
	playing = { "k_browser_playing_no_watch", "In progress, no spectators" },
	unconfirmed = { "k_browser_unconfirmed", "Could not confirm this lobby is still public." },
	closed = { "k_browser_closed", "That lobby cannot be joined from the list." },
	unavailable = { "k_browser_no_steam", "The lobby list needs Steam." },
	failed = { "k_browser_failed", "The lobby list could not be loaded." },
	busy = { "k_browser_busy", "Already joining a lobby." },
}

function MP.BROWSER.note_text()
	local n = NOTE_KEYS[MP.BROWSER.note_key or ""]
	if not n then return nil end
	return loc(n[1], n[2])
end

function MP.BROWSER.mode_text(row)
	return loc(row.mode_key or "", row.mode or "")
end

function MP.BROWSER.state_text(row)
	if row.state == "play" then return loc("k_browser_playing", "In progress") end
	return loc("k_browser_waiting", "Waiting")
end

function MP.BROWSER.press(id, how)
	if not (MP.STEAM_P2P and MP.STEAM_P2P.join_browser) then
		MP.BROWSER.note_key = "unavailable"
		return MP.BROWSER.redraw()
	end
	MP.STEAM_P2P.join_browser(id, how, function(ok, reason)
		if ok then return end
		MP.BROWSER.note_key = reason or "closed"
		if reason == "private" or reason == "closed" or reason == "unconfirmed" then
			local keep = {}
			for _, row in ipairs(MP.BROWSER.rows or {}) do
				if row.id ~= id then keep[#keep + 1] = row end
			end
			MP.BROWSER.rows = keep
			if #keep == 0 then MP.BROWSER.phase = "empty" end
		end
		MP.BROWSER.redraw()
	end)
end

function MP.BROWSER.redraw()
	if G and G.FUNCS and G.FUNCS.overlay_menu and G.UIDEF and G.UIDEF.mp_lobby_browser then
		G.FUNCS.overlay_menu({ definition = G.UIDEF.mp_lobby_browser() })
	end
end

function MP.BROWSER.refresh()
	if MP.BROWSER.phase == "loading" then return end
	MP.BROWSER.phase = "loading"
	MP.BROWSER.redraw()
	if not (MP.STEAM_P2P and MP.STEAM_P2P.browse) then
		MP.BROWSER.phase = "error"
		MP.BROWSER.note_key = "unavailable"
		MP.BROWSER.rows = {}
		return MP.BROWSER.redraw()
	end
	MP.STEAM_P2P.browse(function(err, rows)
		if err == "busy" then return end
		MP.BROWSER.rows = type(rows) == "table" and rows or {}
		MP.BROWSER.note_key = nil
		if err then
			MP.BROWSER.phase = "error"
			MP.BROWSER.note_key = err == "unavailable" and "unavailable" or "failed"
			MP.BROWSER.rows = {}
		elseif #MP.BROWSER.rows == 0 then
			MP.BROWSER.phase = "empty"
		else
			MP.BROWSER.phase = "ready"
		end
		MP.BROWSER.redraw()
	end)
end

function MP.BROWSER.open()
	MP.BROWSER.page = 1
	MP.BROWSER.note_key = nil
	MP.BROWSER.phase = "idle"
	MP.BROWSER.rows = {}
	MP.BROWSER.refresh()
end

function G.FUNCS.mp_open_browser(e)
	G.SETTINGS.paused = true
	MP.BROWSER.open()
end

function G.FUNCS.mp_browser_refresh(e)
	MP.BROWSER.phase = "idle"
	MP.BROWSER.refresh()
end

function G.FUNCS.mp_browser_prev(e)
	MP.BROWSER.page = math.max(1, (MP.BROWSER.page or 1) - 1)
	MP.BROWSER.redraw()
end

function G.FUNCS.mp_browser_next(e)
	MP.BROWSER.page = (MP.BROWSER.page or 1) + 1
	MP.BROWSER.redraw()
end

local function text_col(text, scale, maxw, minw, colour)
	return {
		n = G.UIT.C,
		config = { align = "cm", minw = minw, padding = 0.02 },
		nodes = {
			{
				n = G.UIT.T,
				config = {
					text = clip(text, scale, maxw),
					scale = scale,
					colour = colour or G.C.UI.TEXT_LIGHT,
					maxw = maxw,
				},
			},
		},
	}
end

function G.UIDEF.mp_lobby_browser()
	local B = MP.BROWSER
	local Browser = MP.STEAM_P2P and MP.STEAM_P2P.browser
	local page_size = (Browser and Browser.PAGE) or 6
	local body = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.05 },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = loc("k_browser_title", "Public lobbies"),
						scale = 0.5,
						colour = G.C.UI.TEXT_LIGHT,
						maxw = 10,
					},
				},
			},
		},
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.04 },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = loc("k_browser_hint", "Private lobbies stay hidden. The lobby code and invites still work."),
						scale = 0.28,
						colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT,
						maxw = 10,
					},
				},
			},
		},
	}

	local status = B.note_text()
	if B.phase == "loading" then status = loc("k_browser_loading", "Looking for public lobbies...") end
	if B.phase == "empty" then status = status or loc("k_browser_empty", "No public lobbies right now.") end
	if B.phase == "error" and not status then status = loc("k_browser_failed", "The lobby list could not be loaded.") end
	if status then
		body[#body + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.08 },
			nodes = {
				{
					n = G.UIT.T,
					config = { text = clip(status, 0.35, 10), scale = 0.35, colour = G.C.UI.TEXT_LIGHT, maxw = 10 },
				},
			},
		}
	end

		local shown, page, pages = {}, B.page or 1, 1
	if B.phase == "ready" then
		if Browser and Browser.slice then
			shown, page, pages = Browser.slice(B.rows, B.page, page_size)
		else
			shown = B.rows
		end
		B.page = page
		body[#body + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.02 },
			nodes = {
				text_col(loc("k_browser_host", "Host"), 0.28, 3.0, 3.0, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT),
				text_col(loc("k_browser_mode", "Mode"), 0.28, 2.4, 2.4, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT),
				text_col(loc("k_browser_count", "Players"), 0.28, 1.3, 1.3, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT),
				text_col(loc("k_browser_state", "Status"), 0.28, 2.2, 2.2, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT),
				text_col("", 0.28, 1.8, 1.8),
			},
		}
		for _, row in ipairs(shown) do
			local how, why = nil, row.reason
			if row.action == "join" or row.action == "watch" then how = row.action
			elseif not why then why = "closed" end
			local name = row.name ~= "" and row.name or loc("k_browser_unknown", "Host")
			local action_node
			if how then
				local key = "mp_browser_" .. how .. "_" .. tostring(row.id)
				G.FUNCS[key] = function() MP.BROWSER.press(row.id, how) end
				local label = how == "watch" and loc("b_browser_watch", "Watch") or loc("b_browser_join", "Join")
				action_node = UIBox_button({
					button = key,
					label = { label },
					minw = 1.7,
					minh = 0.45,
					scale = 0.32,
					colour = how == "watch" and G.C.BLUE or G.C.GREEN,
					ref_table = { id = row.id, how = how },
				})
			else
				local reason = (why == "full" and loc("k_browser_full", "Full"))
					or (why == "playing" and loc("k_browser_no_watch", "No watch"))
					or loc("k_browser_closed", "Closed")
				action_node = text_col(reason, 0.28, 1.8, 1.8, G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT)
			end
			body[#body + 1] = {
				n = G.UIT.R,
				config = { align = "cm", padding = 0.02 },
				nodes = {
					text_col(name, 0.32, 3.0, 3.0),
					text_col(MP.BROWSER.mode_text(row), 0.32, 2.4, 2.4),
					text_col(tostring(row.players) .. "/" .. tostring(row.max), 0.32, 1.3, 1.3),
					text_col(MP.BROWSER.state_text(row), 0.32, 2.2, 2.2),
					action_node,
				},
			}
			body[#body + 1] = {
				n = G.UIT.R,
				config = { align = "cm", padding = 0.01 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = clip(detail_line(row), 0.26, 10),
							scale = 0.26,
							colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT,
							maxw = 10,
						},
					},
				},
			}
		end
		if pages > 1 then
			body[#body + 1] = {
				n = G.UIT.R,
				config = { align = "cm", padding = 0.05 },
				nodes = {
					UIBox_button({
						button = "mp_browser_prev",
						label = { loc("b_browser_prev", "Previous") },
						minw = 2.2, minh = 0.45, scale = 0.32, colour = G.C.RED,
					}),
					{
						n = G.UIT.C,
						config = { align = "cm", minw = 2.4, padding = 0.05 },
						nodes = {
							{
								n = G.UIT.T,
								config = {
									text = fill("k_browser_page", page, pages, "Page " .. page .. "/" .. pages),
									scale = 0.32,
									colour = G.C.UI.TEXT_LIGHT,
									maxw = 2.4,
								},
							},
						},
					},
					UIBox_button({
						button = "mp_browser_next",
						label = { loc("b_browser_next", "Next") },
						minw = 2.2, minh = 0.45, scale = 0.32, colour = G.C.RED,
					}),
				},
			}
		end
		if #B.rows >= 48 then
			body[#body + 1] = {
				n = G.UIT.R,
				config = { align = "cm", padding = 0.02 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = loc("k_browser_capped", "Showing the first 48 lobbies."),
							scale = 0.28,
							colour = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT,
							maxw = 10,
						},
					},
				},
			}
		end
	end

	body[#body + 1] = {
		n = G.UIT.R,
		config = { align = "cm", padding = 0.08 },
		nodes = {
			UIBox_button({
				button = "play_options",
				label = { loc("b_browser_back", "Back") },
				minw = 2.4, minh = 0.5, scale = 0.35, colour = G.C.RED,
			}),
			UIBox_button({
				button = "mp_browser_refresh",
				label = { loc("b_browser_refresh", "Refresh") },
				minw = 2.6, minh = 0.5, scale = 0.35, colour = G.C.BLUE,
			}),
		},
	}

	return create_UIBox_generic_options({
		back_func = "play_options",
		contents = {
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0 },
				nodes = body,
			},
		},
	})
end
