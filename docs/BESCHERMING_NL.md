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

De update-check in het spel haalt één keer per sessie `compat.json` op. Dat gebeurt op de
achtergrond en zonder melding als het mislukt. Hij pakt het bestand van de nieuwste release, of
anders van `main`. Zo kan een nieuwere release een nieuwe Balatro-versie als getest markeren,
zonder dat de code verandert. De lijst wordt bewaard in de mod-config (`compat_cache`), dus hij
werkt ook offline bij de volgende start. Uitzetten kan met `.env`: `compat_check=false`.

Zo'n lijst mag alleen dingen **toevoegen**: geteste versies, en blokkades voor andere versies.
Wat deze build zelf als getest meelevert, kan hij nooit blokkeren. Hij geldt alleen als zijn
`applies_from` niet nieuwer is dan jouw mod-versie. De waarschuwing wacht maximaal 7 seconden op
deze download.

## Installer en updater: vaste (geteste) versies

- De installer leest `payload\BalatroMultiplayer3P\compat.cfg`.
- **Niets geïnstalleerd of een oudere versie:** hij installeert de geteste Steamodded
  1.0.0~BETA-1620a en Lovely 0.10.0. Die zitten in de zip, gecontroleerd met SHA256 bij het
  bouwen.
- **Een nieuwere (of onbekende) versie gevonden:** hij vraagt *"1 = Install the tested version
  (recommended) / 2 = Keep yours"*.
  - Enter kiest de geteste versie. Jouw versie wordt dan eerst gebackupt.
  - Er wordt nooit stilletjes gedowngraded.
- **Zonder vragen** (`-NoPrompt`): de nieuwere versie blijft staan, met een duidelijke melding.
- **De updater** vraagt het ook als je hem zelf start. Gestart met `-NoPrompt` houdt hij jouw
  versie.
- **Lovely heeft geen versienummer in de dll.** De installer herkent de geteste versie aan de
  SHA256, en een andere versie aan de versietekst in het bestand.
- `-DepsPolicy ask|tested|keep` kiest vooraf.
- `-DryRun` laat alleen zien wat er zou gebeuren (`PIN ...`-regels) en verandert niets.
- Het installatie-manifest (`MP3P-install.json`) onthoudt wat er gekozen is. Een versie die je
  houdt, wordt bij het verwijderen niet weggehaald.
- `tools/build_release.py` leest de pins uit `compat.json` en stopt als de versie van de mod of
  de dll-hash niet klopt. De release krijgt `compat.json` als los bestand mee.

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
- de hooks;
- de download van `compat.json`.

`powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_installer_pins.ps1` test de
installer:

- de versievergelijking;
- alle keuzes (ook de vraag);
- `-DryRun` (verandert niets);
- een echte installatie in een wegwerpmap in `%TEMP%`, waarbij je versie wordt gehouden of
  vervangen met een backup.

Het echte spel en AppData worden nooit aangeraakt.

## Grenzen

- Lovely zet zijn eigen patches toe voordat de mod laadt. Een Lovely-patch die niet meer past, ziet
  de mod niet. Alleen de gevolgen daarvan (een bestand dat niet laadt, een hook die faalt) vangt hij
  op.
- Een Balatro-update die het spel al laat crashen voordat mods laden, kan geen enkele mod
  tegenhouden.
