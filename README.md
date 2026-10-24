# Keeper of the Cycle

Hra o cykle, kŕčoch a dýchaní. Pôvodný webový prototyp (`web-export/`) je
prenesený do **Godot 4.4**. Projekt sa upravuje **promptami cez Claude Code** a
každá zmena sa dá hneď vyskúšať v prehliadači.

**▶ Hrať:** https://bliksa.github.io/keeper/ (pôvodná webová verzia na
https://bliksa.github.io/keeper/original/)

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
| Level jaskyne | `godot/data/levels/cave.txt` (legenda v `godot/scripts/level_data.gd`) |
| Texty a preklady (SK/EN/PT) | `godot/data/i18n/*.json` |
| Dialógy (poradie, kto hovorí, tlačidlá) | `godot/data/dialogs.json` |
| Fyzika, správanie kŕčov, boss | `godot/scripts/screens/platformer.gd` |
| Minihry | `godot/scripts/minigames/` |
| Tok hry (čo nasleduje po čom) | `godot/scripts/main.gd` |

## Pauza

Počas hry **Esc** (na gamepade **Start**) otvorí menu: **Pokračovať**,
**Reštartovať hru** (nová hra od začiatku v lese), **Celá obrazovka / Ukončiť
celú obrazovku** alebo **Hlavné menu**.

## Level editor

Na úplne prvej obrazovke klikni na **DEV** (vedľa **Spustiť hru**) → **Level editor**:

- vľavo sú skupiny nástrojov: **plošiny** (plošina, bodák), **nepriatelia**
  (4 druhy kŕčov), **zberateľné** (železo), **eventy** (minihry, boss, nápoveda,
  dialógy) a **spawn a teleporty**, pod nimi guma. Klik na skupinu vyberie jej
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
- **Save to repo** (posledná ikona) level rovno commitne do repa (pozri nižšie).

V developer menu sú aj skratky: preskočiť intro, checkpointy, skok na bossa s
ľubovoľným počtom železa.

## Testovanie animácií

**Developer mode → Animations:**

- Hore vľavo je výber **animácie** (beh, chôdza, státie, skok, bočný skok,
  dvojskok, pád, pozeranie dole, sed, bolesť, smrť, visenie). Pod ním je výber
  **variantu** a ikony **nový variant z PNG**, **duplikovať**, **premenovať** a
  **zmazať**.
- Pod tým je zoznam snímok. Pri každej je **nahradiť** (upload), **posunúť
  hore/dole** a **odstrániť**. Tlačidlo **Add frames…** pridá snímky za
  vybranú (PNG môžeš aj pretiahnuť do okna). Úprava originálu vytvorí kópiu
  „original edit“, pôvodné obrázky sa neprepíšu.
- Vpravo je náhľad. **This animation** prehráva vybranú animáciu (klik na
  snímku ju zastaví presne na nej, ◀ ▶ krokuje). **Gameplay** ukáže postavu, ako
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
