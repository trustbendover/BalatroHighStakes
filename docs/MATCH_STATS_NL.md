# Matchstatistieken (0.6.8)

Aan het einde van elke multiplayer-match (alle modi, 2 tot 8 spelers) ziet iedereen hetzelfde eindscherm,
ook toeschouwers. Het opent vanzelf een paar seconden na het einde van de match, en via de knop
**Statistieken** op het game-over- of winscherm. **Sluiten** brengt je terug naar dat scherm.

## Wat staat erop?

- **Wie er wint** (of welk team).
- **Prijzen** met een gekleurd label, zoals in de patch notes:
  Meeste schade, Beste hand, Meeste jokers, Minste levens kwijt, Meeste PvP's gewonnen,
  Meeste geld verdiend, Hoogste ante. Bij gelijkspel wint wie hoger eindigde.
- **Tabel per speler**: plaats, schade, beste hand (score + soort hand), jokers gebruikt, levens kwijt,
  PvP's gewonnen, geld verdiend, hoogste ante. De winnaar van elke categorie staat in de kleur van die prijs.
- De **laatste jokers** van de winnaar.
- In **Teams** ook de teamtotalen: schade, PvP's gewonnen en teamlevens kwijt.

## Hoe wordt het geteld?

- **Schade** = je score in elke PvP-blind (de chips die je naar je tegenstanders gooit), in elke modus hetzelfde.
  Modi zonder PvP-blinds hebben dus 0 schade.
- De **host beslist**: schade, PvP's en levens telt de host zelf. Elk spel meldt alleen zijn eigen beste hand,
  jokers (je laatste rij en hoeveel verschillende je hebt gehad), verdiend geld (alleen inkomsten) en hoogste ante.
  De host controleert en begrenst die waarden; ze gaan alleen omhoog.
- Alles zit in de gedeelde host-snapshot: het overleeft **host-migratie** en **terugkeren na een disconnect**
  (na terugkeren tellen je tellers verder vanaf de getallen van de host).

## Grenzen

- Getest met de gesimuleerde Steam-backend en een nagebootste Balatro (`mod/tests/test_match_stats.lua`),
  nog niet in een echte match met vrienden. Het scherm zelf is alleen als preview-afbeelding nagemaakt.
- Alleen Steam P2P: de TCP-server (TS) maakt geen statistieken.
- Wie de match verlaat staat er nog in (als uitgeschakeld), met de cijfers tot dat moment.
