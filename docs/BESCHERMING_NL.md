# Bescherming tegen kapotte updates (0.6.8)

Balatro, Steamodded en Lovely kunnen los van onze mod updaten. Een nieuwe versie kan multiplayer
breken. Daarom checkt de mod vanaf 0.6.8 bij het opstarten met welke versies je speelt.

## Eén lijst met geteste versies: `mod/compat.json`

| Onderdeel  | Getest             | Minimum            |
|------------|--------------------|--------------------|
| Balatro    | 1.0.1o             | 1.0.1o             |
| Steamodded | 1.0.0~BETA-1620a   | 1.0.0~BETA-1620a   |
| Lovely     | 0.10.0             | 0.9.0              |

In hetzelfde bestand staan de vaste downloads (URL + SHA256) van Steamodded 1.0.0~BETA-1620a
(GPL-3.0) en Lovely 0.10.0 (MIT), plus een `blocked`-lijst voor versies waarvan we weten dat ze
niet werken. Nieuwe versie getest? Zet hem bij `tested`. Versie kapot? Zet hem in `blocked` met een
reden.

## Wat de mod bij het opstarten doet

1. Hij leest de Balatro-versie (`G.VERSION`), de Steamodded-versie en de Lovely-versie, en
   vergelijkt die met `compat.json`.
2. **Alles getest:** er gebeurt niks.
3. **Iets niet getest** (bijvoorbeeld een nieuwe Balatro-update): na een paar seconden in het
   hoofdmenu verschijnt een kort venster in Balatro-stijl, in het Nederlands of Engels. Het noemt
   het onderdeel en de versie, met een gekleurd label (GETEST / NIET GETEST / ONBEKEND). Je kiest:
   - **Toch spelen:** het venster komt niet meer terug zolang je dezelfde versies hebt.
   - **Multiplayer nu uitzetten:** alleen voor deze sessie. Singleplayer blijft werken. De volgende
     keer dat je opstart wordt het opnieuw gevraagd.
4. **Geblokkeerde versie** (op de blocklist of ouder dan het minimum), **of een kernbestand van de
   mod laadt niet**, **of een belangrijke hook werkt niet meer** (bijvoorbeeld de Play-knop is
   verplaatst door een Balatro-update): dan gaat de **veilige modus** aan.
   - Netwerk en Steam P2P worden niet gestart.
   - De multiplayer-knoppen verdwijnen. Er staat een korte uitleg "Multiplayer staat uit (veilige
     modus)".
   - Je krijgt één keer een venster met het label GEBLOKKEERD en een OK-knop.
   - In het log staat `SAFE MODE` met de reden.
   - Singleplayer werkt gewoon, dus geen crash.
5. Het venster komt nooit bovenop de patch notes. Eerst komt de waarschuwing, daarna de patch
   notes. Het venster verschijnt ook nooit in een lobby of tijdens een run.
6. De extra's in het hoofdmenu (kaarten, versietekst, update-knop, patch notes-knop) draaien in
   `pcall`. Gaat er één mis, dan komt het in het log en start het spel gewoon door.

## Nieuwere lijst van een nieuwere release

De mod kan een nieuwere `compat.json` gebruiken die bewaard is in de mod-config (`compat_cache`).
Zo'n lijst mag alleen dingen **toevoegen**: geteste versies, en blokkades voor andere versies.
Wat deze build zelf als getest meelevert, kan hij nooit blokkeren. Hij geldt alleen als zijn
`applies_from` niet nieuwer is dan jouw mod-versie. Na een update naar een nieuwere release zit de
nieuwe lijst gewoon in de mod.

## Nog niet klaar (geblokkeerd door de veiligheidscontrole van de assistent)

- **Installer-pin met keuze ("Geteste versie installeren (aanbevolen) / De jouwe houden").**
  De logica is uitgeschreven, maar staat nog niet in `install.ps1`. Er is ook een `-DryRun` voor
  ontworpen. De installer installeert nu nog altijd de meegeleverde geteste versies
  (Steamodded 1.0.0~BETA-1620a en Lovely 0.10.0, met SHA256-check bij het bouwen). Een nieuwere
  Steamodded wordt dus wel vervangen, maar altijd eerst gebackupt.
- **De in-game update-check haalt `compat.json` nog niet zelf op.** De verwerking en de cache aan
  de mod-kant zijn klaar en getest. Alleen de download-stap ontbreekt nog.
- **`build_release.py` leest de pins nog niet uit `compat.json`.** Daar staan dezelfde waarden nog
  hard in de code.

## Tests

`luajit tests/test_compat_guard.lua` (vanuit `mod/`) test:

- het vergelijken van versies (Balatro-letters, Steamodded-betas, Lovely 0.10 > 0.9);
- het echte `compat.json`, of de versie overeenkomt met `Multiplayer.json`;
- alle beslissingen (ok / waarschuwing / veilige modus);
- dat "Toch spelen" onthouden wordt;
- de timing (nooit gestapeld met de patch notes);
- het samenvoegen van een nieuwere lijst;
- de veilige modus;
- de Nederlandse teksten;
- de hooks.

## Grenzen

- Lovely zet zijn eigen patches toe voordat de mod laadt. Een Lovely-patch die niet meer past, ziet
  de mod niet. Alleen de gevolgen daarvan (een bestand dat niet laadt, een hook die faalt) vangt hij
  op.
- Een Balatro-update die het spel al laat crashen voordat mods laden, kan geen enkele mod
  tegenhouden.
