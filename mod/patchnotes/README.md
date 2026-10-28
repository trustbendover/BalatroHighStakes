# Patch notes

One file per release: `patchnotes/<version>.lua` (e.g. `0.6.9.lua`), plus the version in `index.lua`
(newest first). The game shows them once after an update, on the main menu (see `lib/patch_notes.lua`).

Keep it short: **at most 5 one-line bullets per version in total** (max 58 characters each, the tests
check this). Start every bullet with the key term in a Balatro text colour; it is drawn bigger and in
colour, the rest in white. Details go in the CHANGELOG.

```lua
return {
	version = "0.6.9",
	en = {
		new = { "{C:green}Big thing{}: what it means for you" },   -- sections: new / changed / fixed / known
		changed = { "{C:chips}Other thing{}: short" },
		fixed = { "{C:attention}Bug{}: fixed" },
		known = { "{C:mult}Heads up{}: short" },                  -- shown as "HEADS UP"
	},
	nl = { ... same keys in Dutch ... },  -- optional: missing sections fall back to English
}
```

Colours: `attention` (orange), `chips` (blue), `mult` (red), `green`, `money` (gold), `purple`.
