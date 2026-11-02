# Dynastia — progress

Źródło wizji: plik `intro` (filary, model danych, zakres MVP). Ten plik to stan prac i kolejność dalszych kroków — sugestia, nie dogmat.
Wizja: `docs/design/vision.md` (najwyższe źródło prawdy), model rodu: `docs/design/family-dynamics.md`, decyzje: `docs/adr/`, terminy: `GLOSSARY.md`.

> Kierunek (02.11.2026): obecne MVP za bardzo przypomina grę o osadzie. Następny etap to dynamika rodu (więzi, przynależność, uwaga jako czas w świecie) według `docs/design/family-dynamics.md`, potem społeczeństwo (targ, praca i lokum jako relacje z konkretnymi ludźmi z innych rodów, a nie abstrakcyjne systemy).

## Jak uruchomić

- Gra: `godot` w katalogu projektu (scena `game/main.tscn`) albo F5 w edytorze.
- Testy sim (headless): `godot --headless --script res://tests/run_tests.gd`
- Sonda balansu: `godot --headless -s res://tools/probe.gd -- <dni> <seed> <strategia>` (strategie: `default`, `wood2`, `craft`, `labor`, `thief`, `forage`, `none`) — drukuje dzienną kasę, zapasy, zdarzenia.
- Zrzuty ekranu: `SHOT_DIR=/ścieżka godot --audio-driver Dummy -s res://tools/screenshot.gd` (wymaga wyświetlacza).

## Stan (02.11.2026) — grywalne MVP, przekrój pionowy

Zamiast domykać etapy po kolei, zrobiony jest jeden spójny przekrój przez etapy 3–9 w uproszczonej formie, żeby dało się grać. Poprzednia implementacja etapu 2 (anonimowi agenci, licznik drewna, nieczytelny render) została zastąpiona.

Pętla gry: ród Wilków (6 osób, 3 pokolenia) w chacie pod lasem. Co 5 dni czynsz; trzeba karmić rodzinę, zimą palić w piecu. Pieniądze z drewna (drwal → tartak → tracz → deski → tragarz → targ), z krzeseł (stolarz; jakość = umiejętność, buduje reputację), z dniówki w dworze albo z kradzieży. Bieda prowadzi do długu, dług do aresztu; głód, zimno i choroby zabijają. Ślub, dzieci, starzenie, śmierć, sukcesja głowy rodu, koniec gry przy wygaśnięciu krwi.

### Zrobione

- [x] Czas: doba/sezon/rok, światło per sezon (praca po ciemku wolniejsza i groźniejsza), prędkości 1/2/4/8×, pauza; teren zmienia kolor z sezonem (zima = śnieg).
- [x] Osada (`sim/building.gd`, `sim/tree.gd`): budynki z zapasami i pojemnością, drzewa z rezerwacją i odrostem, chata/tartak/stolarnia/targ/dwór/areszt.
- [x] Agenci (`sim/agent.gd`, `sim/jobs.gd`): przydział pracy, plan krokowy, harmonogram (sen/praca/wolne), potrzeby (jedzenie, sen), obowiązki domowe, `idle_reason` zawsze ustawiony, alarm „!" przy problemie (ADR-0007).
- [x] Łańcuch drewno → deski → targ i deski → krzesła → targ; tragarz jako rola; wąskie gardła widoczne jako czekanie z powodem.
- [x] Ekonomia (`sim/household.gd`): gotówka, czynsz co K dni, dług z odsetkami, areszt za długi, ceny z nasyceniem dziennym (mały rynek), reputacja stolarska, zakup jedzenia i opału.
- [x] Survival: głód, zimno bez opału, choroby (zima/zimno/głód zwiększają szansę), zbieractwo w lesie jako darmowe jedzenie (zimą prawie nic).
- [x] Ród (`sim/family.gd`, `sim/person.gd`): wiek i etapy życia, traity z danych (wpływ na pracę, zdrowie, wypadki, jakość), dziedziczenie traitów, drzewo (rodzice, historia małżeństw), ślub z kandydatem materializowanym deterministycznie na żądanie, ciąża i poród z ryzykiem, śmierć ze starości, sukcesja (potomkowie zmarłego, dorośli, starsi; małżonek nigdy), koniec gry przy wygaśnięciu krwi.
- [x] Ryzyko: wypadki przy wyrębie/pile/stolarce zależne od umiejętności, traitów i ciemności; lekki/ciężki uraz (trwałe „kulawy"), śmierć.
- [x] Lekka przestępczość: złodziej na targu, szansa złapania (umiejętność, ciemność), areszt, grzywna, spadek reputacji, wybór: kaucja albo odsiadka.
- [x] Interfejs przez świat: kamera ortogonalna izo (ADR-0006), panel rodu, panel osoby/budynku z poleceniami, etykiety zapasów nad budynkami, dymki z kwotami, dziennik, okna decyzji z auto-pauzą tylko przy krytycznych zdarzeniach, przejęcie ręczne (PPM: idź / zetnij drzewo).
- [x] Testy headless (45): determinizm, 30 dni bez zakleszczeń i bez agenta bez powodu, łańcuch produkcji daje dochód, brak dochodu = dług, sukcesja i koniec gry, ślub i narodziny, 30 lat życia bez awarii.

### Świadome uproszczenia względem `intro`

- Brak więzi (`Bond`), `strength`, rdzenia i dryfu — wszyscy w chacie są pod kontrolą gracza. To następny duży krok (filar 1).
- Jedno gospodarstwo i jedna chata; dorosłe dzieci nie wyprowadzają się (limit 12 osób w chacie hamuje nowe ciąże).
- Brak zleceń na obiektach (`Order`) — jest przydział pracy (ADR-0007). Cele zapasów chaty i sprzedaż desek ustawia się w panelu budynków.
- Drogi są dekoracją: brak wydeptywania i kosztu nawierzchni, brak sezonowego błota/śniegu w ruchu.
- Brak LOD, agregatów regionu i rodów w tle; sąsiedzi istnieją tylko jako źródło kandydatów do ślubu.
- Brak zapisu/odczytu gry.
- Jeden scenariusz. Scenariusz „sami na odludziu" (bez targu w zasięgu, polowanie/zbieractwo, bardzo trudny) — do dodania jako nowe dane.

## Iteracja 1 — dynamika rodu

Źródło: `docs/design/family-dynamics.md`. Format: **wejście → wyjście → weryfikacja**. Kolejność ma znaczenie: każda faza stoi na poprzedniej.

### Decyzje szkieletowe (zatwierdzone przez autora 02.11.2026)

- **S1. Ród jako osobny byt.** `SimLineage { id, name, root_id, members }`; `Person.lineage_id`. Gospodarstwo (kto mieszka razem, kasa wspólna) to osobny byt; ród może mieć ich 0..n. Przynależność zmieniają tylko zdarzenia.
- **S2. Jeden magazyn więzi dla ludzi i czynności.** Rzadki słownik `(od, cel) → Bond`, gdzie cel to id osoby albo klucz czynności/miejsca (`act:saw`, `place:sawmill`).
- **S3. Wspomnienie.** `{ kind, day, weight, permanent, with: [ids] }`. Tekst i wagi rodzajów wspomnień w `data/memories.json` (pod epoki i tłumaczenia). Wartość więzi = suma wag wspomnień z blaknięciem, liczona, a nie przechowywana osobno.
- **S4. Siła przynależności** liczona raz na dobę od roota po krawędziach pokrewieństwa i małżeństwa, ważona więziami (wzór z `intro` §5.1). Wyzwala odejście dopiero po utrzymaniu się poniżej progu przez kilka dni.
- **S5. Pieniądze.** `Person.purse` + `Household.cash`. Zarobek trafia do osoby, a część oddawana do wspólnej zależy od siły przynależności.

### Faza 0 — porządki pod nowy model

- [x] 0.1 Czas jak w Simsach: długości procesów w dobach w danych (ciąża ~3, etapy życia osobno) → `balance.json` bez przeliczania z „lat” → testy cyklu życia.
- [x] 0.2 Cechy kontra charakter: `people.json` dzieli `traits` (silny, chorowity…) i `character` (lojalny, porywczy, pamiętliwy, ambitny, ciekawski) → obie listy przy osobie → test wczytania i dziedziczenia.
- [x] 0.3 Wartości z kodu do nazwanych stałych i danych w plikach, których dotyka iteracja → brak liczb w środku logiki → przegląd. (`family.gd`, `world.gd`; `jobs.gd` przy D4, `hud.gd` przy E1.)

### Faza A — fundamenty danych

- [x] A1 `sim/lineage.gd` (S1) → ród startowy z rootem, `Person.lineage_id` → test: wszyscy startowi w rodzie gracza, root ustawiony.
- [x] A2 `sim/bonds.gd` (S2, S3): dodaj wspomnienie, wartość więzi z blaknięciem, ciężkie trwałe → test: asymetria, blaknięcie, trwałe nie blakną.
- [x] A3 `data/memories.json`: rodzaje wspomnień (waga, blaknięcie, szablon tekstu), modyfikatory od charakteru → test: pamiętliwy pamięta dłużej, porywczy mocniej przeżywa kłótnię.
- [x] A4 Więzi startowe: rodzina startowa dostaje wspomnienia z „przeszłości” (wychowanie, małżeństwo) → sensowne więzi na starcie → test: dzieci–rodzice dodatnie.

### Faza B — czas razem

- [x] B1 Wykrywanie wspólnego czasu: te same miejsce i czynność (praca, posiłek, wieczór) → licznik par → na koniec doby wspomnienie („pracowali razem w tartaku”) → test: dwoje w tartaku zyskuje więź, rozdzieleni nie.
- [x] B2 Wspólny posiłek wieczorny: blok kolacji, ród schodzi się w domu → okazja do czasu razem → test: obecni przy kolacji mają wspomnienie.
- [x] B3 Wspomnienia o czynnościach: praca tworzy więź z czynnością (wypadek mocno na minus, praca z lubianą osobą na plus); dzieci przeżywają mocniej → test: dziecko w tartaku z ojcem lubi tartak, po wypadku nie.
- [x] B4 Dryf: brak kontaktu blaknie ku „obcy”, nigdy niżej bez zdarzenia → test: izolowany traci więź, ale nie schodzi poniżej podłogi.

### Faza C — przynależność

- [x] C1 Siła od roota (S4) → wartość per osoba raz na dobę → testy scenariuszowe: łańcuch słabnie, gęsta sieć trzyma, małżonek nie wciąga swojej rodziny.
- [x] C2 Przełączanie roota na członka rodu → wyraźny znacznik w świecie i panelu → test: siła przeliczona od nowego roota.
- [x] C3 Odejście: siła poniżej progu przez N dni → nowy ród jednoosobowy z sobą jako rootem, poza kontrolą, wyprowadzka (na razie do chaty sąsiadów albo poza mapę), wpis w kronice → test: zaniedbany odchodzi, zadbany zostaje.
- [x] C4 Minimalny ród AI: odszedły żyje dalej na autopilocie (praca, jedzenie, sen) → test: żyje po odejściu i ma własne decyzje.
- [x] C5 Kronika rodu: trwały zapis ważnych zdarzeń (narodziny, śluby, śmierci, odejścia) oddzielony od dziennika bieżącego → test: odejście jest w kronice.

### Faza D — sygnały i wola

- [x] D1 Sakiewki (S5): wypłata do osoby, część do wspólnej kasy według siły → test: oddalający się oddaje mniej.
- [x] D2 Sygnały dryfu w zachowaniu: je osobno, wraca późno, unika kolacji, wieczór poza domem; słaby, opisowy `idle_reason` bez liczb → test: przy niskiej sile pojawiają się te zachowania.
- [x] D3 Preferencje: wyliczane z więzi do czynności i charakteru, z informacją skąd → test: preferencja wynika ze wspomnień.
- [x] D4 Wymiganie się: praca nielubiana albo przy słabej więzi trwa krócej, porzucana w połowie, z opisowym powodem; przydział wbrew woli zostawia wspomnienie → test: niechętny robi mniej, rozkaz wbrew woli ma ślad.
- [x] D5 Dzieci chodzą za lubianym dorosłym; gracz może nadpisać („idź z ojcem”) → test: dziecko z nadpisaniem idzie do tartaku z ojcem.

### Faza E — interfejs

- [x] E1 Panel osoby z zakładkami: Teraz / Wspomnienia (rozwijana lista) / Preferencje / Cechy i charakter, bez liczb → zrzut ekranu.
- [x] E2 Panel rodu pokazuje faktycznych członków rodu, root oznaczony, przycisk „ustaw jako roota” → zrzut ekranu.
- [x] E3 Podgląd kroniki (osobny panel, klawisz) → zrzut ekranu.
- [x] E4 Tryb debug (F3): ukryte liczby (więzi, siła) widoczne dla dewelopera → zrzut ekranu.

## Iteracja 2b — wieś, która żyje (BIEŻĄCA, przed resztą iteracji 2)

Źródło: `docs/design/living-village.md` (playtest i rozmowa 02.11.2026). Reszta iteracji 2 wstrzymana; H4 (pole) i H7 (praca u kogoś) wchodzą tu jako L, I1/I2 jako O2. Zasada: każdy skutek wynika z procesu w świecie, każdy punkt ma w weryfikacji „co gracz zobaczy”.

### Decyzje szkieletowe (zatwierdzone przez autora 02.11.2026)

- **S14. Pieniądze mają miejsce.** Kwota (liczba) leży w skrzyni (zapas `coin` budynku) albo w sakwie (`Person.purse`). Przenosi ją tylko osoba czynnością na miejscu. `Household.cash` to podgląd skrzyni domu. Członkowie biorą zapas „na okazję”; pełna sakwa nie jest sama w sobie dryfem.
- **S15. Umowa o pracę.** `SimContract { pracodawca (gospodarstwo), pracownik, miejsce, czynność, stawka/dobę, do_dnia }`. Pracodawca wystawia oferty (ile osób, za ile); AI wybiera najlepszą (stawka, droga, więź), za niską nikt nie przyjdzie. Wypłatę wręcza płatnik z gospodarstwa pracodawcy z sakwy na miejscu pracy; niezapłacony pamięta i odchodzi.
- **S16. Stragan z ladą.** Budynek z właścicielem, zapasem i cennikiem; sprzedaje tylko z kimś za ladą; niezwinięty na noc kusi złodziei. Targ = plac z miejscami na stragany. Transakcja `trade(kupujący, sprzedawca, stragan, towar, ilość)` tylko przy obu osobach na miejscu; cena z targowania między granicami (gracz ustawia min. sprzedaży i maks. kupna, AI liczy z potrzeb i kasy). `SimMarket` i zawór znikają; kupiec to ród, który skupuje hurtem i sprzedaje w detalu tą samą transakcją.
- **S17. Rozmowa** (`talk`) jako jedyne źródło więzi spoza domu i wspólnej pracy: dwie osoby w miejscu publicznym, stoją, dymek, wspomnienie.
- **S18. Romans** jako osobny kanał w `SimBonds` (`love:<id>`). Etapy z wartości i wspomnień: wpadł w oko → szuka okazji → zaloty → zgoda rodów → ślub. Znikają `seeking_spouse` i `marry_chance_per_day`.
- **S19. Pozycja społeczna** liczona (majątek w skrzyniach i budynkach + opinia innych), nie przechowywana.
- **S20. Brak klas rodów.** Dwór to budynek i przedsięwzięcie, nie rola. Zachowanie AI wynika z majątku i przedsięwzięć; znikają role zmieniające zachowanie (`gentry`, `merchant`, `idle_roles`). Każdy ród, także gracza, może dorobić się dworu.

### Faza K — skarbiec i sakwy

- [x] K0 „Nosiciel” → „tragarz” w danych, UI i dokumentach → grep pusty.
- [x] K1 Skrzynia (S14): kasa gospodarstwa jako `coin` w domu → test: suma pieniędzy w świecie stała; gracz widzi monety na etykiecie domu.
- [x] K2 Zakup przez sakwę: brak w sakwie → najpierw dom i skrzynia, płaci z sakwy, reszta zostaje na okazję albo wraca → test: bez pieniędzy w sakwie i bez wizyty w domu nie kupi; gracz widzi, jak ktoś zagląda do chaty przed targiem.
- [ ] K3 Zarobek do sakwy, oddanie do skrzyni to czynność w domu; ile oddaje i ile wydaje na siebie zależy od siły (D1 w świecie) → test: oddalający się oddaje mniej, zadbany oddaje mimo pełnej sakwy.

### Faza L — widoczna praca

- [ ] L1 Pola (`SimField`): działki na mapie z właścicielem, cykl pór roku → test: plon tylko w sezonie; pola zmieniają wygląd.
- [ ] L2 Robota polowa krokowa (orka, siew, żniwa na konkretnej działce), plon noszony do spichrza → gracz widzi ludzi na polu i tragarzy ze zbiorem.
- [ ] L3 Umowy (S15): oferty pracy, wybór AI według stawki, płatnik wręcza wypłatę; koniec `_labor` „w środku dworu” → test: płaca przechodzi z ręki do ręki, za mało płacisz — nikt nie przychodzi, niezapłacony pamięta.
- [ ] L4 Gracz wystawia oferty (ile osób, stawka) do własnego tartaku/pola → test + zrzut.
- [ ] L5 AI bez klas (S20): ród z majątkiem zatrudnia zamiast robić sam, reszta wybiera między ofertami, lasem, warsztatem i straganem → test: w godzinach pracy dorośli AI są poza domem; zero `idle_roles`.
- [ ] L6 Nadzór: członek rodu przy miejscu pracy jako nadzorca, pracownicy mniej się migają, jeden nadzorca na N ludzi (w danych) → test.

### Faza M — handel

- [ ] M1 Stragan (S16) jako budynek, także przy domu (z desek) → zrzut.
- [ ] M2 Przydział „za ladą”, zwijanie na noc → bez sprzedawcy nie ma sprzedaży.
- [ ] M3 Granice cen gracza (panel gospodarstwa), AI liczy swoje → test.
- [ ] M4 Kupujący obchodzą stragany (cena, odległość, więź) i się targują → test: tańszy wygrywa, przy równej cenie lubiany, bez porozumienia brak transakcji; gracz widzi ludzi przy ladzie i dymek z ceną.
- [ ] M5 Kupiec hurt → detal zamiast `SimMarket` → test: zarabia tylko, gdy marża pokrywa drogę.
- [ ] M6 Brak zbytu widoczny (towar zalega, „nikt nie kupuje”) → sonda.
- [ ] M7 Wozy wędrowne jadą drogą od krawędzi mapy i stają na targu jako stragan.

### Faza N — spotkania i romans

- [ ] N1 Rozmowa (S17) → test: obcy z targu się poznają, bez spotkań więź spoza domu nie rośnie.
- [ ] N2 Miejsca i czas wolny: karczma wieczorem (wydatek z sakwy), święto na placu co N dób; wolni od pracy członkowie rodu bywają.
- [ ] N3 Wpadnięcie w oko (S18): zakochany spędza wolny czas tam, gdzie bywa druga osoba.
- [ ] N4 Zaloty: wzajemność, prezent z sakwy → próg w obie strony uruchamia rozmowę rodzin.
- [ ] N5 Zgoda rodów i mezalians (S19); gracz dostaje okno tylko na tym etapie → test: mezalians trudny, ale możliwy.

### Faza O — mieszkanie

- [ ] O1 Rozkazy: wynajmij, kup, wyprowadź, wyrzuć, odejdź; koniec `free_house()` dla gracza → test + zrzut panelu domu.
- [ ] O2 Plac budowy i zlecenie domu (dawne I1/I2), budowlańcy na umowie z L3.

### Faza P — kradzież

- [ ] P1 Proces: upatrzenie celu (stragan, niezwinięty towar, sakwa w tłumie), obserwacja, moment bez patrzących.
- [ ] P2 Świadkowie (znajomy może przemilczeć), donos do strażnika, strażnik idzie aresztować → test.

### Faza Q — interfejs i balans

- [ ] Q1 Panele: dom (skrzynia, mieszkańcy), stragan, osoba (sakwa, umowa) → zrzuty.
- [ ] Q2 Sonda wsi na 60 dób: brak zakleszczeń, pieniądze krążą, rody AI przeżywają, ludzie widocznie pracują.

## Iteracja 2 — społeczeństwo (wstrzymana w połowie)

Cel: rodzina przestaje być oderwana od świata. Inne rody żyją z tych samych danych i tym samym kodem, popyt i ceny biorą się z ich pieniędzy i potrzeb, małżonek to ktoś, kogo się zna, a dom to aktywo, które można wynająć, kupić albo zbudować. Decyzje S6–S12 zatwierdzone przez autora (02.11.2026), S9 rozszerzona o kupców wędrownych, S13 dopisana (do potwierdzenia). Podział na punkty niżej (format jak w iteracji 1).

**Zakres towarów:** jedzenie lokalnie (pole → zboże → młyn → mąka → chleb; pole sezonowe), budulec: deski (są) i kamień, opał (jest), praca u kogoś jako relacja (nie towar). Czego okolica nie robi (np. żelazo, narzędzia, sól, sukno), przywożą kupcy wędrowni; nadwyżki wywożą. Woda: studnia jako miejsce w iteracji 3.

### Decyzje szkieletowe

- **S6. Gospodarstwo jako byt świata.** `SimHousehold { id, home_id, members, cash }`, wiele w świecie; ród ma ich 0..n. Kasa wspólna należy do gospodarstwa, nie do rodu. Sakiewki osób (S5) zostają. Odszedły zakłada własne gospodarstwo.
- **S7. Budynek jako aktywo.** `SimBuilding.owner` (osoba, ród albo nikt) i `tenant` (gospodarstwo). Czynsz i płace liczone **na dobę**, płacone konkretnej osobie lub gospodarstwu. Eksmisja przy długu, bezdomność jako stan, nie koniec gry.
- **S8. Rody AI pełne.** Kilka rodów startowych z danych, z ciałami na mapie, tym samym `SimFamily`/`SimBonds`/`SimJobs` co gracz. Gracz to tylko ród, któremu przypisano „player”. Różnią się decyzjami (AI wybiera prace, śluby, zakupy), nie modelem. Ich ludzie są w świecie wyraźnie odróżnieni od twoich.
- **S9. Rynek jako ludzie.** Kupiec to osoba z rodu kupieckiego z własną kasą i zapasem. Kupuje tylko, gdy ma pieniądze i zbyt; cena zależy od jego zapasu i kasy. Popyt mają konkretni kupujący (jedzenie, deski na budowę).
  **Kupcy wędrowni (import/eksport):** wóz z kupcem przyjeżdża zza krawędzi mapy według rozkładu z danych, z konkretną ofertą („kupię 20 desek po 3 zł”, „mam 10 sztabek żelaza”) i własną kasą. Stoi na targu przez określony czas, towar fizycznie się donosi i odbiera; potem odjeżdża i z nim towar. Nie zdążysz — przepada okazja. Kupcy żyją na mapie tylko w czasie pobytu (lekki LOD), ale to ludzie z imieniem, z którymi można mieć więź (stały odbiorca).
- **S10. Budowa.** Plac budowy jako byt: typ budynku z danych, lista materiałów i ilość pracy. Na razie tylko dom. Ród AI buduje, gdy jest za ciasno i ma pieniądze; gracz może zlecić budowę w wybranym miejscu. Tłok i prywatność wpływają na więzi (za ciasno: kłótnie, osobno: rzadszy wspólny czas).
- **S11. Małżeństwo z istniejącymi ludźmi.** Kandydaci to wolni dorośli z innych rodów w okolicy, uszeregowani po więzi (poznali się w pracy, na targu). Bez materializacji z powietrza; brak kandydatów to brak ślubu (szersza okolica przyjdzie z LOD).
- **S13. Receptury w danych.** Każda produkcja to wpis w `data/recipes.json`: budynek, czynność, wejścia, wyjścia, czas, umiejętność. Piłowanie i stolarka przechodzą z kodu (`_plan_producer`) do danych; młyn, piekarnia, kamieniołom to nowe dane i model, bez nowej logiki. Pole (cykl sezonowy) to osobny mały moduł.
- **S12. Ludzie z innych rodów w więziach.** Te same `SimBonds` i `SimTogether` dla wszystkich par, także między rodami (przyjaźń, wrogość, sąsiedzi). Siła przynależności liczona per ród od jego roota.

### Faza F — fundamenty świata (refaktor pod wiele rodów)

- [x] F1 `SimFamily` jako rejestr wszystkich ludzi i rodów: logika doby (wiek, poczęcia, sukcesja) per ród; okna decyzji i koniec gry tylko dla rodu gracza, ród AI wybiera następcę sam → test: dwa rody żyją niezależnie, śmierć roota AI nie pyta gracza.
- [x] F2 Gospodarstwa (S6): `SimHousehold` per dom (członkowie, kasa, spiżarnia w domu), `SimJobs` używa domu i kasy gospodarstwa agenta zamiast globalnych → test: dwa gospodarstwa mają osobne kasy i zapasy; odszedły zakłada własne.
- [x] F3 Budynek jako aktywo (S7): `owner`, `tenant`, czynsz i płace na dobę do konkretnej osoby/gospodarstwa; dług → eksmisja po N dobach → bezdomność (śpi pod gołym niebem, opisowy powód) → test: czynsz płynie do właściciela, eksmisja i bezdomność bez końca gry.
- [x] F4 Receptury w danych (S13): `data/recipes.json`, piłowanie i stolarka przeniesione z kodu → test: łańcuch działa jak wcześniej (sonda: podobny dochód), nowa receptura bez zmian w kodzie.

### Faza G — rody AI

- [x] G1 Rody startowe w danych (3–4 rody, domy zamiast dekoracji, członkowie, kasa) → wszyscy na mapie z domami → test wczytania i przypisań.
- [x] G2 Decyzje AI: wybór pracy według potrzeb i dostępnych miejsc, zakupy jedzenia i opału z własnej kasy, ślub i dzieci tymi samymi regułami → test: 30 dób bez zakleszczeń, każdy agent ma powód, rody AI nie głodują przy normalnych warunkach.
- [x] G3 Obcy odróżnieni w świecie (barwy rodu, oznaczenie przy imieniu), panel osoby z innego rodu bez poleceń → zrzut ekranu.
- [x] G4 Więzi między rodami (S12): wspólny czas i wspomnienia działają między rodami, siła przynależności liczona per ród od jego roota → test: sąsiedzi pracujący razem się lubią, nie zmienia to ich rodu.
- [x] G5 Małżeństwo z istniejącymi ludźmi (S11): kandydaci to wolni dorośli z innych rodów według więzi, kto się przenosi do kogo z danych, AI żeni się też między sobą; koniec materializacji kandydata → test: ślub łączy dwie istniejące osoby, bez kandydatów nie ma ślubu.

### Faza H — gospodarka

- [x] H1 Kupiec jako osoba (S9): własna kasa i zapas, kupuje tylko, gdy ma pieniądze i zbyt, cena z zapasu i kasy; zastępuje `household.sell` → test: kupiec bez pieniędzy nie kupi, cena spada z zapasem.
- [x] H2 Kupujący: gospodarstwa kupują jedzenie i opał u kupca za własne pieniądze → test: biedna okolica nie kupi desek, pieniądze krążą (suma w świecie stała bez importu/eksportu).
- [x] H3 Kupcy wędrowni: rozkład w danych, wóz z krawędzi mapy, oferta kupna/sprzedaży z ilością, ceną i terminem, towar donoszony fizycznie, odjazd z towarem → test: dostarczona oferta płaci, przegapiona przepada.
- [ ] H4 Pole (osobny moduł): siew wiosną, wzrost, żniwa latem, zboże do spichrza; zima bez plonów → test: plon tylko w sezonie, zaniedbane pole daje mniej.
- [ ] H5 Młyn i piekarnia z receptur: zboże → mąka → chleb, chleb jest jedzeniem → test: łańcuch daje chleb bez nowego kodu produkcji.
- [ ] H6 Kamieniołom z receptury: kamień jako budulec → test: kamień trafia do składu.
- [x] H7a Dwór jako pracodawca (zrobione wcześniej, bo bez tego gospodarka nie miała obiegu): dniówka płacona z kasy dworu, praca na folwarku daje plon (jedzenie, sezonowo) do spiżarni dworu, dwór sprzedaje nadwyżki kupcowi; bez pieniędzy nie zatrudnia (AI idzie do lasu).
- [ ] H7 Praca u kogoś: miejsce pracy ma właściciela, zatrudnia ludzi z innych gospodarstw, dniówka na dobę od pracodawcy do sakiewki pracownika; dwór to pracodawca, nie automat → test: płaca przechodzi od pracodawcy, pracodawca bez pieniędzy nie zatrudnia.

### Faza I — budowa i mieszkanie

- [ ] I1 Plac budowy (S10): typ budynku z danych (dom: deski, kamień, praca), materiały donoszone, budowlańcy pracują, gotowy budynek należy do zleceniodawcy → test: dom powstaje po dostarczeniu materiałów i pracy.
- [ ] I2 Kto buduje: ród AI, gdy ciasno i ma pieniądze; gracz zleca dom w wybranym miejscu (UI) → test + zrzut ekranu.
- [ ] I3 Tłok i prywatność: za dużo osób na dom → kłótnie (wspomnienia) między współlokatorami; osobny dom → mniej wspólnego czasu sam z siebie → test: ciasny dom daje kłótnie, przestronny nie.
- [ ] I4 Wyprowadzka w obrębie rodu: dorosły (np. po ślubie) zakłada nowe gospodarstwo rodu w wolnym domu → test: ród ma dwa gospodarstwa, przynależność bez zmian.

### Faza J — interfejs i balans

- [ ] J1 Panel domu: właściciel, mieszkańcy, czynsz, zapasy; panel osoby pokazuje gospodarstwo i sakiewkę → zrzut ekranu.
- [ ] J2 Panel targu: kupiec, ceny, wozy z ofertami i czasem do odjazdu → zrzut ekranu.
- [ ] J3 Sonda społeczeństwa: strategie gracza + 60 dób → brak zakleszczeń, pieniądze krążą (nie rosną bez końca), rody AI przeżywają → sonda i test długi.

## Iteracja 3 — codzienność i ciało

Zegar pór dnia zamiast godzin (tarcza jak w Don't Starve: poranek, dzień, zmierzch, noc, z długościami zależnymi od pory roku) razem z płynnymi fazami dnia. Zróżnicowany rytm dnia jak w RimWorldzie (różne pory snu i pracy, droga do domu trwa, kolacja nie jest natychmiastowa), temperatura i ubiór, kontrola poczęć (przełącznik, szanse w danych, nigdy 0 i 100%), cmentarze i pomniki, czytelna progresja doświadczenia, płeć jako składnik naśladowania dorosłych (`goals.md`).

## Dalej

1. [ ] Więcej łańcuchów produkcji (ruda → żelazo → narzędzia, zboże → mąka → chleb) i rozwój interesu (kolejne warsztaty, pracownicy) — sens dopiero przy realnym popycie z iteracji 2.
2. [ ] Wyjazdy (`away`) i powroty, pojednanie (okno decyzji), drzewo genealogiczne znanych osób.
3. [ ] Zapis/odczyt (serializacja `SimWorld` do JSON, wersjonowana) — po ustabilizowaniu modelu społeczeństwa.
4. [ ] Zlecenia na obiektach jako warstwa nad wykonawcą kroków.
5. [ ] Drogi jako mechanika (koszt ruchu, sezon, noc) i magazyn.
6. [ ] Zagrożenia, zaginięcia i porwania, ścieżki kariery (`goals.md`).
7. [ ] Scenariusz „odludzie”, mapa proceduralna, wybór epoki/miejsca/rodziny na starcie.
8. [ ] LOD i rody w tle, materializacja osób spoza okolicy.
9. [ ] Epoki jako dane i zmiana epoki w trakcie gry (nauka).
10. [ ] Księgowość jako miejsce pracy: księga przychodów i rozchodów, bez niej gracz zna tylko stan skrzyni (`living-village.md`).
11. [ ] Wózki, plecaki, potem auta jako towar zwiększający udźwig.

## Uwagi autora do wdrożenia (02.11.2026)

- [x] Rozkazy ręczne jako kolejka (PPM zastępuje, Shift+PPM dopisuje); po wykonaniu agent sam wraca do autopilota.
- [x] Doba trwa 10 min realnych przy 1× (`time.day_seconds`). Tempo życia bez zmian w czasie realnym (rok życia ≈ 4 min, `aging.days_per_year_of_life` = 0.4), więc pokolenia dalej mieszczą się w kilku godzinach; szanse rodzinne liczone na rok życia (`*_per_year`), czynności wydłużone tak, by dochód na dobę został podobny.
- [ ] Płynne fazy dnia: poranek, dzień, zmierzch, noc — długości zależne od pory roku, bez „pyk i ciemno".
- [ ] Czynsz nie jest osią gry: możliwy własny dom (bez czynszu) i możliwa eksmisja → bezdomność jako stan gry, nie koniec.
- [ ] Wartości w kodzie (render, UI, sim) wyniesione do dobrze nazwanych stałych / `data/*.json`.
- [ ] Później: półotwarte budynki albo podgląd wnętrza po kliknięciu, żeby toczyć grę w środku.

## Uwagi z playtestu iteracji 1 (02.11.2026)

Zrobione od razu:
- [x] Kamera za osobą (F, przycisk w panelu), „Pokaż głowę rodu” (R), większa korona roota.
- [x] Lista rodu po pokrewieństwie do roota (głowa, małżonek, dzieci, rodzice, rodzeństwo…) z opisem relacji.
- [x] „Nowa osoba w rodzinie”, nie „w chacie” (dom to jeden z wielu, ród jest kotwicą).

Największy ból: **abstrakcyjność, brak społeczeństwa.** Rodzina jest oderwana od świata, brak silnych potrzeb indywidualnych i społecznych (budowa domów, budynków), małżonek materializuje się z powietrza. → kandydat na następną iterację (patrz „Dalej” 1–2).

Do omówienia i zaplanowania:
- [ ] Targ bez stałego popytu: deski kupują konkretne rody, które ich potrzebują (np. budują chatę). Podaż i popyt, logistyka.
- [ ] Więcej łańcuchów jak w Cultures (ruda → żelazo → miecz, zboże → mąka → chleb). Obecny drewno → deski → sprzedaż autor lubi.
- [ ] Doświadczenie w zawodzie widoczne jak w Cultures (mechanika już jest: `skills`, `eff_per_level`; brakuje czytelności/progresji).
- [ ] Zróżnicowany rytm dnia jak w RimWorldzie: różne pory snu i pracy, dojście do domu trwa — kolacja nie może być „wszyscy natychmiast w domu”.
- [ ] Kontrola poczęć: przełącznik „starają się o dziecko / nie” zmienia szansę (nigdy 0% ani 100%), wartości w danych.
- [ ] Prywatność i tłok: wielopokoleniowy dom daje bliskość, ale i konflikty; za blisko — kłótnie, za daleko — oddalenie. Szukać balansu (osobne domy).
- [ ] Wrażliwość na temperaturę i ubiór (zimą nie w sukienkach).
- [ ] Opłaty dzienne zamiast co K dni: czynsz, wypłaty pracowników itd.
- [ ] Trupy i pamięć: cmentarze, pomniki.
- [ ] Rozwój biznesu (kolejne tartaki) — dopiero gdy świat ma realny popyt; teraz pieniądze nie mają na co iść.
- [ ] Ludzie AI muszą być odróżnialni od „swoich” w świecie.
- Zostaje jak jest: małe dziecko biega koło chaty (jak w Cultures).

## Otwarte pytania (z `intro` §15)

- Mechanika sporu o spadek.
- System walki i wojny.
- Medycyna i poziom opieki jako zależność od epoki.
- Reguły dziedziczenia i ról płci w epokach (dane czy kod).
- Skala liczebności LOD 0.
- Tytuł i warstwa artystyczna.
