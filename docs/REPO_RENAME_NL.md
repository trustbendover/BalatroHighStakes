# Repo hernoemen naar BalatroHighStakes (samen met 0.6.8)

`trustbendover/BalatroMultiplayer3P` wordt `trustbendover/BalatroHighStakes`. Doe het **pas op de releasedag
van 0.6.8**, in de volgorde hieronder. De code in 0.6.8 is er al klaar voor.

## Overleven oude installaties (0.6.6 / 0.6.7) het? Ja.

Oude versies kennen alleen de oude naam. Ze werken via de doorverwijzing (redirect) die GitHub na een
hernoeming automatisch maakt. Dat is gecontroleerd op 29-10-2026 op een Windows-pc met een repo die echt
hernoemd is (`jashkenas/coffee-script` → `jashkenas/coffeescript`), met de manier van ophalen die de oude
versies gebruiken:

| Wat oude versies doen | Hoe | Resultaat met de oude naam |
| --- | --- | --- |
| In-game check (`lib/updater.lua`) | `SMODS.https` → Balatro's `https.dll` = **WinINet** (geen `libcurl` aanwezig) | `api.github.com/.../releases/latest` → **200**, juiste `tag_name` |
| In-game terugval | idem, `raw.githubusercontent.com/<oud>/main/version.json` | **200**, juiste inhoud |
| `Update.bat` / `update.ps1` | Windows PowerShell 5.1 `Invoke-RestMethod` | **tag gevonden**, `html_url` op de nieuwe naam |
| Downloaden zip + SHA256SUMS | `Invoke-WebRequest` | volgt redirects (downloads lopen nu al via een redirect naar GitHub's opslag) |
| Releases-pagina (knop als er geen script is) | browser | volgt redirect |

- WinINet volgt redirects vanzelf, tenzij `INTERNET_FLAG_NO_AUTO_REDIRECT` aanstaat. lua-https zet die vlag
  niet (`src/windows/WinINetClient.cpp`), en de test op de pc gebruikte precies dezelfde vlaggen.
- `https.dll` in de Balatro-map importeert WinINet (`HttpSendRequestA`). `luaopen_https` zit daar ook in.
- De API zelf stuurt de oude naam door: `api.github.com/repos/jashkenas/coffee-script` geeft `full_name: jashkenas/coffeescript`.
- Alleen de curl-backend van SMODS (macOS/Linux-native, niet Windows) volgt geen redirects (`CURLOPT_FOLLOWLOCATION`
  wordt niet gezet). High Stakes is alleen voor Windows (en Proton draait de Windows-versie), dus dat raakt
  niemand. In het ergste geval ziet zo iemand gewoon geen update-knop; er gaat niets kapot.
- Oude updaters zoeken een asset die eindigt op `Installer.zip`. In hun terugval bouwen ze precies
  `BalatroMultiplayer3P-<tag>-Installer.zip`. Daarom **blijven de zip-namen `BalatroMultiplayer3P-v…`**
  (`asset_prefix` in `mod/brand.cfg`). We uploaden ze niet ook onder een tweede naam, want twee Installer-zips
  maken "de eerste" voor oude updaters onzeker.

**Enige echte risico:** de doorverwijzing verdwijnt als er ooit een **nieuwe repo met de oude naam**
`trustbendover/BalatroMultiplayer3P` wordt gemaakt. Doe dat dus nooit, behalve als noodplan (zie onderaan).

## Wat 0.6.8 anders doet

- `mod/brand.cfg` is de ene plek voor `repo` (nieuw), `repo_old`, `asset_prefix` en `folder`.
  `MP.BRAND` in `mod/core.lua` is een kopie; `tests/test_brand.lua` controleert dat ze gelijk zijn.
- In-game check, compat.json-download en `update.ps1` proberen eerst de nieuwe naam en dan de oude
  (bij 404, timeout of andere fout). Vóór de hernoeming werkt dus alles via de oude naam.
- De GitHub-knop, README, CREDITS en LEES_MIJ wijzen naar de nieuwe naam. Vóór de hernoeming geeft
  die link een 404, maar dat zie je alleen in de preview.
- Ongewijzigd: mod-id `Multiplayer`, installatiemap `%APPDATA%\Balatro\Mods\BalatroMultiplayer3P`,
  zip-namen, `.env`.
- Release-workflow:
  - test de terugval op Windows (`tools/test_updater_rename.ps1`);
  - waarschuwt als de repo nog niet hernoemd is;
  - controleert na publiceren of de oude naam de nieuwe release geeft.

## Checklist releasedag

1. **Vooraf:** de vrienden-test van 0.6.7 is klaar en de fixes zitten in `feature/host-migration`.
   Merge die branch naar `main`.
2. Zet `version.json` op `"version": "0.6.8", "tag": "v0.6.8"`. Loop ook de rest van
   `docs/RELEASING.md` stap 1 na, en commit.
3. **Hernoem op GitHub:** repo → *Settings* → *General* → *Repository name* → `BalatroHighStakes` → *Rename*.
   Maak daarna **geen** nieuwe repo met de oude naam.
4. Zet de remotes op elke pc/box: `git remote set-url origin https://github.com/trustbendover/BalatroHighStakes.git`.
5. Controleer de doorverwijzing **vóór** het taggen:
   ```powershell
   (Invoke-RestMethod https://api.github.com/repos/trustbendover/BalatroMultiplayer3P).full_name
   ```
   Dit moet `trustbendover/BalatroHighStakes` geven.
6. Push en tag:
   ```
   git push origin main
   git tag v0.6.8
   git push origin v0.6.8
   ```
7. Kijk bij *Actions* of alles groen is en of er **geen** waarschuwingen staan bij *Check repo name* of
   *Verify the old-client update path*. De release moet de assets `BalatroMultiplayer3P-v0.6.8-Installer.zip`,
   `…-source.zip`, `SHA256SUMS-v0.6.8.txt` en `compat.json` hebben, en als *Latest* gemarkeerd zijn.
8. **Controleer het pad voor oude clients**, op een pc met 0.6.7 nog geïnstalleerd:
   - [ ] Run het **0.6.7**-script, dat alleen de oude naam kent:
     `powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDATA%\Balatro\Mods\BalatroMultiplayer3P\updater\update.ps1" -CheckOnly`
     Verwacht: `UPDATE AVAILABLE: v0.6.8`.
   - [ ] Start Balatro (0.6.7). Linksboven moet **"Update available: v0.6.8"** staan. Klik erop, sluit Balatro,
     wacht op "Updated to v0.6.8" en start opnieuw. In het hoofdmenu staat dan `0.6.8`.
   - [ ] Open `https://raw.githubusercontent.com/trustbendover/BalatroMultiplayer3P/main/version.json`
     (de terugval van de oude versies). Hij moet `0.6.8` tonen.
   - [ ] Klik in 0.6.8 op de GitHub-knop: die opent `trustbendover/BalatroHighStakes`.
9. Laat de vrienden updaten via de knop of `Update.bat`. Iedereen in een match heeft 0.6.8 nodig.

## Noodplan (als stap 8 faalt)

1. **Snelst en veilig: hernoem de repo terug** naar `BalatroMultiplayer3P`.
   - Oude clients werken dan direct weer.
   - 0.6.8 valt vanzelf terug op de oude naam.
   - Daarna rustig uitzoeken wat er misging.
2. Vrienden kunnen altijd handmatig updaten: de Installer-zip van de releases-pagina downloaden en `Install.bat` draaien.
3. Alleen als de redirect echt niet werkt maar de nieuwe naam moet blijven: maak een kleine repo
   `BalatroMultiplayer3P` met alleen een release v0.6.8 met dezelfde vier assets.
   - Let op: dit **zet de doorverwijzing voor alle oude links uit**.
   - Die repo moet dan bij elke volgende release mee-updaten.
   - Dus liever optie 1.
