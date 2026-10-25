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
| Levely: jaskyňa (1), lúka (2), vrchol (3) | `godot/data/levels/cave.txt`, `meadow.txt`, `garden.txt` (legenda v `godot/scripts/level_data.gd`) |
| Texty a preklady (SK/EN/PT) | `godot/data/i18n/*.json` |
| Dialógy (poradie, kto hovorí, tlačidlá) | `godot/data/dialogs.json` |
| Fyzika, správanie kŕčov, boss | `godot/scripts/screens/platformer.gd` |
| Minihry | `godot/scripts/minigames/` |
| Tok hry (čo nasleduje po čom) | `godot/scripts/main.gd` |

## Levely a smery

Hra obieha cyklus ako kruh: level 1 ide **dole**, level 2 **doprava**, level 3
**hore** (a plánovaný level 4 **doľava**).

### Level 2: Lúka (folikulárna fáza, zľava doprava)

Po porazení Veľkého kŕču Kyra vstane, odíde doprava a ocitne sa na lúke po
daždi (Kráľovstvo Rastov podľa poznámok v game design dokumente). Sprevádza ju
**Iskra (FSH)**, malá bytosť z iskier.

- Plošiny sú vo viacerých vrstvách ako v jaskyni: schody hore a dole, ostrovy
  a kamene nad riekou, koruny stromov, skryté vysoké miesta so semienkami.
- **Rieka** pod plošinami je minulý cyklus, ktorý odteká: stará voda. Nie je to
  smrť: Kyra v nej pláva, môže aj proti prúdu, ale prúd ju stále unáša späť,
  takže skôr či neskôr musí pri hladine vyskočiť na plošinu a pokračovať
  skákaním.
- **Rosa (estrogén)** je nová voda, ktorú ráno nechalo na listoch hore; preto
  sa zbiera na vyšších plošinách a plní nádobu dole na obrazovke. Beh aj
  dvojskok Kyre z jaskyne ostávajú; nádoba odomyká niť: pri 25 % dosiahne
  ďalej, pri 50 % ťahá rýchlejšie, pri 75 % rosa vstrebe prvý zásah tieňa.
- **Svetelné semienka (folikuly)** sa nechytajú dotykom. Zamieriš myšou
  (na gamepade pravou páčkou), podržíš ľavé tlačidlo / `E` / `LB` a niť
  sústredenia semienko priťahuje. Keď pustíš priskoro, unikne. Semienka sú
  stále ťažšie: stoja, blikajú, plávajú, uhýbajú.
- **Tieňoví enemáci (stres)** prichádzajú, kým držíš niť. Zásah preruší
  sústredenie, vyleje vodu a **posunie bránu levelu ďalej** (stres oddiali
  ovuláciu). Pustiť niť alebo vyskočiť = tiene prejdú.
- **Notifikácie** spomalia, **tŕne** zrania (strata železa ako v jaskyni).
- **Minihry:** Pamätaj si čo najviac (3 kolá, rozpoznávanie predmetov),
  Chyť, čo potrebuješ (živiny na podušku, vyhýbaj sa bleskom), Priraď
  symptóm (dvojice jav a vysvetlenie s nápovedou pri chybe).
- **Brána** sa otvorí s plnou nádobou a 10 semienkami. Kyra vyleje vodu,
  vyrastie zlatý kvet, obraz sa rozžiari dobiela a nasleduje level 3.

### Level 3: Vrchol (ovulácia, hore)

Icy Tower: jedna krátka plošina na každom poschodí, čím vyššie, tým užšie.
**Rozbeh sa mení na výšku skoku** (z miesta vyskočíš jedno poschodie,
v plnom behu tri), **steny ťa odrazia** späť so zachovanou rýchlosťou (a pri
stene sa dá aj kopnúť do skoku), **vlna LH stúpa od začiatku** a zrýchľuje,
takže sa nedá zastaviť; pri dialógoch a minihrách počká a dá náskok. HUD
počíta **poschodia** a **kombo** za skoky cez dve a viac poschodí (pád ho
zruší). Každých 25 poschodí je plné „stage“ poschodie: tam sú minihry Tanier
so železom, Chyť rytmus a Signály tela (power-upy: vyšší skok, šprint, super
dvojskok) a tam sa vraciaš, keď ťa vlna dobehne. Na 200. poschodí vlna
zrýchli na finálny šprint, hore je vrchol a vajíčko.

Texty sú v troch jazykoch (`DIA_M*` lúka, `DIA_G*` vrchol, `MG5_*`–`MG10_*`).
Fakty treba dať skontrolovať odborníčke.

## Pocit z ovládania (level 2 a 3)

Oproti jaskyni (ktorá je presný port webovej verzie) majú lúka a vrchol
rýchlejšie zrýchlenie a brzdenie, coyote time (skok ešte chvíľu po zídení
z okraja), buffer skoku (stlačené tesne pred dopadom), variabilnú výšku skoku
(krátke stlačenie = nízky skok) a squash pri dopade. Konštanty `FEEL_*`,
`SWIM_*`, `SUMMIT_*`, `MOMENTUM_JUMP`, `WALL_*` a `WAVE_*` sú v
`godot/scripts/screens/platformer.gd`.

## Záloha

Hra pred levelom 2 je vo vetve `backup/v1-jaskyna` a hrateľná na
https://bliksa.github.io/keeper/v1/ (buildí sa z commitu `V1_SHA` v
`.github/workflows/web.yml`). Prvá verzia levelu 2 (záhrada hore) je vo vetve
`backup/v2-zahrada-hore`.

## Pauza

Počas hry **Esc** (na gamepade **Start**) otvorí menu: **Pokračovať**,
**Reštartovať hru** (nová hra od začiatku v lese), **Celá obrazovka / Ukončiť
celú obrazovku** alebo **Hlavné menu**.

## Level editor

Na úplne prvej obrazovke klikni na **DEV** (vedľa **Spustiť hru**) → **Level editor**:

- v hlavičke vyberieš, ktorý level upravuješ: **Cave** (jaskyňa), **Meadow**
  (lúka, vodorovný level, koliesko scrolluje do strany) alebo **Summit**
  (vrchol); každý má vlastné automatické uloženie,
- vľavo sú skupiny nástrojov: **plošiny** (plošina, bodák), **nepriatelia**
  (4 druhy kŕčov), **zberateľné** (železo), **eventy** (minihry, boss, nápoveda,
  dialógy), **spawn a teleporty**, **lúka** (rieka, semienko, minihry K/M/Q,
  brána) a **vrchol** (bubliny, prúd, rozptýlenie, minihry 6–8, vlna LH,
  vrchol), pod nimi guma. Klik na skupinu vyberie jej
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
lúky aj vrcholu, skok na bossa s ľubovoľným počtom železa. V hre: `1–4`
checkpoint, `Shift+2–5` skok na minihru / bossa / bránu / vlnu, `H` lúka s plnou
nádobou, `G` vrchol s power-upmi.

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
