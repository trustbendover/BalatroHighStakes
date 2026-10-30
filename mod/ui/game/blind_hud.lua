-- All in Jest compat (0.6.8): its "Blind Drawn" joker hides the nemesis' score/hands. AiJ's lovely patches
-- target the old file layout (ui/game.lua, ui/hud.lua) and no longer apply, so the effect lives here.
function MP.UI.aij_blind_drawn()
	return SMODS and SMODS.find_card and next(SMODS.find_card("j_aij_mp_blind_drawn")) ~= nil or false
end

function MP.UI.update_blind_HUD(blind, reset, silent)
    if MP.is_mp_or_ghost() then
        -- Prepare blind name
        local blind_name_string
        if MP.GHOST.is_active() then
            blind_name_string = MP.GHOST.get_blind_name_ui()
        else
            blind_name_string = {
                {
                    ref_table = MP.GAME.enemy,
                    ref_value = "hud_title",
                },
            }
        end
        -- Setup blind name display
        local name_element = G.HUD_blind:get_UIE_by_ID("HUD_blind_name")
        name_element.config.object.config.string =  {
            {
                ref_table = MP.GAME.enemy,
                ref_value = "hud_title",
            },
        }
        name_element.config.object.config.old_maxw = name_element.config.object.config.maxw
        name_element.config.object.config.mp_maxw = true
        if MP.THREEP then MP.THREEP.refresh_hud() end
        name_element.config.object.config.maxw = 4.5
        name_element.config.object.scale = name_element.config.object.config.scale
        name_element.config.object:update_text(true)
        if name_element.config.object.config.maxw then
            name_element.config.object.scale = name_element.config.object.scale * math.min(1, name_element.config.object.config.maxw/name_element.config.object.config.W)
        end
        name_element.config.object:update_text(true)
        name_element.states.visible = false
        -- Setup enemy score text
        G.HUD_blind:get_UIE_by_ID("HUD_blind_count").config.ref_table = MP.GAME.enemy
        G.HUD_blind:get_UIE_by_ID("HUD_blind_count").config.ref_value = "score_text"
        G.HUD_blind:get_UIE_by_ID("HUD_blind_count").config.func = "multiplayer_blind_chip_UI_scale"
        -- Setup labels
        -- Casual balala UI experience right here
        G.HUD_blind:get_UIE_by_ID("HUD_blind").children[2].children[2].children[2].children[1].children[1].config.text =
            localize("k_enemy_score")
        G.HUD_blind:get_UIE_by_ID("HUD_blind").children[2].children[2].children[2].children[3].children[1].config.text =
            localize("k_enemy_hands")
        -- Setup enemy hands
        G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").parent.parent.states.visible = false
        G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").config.object.config.string =
            { { ref_table = MP.GAME.enemy, ref_value = "hands_text" } }
        G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").config.object:update_text()

        G.HUD_blind.alignment.offset.y = 0
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.15,
            blockable = false,
            func = (function()
                local self = G.GAME.blind

                if self.config.blind.key == "bl_mp_nemesis" then
                    -- Setup blind atlas and pos
                    self.children.animatedSprite.atlas = G.ANIMATION_ATLAS["mp_player_blind_col"]
                    local nemesis_blind_col = MP.UTILS.get_nemesis_key()
                    self.children.animatedSprite:set_sprite_pos(G.P_BLINDS[nemesis_blind_col].pos)
                end

                G.HUD_blind:get_UIE_by_ID("HUD_blind_name").states.visible = true
                G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").parent.parent.states.visible = true
                G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").config.object:pop_in(0)
                G.HUD_blind:get_UIE_by_ID("HUD_blind_name").config.object:pop_in(0)
                G.HUD_blind:get_UIE_by_ID("HUD_blind_count"):juice_up()
                self.dissolve = 0
                self.blind_set = true
                G.ROOM.jiggle = G.ROOM.jiggle + 3
                if not reset and not silent then
                    self:juice_up()
                    if blind then play_sound('chips1', math.random()*0.1 + 0.55, 0.42);play_sound('gold_seal', math.random()*0.1 + 1.85, 0.26)--play_sound('cancel')
                    end
                end
                return true
            end)
        }))
    end
end

function MP.UI.reset_blind_HUD()
	if MP.is_mp_or_ghost() then
        local name_element = G.HUD_blind:get_UIE_by_ID("HUD_blind_name")
		name_element.config.object.config.string =
			{ { ref_table = G.GAME.blind, ref_value = "loc_name" } }
        if  name_element.config.object.config.mp_maxw then            
            name_element.config.object.config.maxw = name_element.config.object.config.old_maxw
            name_element.config.object.config.old_maxw = nil
            name_element.config.object.scale = name_element.config.object.config.scale
            name_element.config.object:update_text(true)
            if name_element.config.object.config.maxw then
                name_element.config.object.scale = name_element.config.object.scale * math.min(1, name_element.config.object.config.maxw/name_element.config.object.config.W)
            end
            name_element.config.object:update_text(true)
        end
		G.HUD_blind:get_UIE_by_ID("HUD_blind_count").config.ref_table = G.GAME.blind
		G.HUD_blind:get_UIE_by_ID("HUD_blind_count").config.ref_value = "chip_text"
		G.HUD_blind:get_UIE_by_ID("HUD_blind").children[2].children[2].children[2].children[1].children[1].config.text =
			localize("ph_blind_score_at_least")
		G.HUD_blind:get_UIE_by_ID("HUD_blind").children[2].children[2].children[2].children[3].children[1].config.text =
			localize("ph_blind_reward")
		G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").config.object.config.string =
			{ { ref_table = G.GAME.current_round, ref_value = "dollars_to_be_earned" } }
		G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned").config.object:update_text()
	end
end

-- Contains function overrides (monkey-patches) for blind-related functionality
-- Overrides functions like get_blind_main_colour, Blind:change_colour, Blind:set_blind, etc.

local get_blind_main_colourref = get_blind_main_colour
function get_blind_main_colour(type) -- handles ui colour stuff
	local nemesis = G.GAME.round_resets.blind_choices[type] == "bl_mp_nemesis" or type == "bl_mp_nemesis"
	if nemesis then type = MP.UTILS.get_nemesis_key() end
	return get_blind_main_colourref(type)
end

local blind_change_colourref = Blind.change_colour
function Blind:change_colour(blind_col) -- ensures that small/big blinds have proper colouration
	local small = false
	if self.config.blind.key == "bl_mp_nemesis" then
		local blind_key = MP.UTILS.get_nemesis_key()
		if blind_key == "bl_small" or blind_key == "bl_big" then small = true end
	end
	local boss = self.boss
	if small then self.boss = false end
	blind_change_colourref(self, blind_col)
	self.boss = boss
end

local blind_set_blindref = Blind.set_blind
function Blind:set_blind(blind, reset, silent) -- hacking in proper spirals, far from good but whatever
	blind_set_blindref(self, blind, reset, silent)
	if (blind and blind.key == "bl_mp_nemesis") or (self and self.name and self.name == "bl_mp_nemesis") then -- this shouldn't break and this fix shouldn't work
		local boss = false
		local showdown = false
		local blind_key = MP.UTILS.get_nemesis_key()
		if G.P_BLINDS[blind_key].boss then
			boss = true
			if G.P_BLINDS[blind_key].boss.showdown then
				showdown = true
			end
		end
		G.ARGS.spin.real = (G.SETTINGS.reduced_motion and 0 or 1) * (boss and (showdown and 0.5 or 0.25) or 0)
	end
end

local ease_background_colour_blindref = ease_background_colour_blind
function ease_background_colour_blind(state, blind_override) -- handles background
	local blindname = (
		(blind_override or (G.GAME.blind and G.GAME.blind.name ~= "" and G.GAME.blind.name)) or "Small Blind"
	)
	local blindname = (blindname == "" and "Small Blind" or blindname)
	if blindname == "bl_mp_nemesis" then
		blind_override = MP.UTILS.get_nemesis_key()
		for k, v in pairs(G.P_BLINDS) do
			if blind_override == k then blind_override = v.name end
		end
	end
	return ease_background_colour_blindref(state, blind_override)
end

local add_round_eval_rowref = add_round_eval_row
function add_round_eval_row(config) -- if i could post a skull emoji i would, wtf is this (cashout screen)
	if config.name == "blind1" and G.GAME.blind.config.blind.key == "bl_mp_nemesis" then
		G.GAME.blind.chip_text = MP.INSANE_INT.to_string(MP.GAME.enemy.score)

		G.P_BLINDS["bl_mp_nemesis"].atlas = "mp_player_blind_col"
		G.GAME.blind.pos = G.P_BLINDS[MP.UTILS.get_nemesis_key()].pos -- this one is getting reset so no need to bother
		add_round_eval_rowref(config)
		G.E_MANAGER:add_event(Event({
			trigger = "before",
			delay = 0.0,
			func = function()
				G.P_BLINDS["bl_mp_nemesis"].atlas = "mp_player_blind_chip" -- lmao
				return true
			end,
		}))
	else
		add_round_eval_rowref(config)
	end
end

local blind_defeat_ref = Blind.defeat
function Blind:defeat(silent)
	blind_defeat_ref(self, silent)
	if MP.is_mp_or_ghost() and MP.UI.reset_blind_HUD then MP.UI.reset_blind_HUD() end
end

local blind_disable_ref = Blind.disable
function Blind:disable()
	if MP.is_pvp_boss() and not (G.GAME.blind and G.GAME.blind.name == "Verdant Leaf") then -- hackfix to make verdant work properly
		return
	end
	blind_disable_ref(self)
end

G.FUNCS.multiplayer_blind_chip_UI_scale = function(e)
	if MP.THREEP then MP.THREEP.refresh_hud() end
	MP.GAME.enemy.hands_text = tostring(MP.GAME.enemy.hands)
	if MP.UI.aij_blind_drawn() then
		MP.GAME.enemy.hands_text, MP.GAME.enemy.score_text = "?", "???"
		e.config.scale = 0.7
		return
	end

	-- Hide the opponent's score until we have played a hand this PvP blind, so
	-- a player can't watch the enemy score before committing their own hand.
	-- (The server also withholds the score, this is the matching display.)
	-- Gated by the hide_score_until_played lobby option (on by default only on
	-- standard-layer rulesets; host-toggleable in non-forcing lobbies).
	if
		MP.LOBBY.config.hide_score_until_played
		and MP.is_pvp_boss()
		and G.GAME.current_round
		and G.GAME.current_round.hands_played == 0
	then
		MP.GAME.enemy.score_text = "???"
		return
	end
	local new_score_text = MP.INSANE_INT.to_string(MP.GAME.enemy.score)
	if G.GAME.blind and MP.GAME.enemy.score and MP.GAME.enemy.score_text ~= new_score_text then
		if not MP.INSANE_INT.greater_than(MP.GAME.enemy.score, MP.INSANE_INT.create(0, G.E_SWITCH_POINT, 0)) then
			e.config.scale = scale_number(MP.GAME.enemy.score.coeffiocient, 0.7, 100000)
		end
		MP.GAME.enemy.score_text = new_score_text
	end
end

function MP.UI.juice_up_pvp_hud()
	if MP.is_pvp_boss() and not MP.UI.aij_blind_drawn() then
		G.HUD_blind:get_UIE_by_ID("HUD_blind_count"):juice_up()
		G.HUD_blind:get_UIE_by_ID("dollars_to_be_earned"):juice_up()
	end
end

-- The "prevent losing" path in Game:update_new_round sets G.GAME.blind.chips = -1 as a
-- sentinel. SMODS' G.FUNCS.blind_chip_UI_scale formats blind.chips into chip_text every
-- frame, so the HUD showed "Score at least -1" (most visible for eliminated players, who
-- stay on that blind). Never show the sentinel: show "Out" when eliminated, "Failed" otherwise.
function MP.UI.blind_sentinel_text(chips, lives)
	local neg
	if type(chips) == "number" then
		neg = chips < 0
	elseif type(chips) == "table" and to_big then
		local ok, r = pcall(function() return to_big(chips) < to_big(0) end)
		neg = ok and r
	end
	if not neg then return nil end
	local out = (lives ~= nil and (tonumber(lives) or 1) <= 0)
		or (MP.SPECTATE and MP.SPECTATE.watching and MP.SPECTATE.watching())
	if out then return localize("k_mp_blind_out") end
	return localize("k_mp_blind_failed")
end

local blind_chip_UI_scale_ref = G.FUNCS.blind_chip_UI_scale
G.FUNCS.blind_chip_UI_scale = function(e)
	if blind_chip_UI_scale_ref then blind_chip_UI_scale_ref(e) end
	if MP.is_mp_or_ghost and MP.is_mp_or_ghost() and G.GAME and G.GAME.blind then
		local label = MP.UI.blind_sentinel_text(G.GAME.blind.chips, MP.GAME and MP.GAME.lives)
		if label then
			G.GAME.blind.chip_text = label
			if e and e.config then e.config.scale = (#label > 8) and 0.45 or 0.6 end
		end
		MP.UI.set_blind_target_label(label == nil)
	elseif MP.UI.sentinel_label_hidden then
		MP.UI.set_blind_target_label(true)
	end
end

-- Hide the "Score at least" line while the sentinel label is shown; restore it afterwards.
-- Only restores what we hid (PvP sets its own "Current Enemy score" label, left alone).
local function target_label_node()
	local ok, node = pcall(function()
		return G.HUD_blind:get_UIE_by_ID("HUD_blind").children[2].children[2].children[2].children[1].children[1]
	end)
	return ok and node and node.config and node or nil
end
function MP.UI.set_blind_target_label(visible)
	if visible and not MP.UI.sentinel_label_hidden then return end
	if not visible and MP.UI.sentinel_label_hidden then return end
	local node = target_label_node()
	if not node then return end
	if visible then
		if node.config.text == "" then node.config.text = MP.UI.sentinel_label_saved or localize("ph_blind_score_at_least") end
		MP.UI.sentinel_label_hidden, MP.UI.sentinel_label_saved = false, nil
	else
		MP.UI.sentinel_label_saved = node.config.text
		node.config.text = ""
		MP.UI.sentinel_label_hidden = true
	end
end
