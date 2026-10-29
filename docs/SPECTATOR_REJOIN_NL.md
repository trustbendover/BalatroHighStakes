# Meekijken en terugkeren na een disconnect (0.6.8)

Kort overzicht voor spelers en testers. Geldt voor Steam P2P (sinds 0.6.8 de enige manier om te spelen), 2 tot 8 spelers.

## Meekijken (spectator)

- **Wie?** Wie eruit ligt (Deathmatch, Attrition, KotH, Teams, ...) krijgt op het game-over-scherm een knop
  **Meekijken**. Wie een lobby joint waar al een match bezig is, kijkt mee in plaats van een foutmelding te krijgen
  (Deathmatch en Teams, of een volle lobby). In Attrition e.d. neem je nog steeds een vrije plek in (late join).
  Maximaal 8 toeschouwers per lobby.
- **Wat zie je?** De speler die je volgt (levens, score, handen over, ante, waar hij nu is of "verbinding weg"),
  een lijst van alle overgebleven spelers met wie er **voorop** ligt, en **< Vorige / Volgende >** om te wisselen.
- **Terug naar lobby** sluit het meekijken. In de lobby wordt de startknop **Kijk mee** zolang de match loopt.
- Je kunt het spel niet beïnvloeden: de host negeert alle spelacties van toeschouwers en van wie eruit ligt
  (alleen de eindscherm-info werkt nog). Toeschouwers tellen niet mee als levende speler voor winst, PvP-paren of
  "iedereen klaar", en krijgen geen win/verlies (alleen "match voorbij"). Na de match krijgen ze een vrije plek.
- **Host-migratie:** toeschouwers kunnen wel host worden (ze krijgen dezelfde snapshots en draaien dezelfde code),
  maar pas na alle spelers met een plek. Zo blijft een lobby zelfs leven als alle spelers weg zijn.

## Terugkeren na een disconnect

- Crash, verbinding kwijt of Balatro dicht? Je plek blijft vrij voor de **terugkeertijd** (lobby-optie
  "Tijd om terug te keren": standaard 3 min, in Deathmatch 1 min; instelbaar 1-10 min). De anderen zien
  "X verbinding weg - wacht op terugkeer 2:41" en daarna "X is terug" of "X kwam niet op tijd terug"
  (dan lig je eruit, zoals vroeger). Tijdens die tijd tel je als "weg", niet als uitgeschakeld.
- Terugkeren: start Balatro, ga via Steam (of de lobbycode) terug naar dezelfde lobby.
- **Je run wordt hersteld** (deck, jokers, geld, ante) uit een eigen lokaal checkpoint `mp3p_rejoin.jkr`
  (bij elke shop en blind-keuze geschreven; je gewone `save.jkr` wordt nooit aangeraakt), als het bij deze lobby,
  seed en het laatste checkpoint van de host past. Anders start je run opnieuw op je ante (zelfde seed) met het
  geld dat de host het laatst zag. Levens komen altijd van de host.
- De host bewaart per speler alleen een kleine samenvatting met getallen (ante, geld, aantal jokers, deckgrootte,
  ...). Run-data van het netwerk wordt nooit ingeladen (veiligheid).
- **Met host-migratie:** valt de host weg, dan neemt de volgende speler over; de samenvattingen gaan mee in de
  snapshots en de oude host komt terug als gewone speler.

## Grenzen (eerlijk)

- Getest met de gesimuleerde Steam-backend en een nagebootste Balatro (zie `mod/tests/test_spectator_rejoin.lua`),
  nog niet met echte vrienden over Steam. Het echt herladen van een run uit het checkpoint is nog niet in het
  echte spel getest.
- Een PvP-blind die bezig was toen je wegviel kun je niet afmaken: je komt terug in shop of blind-keuze.
