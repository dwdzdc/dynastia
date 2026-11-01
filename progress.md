# Dynastia — progress

Roboczy plan implementacji. Źródło: plik `intro` (wizja, filary, model danych, architektura, zakres MVP).
Faza: **planowanie** — nic nie jest zaimplementowane, ten plik tylko rozbija pracę na atomowe kroki.

## Decyzje i dokumentacja towarzysząca

Rozstrzygnięte decyzje domeny i architektury są zapisane osobno:

- `GLOSSARY.md` — terminologia domeny (kanoniczne terminy EN, opisy PL).
- `docs/adr/` — decyzje architektoniczne.

Kluczowe rozstrzygnięcia mające wpływ na kroki poniżej:

- Pełny determinizm w `sim/`: ten sam seed + te same akcje gracza → ten sam przebieg (ADR-0002).
- Jedna ciągła, chodzona mapa (Cultures-like), odległości skompresowane; LOD sterowany „okiem" (kamera + członkowie rdzenia), miejsca minimalnie abstrakcyjne (ADR-0003).
- Brak pola `attention`: uwaga to stan wyprowadzony (`last_interaction_day` + delegacja do pracy + liczebność rdzenia → dryf), nigdy w UI (ADR-0004).
- Leniwa materializacja relacji: relacje/więzi postaci LOD 0 do osób spoza ekranu nie są generowane, dopóki gracz nie zdobędzie o nich wiedzy (ADR-0005).
- `sim/logistics` niezależny od rodziny/traitów/więzi (ADR-0001).

## Legenda statusu

- `[ ]` — do zrobienia
- `[x]` — zrobione

## Zasady pracy (obowiązują przez cały projekt)

- Jeden etap = jeden commit (lub gałąź). Każdy etap kończy się działającym stanem i testami logiki symulacji.
- Po każdym etapie — krótki opis decyzji architektonicznych (ADR).
- Nie wolno przechodzić do następnego etapu bez spełnionych kryteriów akceptacji.
- Przy niejasności projektowej — pytać, nie zgadywać.
- Kolejność etapów wynika z ryzyka: logistyka z autonomicznymi agentami (najwyższe ryzyko: korki, zakleszczenia) jest prototypowana **przed** tożsamością i więziami.
- Stałe balansu wyłącznie w `data/balance.json` — zero stałych w kodzie.
- RNG wyłącznie deterministyczny (seed świata) — zakaz `randi()` w `sim/`.
- Podział katalogów: `sim/` (czysta logika, RefCounted, headless), `data/` (JSON), `game/` (sceny, agenci, nawigacja, kamera), `ui/` (ikony, menu, dziennik, drzewo rodziny), `tests/` (GUT lub własny runner).
- Wymóg diagnostyczny (globalny, dotyczy każdego agenta od etapu 2): każdy agent trzyma `idle_reason` i pokazuje go po kliknięciu. Żaden agent nie stoi bez widocznego powodu.

---

## Etap 0 — Szkielet

Projekt Godot 4, struktura katalogów, loader JSON, `data/balance.json`, deterministyczny RNG, runner testów.

- [x] Utworzyć projekt Godot 4.x (`project.godot`)
- [x] Utworzyć strukturę katalogów: `sim/`, `data/`, `game/`, `ui/`, `tests/`
- [x] Dodać `data/balance.json` z kilkoma początkowymi stałymi
- [x] Zaimplementować loader JSON wczytywany do `sim/`
- [x] Zaimplementować deterministyczny RNG: `hash(seed, id, purpose)`
- [x] Dodać runner testów (własny, bez GUT)
- [x] Test: ten sam `seed` → ten sam wynik

**Akceptacja:** projekt się uruchamia; test sprawdza, że ten sam seed daje ten sam wynik.

---

## Etap 1 — Czas

Zegar symulacji, doba, sezony, rok, długość światła per sezon, pauza i prędkości.

- [x] Klasa zegara symulacji (`sim/`) — własny zegar, niezależny od FPS
- [x] Doba / sezon / rok ze stałymi z `balance.json` (doba = N s, sezon = M dób, rok = 4 sezony)
- [x] Długość dnia/zmierzchu/nocy zależna od sezonu
- [x] Prędkości: pauza, 1x, 2x, 3x
- [x] Prosty widok: pasek czasu
- [x] Widok: zmiana oświetlenia wg pory dnia/sezonu
- [x] Test headless: przewinięcie 10 lat gry

**Akceptacja:** test headless przewija 10 lat; wizualnie widać zmianę długości dnia między sezonami.

---

## Etap 2 — Świat i anonimowi agenci

Mapa 2D, nawigacja, agenci według harmonogramów i potrzeb; przejęcie ręczne; `idle_reason`.

- [x] Mapa 2D z góry: wieś, las, miasteczko (placeholdery — kolorowe kształty)
- [ ] Nawigacja agentów (`NavigationAgent2D`) — przesunięta do Etapu 3 (razem z drogami/przeszkodami); teraz dojazd liniowy liczony deterministycznie w `sim/`
- [x] Agent anonimowy: tylko `id`, wiek, umiejętności, potrzeby (bez traitów, rodzin, więzi)
- [x] Harmonogram bloków (sen, praca, dom, wolne) — uproszczony do faz dnia; pełny utility-based w Etapie 3
- [x] Potrzeby (sen, jedzenie) sterujące zachowaniem
- [x] Ruch i praca agentów
- [x] Przejęcie ręczne dowolnego agenta
- [x] `idle_reason` w stanie każdego agenta + widok po kliknięciu
- [x] Kamera i widok mapy

**Akceptacja:** osada sama żyje dobę i noc; kliknięcie agenta mówi, co robi albo na co czeka.

---

## Etap 3 — Logistyka i produkcja (osada bez rodziny)

Moduł `sim/logistics`, niezależny od rodzin/traitów/więzi. Łańcuch drewno → deski → sprzedaż.

- [ ] Moduł `sim/logistics`: zna tylko agentów, budynki, towary, drogi, zlecenia
- [ ] Budynki zgłaszają zapotrzebowanie i nadwyżki (wejścia produkcji, jedzenie, opał)
- [ ] Parowanie popytu z podażą → zlecenia transportu
- [ ] Magazyny i bufory (towar bez magazynu psuje się/ginie)
- [ ] Drogi: wydeptywanie, koszt ruchu (nawierzchnia, sezon, noc)
- [ ] Nosiciel jako rola (nie typ jednostki) — może być robotnik lub członek rodziny (rodzina dochodzi w etapie 7)
- [ ] Kolejka zleceń (worker bierze wolny kompetentny człowiek)
- [ ] Menu kontekstowe na obiektach (lista prac, np. „uszyj czapkę z wełny")
- [ ] Łańcuch drewno → deski → sprzedaż: 3 budynki, 2 towary
- [ ] Wpływ sezonu i nocy na transport
- [ ] Test headless: brak agenta bezczynnego dłużej niż próg, brak towaru bez zlecenia przy wolnym nosicielu, brak surowca = oczekiwanie (nie zakleszczenie)

**Akceptacja:** osada działa 30 dni gry bez ręcznej ingerencji; logistyka działa jako osada bez rodziny zanim dojdzie tożsamość (etapy 5–7).

---

## Etap 4 — Ekonomia

Gospodarstwo domowe, koszty stałe, jedzenie/opał zimą, sprzedaż na targu, jakość i reputacja.

- [ ] Jednostka `Household`: kto mieszka razem, `dwelling_id`, czynsz/koszty stałe, spiżarnia, gotówka, dług
- [ ] Koszty stałe co K dni (czynsz — pętla napięcia, kalendarz widoczny)
- [ ] Konsumpcja jedzenia i opału (nasilona zimą)
- [ ] Sprzedaż na targu
- [ ] Jakość produktu wpływa na cenę
- [ ] Reputacja lokalna per sfera (`reputation{sphere: value}`)

**Akceptacja:** rodzina bez dodatkowego dochodu bankrutuje w przewidywalnym czasie; z rzemiosłem może rosnąć.

---

## Etap 5 — Ludzie i drzewo genealogiczne

`Person` jako warstwa tożsamości nałożona na agentów z etapu 2.

- [ ] Traity jako dane (`id`, wpływ na skille, szanse, więzi) — pliki w `data/`
- [ ] Umiejętności per osoba (`skills{skill: level}`)
- [ ] Drzewo genealogiczne: krawędzie `parent_of(parent, child)` i `Union(a, b, start_day, end_day?, kind)` — fakty, nic nie jest kasowane
- [ ] Starzenie: `dni_na_rok_życia`, progi etapów (dziecko/nastolatek/dorosły/starzec) w configu
- [ ] Śmierć (`death_day`)
- [ ] Generator początkowej populacji (deterministyczny, hashowany)
- [ ] Integracja: `Person` jako tożsamość nad agentami z etapu 2
- [ ] Test headless: symulacja 100 lat bez rąk gracza

**Akceptacja:** 100 lat bez gracza nie wywala się; populacja nie wybucha ani nie wymiera; wiek zgadza się ze stałymi; logistyka z etapu 3 nadal działa.

---

## Etap 6 — Więzi i rdzeń (cohesion)

Skierowane więzi, `strength`, statusy, dryf, root, sukcesja.

- [ ] `Bond(from, to)` z `value` (−100..100) i `reasons[]` (dlaczego)
- [ ] Przechowywanie rzadkie (tylko pary z historią), nie macierz N×N
- [ ] Obliczanie `strength` iteracyjnie z tłumieniem; przycinanie gałęzi poniżej `min_strength`
- [ ] Statusy od `strength`: `core`, `attached`, `worker`, `independent`, `estranged`
- [ ] Reguła małżonka: wnosi tylko siebie i dzieci (jego rodzice/rodzeństwo nie wchodzą)
- [ ] Rozstanie → `end_day` → wypadnięcie przez próg bez szczególnych przypadków
- [ ] Budżet uwagi na dobę + dryf (szybszy przy większym rdzeniu; tylko do podłogi „obcy")
- [ ] Root i kandydaci na sukcesję (potomek krwi wg reguły epoki; małżonek nigdy)
- [ ] Sukcesja z bezpiecznikiem: kamera → potomek krwi → najwyższa siła; game over tylko przy braku potomka
- [ ] Testy scenariuszowe: (a) liniowa rodzina traci łańcuch, (b) gęsta sieć trzyma, (c) małżonek nie wciąga rodziny, (d) śmierć roota przenosi kamerę, (e) wygaśnięcie linii = game over

**Akceptacja:** wszystkie scenariusze (a)–(e) przechodzą.

---

## Etap 7 — Rodzina w ruchu

Zamiary, małżeństwa, porody z ryzykiem, wychowanie, dziedziczenie podstawowe, rodzina jako siła robocza.

- [ ] Zamiary na ludziach: „zaprzyjaźnij się", „flirtuj", „unikaj", „ucz się" (nie czynności)
- [ ] Rozstrzyganie zamiarów: traity, nastrój, relacje
- [ ] Małżeństwo (`Union`)
- [ ] Poród z ryzykiem
- [ ] Wychowanie dzieci
- [ ] Dziedziczenie podstawowe: zdarzenie śmierci głowy odpytuje graf więzi, bliscy dzielą majątek
- [ ] Członek rodziny jako nosiciel/robotnik zamiast najętego pracownika
- [ ] Koszt/kompromis: godzina noszenia = godzina niezużyta na rzemiosło/naukę/dzieci/więzi
- [ ] Test: pełny cykl 2 pokoleń

**Akceptacja:** pełny cykl dwóch pokoleń bez ręcznej ingerencji w dane; praca rodziny zamiast najętych widocznie zmienia koszty i więzi.

---

## Etap 8 — Ryzyko

Wypadki, choroby, urazy; fazy przygotowanie/wykonanie/następstwa jako wspólna infrastruktura.

- [ ] Wspólna infrastruktura faz: przygotowanie / wykonanie / następstwa
- [ ] Wypadki w pracy — zależne od zawodu, warunków, doświadczenia, narzędzi
- [ ] Choroby
- [ ] Urazy ze stopniami pośrednimi
- [ ] Uraz zmienia możliwości postaci (np. kaleki drwal też może być księgowym)

**Akceptacja:** wypadki zależą od zawodu i doświadczenia; uraz realnie zmienia możliwości postaci.

---

## Etap 9 — Lekka przestępczość

Kradzież i przemyt, wykrywalność, areszt, kaucja, wyrok, konsekwencje dla rodziny.

- [ ] Zlecenie kradzieży
- [ ] Przemyt
- [ ] Wykrywalność (okolica, obserwatorzy)
- [ ] Areszt
- [ ] Faza następstw: kaucja / adwokat / przekupstwo / zastraszenie świadków / ucieczka
- [ ] Wyrok
- [ ] Konsekwencje dla rodziny

**Akceptacja:** złapanie otwiera fazę następstw, nie kończy historii.

---

## Etap 10 — LOD i materializacja

Agregaty regionu, rody w tle, materializacja na żądanie, determinizm, zapisywanie na stałe.

- [ ] Agregaty regionu (populacja wg zawodów/klas, ceny, surowość prawa, policja, lista rodów)
- [ ] LOD 2: osoba jeszcze nie istnieje (tylko agregat)
- [ ] LOD 1: rody w tle, zgrubnie (raz na sezon, statystycznie)
- [ ] LOD 0: pełna symulacja (obszar gracza)
- [ ] Materializacja na żądanie: `hash(world_seed, entity_id, purpose)`, deterministyczna
- [ ] Generowanie z ograniczeniami: wiek, rocznik, status, brak pokrewieństwa z już znanymi
- [ ] Materializowane osoby zapisywane na stałe (save)
- [ ] Awans społeczny = odblokowanie wyższego LOD

**Akceptacja:** ta sama osoba po wczytaniu save'a jest identyczna; sumy populacji w agregatach się zgadzają; generowanie nie łamie pokrewieństw ani wieku.

---

## Etap 11 — Interfejs i UX

Ikony zdarzeń, auto-pauza, dziennik, drzewo rodziny z więziami, wieczorne decyzje, sygnały dryfu.

- [ ] Ikony zdarzeń nad głowami/obiektami (zamiast okien)
- [ ] Auto-pauza tylko przy krytycznych zdarzeniach (wypadek, śmierć, areszt, propozycja ślubu)
- [ ] Dziennik zdarzeń jako oś czasu
- [ ] Widok drzewa rodziny z więziami
- [ ] Wieczorne decyzje: ograniczony czas wspólny (lekcje, rozmowy o pieniądzach, pub, nauka)
- [ ] Sygnały oddalania się członków rodziny
- [ ] Klik w ikonę → przybliżenie kamery; stan widoczny w zachowaniu i wyglądzie
- [ ] Warunek: pełna sesja bez wyskakujących okien poza krytycznymi

**Akceptacja:** da się zagrać pełną sesję bez wyskakujących okien poza krytycznymi.

---

## Etap 12 — Zapis i strojenie

Save/load z wersjonowaniem, tryb debug, dopracowanie `balance.json`.

- [ ] Serializacja stanu `sim/` do JSON, wersjonowana
- [ ] Save/load bez rozjazdów
- [ ] Tryb debug: podgląd ukrytych wartości (prawdopodobieństwa, postęp wiedzy)
- [ ] Dopracowanie `balance.json`
- [ ] Test: sesja kilku pokoleń zapisuje się i wczytuje bez rozjazdów

**Akceptacja:** sesja kilku pokoleń zapisuje się i wczytuje bez rozjazdów.

---

## Po MVP (kolejność do ustalenia)

- [ ] Wiedza i nauka (observacje, koncepty, nośniki, droga do wpływu)
- [ ] Cwaniactwo z sekretami i plotkami
- [ ] Większe przedsięwzięcia
- [ ] Półświatek z hierarchią dziedziczoną w rodzie
- [ ] Wojna
- [ ] Spór o spadek
- [ ] Druga epoka (test: wystarczą nowe pliki danych, bez zmian w kodzie)
- [ ] Rozszerzenie regionu do kraju

---

## Otwarte wątki techniczne (do etapów 2–3)

- [ ] Współgranie autopilota (harmonogramy bloków) z kolejką zleceń — robocza propozycja: harmonogram definiuje bloki dnia (sen/praca/dom/wolne), a zlecenia wypełniają blok pracy. Do potwierdzenia i doprecyzowania przy implementacji etapów 2–3, nie blokuje planowania.

## Otwarte pytania (z `intro`, sekcja 15)

- [ ] Mechanika sporu o spadek
- [ ] System walki i wojny (osobny tryb czy to samo co świat)
- [ ] Medycyna i poziom opieki jako zależność od epoki
- [ ] Reguły dziedziczenia i ról płci w epokach (dane czy kod)
- [ ] Dokładna skala liczebności: ilu ludzi w LOD 0 jednocześnie
- [ ] Tytuł i warstwa artystyczna

---

## Test sukcesu MVP

Po 2–3 pokoleniach gracz ma historie do opowiedzenia i czuje, że to jego rodzina. Śmierć kogoś z rdzenia coś znaczy.
