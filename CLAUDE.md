# Dynastia

Gra w Godot 4.7 (GDScript): ród próbujący przetrwać i wybić się w społeczeństwie, przez pokolenia. Dokumentacja, UI i komentarze po polsku; identyfikatory w kodzie po angielsku.

## Zanim cokolwiek zmienisz, przeczytaj

1. `docs/design/vision.md`: czym gra jest i czym nie jest, plus ustalenia z autorem. Najwyższe źródło prawdy.
2. `docs/design/family-dynamics.md`: model rodu (więzi, przynależność, uwaga, kronika). Rdzeń gry.
   `docs/design/goals.md`: cele długoterminowe (jeszcze nie do roboty, ale nie blokuj ich modelem).
   `docs/design/living-village.md`: ustalenia po playteście iteracji 2 i zasada „proces w świecie zamiast abstrakcyjnej funkcji”.
   `docs/design/wzorce-cultures.md`: jak naprawdę działa Cultures (z instrukcji i recenzji). Autor chce wiele elementów jak w Cultures: czytaj to, zanim cokolwiek „jak w Cultures” zrobisz. Czego tam nie ma, o to pytaj autora, nie zgaduj.
3. `progress.md`: stan, plan bieżącej iteracji (z decyzjami szkieletowymi) i kolejka dalszych kroków.
4. `intro`: pierwotny szkic (model danych, architektura, MVP). Ważny tam, gdzie powyższe go nie nadpisują.

Decyzje architektoniczne są w `docs/adr/`, terminy w `GLOSSARY.md`.

## Gdzie jesteśmy

- Iteracje 1, 2b (wieś, która żyje), 3 (gospodarka bez gracza) i 3b X1–X7 (świat, który trwa) są zrobione; autor jeszcze ich nie playtestował.
- **Bieżące: Iteracja 5 — świat, który żyje sam** (`progress.md`, `docs/design/world-economy.md`). E1–E9 i E11 zrobione (19.11.2026), czeka na playtest autora (E10). Kod: `sim/econ/` (sieć miast, rynki, firmy, ciężarówki, aktorzy z kapitałem, skarb państwa, wstrząsy, kronika, gazeta „Kurier”), dane `data/economy.json`, podgląd `game/economy_view.tscn` (główna scena). Stara wieś (iteracje 1–4) leży nietknięta w `game/main.tscn` i `sim/*.gd`.
- **Zwrot 19.11.2026: nowy core** (sekcja „Core” na górze `docs/design/vision.md`, ma pierwszeństwo). Gra jest o budowaniu biznesu i własnej logistyki w wielkim, otwartym, żywym świecie (X4, Port Royale), w dzisiejszych czasach (bez zmiany epok), z wąskim kręgiem ważnych ludzi, pokoleniami i szarą masą najemnych. Dynamika rodu jest wspierająca, a średniowieczna wieś nieaktualna. Iteracje 1–4 powstały pod stary kierunek. Następny krok to wybór pierwszego kawałka gry pod nowy core, razem z autorem. Projekt był odłożony 03.11.2026, bo autor czuł, że gra rozjechała się z jego pomysłem.
- Wstrzymane: Iteracja 3b X8 — wieś bez gracza biednieje (pieniądze płyną do miast). Czeka na decyzję autora, jak pieniądze z miast mają wracać do wsi: (a) miasta kupują to, co wieś ma — rekomendacja Claude'a; (b) kredyt na start warsztatu; (c) mennica płaci producentom. Rozmawiając z autorem, opisuj problem słowami, nie kodami punktów.
- Zasady z rozmów (w `docs/design/vision.md`): świat nie zależy od gracza (game over gracza ≠ koniec świata; sonda `solo` to kryterium), monety tylko z procesu, Port Royale/X4 jako wzór, wiele dróg sukcesu (`intro` §7), menu budowy jak w Cultures.
- Pomiar świata: `godot --headless -s res://tools/probe_economy.gd -- <dni> <seed> [co_ile] [prof]` (720 dób ≈ 1–1,5 min). Kryteria „żyje” drukuje na końcu. Testy gospodarki: `godot --headless --script res://tests/run_econ_tests.gd` (~15 s).
- Lekcje z balansu gospodarki: cena ma być funkcją pokrycia zapasu, a nie całką (inaczej rośnie bez końca); popyt liczy tylko pieniądze, które kupujący ma; bez skarbu państwa świat upada w rok, bo zyski zbierają się u kapitalistów; firma bez gotówki potrzebuje właściciela, który patrzy na dzisiejsze ceny, a nie na stare straty.

## Jak pracujemy

- Praca bezpośrednio na `master`. Po każdym skończonym punkcie planu: testy, commit, push. Commity bez podpisu (`git -c commit.gpgsign=false commit …`); lokalny `user.email` to noreply GitHuba (zostaw go).
- Odhaczaj punkty w `progress.md` w tym samym commicie, w którym je robisz.
- Każda liczba balansu trafia do `data/*.json`; stałe renderu i UI to nazwane `const` na górze skryptu. Nic magicznego w środku logiki.
- `sim/` to czysta, deterministyczna logika (RefCounted, bez Node, RNG wyłącznie przez `SimRng` z seeda). `game/` i `ui/` tylko czytają stan i wołają komendy `SimWorld`.
- Zmiany projektowe (nowa mechanika, zmiana modelu) najpierw omawiaj z autorem, a ustalenia zapisuj w `docs/design/`.

## Komendy

- Testy (headless, ok. 2–3 min): `godot --headless --script res://tests/run_tests.gd`
- Sonda balansu rodu gracza: `godot --headless -s res://tools/probe.gd -- <dni> <seed> <strategia>` (strategie są w pliku)
- Sonda całej wsi: `godot --headless -s res://tools/probe_village.gd -- <dni> <seed> [solo]`
- Zrzuty ekranu (wymaga wyświetlacza): `SHOT_DIR=<katalog> godot --audio-driver Dummy -s res://tools/screenshot_economy.gd` (podgląd świata) albo `tools/screenshot.gd` (stara wieś). Sprawdzaj nimi każdą zmianę wizualną.
- Odśwież cache klas po dodaniu `class_name`: `godot --headless --import`

## Pułapki GDScript w tym repo

- `var x := dict["k"]` i `:=` na wyniku metody nietypowanego obiektu nie kompilują się („Cannot infer the type”). Typuj jawnie: `var x: float = …`, `for t: SimTree in …`.
- Nie nazywaj metod ani zmiennych `log` (koliduje z funkcją wbudowaną). Dziennik to `SimWorld.note()` i `SimEvents.entries`.
- `SimJobs` i `SimFamily` trzymają `w: SimWorld`; cykliczne odwołania przez `class_name` działają.
