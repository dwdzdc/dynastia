# Dynastia

Glosariusz domeny gry. Terminy kanoniczne są po angielsku (zgodnie z kodem i kluczami danych), opisy po polsku. To słownik pojęć — nie spec i nie notatnik decyzji; decyzje architektoniczne żyją w `docs/adr/`.

## Społeczność i krew

**Person**:
Osadzona istota ludzka — warstwa tożsamości (wiek, płeć, traity, skille, więzi, wiedza) nałożona na anonimowego agenta z symulacji ruchu.
_Avoid_: agent (animowany byt bez tożsamości).

**Trait** (cecha):
Cecha ciała albo talentu (silny, chorowity, zręczny, kulawy). Działa na ciało: pracę, zdrowie, wypadki. Część jest dziedziczna, część nabyta (uraz).

**Character** (charakter):
Usposobienie (lojalny, porywczy, pamiętliwy, ambitny, ciekawski). Działa na więzi, pamięć i wolę, a nie na ciało. Dziedziczny według tych samych reguł co cechy, osobna pula.
_Avoid_: trait (dla charakteru).

**House**:
Ród — nazwisko i przynależność prawno-społeczna; mogą do niego należeć osoby przez urodzenie, wżenienie albo adopcję, wg reguł epoki.
_Avoid_: klan, "rodzina" (nieostre).

**bloodline**:
Linia krwi — biologiczne pochodzenie wzdłuż krawędzi `parent_of`. To ją, nie `House`, czyta sukcesja i warunek game over; adopcja i wżenienie jej nie przedłużają.
_Avoid_: ród, dynastia (gdy chodzi o biologię).

**Household**:
Gospodarstwo domowe — kto mieszka razem; `dwelling_id`, koszty stałe/czynsz, spiżarnia, gotówka, dług.

## Więzi i przynależność

**Bond**:
Skierowana więź `from → to`: co `from` czuje do `to` (`value` −100..100) i dlaczego (`reasons[]`). Asymetryczna; przechowywana rzadko (tylko pary z historią).

**strength**:
Siła przynależności osoby do rdzenia gracza — wartość liczona iteracyjnie wzdłuż grafu pokrewieństwa i małżeństw, napędzana tym, co dana osoba czuje do sąsiadów. Gałęzie poniżej `min_strength` są przycinane.

**core** (rdzeń):
Wynik obliczenia przynależności — zbiór osób, które gracz kontroluje. To stan wyliczany, nie fakt jak drzewo genealogiczne.

**attached**:
Małżonek wżeniony. Kontrola ograniczona więzią, własne cele; nie może być rootem.

**worker** (status):
Członek przypisany do miejsca pracy — gracz wyznacza miejsce, resztę robi sam.
_Avoid_: nie mylić z `occupation` ani z rolą `carrier` (nosiciel).

**independent**:
Poza rdzeniem; sterowany przez AI.

**estranged**:
Wyobcowany; AI, może konkurować o spadek.

**drift**:
Dryf więzi — bezczynność/zaniedbanie obniża `Bond(członek→rdzeń)` ku podłodze „obcy"; rośnie szybciej przy większym rdzeniu. Nigdy nie schodzi do wrogości (to wymaga zdarzenia).

## Akcje i polecenia

**Order** (zlecenie):
Robocze polecenie na obiekcie (`verb`, `actor`, `target`, `params`, `state`, `cost`); trafia do kolejki i bierze je wolny kompetentny agent.

**Intent** (zamiar):
Społeczna dyrektywa na człowieku („zaprzyjaźnij się", „flirtuj", „unikaj", „ucz się"); rozstrzyga ją symulacja z traitów, nastroju i relacji. Odrębny byt od `Order`.

**Event** (zdarzenie):
Typ, uczestnicy, dzień i ważność (decyduje o ikonie i auto-pauzie).

## Wierność symulacji (LOD)

**LOD**:
Poziom wierności, z jaką świat odwzorowuje byt: 0 = pełna symulacja (obszar oka gracza), 1 = zgrubna (raz na sezon, statystycznie), 2 = tylko agregat (osoba jeszcze nie istnieje).

**eye** (oko):
To, co gracz widzi: ślad kamery plus obecność członków rdzenia. Definiuje focus i granicę LOD 0.

**focus area**:
Obszar w zasięgu oka — symulowany w pełni. Wszystko poza nim to fog of war.

**fog of war**:
Teren i byty poza okiem — nie renderowane, zamrożone w agregacie; ożywają deterministycznie przy powrocie oka.

**aggregate**:
Źródło prawdy o regionie gdy nie patrzy oko: populacja wg zawodów/klas, ceny, prawo, lista rodów. Sumy muszą się zgadzać z materializowanymi osobami.

**materialization**:
Deterministyczne wygenerowanie osoby (LOD 2 → 0; `hash(world_seed, entity_id, purpose)`) przy kontakcie gracza; zapisana na stałe i spójna niezależnie od kolejności.

**lazy data**:
Pole lub krawędź celowo nie-wygenerowane — np. relacje postaci LOD 0 do osób spoza ekranu — powstające dopiero, gdy gracz zdobędzie o nich wiedzę.

## Uwaga

**attention** (uwaga):
Miara zadbania o członka rodziny, nie waluta: wyłania się z `last_interaction_day`, oddelegowania do mechanicznej pracy i liczebności rdzenia. Nie ma pola w `sim/` i nie pojawia się w UI.
_Avoid_: budżet, punkty uwagi (jej nie wydajesz — o nią dbasz).

## Praca i plan dnia (MVP)

**job** (przydział):
Stała rola osoby nadana przez gracza (drwal, tracz, stolarz, nosiciel, zbieracz, dniówka, złodziej, bez przydziału). Wypełnia blok pracy w harmonogramie; reszta dnia to potrzeby i obowiązki.
_Avoid_: occupation (to fakt biograficzny), worker (status względem rdzenia).

**plan**:
Krótka kolejka kroków agenta (`walk` / `act` / `do`) zbudowana z przydziału, potrzeb i bloku dnia; przeliczana, gdy się skończy albo zmieni się sytuacja. Ostatni krok zawsze ma `idle_reason`.

**chore** (obowiązek domowy):
Zakup jedzenia i donoszenie opału, gdy zapas w chacie spada poniżej celu; robi to nosiciel, osoba bez przydziału albo każdy dorosły po pracy. Jedna osoba na raz (rezerwacja).

**scenario** (scenariusz):
Zestaw danych startowych: mapa, rodzina, reguły (czynsz, odległość od targu). MVP ma jeden („drwale pod wsią"); kolejne, np. „sami na odludziu", mają być nowymi plikami danych.
