# Deathmatch – Balatro High Stakes 0.6.7 (2 tot 8 spelers)

*Status: uitgebracht in 0.6.7 (28-10-2026). Onofficiële fork van
Balatro Multiplayer (GPL-3.0, credits aan Virtualized en het Balatro Multiplayer-team), door Trust Ben Dover.*

## Regels in het kort
- **2-8 spelers**, iedereen tegen iedereen, **tot er één overblijft**. Standaard 4 levens (instelbaar).
- Na de eerste ante is elke boss blind een **Aartsvijand-blind** (zoals Attrition).
- Elke PvP-blind speelt **ALLE levende spelers tegelijk**; niemand zit over of speelt een normale blind.
- De **laagste score verliest een leven**; met 6-8 levende spelers de **laagste twee**
  (k = max(1, floor(levend / 3)), gelijke scores op de grens worden gespaard – precies zoals Attrition).
- **Doodgaan of weggaan beëindigt de match niet**: de anderen spelen door tot er één over is.
  De laatste die overblijft wint.
- **Gelijktijdige laatste doden:** gaan alle overgebleven spelers in dezelfde PvP dood (bv. allemaal
  de timer laten aflopen), dan wint de **hoogste score** van die PvP (bij gelijkspel: allen).
- **Weggaan** (Leave lobby / Balatro afsluiten via Leave) = meteen uitgeschakeld (plaats wordt vastgelegd).
- **Verbinding kwijt**: je plek blijft **60 seconden** vast (optie `deathmatch_grace`, 1-300 s; nog geen knop in de lobby).
  Kom je binnen die tijd terug met dezelfde code/naam, dan speel je gewoon verder met je levens.
  Daarna ben je uitgeschakeld (reden "disconnected"); kom je later nog terug, dan kijk je mee als toeschouwer.
- **Geen late join:** een nieuwe speler kan een lopende Deathmatch niet binnenkomen
  ("Deathmatch in progress: no late join.").
- **Uitgeschakeld?** Op het Game Over-scherm zie je live de stand ("Deathmatch: 3 left | Bob 3 Ann 2 …")
  en verschijnen meldingen "X uitgeschakeld – nog N over". **Terug naar lobby (match gaat door)** brengt je
  netjes naar de lobby **zonder** de match voor de anderen te stoppen; **Leave lobby** gaat naar het menu.
  De stand blijft binnenkomen zolang je in de lobby zit; aan het eind zie je wie gewonnen heeft.
- Jokers die op uitschakelingen reageren (Gier, Lachende Derde, Premiejager) werken ook bij een
  weggaande of time-out speler. Een speler die weggaat met nog 3 levens telt voor Lachende Derde als
  **één** verloren leven (niet als drie), zodat weggaan geen gratis bonus geeft.

## Verschil met Attrition (is Attrition al zo?)
Grotendeels wel, maar niet gegarandeerd. Onderzocht in 0.6.7:

| | Attrition | **Deathmatch** |
| --- | --- | --- |
| Iedereen tegelijk in elke PvP | ja | ja |
| Match gaat door na een uitschakeling | ja | ja |
| Weggaan = uitgeschakeld | ja | ja (met plaats + melding "left") |
| Verbinding kwijt | plek blijft vast **tot het einde** (zonder tijdslimiet: een weggevallen speler blijft "levend" meetellen) | plek **60 s** vast, daarna uitgeschakeld |
| Late join | ja (laat iemand halverwege instappen; die zit de lopende PvP over) | **nee** |
| Iedereen tegelijk op 0 | **bug:** niemand kreeg een winst | hoogste score wint (nu ook in Attrition/Showdown gerepareerd) |
| Uitgeschakelde speler drukt "Terug naar lobby" | **bug:** stopte de match voor iedereen | alleen jij gaat terug (nu in alle modi gerepareerd) |
| Live stand voor toeschouwers | nee | ja (`deathmatchUpdate`) |

Dus: Attrition blijft zoals het was (met late join en een vaste plek bij wegvallen), Deathmatch is de
strikte "laatste die overblijft"-variant. De twee bugfixes (geen winnaar bij gelijktijdige dood, en
"Terug naar lobby" van een uitgeschakelde speler) gelden voor alle modi.

## Serverpaden
- **Steam P2P** (host draait `mod/networking/p2p_server.lua`): alles hierboven. Vanaf 0.6.8: verlaat de **host**
  de lobby of sluit hij Balatro, dan neemt de volgende speler het over (host-migratie, zie
  `HOST_MIGRATIE_NL.md`); de host telt dan als weggegaan (= uitgeschakeld). In 0.6.7 stopte de match.
- **TS-server** (`server/src`): dezelfde regels (`Lobby.ts`: `checkGameOver`, `deathmatchExpire`,
  `deathmatchBroadcast`).

## Techniek
- Moduscode `deathmatch` (`gamemodes/deathmatch.lua`, client `lib/deathmatch.lua`, limiet in `lib/modes.lua`).
- Nieuw bericht server → client `deathmatchUpdate { you, alive[{id,username,lives,away}], out[{id,place}], running, winnerId }`,
  na elke PvP, uitschakeling, weggaan en aan het eind; ook naar uitgeschakelde spelers.
- `playerEliminated` heeft nu een `reason` (`left` / `disconnected`; leeg = levens op).
- Tijdens een PvP-blind worden doden pas bij het afronden verwerkt, zodat spelers die in dezelfde
  PvP sterven tegelijk sterven.
- `startGame` terwijl een match loopt wordt geweigerd ("A match is still running.").

## Tests
- `server/test/deathmatch.test.mjs` (TS én Lua-kern via `SERVER_ENTRY=test/luaBridge.mjs`):
  3 spelers met weggaan, 5 spelers met rejoin binnen de grace en disconnect erna, late join geweigerd,
  uitgeschakelde speler terug naar lobby, 8 spelers met weggaan + disconnect tot het einde,
  gelijktijdige laatste dood.
- `mod/tests/test_steam_p2p.lua`: Deathmatch met 5 spelers over Steam P2P (weggaan, time-out + grace,
  uitgeschakelde host terug naar lobby, eindstand voor toeschouwer).
- `mod/tests/test_deathmatch_client.lua`: teksten, stand, toeschouwer, jokers bij weggaan/time-out.
