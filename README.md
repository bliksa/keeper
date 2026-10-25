# Keeper of the Cycle

Hra o cykle, kŕčoch a dýchaní. Pôvodný webový prototyp (`web-export/`) je
prenesený do **Godot 4.4**. Projekt sa upravuje **promptami cez Claude Code** a
každá zmena sa dá hneď vyskúšať v prehliadači.

**▶ Hrať:** https://bliksa.github.io/keeper/ (pôvodná webová verzia na
https://bliksa.github.io/keeper/original/, záloha hry pred levelom 2 na
https://bliksa.github.io/keeper/v1/)

## Ako to funguje

1. Napíšeš prompt, napr. *„pridaj do levelu za druhou minihrou tri plošiny so
   železom“* alebo *„zmeň text dialógu DIA_015 v slovenčine“*.
2. Claude upraví textové súbory v `godot/` (skripty, JSON, level), spustí
   automatický test celej hry (`tools/test.sh`) a zmenu pushne.
3. GitHub Actions hru zbuildí do webu a nasadí na GitHub Pages. Za pár minút je
   nová verzia na odkaze vyššie.

Godot editor na to netreba. Všetko je v čitateľných súboroch:

| Čo chceš meniť | Kde |
|---|---|
| Level jaskyne (1) a záhrady (2) | `godot/data/levels/cave.txt`, `garden.txt` (legenda v `godot/scripts/level_data.gd`) |
| Texty a preklady (SK/EN/PT) | `godot/data/i18n/*.json` |
| Dialógy (poradie, kto hovorí, tlačidlá) | `godot/data/dialogs.json` |
| Fyzika, správanie kŕčov, boss | `godot/scripts/screens/platformer.gd` |
| Minihry | `godot/scripts/minigames/` |
| Tok hry (čo nasleduje po čom) | `godot/scripts/main.gd` |

## Level 2: Záhrada (folikulárna fáza)

Po porazení Veľkého kŕču hra pokračuje do **záhrady**. Menštruácia skončila,
estrogén stúpa a Kyra tentoraz **šplhá hore** z tmavej modro-ružovej jaskyne
cez úsvit do jarného rána. Návrh je v `docs/gdd_levely_fazy_cyklu.md`.

- **Bubliny** (folikuly): ružové ťa udržia, žlté o chvíľu prasknú a dorastú.
- **Vzdušné prúdy** ťa vynesú vyššie než skok.
- **Rozptýlenia** (notifikácie) nebolia, len spomalia; dych ich odfúkne,
  šprint cez ne prejde.
- **Minihry** dávajú silu (stúpajúci estrogén):
  1. **Tanier so železom:** vyber 4 jedlá, ktoré pomôžu vstrebať železo
     (vitamín C áno, čaj, káva, kola nie) → vyšší skok;
  2. **Chyť rytmus:** stláčaj na úder (pohyb vo folikulárnej fáze) → šprint
     na Shift;
  3. **Signály tela:** roztrieď príznaky do fáz cyklu → vyšší dvojskok.
- **Vlna LH:** namiesto bossa. Zospodu stúpa zlatá vlna a treba vyšplhať na
  vrchol skôr, než ťa dobehne. Hore sa uvoľní vajíčko (ovulácia) a Estra
  vysvetlí plodné dni.

Texty sú v troch jazykoch (`DIA_G01`–`DIA_G27`, `MG5_*`, `MG6_*`, `MG7_*`).
Fakty treba dať skontrolovať odborníčke.

## Záloha

Hra pred levelom 2 je vo vetve `backup/v1-jaskyna` a hrateľná na
https://bliksa.github.io/keeper/v1/ (buildí sa z commitu `V1_SHA` v
`.github/workflows/web.yml`).

## Pauza

Počas hry **Esc** (na gamepade **Start**) otvorí menu: **Pokračovať**,
**Reštartovať hru** (nová hra od začiatku v lese), **Celá obrazovka / Ukončiť
celú obrazovku** alebo **Hlavné menu**.

## Level editor

Na úplne prvej obrazovke klikni na **DEV** (vedľa **Spustiť hru**) → **Level editor**:

- v hlavičke vyberieš, ktorý level upravuješ: **Cave** (jaskyňa) alebo
  **Garden** (záhrada); každý má vlastné automatické uloženie,
- vľavo sú skupiny nástrojov: **plošiny** (plošina, bodák), **nepriatelia**
  (4 druhy kŕčov), **zberateľné** (železo), **eventy** (minihry, boss, nápoveda,
  dialógy), **spawn a teleporty** a **záhrada** (bubliny, prúd, rozptýlenie,
  minihry 6–8, vlna LH, vrchol), pod nimi guma. Klik na skupinu vyberie jej
  posledný nástroj a hneď otvorí menu s ostatnými. Názvy ukáže tooltip.
- mriežka vypĺňa celú plochu vpravo, koniec levelu je zvýraznený zelenou
  čiarou a pásom „END OF LEVEL“,
- hore v lište sú akcie levelu: test, použiť v hre, späť na pôvodný level,
  načítať level hry, nový, pridať riadky, import, export, uložiť do repa
  (názov ukáže tooltip),
- ľavé tlačidlo myši kreslí, pravé maže, koliesko scrolluje,
- **Test Level** (alebo Enter) spustí test levelu priamo v hre; späť sa vrátiš
  tlačidlom **Back to editor**, Enterom alebo Esc,
- **Use in game** použije upravený level v hre (do obnovenia stránky),
- **Export** level skopíruje a stiahne ako `cave.txt`. Ten stačí vložiť do
  promptu („nahraď level týmto“) alebo do `godot/data/levels/cave.txt`.
- **Save to repo** (posledná ikona) level rovno commitne do repa (pozri nižšie);
  uloží sa ten level, ktorý je vybraný v hlavičke.

V developer menu sú aj skratky: preskočiť intro, checkpointy jaskyne aj
záhrady, skok na bossa s ľubovoľným počtom železa. V hre: `1–4` checkpoint,
`Shift+2–5` skok na minihru / bossa / vlnu, `G` záhrada s power-upmi.

## Testovanie animácií

**Developer mode → Animations:**

- Hore vľavo je výber **animácie** (beh, chôdza, státie, skok, bočný skok,
  dvojskok, pád, pozeranie dole, sed, bolesť, smrť, visenie). Pod ním je výber
  **variantu** a ikony **nový variant z PNG**, **duplikovať**, **premenovať** a
  **zmazať**.
- Pod tým je zoznam snímok. Pri každej je **vybrať z assetov**, **nahradiť**
  (upload z počítača), **posunúť hore/dole** a **odstrániť**. **Upload frames…**
  pridá PNG z počítača za vybranú snímku (dajú sa aj pretiahnuť do okna).
  **From assets…** ich pridá z repa.
- **Prehliadač assetov** ukazuje obrázky z repa (`assets/images`, uložené
  varianty v `assets/anim_test/…`) a obrázky nahraté v tomto prehliadači. Má
  filter podľa názvu. Klik na obrázok ho priradí k snímke.
- Ikona vpravo hore v náhľade mení **pozadie náhľadu** (napr. les alebo
  jaskyňa z assetov, alebo žiadne). Pamätá si ho tento prehliadač. Úprava originálu vytvorí kópiu
  „original edit“, pôvodné obrázky sa neprepíšu.
- Vpravo je náhľad. **Animation** prehráva vybranú animáciu. **Pause/Play**,
  medzerník alebo klik do náhľadu ju zastaví. ◀ ▶ (alebo šípky) krokujú po
  snímkach a klik na snímku v zozname zastaví animáciu presne na nej. **Gameplay** ukáže postavu, ako
  beží a skáče, alebo ju ovládaš šípkami a medzerníkom. Posuvníky menia rýchlosť
  behu, tempo snímok, snímky za sekundu pri pózach a veľkosť postavy.
- Neuložené varianty sú len v tvojom prehliadači (značka *• unsaved*).
- **Use in game** ich použije v hre do obnovenia stránky.
- **Save to repo** ich uloží natrvalo:
  - PNG idú do `godot/assets/anim_test/`, nastavenia do
    `godot/data/anim_variants.json`.
  - Vybrané varianty a posuvníky sa stanú predvolenými v hre pre všetkých.

## Ukladanie z prehliadača do repa

**Save to repo** v animáciách a ikona commitu v hlavičke level editora urobia
commit priamo do `bliksa/keeper`. Level sa uloží do `godot/data/levels/cave.txt`.
Hra sa potom sama zbuildí a o pár minút je na webe.

Pri prvom uložení sa hra opýta na GitHub token. Ostane uložený len v tom
prehliadači. Vytvoríš ho takto:

1. github.com → Settings → Developer settings → **Fine-grained tokens** →
   Generate new token.
2. Repository access: **Only select repositories → bliksa/keeper**.
3. Permissions → Repository permissions: **Contents → Read and write**.

Neplatný token sa zabudne a hra si pri ďalšom uložení vypýta nový.

## Lokálne

```
tools/test.sh          # stiahne Godot 4.4.1 (headless), spustí test celej hry
tools/export_web.sh    # web build do build/web
python3 -m http.server -d build/web 8000   # http://localhost:8000
```

Projekt sa dá otvoriť aj v Godot editore (`godot/project.godot`). Nové uzly ale
radšej pridávaj v kóde, nie do `.tscn`, aby sa projekt dal ďalej upravovať promptami.

## Credits

Nápad: Nataša Juračková · Kód: Michal Kabát & Klaara · Vizuál: Alexandra Pavelová,
Alexandra Just, Barbora Grellová, Hana Filipovičová, Emma Čičáková · Zvuk: Tomáš
Farkaš · Hlasy: Aďa Farkašová, Alicka Farkašová. Písmo Comfortaa (SIL OFL,
`godot/assets/fonts/OFL.txt`). Ikony editora Lucide (ISC,
`godot/assets/ui/icons/LICENSE-lucide.txt`).
