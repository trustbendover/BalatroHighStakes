# Host-migratie – Balatro High Stakes 0.6.8 (Steam P2P)

*Status: in ontwikkeling (branch `feature/host-migration`), nog niet uitgebracht, geen tag.
Onofficiële fork van Balatro Multiplayer (GPL-3.0, credits aan Virtualized en het Balatro Multiplayer-team),
door Trust Ben Dover.*

## Wat het doet
In Steam-modus draait de host de server in zijn eigen Balatro. Tot en met 0.6.7 stopte de match voor
iedereen als de host wegging. Vanaf 0.6.8 neemt een andere speler het over en speelt iedereen gewoon door:
in de lobby, in de winkel en midden in een PvP-blind. Niemand begint opnieuw aan zijn run.
Iedereen ziet kort: **"Host weg – X is nu host"** (of "jij bent nu host").

## Hoe het werkt (in gewone zinnen)
1. **De host deelt steeds de stand.** Bij elke verandering stuurt de host alle spelers een kopie van de
   complete lobby- en spelstand: levens, scores, de lopende PvP-ronde, ready-vlaggen, kroon en premie
   (King of the Hill), teams en teamlevens, uitschakelingen en wachttijden (Deathmatch), seed en
   lobby-instellingen. Ook de **opvolgvolgorde** zit erin: de spelers in stoelvolgorde.
2. **Geen berichten kwijt.** Elk spelbericht van een gast krijgt een volgnummer en blijft bewaard tot de
   host in een nieuwe kopie bevestigt dat hij het verwerkt heeft. Valt de host weg, dan worden de nog niet
   bevestigde berichten opnieuw naar de nieuwe host gestuurd.
3. **Merken dat de host weg is**, op drie manieren: de host drukt *Leave lobby* (hij laat het eerst weten),
   Steam haalt de host uit de lobby (Balatro gesloten, crash, internet weg), of de host is **bevroren**
   (Balatro hangt, maar Steam ziet hem nog in de lobby). Zie "Bevroren host" hieronder.
4. **Wie wordt host?** Iedereen kijkt naar dezelfde lijst: de eerste speler na de host in stoelvolgorde die
   nog in de Steam-lobby zit. Alleen die speler promoveert zichzelf; de anderen wachten op zijn
   aankondiging. Komt die er niet binnen 6 seconden, dan is de volgende op de lijst aan de beurt.
5. **De nieuwe host** bouwt de server opnieuw op uit de laatste kopie, neemt zelf weer zijn plaats in, en
   kondigt zich aan. De gasten verbinden met hem met hun herverbindingstoken en sturen hun niet-bevestigde
   berichten opnieuw. Spelers houden hun eigen speler-id, zodat HUD, jokers en uitschakelingen gewoon kloppen.
   De Steam-lobby-eigenaar draagt de lobby over aan de nieuwe host, zodat de code en uitnodigingen blijven werken.
6. **Even wachten op iedereen.** Tot alle spelers terug zijn (maximaal 15 s) start of eindigt er geen blind.
   Wie dan nog ontbreekt, telt als "verbinding kwijt" (plek blijft vast, zoals gewoonlijk).
7. **Geen twee hosts tegelijk.** Een aankondiging telt alleen met een hoger volgnummer ("epoch"), of bij
   hetzelfde nummer van de speler die hoger op de lijst staat. Een host die een betere aankondiging hoort,
   stapt terug en wordt gast.

## Een PvP-blind die bezig was
Gekozen: **doorspelen, niet overdoen.** De ronde loopt gewoon verder vanaf de laatste stand: wie al klaar
was, blijft klaar met zijn score; wie nog speelt, speelt verder; berichten die de oude host niet meer
verwerkte, komen via de herhaling alsnog binnen. De ronde wordt pas afgerekend als iedereen terug is
(of na 15 s, dan zonder wie ontbreekt). De oude host doet aan deze ronde niet meer mee.

## De oude host
- **Drukt op Leave lobby:** telt als weggegaan. In Deathmatch = uitgeschakeld ("left"). In de andere modi
  zoals een gewone speler die weggaat.
- **Sluit Balatro / crasht / verbinding weg:** telt als "verbinding kwijt": de plek blijft vast. In Deathmatch
  heeft hij de gewone 60 seconden om terug te komen, daarna is hij uitgeschakeld.
- **Terugkomen:** een host die alleen zijn verbinding kwijt was, merkt dat Steam hem uit de lobby heeft gehaald
  en joint vanzelf opnieuw als gast (tot 3 minuten lang elke 5 s een poging), met zijn eigen plek, levens en
  run. Na een herstart van Balatro kan hij met dezelfde code opnieuw joinen.

## Als het niet lukt
Geen kopie ontvangen (bijvoorbeeld de host viel weg vlak na het joinen) of niemand meer over om het over te
nemen: dan gebeurt wat er in 0.6.7 altijd gebeurde – terug naar het menu, met de melding *"De host is weg en
niemand kon de lobby overnemen"*. Was jij zelf je verbinding kwijt: *"Verbinding met de Steam-host verloren"*.

## Grenzen
- Alleen **Steam P2P**. De TS-server is zelf de baas en heeft dit niet nodig (ongewijzigd).
- Iedereen moet **0.6.8** hebben (0.6.7 kent de nieuwe berichten niet).
- Berichten die de oude host in zijn allerlaatste fractie van een seconde nog verstuurde, kunnen in een
  zeldzaam geval dubbel aankomen (bv. een PvP-uitslag die de nieuwe host opnieuw berekent). Dat is niet
  in het echt getest; de kans is klein omdat de stand in hetzelfde moment wordt doorgestuurd.
- Speelt de oude host nog een PvP-ronde op het moment dat hij wegvalt, dan telt zijn score in die ronde niet.
- De kopie bevat de herverbindingstokens van alle spelers (nodig om over te nemen). Iedereen in de lobby kan
  die dus in theorie zien; tussen vrienden is dat geen probleem.
- Met **2 spelers** kan de gast een bevroren host niet onderscheiden van zijn eigen kapotte verbinding: hij
  neemt na 13 s over. Komt de verbinding terug, dan sluit de oude host zich gewoon bij hem aan (zelfde
  regel als bij ontdooien), dus het spel gaat door.
- Met **3 spelers** waarbij de host **en** een gast tegelijk vastlopen, blijft er één gast over: dat is geen
  meerderheid van 2, dus geen overname; die gast gaat na 30 s terug naar het menu (tenzij Steam de host
  eerder uit de lobby haalt, dan wordt er wel gewoon overgenomen).
- De wachttijden (10 s stilte, 13 s met 2 spelers, 6 s per kandidaat, 15 s op iedereen, 30 s terugval) zijn
  nog niet instelbaar. Echte Steam-tests met bevroren Balatro zijn nog niet gedaan (alleen nagebootst).

## Bevroren host (sinds 0.6.8, stemmen onder de gasten)
De host stuurt minstens elke 3 seconden een teken van leven. Zo werkt het als dat stopt:
- **Stemmen.** Elke gast vertelt de andere gasten elke 2 seconden (en meteen bij een verandering) of hij de
  host nog hoort. Hoort een gast de host **10 seconden** niet, dan stemt hij "host stil".
- **Meerderheid.** Zodra een **meerderheid van de verbonden gasten** "host stil" stemt (bv. 2 van 2, 2 van 3,
  4 van 7), neemt de opvolger de lobby over, zonder op Steam te wachten. In de praktijk gebeurt dat na
  **ongeveer 10-11 seconden**; zit de opvolger zelf ook vast, dan komt de volgende na nog 6 s (rond 16-17 s).
- **Met 2 spelers** is er maar één gast en dus niemand om mee te stemmen: die neemt over na **13 seconden**
  stilte.
- **Geen vals alarm.** Heeft maar één gast een slechte verbinding, dan horen de anderen de host nog wel: geen
  meerderheid, dus geen overname. Die ene gast gaat na **30 seconden** (vroeger 60) terug naar het menu met
  een melding; zijn plek blijft vast en hij kan met de code terug in hetzelfde spel.
- **De bevroren host ontdooit.** De nieuwe host blijft de oude host (zolang Steam die nog in de lobby ziet)
  elke 3 seconden laten weten dat er een nieuwe host is, met een hoger volgnummer (epoch). Zodra de oude
  host weer draait, ziet hij dat, stopt hij als host, geeft hij het Steam-lobby-eigenaarschap door en komt
  hij terug als gast op zijn eigen plek (met zijn levens). Ook na een bevriezing van 90 s werkt dat.
- **Joinen terwijl de oude host nog bevroren is.** Steam laat alleen de lobby-eigenaar (de bevroren host)
  lobbygegevens aanpassen. Daarom zet de nieuwe host een markering in zijn eigen Steam-ledengegevens;
  wie met de code joint, gaat naar het lid met de hoogste markering in plaats van naar de eigenaar.
- **Nooit langer dan 30 s.** Bevroren host: overname na ~11 s (13 s met 2 spelers, ~17 s als de opvolger
  ook vastzit). Komt er geen meerderheid, dan is het uiterlijk na 30 s terug naar het menu.

## Techniek
- `mod/networking/host_migration.lua` – verkiezing, snapshots, berichtnummers, aankondigingen (router-kant).
- `mod/networking/steam_p2p.lua` – router: frames `S` (stand), `Q<nr>|…` (genummerd bericht), `A` (nieuwe host),
  `L` (host vertrekt), `V` (stem "host stil" tussen gasten); Steam `SetLobbyOwner`, `SetLobbyMemberData` /
  `GetLobbyMemberData` (markering van de echte host).
- `mod/networking/p2p_server.lua` – `Server:snapshot`, `Core.restore`, `end_migration`, wachttijd voor blinds.
- `mod/lib/host_migration_ui.lua` + `networking/action_handlers.lua` – meldingen `hostMigrating`,
  `hostMigrated`, `hostMigrationFailed`.

## Tests
`luajit tests/test_host_migration.lua` (vanuit `mod/`), met een nagebootst Steam-netwerk:
- host sluit Balatro in de **lobby**: 2, 3, 5 en 8 spelers, alle modi (Attrition, Showdown, KotH, Teams,
  Deathmatch, 1v1 Duel, Survival); de nieuwe host kan daarna starten;
- host sluit Balatro **in de winkel** en **midden in een PvP** (met een laatste hand die de oude host nooit
  las): 2, 3, 5, 8 spelers, alle PvP-modi; de ronde wordt afgerekend en het spel gaat door;
- host drukt **Leave lobby** midden in een PvP in alle PvP-modi; in Deathmatch telt hij als uitgeschakeld;
- de **nieuwe host vertrekt meteen ook**; **twee spelers tegelijk weg**; een opvolger die stil is maar nog
  in de Steam-lobby staat (3, 5, 8 spelers);
- de **oude host** verliest zijn verbinding en komt vanzelf terug als gast met zijn levens;
- **twee spelers promoveren tegelijk** (split brain): er blijft één host over;
- geen kopie → **terug naar het menu**; een nieuwe speler kan daarna gewoon joinen met de code;
- **bevroren host** (blijft in de Steam-lobby): 2, 3, 5, 8 spelers, in de winkel en midden in een PvP;
  vervangen binnen 11 s (13 s met 2 spelers); joinen met de code bereikt de nieuwe host; na het ontdooien
  wordt de oude host gast en speelt hij de volgende PvP mee;
- **host én opvolger bevroren** (5 spelers): plek 3 neemt over na 16 s; na 90 s ontdooien komen beiden terug;
- **vals alarm**: één gast met slechte verbinding (3, 5, 8 spelers, ook als dat de opvolger is): niemand
  neemt over, die gast is na 30 s terug in het menu en kan terug joinen;
- **2 spelers, verbinding van de gast weg**: de gast neemt over na 12-13 s, de oude host sluit zich aan zodra
  de verbinding terug is.
`tests/test_host_migration_ui.lua` test de meldingen. Alle bestaande tests blijven slagen.
