# Balatro High Stakes 0.6.7 – overzicht (2 tot 8 spelers)

*Status: uitgebracht in 0.6.7 (28-10-2026). Onofficiële fork van
Balatro Multiplayer (GPL-3.0, credits aan Virtualized en het Balatro Multiplayer-team), door Trust Ben Dover.
Voorheen "Balatro Multiplayer 3P".*

## Nieuwe naam
- Overal waar spelers het zien: **Balatro High Stakes** (mod-naam in Steamodded, installer, README,
  credits, updater-teksten). Alle namen op één plek in de code: `MP.BRAND` in `mod/core.lua`.
- **Bewust niet veranderd (veilig voor bestaande installaties):**
  - Mod-id `Multiplayer` (prefix `mp`): instellingen, saves en `SMODS.Mods["Multiplayer"]` blijven werken.
  - Installatiemap `%APPDATA%\Balatro\Mods\BalatroMultiplayer3P`, de `.env` blijft staan.
  - GitHub-repo `trustbendover/BalatroMultiplayer3P` en de zip-namen `BalatroMultiplayer3P-v…-Installer.zip`:
    de updater van 0.6.6 zoekt precies die naam, dus anders vinden vrienden de update niet.
  - Versie blijft `0.6.7~3P` (de updater vergelijkt alleen de cijfers; het achtervoegsel is cosmetisch).
- **Repo hernoemen (0.6.8):** de repo wordt `trustbendover/BalatroHighStakes`, samen met de 0.6.8-release.
  De code is al klaar (nieuwe naam eerst, oude naam als terugval; zip-namen blijven `BalatroMultiplayer3P-…`).
  Stappen voor de releasedag en het bewijs dat 0.6.6/0.6.7 blijven updaten: `docs/REPO_RENAME_NL.md`.
  De installatiemap blijft `BalatroMultiplayer3P` (hernoemen alleen met een migratiestap in de installer).

## Alleen Steam (0.6.8)
- Vanaf 0.6.8 speelt Balatro High Stakes **alleen via Steam peer-to-peer**: de Balatro van de host is de server.
  Er is geen servermodus meer (geen IP-adres, geen playit.gg, geen Tailscale, geen eigen server hosten).
- De installer vraagt niets meer en schrijft altijd `mode=steam`. Stond een bestaande installatie op een
  serveradres (of had de `.env` geen `mode=steam`), dan zet de 0.6.8-installer/updater dat **een keer** om naar
  Steam: de andere instellingen blijven, de oude `.env` gaat naar `MP3P-backup-*\settings__.env`, en je krijgt
  een melding in gewone taal.
- De mod zelf: de TCP-client (`networking/socket.lua`) is weg. Leest hij toch een andere `mode` of
  `server_url`, dan schrijft hij een logregel en gebruikt hij Steam. Lukt Steam niet (Balatro niet via Steam
  gestart), dan staat er "Steam-multiplayer niet klaar" in het menu en probeert **Reconnect** het opnieuw.
- `server/` blijft in de repo als referentie van de spelregels en als testharnas (`npm test`, en `npm run test:lua`
  draait dezelfde scenario's tegen de Lua-host in het spel). Hij zit niet in de Installer-zip en wordt niet gehost;
  Docker/compose/standalone-buildbestanden zijn verwijderd.

## Botsing met de officiele Multiplayer (0.6.8)
- De officiele Balatro Multiplayer (mod-id `Multiplayer`, hetzelfde als de onze) en het 1.0-platform
  (`MultiplayerPvP` met dezelfde prefix `mp`, `MultiplayerAPI`, `MultiplayerSPDRN`) botsen met High Stakes.
- `Install.bat` zoekt ze in `%APPDATA%\Balatro\Mods` (ook een map dieper), toont ze en verplaatst ze na "Y"
  (standaard) naar `MP3P-backup-*` - nooit verwijderen; `Uninstall.bat` zet ze terug. `-NoPrompt` verplaatst,
  `-KeepOtherMultiplayer` laat ze staan, `-DryRun` print alleen `CLASH ...`-regels. Een oudere High
  Stakes-kopie (versie `~3P`) in een andere map telt niet als botsing en wordt zoals vroeger vervangen.
- In het spel: de startcheck (`compat_guard.lua`) ziet zo'n mod in `SMODS.Mods` en toont "Let op: nog een
  Multiplayer-mod" met Toch spelen / Multiplayer nu uit. Tests: `test_compat_guard.lua`, `tools\test_installer_clash.ps1`.

## Spelersaantallen
| Modus | Spelers | Standaard levens | Bijzonderheden |
| --- | --- | --- | --- |
| **1v1 Duel** | precies 2 | 4 (instelbaar) | Klassiek duel zoals Attrition in de originele mod. Een 3e speler wordt geweigerd. |
| Attrition | 2-8 | 4 | Laagste score verliest een leven; vanaf 6 spelers de laagste twee. |
| Showdown | 2-8 | 4 | Zelfde verliesregel, PvP pas na de eerste antes. |
| King of the Hill | 2-8 | 3 | Doelreeks 5 / 4 / 3 (2 / 3-4 / 5-8 spelers), zie `KING_OF_THE_HILL_NL.md`. |
| **Teams** | 4, 6, 8 | 4 (gedeeld) | 2v2, 3v3, 4v4, 2v2v2, 2v2v2v2, zie `TEAMS_NL.md`. |
| **Deathmatch** | 2-8 | 4 | Iedereen tegelijk, tot de laatste; weggaan = uit, 60 s grace bij wegvallen, geen late join. Zie `DEATHMATCH_NL.md`. |
| Survival | 2-8 | 1 | Ongewijzigd. |

- **Verliesregel vrij-voor-allen:** k = max(1, floor(spelers / 3)) verliezers per PvP: 2-5 spelers één,
  6-8 spelers twee. Gelijke scores op de grens worden gespaard (dus soms minder verliezers).
- **Late join** (tot 8 spelers): in alle modi behalve 1v1 Duel (vol bij 2), Teams en Deathmatch.
- **Rejoin** werkt in alle modi (plek blijft vast tot het einde; in Deathmatch 60 seconden).
- **Iedereen tegelijk op 0 levens** (niet in Teams): de hoogste score van die PvP wint (was: geen winnaar).
- **Uitgeschakeld en "Terug naar lobby"**: alleen jij gaat terug, de match loopt door (was: stopte voor iedereen).
- De lobby laat zien waarom je niet kunt starten ("1v1 Duel heeft precies 2 spelers nodig",
  "Teams heeft 4 tot 8 spelers nodig", "Te veel spelers voor deze modus (max N)").

## Steam P2P met 8 spelers
- De Steam-lobby wordt nu gemaakt voor **8 leden** (was 3). Steam staat tot 250 leden per lobby toe.
- Topologie blijft een **ster**: elke gast praat alleen met de host; de host draait de server-logica
  (`p2p_server.lua`) en stuurt door (host-authoritative relay). Geen mesh nodig: het verkeer groeit
  lineair met het aantal spelers en de berichten zijn klein (scores, levens, jokers bij Game Over).
- 0.6.7: als de host wegviel, stopte de match. **Vanaf 0.6.8** neemt de volgende speler het over (host-migratie,
  zie `HOST_MIGRATIE_NL.md`).

## Interface voor tot 7 tegenstanders
- Lobby-lijst en de in-game lobby-info tonen alle 8 stoelen (kleiner lettertype vanaf 5 spelers,
  teamletter in Teams).
- PvP-HUD: met 1-3 tegenstanders zoals voorheen; met 4 of meer de top 3 op score, dan `+N`
  (nog meer levende spelers) en `N out` (uitgeschakeld). In Teams eerst de teamstanden.
- Game Over: de "nemesis" is bij verlies de sterkste rivaal die nog meedoet, bij winst de laatst
  uitgeschakelde; nooit een teamgenoot.

## Jokers
Alle zeven herwerkt voor 2-8 spelers (schalen met het aantal rivalen, met maximum); in een 1v1
verschijnen Gier, Lachende Derde en Middenmoot niet. Zie `JOKERS_NL.md`.

## Tests
- Lua: `cd mod && luajit tests/test_three_player.lua && luajit tests/test_steam_p2p.lua && luajit tests/test_updater.lua
  && luajit tests/test_koth.lua && luajit tests/test_koth_client.lua && luajit tests/test_jokers_3p.lua
  && luajit tests/test_teams.lua && luajit tests/test_multi_client.lua`
- Server (beide serverpaden, TS en de Lua-core via een brug): `cd server && npm ci && npm test && npm run test:lua`.
  `test/multiPlayer.test.mjs` speelt complete potjes met 2, 3, 4, 6 en 8 spelers (Attrition), Showdown met 2,
  1v1 Duel, Teams 2v2 / 3v3 / 2v2v2 / 4v4 / 2v2v2v2 (incl. disconnect en rejoin), KotH-doelreeks voor
  2/4/5/8 spelers en weigert een 9e speler.
- `test_steam_p2p.lua` speelt een 4v4 met 8 spelers via de Steam-P2P-router en weigert een 9e.
- Nog niet getest: echt spelen met 8 mensen via Steam (alleen gesimuleerd).

## Risico's
- Lay-out met 8 spelers (lobby-lijst, lobby-info) is niet in het echte spel bekeken; kan krap zijn.
- 0.6.6 en 0.6.7 door elkaar geeft een versiewaarschuwing en ander gedrag; iedereen moet updaten.
- Teams/Duel waren nieuwe servermodi in 0.6.7. Sinds 0.6.8 is er alleen nog Steam P2P (geen losse server).
