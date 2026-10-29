# Balatro High Stakes

**[Balatro Multiplayer](https://github.com/Balatro-Multiplayer/BalatroMultiplayer) for 2 to 8 players** —
an unofficial fork by **Trust Ben Dover** (formerly "Balatro Multiplayer 3P"). Modes: **1v1 Duel**,
**Attrition** and **Showdown** (2-8 players; with 6+ players the bottom two lose a life), **King of the Hill**
(crown, bounty, crown shield), **Teams** (2v2, 3v3, 4v4, 2v2v2, 2v2v2v2 with shared team lives) and **Deathmatch**
(everyone against everyone to the last one standing; leaving or a long disconnect eliminates you), plus seven
special multiplayer jokers. Plays over **Steam only** (peer-to-peer: no server, no IP address, no port forwarding).

> Unofficial fork. Not affiliated with, endorsed by or supported by LocalThunk, Playstack or the
> Balatro Multiplayer team. You need your own copy of Balatro (Windows, Steam).

## Install

1. Go to **[Releases](https://github.com/trustbendover/BalatroHighStakes/releases/latest)** and download
   `BalatroMultiplayer3P-vX.Y.Z-Installer.zip`.
2. Close Balatro, **unzip** the whole zip, and double-click **`Install.bat`**.
   (SmartScreen: "More info" → "Run anyway". It's a plain PowerShell script you can read first.)
3. The installer finds Balatro, installs Lovely 0.10.0, Steamodded 1.0.0~BETA-1620a and this mod,
   and backs up anything it replaces. It always sets up Steam mode (nothing to choose).
4. Start Balatro from Steam. The version (`0.6.x~3P`) shows in the main menu.

Everyone in a match needs the same version. The install folder is still called `BalatroMultiplayer3P`
and the mod id is still `Multiplayer`, so updating keeps your settings. The repository used to be
`trustbendover/BalatroMultiplayer3P`; old links redirect here, and the release zips keep the
`BalatroMultiplayer3P-` prefix so older installs (0.6.6/0.6.7) keep updating. `Uninstall.bat` restores your backup.

## Updates

From 0.6.6 on the mod checks GitHub in the background after the main menu loads. When a newer release
exists you get an **"Update available: vX"** button (top left). Click it and close Balatro: the updater
downloads the new Installer zip, verifies its SHA256 against the release's `SHA256SUMS` file, installs it
(your settings are kept) and tells you to restart Balatro. You can also run `Update.bat`
(in the Installer folder or in `%APPDATA%\Balatro\Mods\BalatroMultiplayer3P\updater`).
Turn the check off with `update_check=false` in the mod's `.env`.

## Playing over Steam

- **Host:** Play → Create Lobby. The host's Balatro runs the game server. From 0.6.8 on, if the host leaves, quits or
  loses connection, the next player in the lobby automatically becomes host and the match goes on (host migration).
- **Join:** Play → Join Lobby → type the code (wait ~10 s after the lobby is created), or use
  **Invite Steam friend** in the lobby / Steam friends list → *Join game*.
  If an invite doesn't land you in the lobby: Play → *Join Steam invite again*, or *Join From Clipboard*.
- **Rejoin:** crashed or disconnected? Join again with the same code and name — you keep your seat, lives and ante.
- **Late join:** another player (up to 8) can join a running match at the lowest ante/lives (not in 1v1 Duel, Teams or Deathmatch).

**Steam only (0.6.8):** there is no server / IP address / playit.gg / Tailscale mode any more. If an older install
was set to a server address, the 0.6.8 installer or updater switches it to Steam once (other settings are kept,
the old `.env` is saved in the `MP3P-backup-*` folder) and says so.

## Repository layout

| Folder | What |
| --- | --- |
| [`mod/`](mod/) | The Balatro mod (Steamodded mod id `Multiplayer`), incl. the Lua P2P server core and the updater |
| [`server/`](server/) | Reference TypeScript implementation of the lobby/PvP rules + the scenario test harness (not hosted, not shipped) |
| [`installer/`](installer/) | Windows installer / uninstaller scripts and the texts that go into the Installer zip |
| [`docs/`](docs/) | [Releasing](docs/RELEASING.md), [test checklist (NL)](docs/TESTING_NL.md) |
| [`tools/`](tools/) | `build_release.py` — builds the Installer zip, source zip and SHA256SUMS |

Tests: `cd mod && luajit tests/test_three_player.lua && luajit tests/test_steam_p2p.lua && luajit tests/test_updater.lua && luajit tests/test_koth.lua && luajit tests/test_koth_client.lua && luajit tests/test_jokers_3p.lua && luajit tests/test_teams.lua && luajit tests/test_multi_client.lua`,
`cd server && npm ci && npm test && npm run test:lua` (`test:lua` runs the same scenarios against the in-game Lua host).

## Credits

- **Balatro High Stakes fork:** Trust Ben Dover — like it? **[Support us on Ko-fi](https://ko-fi.com/trustbendover)**
- **Balatro Multiplayer** mod: Virtualized and the Balatro Multiplayer contributors —
  <https://github.com/Balatro-Multiplayer/BalatroMultiplayer> (GPL-3.0)
- **BalatroMultiplayerAPI-Server**: the Balatro Multiplayer team —
  <https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI-Server> (GPL-3.0)
- Bundled in the Installer zip, unmodified: [Steamodded](https://github.com/Steamodded/smods) (GPL-3.0),
  [Lovely](https://github.com/ethangreen-dev/lovely-injector) (MIT).

See [FORK_NOTICE.md](FORK_NOTICE.md). Licensed under **GPL-3.0** ([LICENSE](LICENSE)).
