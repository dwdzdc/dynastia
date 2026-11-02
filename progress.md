# Dynastia — progress

Źródło wizji: plik `intro` (filary, model danych, zakres MVP). Ten plik to stan prac i kolejność dalszych kroków — sugestia, nie dogmat.
Decyzje: `docs/adr/`, terminy: `GLOSSARY.md`.

## Jak uruchomić

- Gra: `godot` w katalogu projektu (scena `game/main.tscn`) albo F5 w edytorze.
- Testy sim (headless): `godot --headless --script res://tests/run_tests.gd`
- Sonda balansu: `godot --headless -s res://tools/probe.gd -- <dni> <seed> <strategia>` (strategie: `default`, `wood2`, `craft`, `labor`, `thief`, `forage`, `none`) — drukuje dzienną kasę, zapasy, zdarzenia.
- Zrzuty ekranu: `SHOT_DIR=/ścieżka godot --audio-driver Dummy -s res://tools/screenshot.gd` (wymaga wyświetlacza).

## Stan (02.11.2026) — grywalne MVP, przekrój pionowy

Zamiast domykać etapy po kolei, zrobiony jest jeden spójny przekrój przez etapy 3–9 w uproszczonej formie, żeby dało się grać. Poprzednia implementacja etapu 2 (anonimowi agenci, licznik drewna, nieczytelny render) została zastąpiona.

Pętla gry: ród Wilków (6 osób, 3 pokolenia) w chacie pod lasem. Co 5 dni czynsz; trzeba karmić rodzinę, zimą palić w piecu. Pieniądze z drewna (drwal → tartak → tracz → deski → nosiciel → targ), z krzeseł (stolarz; jakość = umiejętność, buduje reputację), z dniówki w dworze albo z kradzieży. Bieda prowadzi do długu, dług do aresztu; głód, zimno i choroby zabijają. Ślub, dzieci, starzenie, śmierć, sukcesja głowy rodu, koniec gry przy wygaśnięciu krwi.

### Zrobione

- [x] Czas: doba/sezon/rok, światło per sezon (praca po ciemku wolniejsza i groźniejsza), prędkości 1/2/4/8×, pauza; teren zmienia kolor z sezonem (zima = śnieg).
- [x] Osada (`sim/building.gd`, `sim/tree.gd`): budynki z zapasami i pojemnością, drzewa z rezerwacją i odrostem, chata/tartak/stolarnia/targ/dwór/areszt.
- [x] Agenci (`sim/agent.gd`, `sim/jobs.gd`): przydział pracy, plan krokowy, harmonogram (sen/praca/wolne), potrzeby (jedzenie, sen), obowiązki domowe, `idle_reason` zawsze ustawiony, alarm „!" przy problemie (ADR-0007).
- [x] Łańcuch drewno → deski → targ i deski → krzesła → targ; nosiciel jako rola; wąskie gardła widoczne jako czekanie z powodem.
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

## Następne kroki (proponowana kolejność)

1. [ ] Grać i stroić `data/balance.json` (sonda `tools/probe.gd` pomaga).
2. [ ] Zapis/odczyt (serializacja `SimWorld` do JSON, wersjonowana) — bez tego dłuższa rozgrywka boli.
3. [ ] Więzi i rdzeń (etap 6 z intro): `Bond` z powodami, `strength`, statusy, dryf; wieczorne decyzje jako źródło więzi; wyobcowani odchodzą z chaty.
4. [ ] Wyprowadzki i nowe gospodarstwa (dorosłe dzieci, druga chata do wynajęcia lub budowy).
5. [ ] Zlecenia na obiektach (stolarnia: „zrób N krzeseł", targ: „kup X") jako warstwa nad wykonawcą kroków.
6. [ ] Drogi jako mechanika (koszt ruchu, sezon, noc) i magazyn.
7. [ ] Scenariusz „odludzie" + przełączanie scenariusza w menu startowym.
8. [ ] LOD i rody w tle (etap 10), materializacja osób spoza chaty.

## Uwagi autora do wdrożenia (02.11.2026)

- [x] Rozkazy ręczne jako kolejka (PPM zastępuje, Shift+PPM dopisuje); po wykonaniu agent sam wraca do autopilota.
- [x] Doba trwa 10 min realnych przy 1× (`time.day_seconds`). Tempo życia bez zmian w czasie realnym (rok życia ≈ 4 min, `aging.days_per_year_of_life` = 0.4), więc pokolenia dalej mieszczą się w kilku godzinach; szanse rodzinne liczone na rok życia (`*_per_year`), czynności wydłużone tak, by dochód na dobę został podobny.
- [ ] Płynne fazy dnia: poranek, dzień, zmierzch, noc — długości zależne od pory roku, bez „pyk i ciemno".
- [ ] Czynsz nie jest osią gry: możliwy własny dom (bez czynszu) i możliwa eksmisja → bezdomność jako stan gry, nie koniec.
- [ ] Wartości w kodzie (render, UI, sim) wyniesione do dobrze nazwanych stałych / `data/*.json`.
- [ ] Później: półotwarte budynki albo podgląd wnętrza po kliknięciu, żeby toczyć grę w środku.

## Otwarte pytania (z `intro` §15)

- Mechanika sporu o spadek.
- System walki i wojny.
- Medycyna i poziom opieki jako zależność od epoki.
- Reguły dziedziczenia i ról płci w epokach (dane czy kod).
- Skala liczebności LOD 0.
- Tytuł i warstwa artystyczna.
