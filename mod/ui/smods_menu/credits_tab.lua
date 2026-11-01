-- Balatro High Stakes credits tab (Mods -> Balatro High Stakes -> Credits). GPL-3.0.
-- The fork's own credits; the original Balatro Multiplayer authors are credited in CREDITS.md,
-- FORK_NOTICE.md and LICENSE.md (kept), with one small line here pointing to them.
MP.UI.CREDITS = MP.UI.CREDITS or {}
local CR = MP.UI.CREDITS
CR.ORIGINAL_URL = "https://github.com/Balatro-Multiplayer/BalatroMultiplayer"
CR.FALLBACK = {
	k_hs_made_by = "A mod by",
	k_hs_features = "New modes, jokers & art, up to 8 players",
	k_hs_kofi = "Like it? Support the mod on Ko-fi",
	b_hs_kofi = "Ko-fi",
	b_hs_github = "GitHub",
	b_hs_discord = "Join our Discord",
	b_hs_original = "Original mod",
	k_hs_based_on = "Based on Balatro Multiplayer by the Balatro Multiplayer team (GPL-3.0)",
	k_hs_full_credits = "Full credits in CREDITS.md",
}

function CR.text(key)
	local ok, s = pcall(localize, key)
	if ok and type(s) == "string" and s ~= "ERROR" and s ~= "" then return s end
	return CR.FALLBACK[key] or key
end

local function T(text, scale, colour)
	return { n = G.UIT.T, config = { text = text, scale = scale, colour = colour, shadow = true } }
end
local function row(nodes, padding) return { n = G.UIT.R, config = { align = "cm", padding = padding or 0.05 }, nodes = nodes } end

function CR.author()
	return (MP.BRAND and MP.BRAND.author) or "Trust Ben Dover"
end

function MP.UI.create_credits_tab()
	local grey = G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
	local logo = MP.PATCH_NOTES and MP.PATCH_NOTES.logo_node and MP.PATCH_NOTES.logo_node()
	return {
		n = G.UIT.ROOT,
		config = { emboss = 0.05, minh = 6, r = 0.1, minw = 8, align = "cm", padding = 0.15, colour = G.C.BLACK },
		nodes = {
			logo or row({ T("Balatro High Stakes", 0.8, G.C.GOLD) }),
			row({ T(CR.text("k_hs_made_by") .. " ", 0.5, G.C.UI.TEXT_LIGHT), T(CR.author(), 0.65, G.C.GOLD) }, 0.1),
			row({ T(CR.text("k_hs_features"), 0.4, G.C.UI.TEXT_LIGHT) }),
			row({ T(CR.text("k_hs_kofi"), 0.42, G.C.MULT or G.C.RED) }, 0.1),
			row({
				UIBox_button({ minw = 3, button = "open_kofi", label = { CR.text("b_hs_kofi") }, colour = G.C.RED, col = true }),
				{ n = G.UIT.B, config = { w = 0.2, h = 0.1 } },
				UIBox_button({ minw = 3, button = "bmp_github", label = { CR.text("b_hs_github") }, colour = G.C.CHIPS or G.C.BLUE, col = true }),
				UIBox_button({ minw = 3, button = "mp_open_discord", label = { CR.text("b_hs_discord") }, colour = { 0.345, 0.396, 0.949, 1 }, col = true }),
			}, 0.1),
			-- the original mod, lightly: one small grey line (names are in CREDITS.md)
			row({ T(CR.text("k_hs_based_on"), 0.3, grey) }, 0.02),
			row({
				T(CR.text("k_hs_full_credits") .. "  ", 0.28, grey),
				UIBox_button({ minw = 2, minh = 0.35, scale = 0.3, button = "bmp_original_github", label = { CR.text("b_hs_original") },
					colour = G.C.UI.BACKGROUND_INACTIVE or grey, col = true }),
			}, 0.02),
		},
	}
end

if G and G.FUNCS then
	G.FUNCS.bmp_original_github = function() love.system.openURL(CR.ORIGINAL_URL) end
end
