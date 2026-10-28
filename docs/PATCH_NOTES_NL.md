# Patch notes-pop-up (0.6.8)

Na een update toont Balatro High Stakes **een keer** een kort venster met alleen het belangrijkste:
- bovenaan het **Balatro High Stakes-logo** (eigen pixel-art: goud *HIGH*, rood *STAKES*, twee fiches,
  donkere rand en schaduw). Het springt even op als het venster opent en wiebelt daarna zachtjes om de
  paar seconden, zoals een kaart in Balatro. Zonder het plaatje valt het terug op gekleurde tekst;
- per versie alleen de **kop "Versie 0.6.8"** (zonder "in development") en **3 tot 5 korte regels**;
- **gekleurde labels** per soort: **NIEUW** (groen), **ANDERS** (blauw), **OPGELOST** (oranje),
  **LET OP** (rood). Engels: NEW / CHANGED / FIXED / HEADS UP;
- elke regel begint met een **trefwoord in een Balatro-kleur** (zoals in de jokerteksten: oranje,
  blauw, rood, groen, goud), groter getekend met schaduw. Balatro's lettertype heeft geen vet, dus
  "vet" = groter + gekleurd + schaduw. De rest van de regel is wit;
- onderaan een klein regeltje "Meer details: CHANGELOG op GitHub" en de groene knop **Begrepen**
  (*Got it*).
Een versie past altijd op een pagina. Heb je versies overgeslagen, dan krijgt elke versie een eigen
pagina met `<  Pagina 1/2  >`.

## Wanneer verschijnt hij?
- Alleen op het **hoofdmenu**, ongeveer 3 seconden nadat het menu er staat (dus na de knop
  "Update available"), en pas als de update-controle klaar is (maximaal 8 s wachten).
- **Nooit** in een lobby, midden in een match, of terwijl je via een Steam-uitnodiging aan het joinen
  bent. Start je het spel via een uitnodiging, dan komt hij pas als je later terug bent op het hoofdmenu.
- **Nooit bovenop** een ander venster (bv. de dev-build-waarschuwing): hij wacht tot dat dicht is.
- Begint een lobby-join terwijl hij open staat, dan gaat hij dicht en telt hij nog niet als gezien.

## Een keer per versie
- De laatst geziene versie staat in de mod-config (`patchnotes_seen` in `config/Multiplayer.jkr` in
  de Balatro-savemap), niet in `.env`. Die blijft bij een update gewoon staan.
- **Nieuwe installatie** (of de eerste keer met deze functie, bv. van 0.6.7 naar 0.6.8): alleen de notes
  van de huidige versie.
- **Versies overgeslagen** (bv. 0.6.6 -> 0.6.8): de notes van alle versies sinds je laatst speelde, de
  nieuwste eerst, elk met een eigen kop "Versie 0.6.x" (maximaal 5 versies).
- Dezelfde versie opnieuw opstarten: geen pop-up meer.

## Opnieuw bekijken
Knop **Patch notes** rechtsboven op het hoofdmenu (onder het versienummer) en in de mod-instellingen
(Mods -> Balatro High Stakes -> Config). Die toont de notes van de huidige versie.

## Taal
Volgt de taal van het spel: Nederlands als het spel op Nederlands staat, anders Engels. Ontbreekt een
Nederlandse sectie in een bestand, dan wordt de Engelse gebruikt.

## Zelf notes schrijven (per release)
1. Maak `mod/patchnotes/<versie>.lua`, bv. `0.6.9.lua` (voorbeeld en uitleg in `mod/patchnotes/README.md`):
   `version`, `date`, en per taal (`en`, `nl`) een `title` en de lijsten `new`, `changed`, `fixed`, `known`.
2. Zet de versie bovenaan in `mod/patchnotes/index.lua`.
3. Maximaal 5 regels per versie, elk hooguit 58 tekens, en elke regel begint met een gekleurd trefwoord:
   `"{C:green}Host-migratie{}: de match gaat door als de host weggaat"`. Kleuren: `attention` (oranje),
   `chips` (blauw), `mult` (rood), `green`, `money` (goud), `purple`. De tests controleren dit.
Een kapot bestand wordt overgeslagen (de rest werkt nog) en staat in de log.

## Techniek en tests
- `mod/lib/patch_notes.lua`: versievergelijking, welke versies tonen, laden, afbreken, pagina's, wanneer
  tonen, de UI (`create_UIBox_generic_options`, `create_option_cycle`, `UIBox_button`).
- Haakjes: `ui/main_menu/main_menu.lua` (knop op het hoofdmenu), `ui/smods_menu/config_tab.lua` (knop in de
  instellingen).
- `luajit tests/test_patch_notes.lua` (vanuit `mod/`): versies vergelijken, nieuwe installatie, update,
  overgeslagen versies, maximaal 5, al gezien, kapotte bestanden, NL/EN en terugval naar Engels, afbreken,
  pagina's, en het hele verloop: niet in de eerste seconden, niet tijdens een invite-join, niet in de lobby,
  niet midden in een match, wel daarna op het hoofdmenu, niet twee keer, "Begrepen" sluit, de knop opent
  hem opnieuw.
- Logo: `mod/assets/1x/mp3p_logo.png` (220x54) en `2x/` (440x108, nearest-neighbour), gemaakt met
  `tools/make_logo.py`; geladen als Steamodded-atlas `mp_mp3p_logo`.
- Voorbeeldafbeelding (nagebootst, geen echte schermafbeelding): `patchnotes_preview_v2.png` (EN) en
  `patchnotes_preview_v2_nl.png` (NL); het logo los: `high_stakes_logo.png`.
