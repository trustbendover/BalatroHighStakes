# Balatro High Stakes (fork, formerly "Balatro Multiplayer 3P")

This is a modified version of [Balatro Multiplayer](https://github.com/Balatro-Multiplayer/BalatroMultiplayer)
by Virtualized and contributors, licensed under GPL-3.0 (see LICENSE.md, unchanged).
Modified 2026-10 by Trust Ben Dover to support 3-player Attrition lobbies and a Steam peer-to-peer mode. It requires the matching
3P server fork (based on https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI-Server, GPL-3.0).

Changes: networking/action_handlers.lua, lib/three_player.lua (new), core.lua,
ui/game/blind_hud.lua, ui/game/lobby_info.lua, ui/lobby/lobby.lua,
ui/lobby/players_display.lua, objects/jokers/penny_pincher.lua,
objects/jokers/sandbox/magnet_sandbox.lua, Multiplayer.json.

0.6.2-0.6.3 additions: networking/p2p_server.lua (Lua port of the 3P server, runs in the host's game),
networking/steam_p2p.lua (Steam lobbies + ISteamNetworkingMessages via LuaJIT FFI on Balatro's own
steam_api64.dll), ui/lobby/lobby_code_buttons.lua (Invite Steam friend), tests/.

0.6.5: ui/game/game_end.lua, ui/game/functions.lua (Ko-fi link of the 3P fork: https://ko-fi.com/trustbendover),
localization/*.lua (Ko-fi texts). The original Balatro Multiplayer mod is by Virtualized and contributors;
support them via their own channels.

0.6.6: lib/updater.lua (background update check against GitHub releases, "Update available" button),
updater/update.ps1 + updater/Update.bat (download, SHA256 check, install in update mode),
ui/main_menu/main_menu.lua. Repository: https://github.com/trustbendover/BalatroMultiplayer3P

0.6.7: King of the Hill gamemode - gamemodes/koth.lua, lib/koth.lua,
networking/koth_rules.lua, tests/test_koth*.lua, tests/koth_vectors.json; hooks in
networking/p2p_server.lua, lib/three_player.lua, ui/main_menu/play_button/*, localization (en-us, nl).
0.6.7: special 3-player jokers - lib/jokers_3p.lua, objects/jokers/threep/*.lua,
assets/{1x,2x}/j_<key>.png (original pixel art, tools/joker_art_3p/), tests/test_jokers_3p.lua.

0.6.7: renamed to Balatro High Stakes (display names, MP.BRAND in core.lua); 2-8 players -
networking/p2p_server.lua, networking/steam_p2p.lua (lobby for 8), networking/pvp_rules.lua and
networking/teams_rules.lua (new), lib/modes.lua and lib/teams.lua (new), gamemodes/duel.lua and
gamemodes/teams.lua (new), lib/three_player.lua, lib/jokers_3p.lua, objects/jokers/threep/*.lua,
networking/action_handlers.lua, ui/lobby/players_display.lua, ui/lobby/lobby.lua,
ui/lobby/start_ready_button.lua, ui/game/lobby_info.lua, ui/main_menu/play_button/*, lib/matchmaking.lua,
localization (en-us, nl, de, fr), tests/test_teams.lua, tests/test_multi_client.lua, tests/teams_vectors.json.

Unofficial fork. Not affiliated with or endorsed by LocalThunk, Playstack, or the Balatro Multiplayer team.

0.6.7: Deathmatch gamemode - gamemodes/deathmatch.lua, lib/deathmatch.lua (new),
networking/p2p_server.lua (grace elimination, final-death rule, deathmatchUpdate), lib/modes.lua, lib/jokers_3p.lua,
ui/game/game_end.lua, ui/main_menu/play_button/gamemode_selection.lua, localization (en-us, nl),
tests/test_deathmatch_client.lua (new), tests/test_steam_p2p.lua.

0.6.8 (in development): host migration for Steam P2P - networking/host_migration.lua and lib/host_migration_ui.lua (new),
networking/steam_p2p.lua (router), networking/p2p_server.lua (snapshot/restore), networking/action_handlers.lua, core.lua,
localization (en-us, nl), tests/test_host_migration*.lua (new), tests/test_steam_p2p.lua.
