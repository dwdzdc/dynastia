# Dynastia

Gra w Godot 4.7 (GDScript): ród próbujący przetrwać i wybić się w społeczeństwie, przez pokolenia. Dokumentacja, UI i komentarze po polsku; identyfikatory w kodzie po angielsku.

## Zanim cokolwiek zmienisz, przeczytaj

1. `docs/design/vision.md`: czym gra jest i czym nie jest, plus ustalenia z autorem. Najwyższe źródło prawdy.
2. `docs/design/family-dynamics.md`: model rodu (więzi, przynależność, uwaga, kronika). Rdzeń gry.
3. `progress.md`: stan, plan bieżącej iteracji (z decyzjami szkieletowymi) i kolejka dalszych kroków.
4. `intro`: pierwotny szkic (model danych, architektura, MVP). Ważny tam, gdzie powyższe go nie nadpisują.

Decyzje architektoniczne są w `docs/adr/`, terminy w `GLOSSARY.md`.

## Gdzie jesteśmy

**Iteracja 1 — dynamika rodu** (`progress.md`) jest zaimplementowana w całości (fazy 0, A–E) i czeka na test rozgrywki autora. Przed iteracją 2 zbierz jego uwagi i popraw balans (`data/memories.json`, `balance.json` → `belonging`, `will`).

## Jak pracujemy

- Praca bezpośrednio na `master`. Po każdym skończonym punkcie planu: testy, commit, push. Commity bez podpisu (`git -c commit.gpgsign=false commit …`); lokalny `user.email` to noreply GitHuba (zostaw go).
- Odhaczaj punkty w `progress.md` w tym samym commicie, w którym je robisz.
- Każda liczba balansu trafia do `data/*.json`; stałe renderu i UI to nazwane `const` na górze skryptu. Nic magicznego w środku logiki.
- `sim/` to czysta, deterministyczna logika (RefCounted, bez Node, RNG wyłącznie przez `SimRng` z seeda). `game/` i `ui/` tylko czytają stan i wołają komendy `SimWorld`.
- Zmiany projektowe (nowa mechanika, zmiana modelu) najpierw omawiaj z autorem, a ustalenia zapisuj w `docs/design/`.

## Komendy

- Testy (headless, ok. 15 s): `godot --headless --script res://tests/run_tests.gd`
- Sonda balansu: `godot --headless -s res://tools/probe.gd -- <dni> <seed> <strategia>` (strategie są w pliku)
- Zrzuty ekranu (wymaga wyświetlacza): `SHOT_DIR=<katalog> godot --audio-driver Dummy -s res://tools/screenshot.gd`. Sprawdzaj nimi każdą zmianę wizualną.
- Odśwież cache klas po dodaniu `class_name`: `godot --headless --import`

## Pułapki GDScript w tym repo

- `var x := dict["k"]` i `:=` na wyniku metody nietypowanego obiektu nie kompilują się („Cannot infer the type”). Typuj jawnie: `var x: float = …`, `for t: SimTree in …`.
- Nie nazywaj metod ani zmiennych `log` (koliduje z funkcją wbudowaną). Dziennik to `SimWorld.note()` i `SimEvents.entries`.
- `SimJobs` i `SimFamily` trzymają `w: SimWorld`; cykliczne odwołania przez `class_name` działają.
