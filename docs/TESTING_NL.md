# Testchecklist Balatro MP 3P – 0.6.5~3P (Steam P2P)

Voorbereiding (iedereen):
- [ ] Iedereen: nieuwste Installer-zip uitpakken → `Install.bat` (sinds 0.6.8 altijd Steam, er is niets te kiezen).
- [ ] Iedereen start Balatro **via Steam**, Steam ingelogd, elkaar als Steam-vriend.
- [ ] In het hoofdmenu staat versie **0.6.5~3P**.

## 1. Steam-modus via code
- [ ] Host: Play → Create Lobby. Code staat in de lobby.
- [ ] Vriend 1 en 2: Play → Join Lobby → code (wacht ~10 s na het aanmaken van de lobby; Steam heeft even nodig om hem vindbaar te maken). Binnen ±10 s in de lobby, 3 spelers zichtbaar.
- [ ] Start game, speel 1 PvP-blind: laagste score verliest een leven bij iedereen gelijk.

## 2. Via uitnodiging (overlay)
- [ ] Host in lobby: knop **Invite Steam friend** → Steam-overlay opent → vriend uitnodigen.
- [ ] Vriend (Balatro al open): uitnodiging accepteren in Steam-chat/overlay → komt in de lobby **zonder code te typen**.
- [ ] Vriend (Balatro dicht): uitnodiging accepteren → Balatro start en joint vanzelf (+connect_lobby).

## 3. Via vriendenlijst "Join game"
- [ ] Vriend: Steam-vriendenlijst → host rechtsklikken → **Join game** (Balatro open én dicht testen).
- [ ] Komt in de lobby zonder code.

## 4. Rejoin
- [ ] Midden in een run: vriend sluit Balatro (of trekt wifi eruit ±30 s).
- [ ] Anderen spelen door (zijn plek blijft vast, hij wordt overgeslagen in PvP).
- [ ] Vriend start opnieuw → Join Lobby met dezelfde code + zelfde naam (of opnieuw via invite) → krijgt zijn plek, levens en ante terug.

## 5. Late join
- [ ] Start met 2 spelers, derde joint tijdens de run (code of invite).
- [ ] Derde krijgt laagste ante/levens; zit een lopende blind uit en doet bij de volgende mee.

## 6. Oude serverinstelling wordt Steam (0.6.8)
- Sinds 0.6.8 is er geen playit-/servermodus meer.
- [ ] Iemand met een oude `.env` met `server_url=...` (zonder `mode=steam`) installeert/updatet naar 0.6.8:
      de installer meldt een keer "now plays over Steam only", de `.env` heeft daarna `mode=steam`, andere regels
      staan er nog, en de oude `.env` staat in `%APPDATA%\Balatro\MP3P-backup-*\settings__.env`.
- [ ] Die speler kan daarna gewoon joinen met de code.

## Als iets faalt: wat screenshotten / doorsturen
Log: `%APPDATA%\Balatro\Mods\lovely\log\` (nieuwste bestand) – stuur het hele bestand als dat kan. Zoek op:
- `Steam P2P mode active` → Steam-modus is aan. Ontbreekt die regel? Dan:
- `Steam P2P unavailable: ... multiplayer needs Steam` → **deze regel met de fout erachter** (Balatro via Steam gestart?).
- `Steam P2P update error:` / `Steam P2P send error:` → screenshot inclusief de regels erboven.
- `Steam lobby ... published for code` (host) / `Steam lobby creation failed`.
- `Started from a Steam invite, lobby ...` / `Steam join request for lobby ...` (invite/Join game).
- `Steam peer ... timed out` (verbinding weg).
- In het spel: foutmeldingen als "No Steam lobby found with code", "Could not join the Steam lobby", "Lost connection to the Steam host".
- Crash-scherm: volledige foto/screenshot van de tekst.
Noteer ook: wie host, wie faalde, Balatro open of dicht bij de invite, en de tijd.

## 0.6.4: invite-fix testen
- [ ] Iedereen 0.6.5 (hoofdmenu). Vriend met Balatro DICHT: invite accepteren → Balatro start → na het hoofdmenu (±2 s) automatisch in de lobby.
- [ ] Vriend met Balatro OPEN: invite accepteren → komt in de lobby.
- [ ] Lukt het niet: Play → "Join Steam invite again", of code kopiëren → "Join From Clipboard".
- Log-regels om te screenshotten (zoek op `MULTIPLAYER-P2P`): `launch command line:`, `invite:`, `callback pump`,
  `Steam join request`, `P2P session request`, `JoinLobby ... ->`, `sent joinLobby to host`.

## 0.6.5: Game Over-scherm testen
- [ ] Speel een 3-spelerpotje uit. Op het Game Over-scherm staat bij "Your Nemesis" een spelersnaam, nooit ERROR
      (verloren: de sterkste speler die nog in het spel zit; gewonnen: de speler die als laatste is afgevallen).
- [ ] "Enemy Jokers" toont de jokers van die nemesis (niet leeg 0/5), ook als één speler al naar het menu is.
- [ ] Doe het ook eens als een speler halverwege de verbinding verliest: geen ERROR.
- [ ] De Ko-fi-knop "Support us on Ko-fi" opent https://ko-fi.com/trustbendover.

## 0.6.7~3P – Balatro High Stakes (2 tot 8 spelers)
- [ ] Mods-menu en hoofdmenu tonen **Balatro High Stakes**; instellingen en `.env` van 0.6.6 zijn er nog.
- [ ] Spelmodus-lijst: Attrition, **1v1 Duel**, Showdown, King of the Hill, **Teams**, **Deathmatch**, (Challenge) Survival.
- [ ] 1v1 Duel: met 2 spelers starten; een 3e speler krijgt "Lobby is full"; levens instelbaar in de opties.
- [ ] Attrition met 4+ spelers: lobby-lijst toont iedereen; HUD toont top 3 + `+N`; met 6+ spelers verliezen de laagste twee.
- [ ] Teams met 4 spelers: `[A]`/`[B]` voor de namen; host-knoppen **Teams husselen** en **Teamgrootte**;
      met 3 of 5 spelers kan de host niet starten (melding in de lobby).
- [ ] Teams in het spel: teamstanden in de HUD, "Jouw team verliest een leven", beide teamgenoten verliezen samen een leven;
      een asteroïde van je teamgenoot raakt jou niet.
- [ ] Teams: teamgenoot sluit Balatro af en joint opnieuw met dezelfde code → zelfde team, zelfde levens.
- [ ] King of the Hill met 2 spelers: badge toont `Heuvel x/5`; met 5+ spelers `x/3`.
- [ ] Jokers: in een 1v1 nooit Gier, Lachende Derde of Middenmoot in de winkel.
- [ ] Game Over in Teams: de nemesis is een rivaal, nooit je teamgenoot.
- [ ] Deathmatch met 3+ spelers: iedereen speelt elke Aartsvijand-blind; wie uitgeschakeld is ziet op Game Over de live stand.
- [ ] Deathmatch: uitgeschakelde speler drukt **Terug naar lobby (match gaat door)** → de anderen spelen gewoon verder.
- [ ] Deathmatch: iemand drukt Leave lobby → melding "X uitgeschakeld – nog N over", de match gaat door.
- [ ] Deathmatch: iemand sluit Balatro af en komt binnen 60 s terug → speelt verder; na 60 s → uitgeschakeld.
- [ ] Deathmatch: een nieuwe speler probeert binnen te komen → "no late join".
