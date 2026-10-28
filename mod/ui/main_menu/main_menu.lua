local game_main_menu_ref = Game.main_menu
---@diagnostic disable-next-line: duplicate-set-field
function Game:main_menu(change_context)
	local ret = game_main_menu_ref(self, change_context)

	-- 0.6.8: each extra is guarded, so a game update that changes the menu cannot crash it
	local safe = MP.safe_call or function(_, f, ...) return pcall(f, ...) end
	safe("main menu cards", Add_custom_multiplayer_cards, change_context)
	safe("version display", Add_version_display)
	safe("dev build warning", MP.UI.show_dev_build_warning)
	if MP.UPDATER then safe("updater", MP.UPDATER.on_main_menu) end
	if MP.PATCH_NOTES then safe("patch notes button", MP.PATCH_NOTES.add_menu_button) end -- the pop-up waits in PN.tick

	return ret
end

-- Modify play button to take you to mode select first
local create_UIBox_main_menu_buttonsRef = create_UIBox_main_menu_buttons
---@diagnostic disable-next-line: lowercase-global
function create_UIBox_main_menu_buttons()
	local menu = create_UIBox_main_menu_buttonsRef()
	-- 0.6.8: if a Balatro update moved the play button, keep the vanilla menu and turn multiplayer off
	local ok, err = pcall(function() menu.nodes[1].nodes[1].nodes[1].nodes[1].config.button = "play_options" end)
	if not ok and MP.COMPAT_GUARD and MP.COMPAT_GUARD.hook_failed then
		MP.COMPAT_GUARD.hook_failed("play button", err, true)
	end
	return menu
end

G.FUNCS.wipe_off = function()
	G.E_MANAGER:add_event(Event({
		no_delete = true,
		func = function()
			delay(0.3)
			if not G.screenwipe then return true end
			G.screenwipe.children.particles.max = 0
			G.E_MANAGER:add_event(Event({
				trigger = "ease",
				no_delete = true,
				blockable = false,
				blocking = false,
				timer = "REAL",
				ref_table = G.screenwipe.colours.black,
				ref_value = 4,
				ease_to = 0,
				delay = 0.3,
				func = function(t)
					return t
				end,
			}))
			G.E_MANAGER:add_event(Event({
				trigger = "ease",
				no_delete = true,
				blockable = false,
				blocking = false,
				timer = "REAL",
				ref_table = G.screenwipe.colours.white,
				ref_value = 4,
				ease_to = 0,
				delay = 0.3,
				func = function(t)
					return t
				end,
			}))
			return true
		end,
	}))
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = 0.55,
		no_delete = true,
		blocking = false,
		timer = "REAL",
		func = function()
			if not G.screenwipe then return true end
			if G.screenwipecard then G.screenwipecard:start_dissolve({ G.C.BLACK, G.C.ORANGE, G.C.GOLD, G.C.RED }) end
			if G.screenwipe:get_UIE_by_ID("text") then
				for k, v in ipairs(G.screenwipe:get_UIE_by_ID("text").children) do
					v.children[1].config.object:pop_out(4)
				end
			end
			return true
		end,
	}))
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = 1.1,
		no_delete = true,
		blocking = false,
		timer = "REAL",
		func = function()
			if not G.screenwipe then return true end
			G.screenwipe.children.particles:remove()
			G.screenwipe:remove()
			G.screenwipe.children.particles = nil
			G.screenwipe = nil
			G.screenwipecard = nil
			return true
		end,
	}))
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = 1.2,
		no_delete = true,
		blocking = true,
		timer = "REAL",
		func = function()
			return true
		end,
	}))
end

function MP.UI.update_player_usernames()
	if MP.LOBBY.code then
		if G.MAIN_MENU_UI then G.MAIN_MENU_UI:remove() end
		set_main_menu_UI()
	end
end
