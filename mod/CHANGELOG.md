# Changelog

## Ranked Update 0.4.0

### Standard Ranked

#### Jokers

- **To Do List** — Reworked. Now pays $5 (up from $4). Target poker hand is chosen from all hands, not just discovered ones.
- **Golden Ticket** — Reverted payout nerf, now earns $4 (up from $3)
- **Speedrun** — Out of rotation.
- **Ouija** and **Ectoplasm** — Now cost $4 (bug fix).

#### Consumables

- **Justice** — Back in rotation.

#### Economy & Enhancements

- **Gold Card** (Enhancement) — Payout increased from $3 to $4.
- **Comeback Gold** — Now awarded on any life loss again, not just PvP boss losses. Payout amounts ($4, or $2 on higher stakes) are unchanged.

### Quality of Life

- **Balanced Sticker** — Now shows a tooltip explaining what was changed on the card it's attached to.
- **Hotkeys — Menu Shortcuts** — Hold Tab in the menu to see context-sensitive shortcuts. Main menu: **C** creates a lobby, **V** joins from clipboard. In a lobby: **C** copies the code, **L** leaves, **D** picks deck. Disconnected: **R** reconnects.
- **Timer and score preview rework** - TODO
- **Match Replays (Practice Mode)** — Practice against a ghost opponent replayed from a past match. Drop a Lovely log (`.log`) or exported `.json` into the `replays/` folder and it shows up in the replay picker. Accessed via Practice → Ruleset → Replay Picker. Flip perspective to play as either side.

### Legacy Ranked

#### Jokers

- **Hanging Chad** — Reworked. Retriggers first 2 cards instead of first card twice.

## Ranked Update 0.3.0

### Jokers

- **Seltzer** — Lasts 8 hands instead of 10.
- **Turtle Bean** — Grants +4 hand size instead of +5.
- **Golden Ticket** — Earns $3 instead of $4. No longer requires Gold cards in deck. Now Uncommon rarity.
- **Speedrun** — Can now activate for both players if the second player joins within 30 seconds.

### Consumables

- **Ouija** — Destroys 3 cards instead of converting all cards to a single suit and reducing hand size.
- **Judgment** — Now draws from its own queue (vanilla behavior) on Orange Stake and above. Still uses the shop queue on lower stakes.

## 0.6.8~3P (in development - not released yet) - host migration

- **Clean log: no "Found invalid metadata JSON file ... compat.json / brand.json" errors.** Steamodded reads every
  file with `.json` anywhere in its name (in any subfolder) as mod metadata. The two data files are now
  `compat.cfg` and `brand.cfg` (still plain JSON inside). The mod, installer and updater read the old names as a fallback; the release asset stays
  `compat.json`, and the in-game check tries `mod/compat.cfg` and then `mod/compat.json` on GitHub main.
  The build now fails if any other `.json` ends up in the mod folder.

- **Warning for the official Balatro Multiplayer mods.** The official mod (id `Multiplayer`, the same id as ours)
  and its 1.0 platform (`MultiplayerPvP` with the same `mp` prefix, `MultiplayerAPI`, `MultiplayerSPDRN`) clash
  with High Stakes. `Install.bat` now lists them and offers to move them to the backup folder (default yes; never
  deleted, `Uninstall.bat` puts them back; `-NoPrompt` moves them, `-KeepOtherMultiplayer` keeps them, `-DryRun`
  only prints `CLASH ...` lines). In the game, the startup check shows a "Heads up: another Multiplayer mod" pop-up
  with Play anyway / Disable multiplayer for now when one of them is installed (also when Steamodded refused to
  load it: it still makes Steamodded restart the game and show errors on every start). Checked against the real
  official v1.0.1 files (folders `BalatroMultiplayerPvP-1.0.1` / `BalatroMultiplayerAPI-1.0.1`, Thunderstore layout).

- **Fix: no more "Found invalid metadata JSON file ... tests/koth_vectors.json" errors in the log.** The Installer
  zip no longer ships the mod's `tests/` folder (Steamodded scanned its JSON files as mod metadata). Harmless, but
  it looked like a broken install.

- **Steam only.** Balatro High Stakes now plays over Steam peer-to-peer only: no server, no IP address, no
  playit.gg / Tailscale. The installer no longer asks how you play and always writes `mode=steam`. An existing
  install with a server address (or no `mode=steam`) is switched to Steam once by the 0.6.8 installer/updater:
  other `.env` settings stay, the old `.env` is saved as `MP3P-backup-*\settings__.env`, and it tells you so.
  In the mod the TCP client (`networking/socket.lua`, `server_url`/`server_port`) is gone; another `mode` in
  `.env` is ignored with a log line. Without Steam the menu says "Steam multiplayer not ready" and Reconnect
  retries Steam. `server/` stays only as the reference implementation and test harness (not shipped, not hosted;
  Docker/compose/standalone build files removed).

- **Fix: `update_check=false` / `compat_check=false` in `.env` are honoured again.** The `.env` reader turns
  `false` into a boolean, so the opt-out was ignored since 0.6.6. Also: the spectator panel, match stats and rejoin
  bar can no longer crash the game if a panel fails to build (warning in the log instead), and a failed rejoin
  restore falls back to restarting at the saved ante.

- **Panels keep a fixed width.** The spectator list is now columns (name | lives | score | status) in a fixed box,
  long names get "..", huge scores become compact (1.23e14), and the status has its own colour. The rejoin bar shows
  the first player by name and the rest as "+N more". The blind HUD line (team totals + opponents) is re-fitted when
  its text changes, and the match stats texts are fitted up front (Balatro text nodes ignore maxw). Worst-case
  layout tests: 8 players, 32-character names, team tags, EN + NL (`tests/test_ui_fit.lua`).

- **New GitHub name: `trustbendover/BalatroHighStakes`** (renamed on release day). The in-game update check,
  `Update.bat`, the compat.json download and the GitHub button try the new name first and the old
  `BalatroMultiplayer3P` name second (GitHub also redirects the old name). Repo names and the zip prefix live in
  one place, `mod/brand.json` (mirrored in `MP.BRAND`). Zip names, the install folder and the mod id stay
  `BalatroMultiplayer3P` / `Multiplayer`, so 0.6.6 and 0.6.7 keep updating. Release-day steps: `docs/REPO_RENAME_NL.md`.

- **Host migration (Steam P2P).** When the host leaves, quits Balatro or loses connection - in the lobby, in the shop
  or in the middle of a PvP blind - the next player in seat order becomes host and the match continues for everyone,
  without restarting anyone's run. "Host left - X is now host" is shown. The host keeps sending a copy of the lobby
  state to all players; guests number their messages so nothing is lost; a running PvP simply continues.
  A host who leaves counts as having left (eliminated in Deathmatch); a host who only lost connection keeps the seat
  and rejoins automatically as a guest. If nobody can take over, you go back to the menu with a clear message.
- The new host also becomes the Steam lobby owner, so the lobby code and invites keep working.
- **Frozen host detected fast.** If the host's Balatro hangs but it stays in the Steam lobby, guests no longer wait
  for Steam (up to 60 s). Guests share "host silent" votes; once the host has been silent for 10 s for a majority of
  the connected guests, the next player takes over (about 10-11 s; 13 s with 2 players; ~17 s if the successor is
  stuck too). A single guest with a bad connection cannot outvote the others: it returns to the menu after 30 s
  (was 60 s) and can rejoin by code. A frozen host that wakes up sees the newer host, steps down and rejoins as a
  guest on its own seat. Players joining by code while the old owner is frozen still reach the new host.
- **Patch notes pop-up.** The first time you open the game after an update, a short Balatro-style window shows only
  the essentials: the new pixel-art **Balatro High Stakes logo** (gently wobbling), then 3-5 one-line bullets per
  version with coloured NEW / CHANGED / FIXED / HEADS UP badges and the key word of each line in a Balatro text
  colour (English or Dutch, following the game language). It appears only on the main
  menu (after the update button, never in a lobby, a match, during a Steam invite join, or on top of another pop-up),
  once per version; skipped versions are combined, newest first. "Got it" closes it; the **Patch notes** button on the
  main menu and in the mod settings reopens it. Notes live in `mod/patchnotes/<version>.lua`; the last version seen
  is kept in the mod config, so it survives updates.
- **Credits screen** now shows Balatro High Stakes: the logo, "A mod by Trust Ben Dover", the Ko-fi and GitHub buttons,
  and one small line "Based on Balatro Multiplayer by the Balatro Multiplayer team (GPL-3.0)" with an "Original mod"
  link. The original authors are credited by name in the new `CREDITS.md` (plus FORK_NOTICE.md and LICENSE.md,
  unchanged). The mods list shows Trust Ben Dover as author.
- **Break protection (compatibility guard).** On start the mod compares your Balatro, Steamodded and Lovely versions
  with `mod/compat.json` (tested: Balatro 1.0.1o, Steamodded 1.0.0~BETA-1620a, Lovely 0.10.0). An untested version
  shows a short Balatro-style warning on the main menu (English/Dutch) naming it, with "Play anyway" (remembered for
  that exact combination) or "Disable multiplayer for now" (this session only; singleplayer keeps working). It never
  stacks with the patch notes (the warning goes first). A blocked version (blocklist or older than the minimum) or a
  core mod file / main-menu hook that fails to load turns on **safe mode**: networking is not started, the multiplayer
  buttons are hidden, a note explains why, and the log says `SAFE MODE` with the reason - instead of a crash.
  Main-menu hooks are wrapped in pcall. A newer `compat.json` (e.g. cached from a newer release) can only add tested
  versions or blocks for other versions; it never blocks what this build shipped as tested.
- **Pinned Steamodded / Lovely in the installer and updater.** Fresh install or older version: the tested Steamodded
  1.0.0~BETA-1620a and Lovely 0.10.0 are installed (bundled, SHA256-checked at build time; licenses included). A newer
  or unknown version already installed is never replaced silently: "1 = Install the tested version (recommended) /
  2 = Keep yours" (Enter = tested, yours is backed up). Without prompts (`-NoPrompt`) yours is kept with a clear
  message. New `-DepsPolicy ask|tested|keep` and `-DryRun` (prints `PIN ...` decisions, changes nothing). The updater
  asks too (keeps yours with `-NoPrompt`). Lovely's version is read from the dll (pinned hash or its version string).
- **compat.json from the latest release.** The in-game update check downloads it once per session (async, silent on
  failure, `.env compat_check=false` to turn off) and caches it, so a newer release can mark a new Balatro or
  Steamodded version as tested without a code change. `tools/build_release.py` now reads the pins from
  `mod/compat.json`, checks the mod version and the dll hash, and adds `compat.json` to the release assets.
- Credits tagline: "New modes, jokers & art, up to 8 players".
- **Spectator mode.** Players who are out (Deathmatch, Attrition, KotH, Teams, ...) get a **Spectate** button on the
  game-over screen, and anyone who joins a lobby whose match is already running (Deathmatch/Teams, a full lobby, or
  `joinLobby` with `spectate`) watches instead of getting "no late join" (up to 8 spectators; Attrition etc. still
  late-join a free seat). The panel shows the player you follow (lives, score, hands left, ante, where they are or
  "disconnected"), a list of everyone left with who is ahead, and Prev / Next to switch; **Back to lobby** leaves.
  In the lobby the start button becomes **Watch match** while the match runs. Spectators and eliminated players can't
  affect the game: the host ignores their game actions (only end-of-game screens still work for players who are out),
  they never count as alive for wins, PvP pairing or "everyone ready", and they get no win/lose (just "match over").
  After the match spectators take a free seat for the next one. EN/NL texts follow the game language.
- **Rejoin after a disconnect.** A player who crashes, closes Balatro or loses connection keeps their seat for a
  **rejoin window** (lobby option "Rejoin Window": default 3 min, Deathmatch 1 min; 1-10 min) in every mode; others see
  "X disconnected - waiting to rejoin 2:41" and "X rejoined" / "X did not return in time" (then eliminated as before).
  Rejoin via Steam or the lobby code: your run is restored from a private local checkpoint (`mp3p_rejoin.jkr`, written
  at every shop / blind select; `save.jkr` is never touched) with your deck, jokers, money and ante, if it matches the
  lobby, seed and the host's last known checkpoint. Otherwise the run restarts at your ante (same seed) with the money
  the host last saw. Lives always come from the host. The host only keeps a numeric summary per player (ante, money,
  jokers, deck size, ...); run data from the network is never loaded. A rejoining player keeps their player id.
  Works with host migration: the summary travels in the host snapshots and a crashed host rejoins as a guest.
  Spectators can still become host (they get the same snapshots), but only after every seated player.
- **Match stats screen.** At the end of every multiplayer match (all modes, 2-8 players) everyone - spectators too -
  sees the same end screen, built from Balatro's own UI pieces (panels, DynaText title, red tabs, orange Back):
  who wins, an **Awards** tab with award cards (Most damage, Best hand, Most jokers, Fewest lives lost,
  Most PvPs won, Most money earned, Highest ante) a **Players** tab with a panel per player (4 per page; place, damage, best hand + hand type,
  jokers used, lives lost, PvPs won, money earned, highest ante), the winner's final jokers as real cards, and in Teams a **Teams** tab with the
  team totals (damage, PvPs won, team lives lost). It opens by itself a few seconds after the match ends and from
  the **Match stats** button on the game-over / win screen; Back goes back to that screen. EN/NL.
  **Damage** = your score in every PvP blind (the chips you threw at your opponents), the same in every mode.
  The host is authoritative: it counts damage, PvPs and lives itself; each game reports only its own best hand,
  jokers, money earned and ante (checked and capped; numbers only go up, so a restarted run can't lower them).
  The stats book is part of the host snapshot, so it survives host migration and rejoin. Ties go to the better place.
- Steam lobby member limit raised from 8 to 16 (8 players + spectators / rejoining players).
- Everyone must be on 0.6.8 (server version 0.6.8). TS server mode is unchanged.

## 0.6.7~3P - 2026-10-28 - "Balatro High Stakes"

- **Deathmatch** (new mode, 2-8 players): Attrition life rules (4 lives), but guaranteed all-vs-all to the last one standing.
  Every Nemesis blind is all living players at once; lowest score loses a life (6-8 alive: bottom two). Leaving = eliminated;
  a disconnect holds the seat for 60 s (option `deathmatch_grace`, no lobby button yet), then eliminates. No late join. Simultaneous final
  deaths: highest score wins. Eliminated players see live standings and can return to the lobby while the match goes on.
  Steam P2P host and TS server. Docs: `docs/DEATHMATCH_NL.md`.
- Fix (all modes): an eliminated player pressing "Return to Lobby" no longer stops the match for everyone.
- Fix (all non-team modes): when all remaining players die in the same PvP, the highest score wins (was: no winner).
- Fix: `startGame` while a match is running is refused.
- Laughing Third: a rival who leaves / times out with lives left counts as one lost life.
- **Renamed** to **Balatro High Stakes** (formerly "Balatro Multiplayer 3P"). Display names only: the
  Steamodded mod id stays `Multiplayer`, the install folder, release zip names and the GitHub repo stay
  `BalatroMultiplayer3P`, and the version keeps the `~3P` suffix, so 0.6.6 installs still find this
  update and keep their settings. Names live in one place: `MP.BRAND` in core.lua.
- **2 to 8 players** (was exactly 3). Both servers (Steam P2P host and TS server) accept 2-8 players;
  the Steam lobby is created for 8 members. Steam P2P stays a star: every guest talks only to the host,
  which runs the server core and relays (host-authoritative).
- **Free-for-all life loss scales**: 2-5 players: the single lowest score loses a life; 6-8 players:
  the bottom two (k = max(1, floor(players / 3))). Ties at the cut are spared. Late join up to 8 players.
- New gamemode **1v1 Duel**: exactly 2 players, classic Attrition duel as in the original Balatro
  Multiplayer, lives configurable (default 4). The server refuses a 3rd player.
- New gamemode **Teams** (4, 6 or 8 players): 2v2, 3v3, 4v4, 2v2v2, 2v2v2v2. Team score = sum of the
  teammates' scores, the single lowest team loses one shared team life (tie for lowest: nobody), an away
  teammate is filled in with the team average, last team standing wins. Nemesis effects only hit rival
  teams. The host can shuffle the teams and pick the team size in the lobby. No late join in Teams.
  Rules: networking/teams_rules.lua + server/src/teams.ts (shared vectors: tests/teams_vectors.json).
- **King of the Hill** for 2-8 players: hold target 5 (2 players) / 4 (3-4) / 3 (5-8), life bounty at
  bounty 3 (2-4 players) / 2 (5-8), crown shield also when the King is among the bottom two.
  Rules in networking/koth_rules.lua + server/src/koth.ts (shared test vectors), client in lib/koth.lua.
  Design: docs/KING_OF_THE_HILL_NL.md.
- **7 multiplayer jokers**, rebalanced for 2-8 players (they read only synced opponent lives /
  eliminations / KotH crown / teams, so they work on Steam P2P and the TS server and never affect
  opponents). Teammates never count as opponents; a rival team counts once. Not offered in a 1v1:
  Vulture, Laughing Third, Middle of the Pack. Third Wheel: up to +24 Mult by the share of rivals with
  more lives. Vulture: $16/rivals (min $3) per elimination, +1 hand size (max +2). Laughing Third:
  X0.5/rivals per rival life lost, max X3. Kingslayer: X(1 + min(1, 2/rivals)) while a rival leads.
  Bounty Hunter: $8/rivals (min $2) and +6/rivals Mult (min +1, max +24) when the leader falls.
  Middle of the Pack: X1.5 in the middle ranks (needs 2+ rival groups), else +10 Mult. Triumvirate:
  X(0.5 + 0.5 per player still in), max X3. Code: lib/jokers_3p.lua + objects/jokers/threep/,
  tests/test_jokers_3p.lua. Art: original Balatro-style pixel art (tools/joker_art_3p/). Design:
  docs/JOKERS_NL.md.
- UI for up to 8 players: lobby list and in-game lobby info show every seat (team letters in Teams),
  the PvP HUD lists the top 3 rivals plus "+N" / "N out" with 4+ opponents and team totals in Teams,
  the Game Over nemesis is never a teammate. Lobby shows why a lobby cannot start (wrong player count).
- Fix (Steam P2P host): lobbyOptions sent to guests now keep the host's full gamemode key, like the TS server.

## 0.6.6~3P (Trust Ben Dover)
- Auto-update: after the main menu loads the mod checks (in the background, 15 s timeout, silent
  when offline) https://api.github.com/repos/trustbendover/BalatroMultiplayer3P/releases/latest,
  falling back to version.json in the repo. When a newer release exists an
  "Update available: vX" button appears top-left in the main menu; clicking it starts the updater.
  Turn the check off with update_check=false in .env.
- New updater (updater/update.ps1 + Update.bat, installed with the mod and in the Installer zip):
  downloads the Installer zip of the latest release, verifies its SHA256 against the SHA256SUMS
  asset, waits until Balatro is closed and runs the installer in update mode (keeps .env).
- The project now lives at https://github.com/trustbendover/BalatroMultiplayer3P; releases are
  built by GitHub Actions on every v* tag.

## 0.6.5~3P (Trust Ben Dover)
- Game Over: "Your Nemesis" no longer shows ERROR in 3-player games. The nemesis is the strongest
  opponent still in (most lives, then score) when you lose, or the runner-up (last one eliminated)
  when you win; falls back to any known opponent / "Opponent" (also after a disconnect).
- Game Over: "Enemy Jokers", the nemesis deck and stats now come from that nemesis. Requests and
  replies carry a targetId so only that player answers (TS server and in-game P2P host); empty or
  wrong-player replies no longer overwrite the jokers.
- Ko-fi button now points to https://ko-fi.com/trustbendover ("Support us on Ko-fi"). Original
  BalatroMultiplayer credits stay in FORK_NOTICE.md / CREDITS (GPL-3.0).

## 0.6.4~3P (Trust Ben Dover)
- Fix: accepting a Steam invite started Balatro but did not join the lobby. Balatro never calls
  luasteam's runCallbacks(), so Steam callbacks were never dispatched; the mod now pumps them each frame.
- Launch from invite: reads +connect_lobby from the full process command line, waits for the main menu, retries JoinLobby.
- Host accepts SteamNetworkingMessages session requests (callback 1251).
- "Join From Clipboard" accepts a Steam lobby id / steam://joinlobby link; "Join Steam invite again" button.
- Much more "MULTIPLAYER-P2P" logging (invite:, launch command line, callback pump, JoinLobby results).
