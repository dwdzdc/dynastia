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
- **Bieżące: Iteracja 6 — świat na mapie: RTS** (`progress.md`, `docs/design/rts-world.md`). R1–R8 zrobione (19.11.2026), czeka na playtest autora (R9). Główna scena to `game/rts/rts_main.tscn`: ciągła mapa 3D, ciężarówki wszystkich firm jako jednostki, ludzie gracza z zadaniami jak w Cultures (praca, dom, PPM: idź), firmy i ciężarówki gracza, koszty życia rodu, minimapa, Kurier. Logika gracza: `sim/rts/`. Silnik gospodarki z iteracji 5: `sim/econ/`, `data/economy.json`; państwa i polityki to klocki w `sim/econ/policies/` (nowa polityka = skrypt + linia w `EconState.POLICIES` + wpis w danych). Podgląd grafu `game/economy_view.tscn` to już tylko narzędzie. Autor nie chce grafów jako gry, tylko RTS z jednostkami.
- **Iteracja 7 (19.11.2026, zrobiona, czeka na playtest):** ciężarówki jeżdżą od budynku do budynku (`sim/econ/econ_layout.gd`: miejsca firm, dojazdy, obwodnice; gracz wozi z firmy do firmy, a towar dla własnej firmy idzie prosto do jej magazynu), trzy państwa z cłami (`EconMap._states`, polityka `import_tariff`), nieruchomości (`sim/econ/econ_housing.gd`: działki płacone gminie, kamienice na wynajem jako firmy aktorów, czynsz z ciasnoty, budownictwo indywidualne). Układ miasta (`"layout"`) jest teraz w `data/economy.json`, a nie w `rts.json`.
- **Zwrot 19.11.2026: nowy core** (sekcja „Core” na górze `docs/design/vision.md`, ma pierwszeństwo). Gra jest o budowaniu biznesu i własnej logistyki w wielkim, otwartym, żywym świecie (X4, Port Royale), w dzisiejszych czasach (bez zmiany epok), z wąskim kręgiem ważnych ludzi, pokoleniami i szarą masą najemnych. Dynamika rodu jest wspierająca, a średniowieczna wieś nieaktualna. Iteracje 1–4 powstały pod stary kierunek. Pierwszy kawałek pod nowy core to świat, który żyje sam (iteracja 5); następny to wpięcie gracza w ten świat, po playteście i rozmowie z autorem. Projekt był odłożony 03.11.2026, bo autor czuł, że gra rozjechała się z jego pomysłem.
- Wstrzymane: Iteracja 3b X8 — wieś bez gracza biednieje (pieniądze płyną do miast). Czeka na decyzję autora, jak pieniądze z miast mają wracać do wsi: (a) miasta kupują to, co wieś ma — rekomendacja Claude'a; (b) kredyt na start warsztatu; (c) mennica płaci producentom. Rozmawiając z autorem, opisuj problem słowami, nie kodami punktów.
- Zasady z rozmów (w `docs/design/vision.md`): świat nie zależy od gracza (game over gracza ≠ koniec świata; sonda `solo` to kryterium), monety tylko z procesu, Port Royale/X4 jako wzór, wiele dróg sukcesu (`intro` §7), menu budowy jak w Cultures.
- Testy RTS: `godot --headless --script res://tests/run_rts_tests.gd` (~1 min). Zrzuty gry: `SHOT_DIR=<katalog> godot --audio-driver Dummy -s res://tools/screenshot_rts.gd`.
- Pomiar świata: `godot --headless -s res://tools/probe_economy.gd -- <dni> <seed> [co_ile] [prof]` (720 dób ≈ 1–1,5 min). Kryteria „żyje” drukuje na końcu. Testy gospodarki: `godot --headless --script res://tests/run_econ_tests.gd` (~15 s).
- Lekcje z balansu gospodarki: cena ma być funkcją pokrycia zapasu, a nie całką (inaczej rośnie bez końca); popyt liczy tylko pieniądze, które kupujący ma; bez skarbu państwa świat upada w rok, bo zyski zbierają się u kapitalistów; firma bez gotówki potrzebuje właściciela, który patrzy na dzisiejsze ceny, a nie na stare straty; dywidenda nie może zabierać kapitału obrotowego, który właściciel zaraz musiałby dopłacić (jedyna huta świata tak padła i zakleszczyła stal); nowa inwestycja, którą wszyscy aktorzy widzą naraz, potrzebuje liczenia tego, co już się buduje.

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
