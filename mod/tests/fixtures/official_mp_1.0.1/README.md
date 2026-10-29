Real metadata of the official Balatro Multiplayer mods (GPL-3.0, Balatro-Multiplayer team), used by
`tests/test_compat_guard.lua` to check the clash detection. Downloaded 2026-10-29:
- `MultiplayerPvP.json`: BalatroMultiplayerPvP v1.0.1 (GitHub source zip folder `BalatroMultiplayerPvP-1.0.1`,
  Thunderstore zip `BalatroMultiplayer-MultiplayerPvP-1.0.1` is flat: json at the top).
- `MultiplayerAPI.json`: BalatroMultiplayerAPI v1.0.1 (folder `BalatroMultiplayerAPI-1.0.1`).
- `Multiplayer-legacy-0.5.5.json`: legacy `BalatroMultiplayer.zip` v0.5.5 (flat: Multiplayer.json, core.lua, lovely.toml).
Each top-level folder also has a Thunderstore `manifest.json` (no `id`).
What Steamodded decides with High Stakes installed (its real preflight loader, run on these files):
- 1.0.0~BETA-1620a: MultiplayerAPI and MultiplayerPvP can_load=false (need Steamodded >= 1814a).
- 1814a / 26.1002.0: MultiplayerAPI loads; MultiplayerPvP can_load=false (it lists `Multiplayer` as a conflict).
