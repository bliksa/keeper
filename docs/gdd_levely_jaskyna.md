# GDD návrh B: Ďalšie levely z existujúcich dielov

Návrh, ktorý ostáva pri tom, čo hra už má: Kyra, Estra, jaskyňa, železo, kŕče,
dýchanie 4-2-6, tri typy minihier (skladačka, potrubie, priraďovanie) a Veľký
kŕč. Ďalšie levely sú ďalšie časti jaskyne, každá s inou sadou tém. Mechaniky
ostávajú, mení sa obsah dialógov, náplň minihier a náročnosť.

Alternatíva s novými mechanikami a svetmi je v `gdd_levely_fazy_cyklu.md`.

## Čo už level 1 pokrýva

Menštruácia z pohľadu tela: kŕče a dýchanie, cukor, voda a káva, cena produktov
a menštruačná chudoba, železo.

## Spoločné pre všetky levely

- Každý level začína krátkym dialógom Estry, ktorý nadväzuje na koniec
  predchádzajúceho. Estra je tá istá, Kyra je skúsenejšia, takže dialógy môžu
  byť kratšie a vtipnejšie.
- Dýchanie a železo sú v každom leveli, v leveloch 3 a 4 sa menej odpúšťa.
- Po každom bossovi je checkpoint, dá sa začať od ktoréhokoľvek levelu.
- Minihry používajú tri existujúce mechaniky s novým obsahom:
  - **skladačka** (ako čokoláda): poskladať obrázok alebo vetu;
  - **potrubie** (ako voda a káva): správne nasmerovať ku Kyre, nesprávne preč;
  - **priraďovanie** (ako ceny): priradiť dvojice, odhaliť dôsledok.
- Fakty v dialógoch dať skontrolovať odborníčke.

## Level 2: Produkty a mýty

- **Jaskyňa:** o niečo ťažšia než level 1, všetky štyri druhy kŕčov naraz, menej
  železa, dlhšie skoky s dvojskokom. Iná farba pozadia a plošín, aby bolo jasné,
  že je to nová časť jaskyne.
- **Témy:** menštruačné produkty a ako sa používajú (vložky, tampóny, kalíšok,
  nohavičky), ako často ich meniť; mýty o menštruácii.
- **Minihry:**
  1. skladačka: poskladať menštruačný „balíček do školy“ (čo mať v taške);
  2. potrubie: pravdu nasmerovať ku Kyre, mýty preč („nemôžeš plávať“, „šport
     škodí“, „nesmie sa o tom hovoriť“);
  3. priraďovanie: produkt → ako dlho vydrží / ako často ho meniť / koľko
     odpadu vznikne.
- **Boss:** Veľký kŕč rýchlejší, viac ostňov.

## Level 3: Telo a cyklus

- **Jaskyňa:** dlhšie skoky, úseky bez železa, kde treba šetriť.
- **Témy:** sledovanie cyklu a čo je v ňom normálne (dĺžka 21 až 35 dní,
  nepravidelnosť v prvých rokoch); čo cyklus rozhádže; kedy ísť k lekárke.
- **Minihry:**
  1. skladačka: poskladať kalendár cyklu, Estra vysvetlí fázy a dĺžku;
  2. potrubie: spánok a pohyb nasmerovať k telu, stres preč;
  3. priraďovanie: príznak → „bežné“ alebo „choď k lekárke“ (veľmi silné
     krvácanie, bolesť, ktorá nedá fungovať, vynechaná menštruácia).
- **Boss:** dva kŕče naraz, alebo kŕč, ktorý sa po zmenšení dýchaním znova
  nafukuje, kým sa ho hráč nezbaví.

## Level 4: Hovoriť o tom

- **Jaskyňa:** najťažšia, stúpanie von z jaskyne, na konci svetlo (symbolicky
  von zo stigmy).
- **Témy:** stigma, ako si vypýtať pomoc, ako podporiť kamarátku.
- **Minihry:**
  1. skladačka: poskladať vetu, ktorou si vypýtať pomoc (od rodiča, učiteľky,
     kamarátky);
  2. potrubie: podpora smerom ku kamarátke, posmech preč;
  3. priraďovanie: situácia → čo povedať alebo spraviť (kamarátka nemá vložku,
     chalan sa smeje, bolí na hodine).
- **Boss:** posledný súboj s Veľkým kŕčom. Záver: Estra uzavrie, že cyklus sa
  vráti, ale Kyra už vie, čo s ním.

## Rozsah

Štyri levely sú veľa obsahu. Začať levelom 2 a podľa toho, ako sa hrá,
rozhodnúť, či témy levelov 3 a 4 spojiť do jedného.

## Technicky

- Nový `godot/data/levels/level2.txt` (atď.) s rovnakou legendou ako
  `cave.txt`.
- Nové dialógy v `data/dialogs.json` a vo všetkých troch jazykoch
  v `data/i18n/`.
- Minihry: existujúce skripty v `scripts/minigames/` dostanú obsah podľa levelu
  (obrázok skladačky, popisy potrubia, dvojice na priraďovanie).
- `scripts/main.gd`: po bossovi pokračovanie do ďalšieho levelu, výber levelu
  v menu alebo v developer móde.
- Level editor: výber súboru levelu.
- Boss: parametre (rýchlosť, počet ostňov) podľa levelu v `platformer.gd`.
