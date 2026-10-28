-- Balatro High Stakes 0.6.8: host migration messages (Steam P2P). GPL-3.0.
-- The migration itself is networking/host_migration.lua; this only shows what happened.
MP.HOST_MIGRATION = MP.HOST_MIGRATION or {}
local M = MP.HOST_MIGRATION

local function L(key, fallback, vars)
	local ok, s = pcall(localize, vars and { type = "variable", key = key, vars = vars } or key)
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= key then return s end
	if vars then
		for i, v in ipairs(vars) do fallback = fallback:gsub("#" .. i .. "#", tostring(v)) end
	end
	return fallback
end

local function name_of(id, fallback)
	local n = (MP.LOBBY and MP.LOBBY.names_by_id and id and MP.LOBBY.names_by_id[id]) or fallback or "?"
	return (tostring(n):gsub("~.*$", ""))
end

--- Pure: the text for a hostMigrated message (tested in tests/test_host_migration_ui.lua)
function M.migrated_text(p)
	if p.hostId and p.hostId == p.you then return L("k_hm_you_host", "Host left - you are now host") end
	return L("k_hm_new_host", "Host left - #1# is now host", { name_of(p.hostId, p.hostName) })
end

function M.migrating_text(p)
	if p and p.reason == "cut_off" then return L("k_hm_cut_off", "Connection lost - rejoining the lobby...") end
	return L("k_hm_migrating", "Host left - switching to a new host...")
end

function M.failed_text(p)
	if p and p.lost then return L("k_hm_lost", "Lost connection to the Steam host. Back to the menu.") end
	return L("k_hm_failed", "The host left and nobody could take over the lobby. Back to the menu.")
end

function M.show(msg, colour)
	pcall(sendWarnMessage, msg, "MULTIPLAYER")
	pcall(function()
		if G.STAGE == G.STAGES.RUN and G.STATE ~= G.STATES.GAME_OVER and G.E_MANAGER then
			G.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.2, blocking = false, blockable = false,
				func = function()
					attention_text({ text = msg, scale = 0.6, hold = 3, major = G.play or G.ROOM_ATTACH, align = "cm",
						offset = { x = 0, y = -2.6 }, backdrop_colour = colour or G.C.BLUE, silent = false })
					return true
				end }))
		elseif MP.UI and MP.UI.UTILS and MP.UI.UTILS.overlay_message then
			MP.UI.UTILS.overlay_message(msg)
		end
	end)
end

function M.on_migrating(p) M.last = "migrating"; M.show(M.migrating_text(p), G and G.C and G.C.ORANGE) end
function M.on_migrated(p) M.last = "migrated"; M.show(M.migrated_text(p), G and G.C and G.C.GREEN) end
function M.on_failed(p) M.last = "failed"; M.show(M.failed_text(p), G and G.C and G.C.RED) end

return M
