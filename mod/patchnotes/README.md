# Patch notes

One file per release: `patchnotes/<version>.lua` (e.g. `0.6.9.lua`), plus the version in `index.lua`
(newest first). The game shows them once after an update, on the main menu (see `lib/patch_notes.lua`).

```lua
return {
	version = "0.6.9",
	date = "2026-11-15",
	en = {
		title = "Short headline",          -- optional
		new = { "Bullet point", "..." },  -- sections are optional: new / changed / fixed / known
		changed = { },
		fixed = { },
		known = { },                       -- "Known issues"
	},
	nl = { ... same keys in Dutch ... }, -- optional: missing sections fall back to English
}
```

Keep bullets short (one or two lines); long lines are wrapped automatically.
