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
