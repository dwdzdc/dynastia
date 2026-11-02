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

- [ ] D1 Sakiewki (S5): wypłata do osoby, część do wspólnej kasy według siły → test: oddalający się oddaje mniej.
- [ ] D2 Sygnały dryfu w zachowaniu: je osobno, wraca późno, unika kolacji, wieczór poza domem; słaby, opisowy `idle_reason` bez liczb → test: przy niskiej sile pojawiają się te zachowania.
- [ ] D3 Preferencje: wyliczane z więzi do czynności i charakteru, z informacją skąd → test: preferencja wynika ze wspomnień.
- [ ] D4 Wymiganie się: praca nielubiana albo przy słabej więzi trwa krócej, porzucana w połowie, z opisowym powodem; przydział wbrew woli zostawia wspomnienie → test: niechętny robi mniej, rozkaz wbrew woli ma ślad.
- [ ] D5 Dzieci chodzą za lubianym dorosłym; gracz może nadpisać („idź z ojcem”) → test: dziecko z nadpisaniem idzie do tartaku z ojcem.

### Faza E — interfejs

- [ ] E1 Panel osoby z zakładkami: Teraz / Wspomnienia (rozwijana lista) / Preferencje / Cechy i charakter, bez liczb → zrzut ekranu.
- [ ] E2 Panel rodu pokazuje faktycznych członków rodu, root oznaczony, przycisk „ustaw jako roota” → zrzut ekranu.
- [ ] E3 Podgląd kroniki (osobny panel, klawisz) → zrzut ekranu.
- [ ] E4 Tryb debug (F3): ukryte liczby (więzi, siła) widoczne dla dewelopera → zrzut ekranu.

### Iteracja 2 (później)

Wyjazdy (`away`) i powroty, pojednanie (okno decyzji), drzewo genealogiczne znanych osób, pełniejsze rody AI, zapis/odczyt gry.

## Dalej (po dynamice rodu)

1. [ ] Społeczeństwo: kilka rodów w pełni symulowanych z tych samych danych; targ, praca i lokum jako relacje z konkretnymi ludźmi (kupiec ustala ceny, popyt z pieniędzy kupujących).
2. [ ] Budynki jako aktywa (0..n), wynajem od konkretnej osoby, eksmisja i bezdomność.
3. [ ] Zapis/odczyt (serializacja `SimWorld` do JSON, wersjonowana).
4. [ ] Zlecenia na obiektach jako warstwa nad wykonawcą kroków.
5. [ ] Drogi jako mechanika (koszt ruchu, sezon, noc) i magazyn.
6. [ ] Scenariusz „odludzie”.
7. [ ] LOD i rody w tle, materializacja osób spoza okolicy.
8. [ ] Epoki jako dane i zmiana epoki w trakcie gry (nauka).

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
