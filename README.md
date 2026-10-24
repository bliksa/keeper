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
**Reštartovať hru** (nová hra od začiatku v lese) alebo **Hlavné menu**.

## Level editor

Na titulnej obrazovke klikni na **Developer mode → Level Editor**:

- ľavé tlačidlo myši kreslí, pravé maže, koliesko scrolluje,
- **Test Level** (alebo Enter) spustí test levelu priamo v hre; späť sa vrátiš
  tlačidlom **Back to editor**, Enterom alebo Esc,
- **Use in game** použije upravený level v hre (do obnovenia stránky),
- **Export** level skopíruje a stiahne ako `cave.txt`. Ten stačí vložiť do
  promptu („nahraď level týmto“) alebo do `godot/data/levels/cave.txt`.

V developer menu sú aj skratky: preskočiť intro, checkpointy, skok na bossa s
ľubovoľným počtom železa.

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
`godot/assets/fonts/OFL.txt`).
