# Lobby presets (0.6.8)

Lobby Options has a **Presets** tab.

- **Built-in presets:** Classic (the defaults), Quick Duel (2 lives, PvP from ante 1, 90 s timer),
  Party 8 (120 s timer, 5 min rejoin window), Relaxed (6 lives, no timer, 10 min rejoin window).
- **My presets:** 4 slots. *Save* stores the current lobby settings in a slot (*Overwrite* if it is in use),
  *Load* applies a slot, *Delete* asks *Sure?* first. Slots get an automatic name such as
  "Attrition, 4 lives, 150s".
- Only the **host** can load a preset (guests can still save one). Loading uses the normal lobby options
  message, so every player gets the new settings at once.
- A preset never switches the **mode or ruleset**: those are fixed when the lobby is created. When a preset was
  saved in another mode, its options are applied and the tab says the mode stays the same. King of the Hill and
  Survival keep their fixed lives. Rulesets that force their own options (for example ranked) cannot be overridden.

## Stored settings

`starting_lives`, `pvp_start_round`, `timer`, `timer_base_seconds`, `timer_increment_seconds`,
`showdown_starting_antes`, `pvp_countdown_seconds`, `rejoin_grace`, all lobby toggles (comeback money, blind
rewards, life loss, Multiplayer jokers, different decks/seeds, random loadout, normal bosses, hide score,
disable preview, The Order, legacy Small World), `custom_seed`, `back`, `sleeve`, `stake`, `challenge`, plus the
mode and ruleset the preset was saved in (for the note).

## File

`%APPDATA%\Balatro\<profile>\hs_lobby_presets.cfg`. It is a plain `key=value` text file with `version=1` and
`[slot N]` sections. It is separate from `save.jkr`, and the `.cfg` name keeps Steamodded from reading it as mod
metadata. When the file is read:

- unknown keys and invalid values are ignored;
- numbers are clamped or snapped to the values the lobby allows;
- a deck from a mod that is no longer installed is skipped;
- a missing or broken file just means no saved presets.
