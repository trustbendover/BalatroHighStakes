# Patch notes-pop-up (0.6.8)

Na een update toont Balatro High Stakes **een keer** een venster met wat er nieuw is, in de stijl van
het spel: secties **Nieuw**, **Veranderd**, **Opgelost** en **Bekende problemen**, grote tekst, en
onderaan een groene knop **Begrepen** (Engels: *Got it*). Is de tekst lang, dan staat er een
paginakiezer onder (`<  Pagina 1/2  >`), zoals bij de andere menu's van Balatro.

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
3. Korte, vriendelijke zinnen; lange zinnen worden vanzelf afgebroken.
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
- Voorbeeldafbeelding (nagebootst, geen echte schermafbeelding): `patchnotes_preview.png` (EN) en
  `patchnotes_preview_nl.png` (NL).
