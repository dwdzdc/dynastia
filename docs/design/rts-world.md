# Świat na mapie: RTS

Ustalenia z autorem z 19.11.2026, po pierwszym podglądzie gospodarki („to są jakieś grafy, a ja chciałem RTS z kontrolą jednostek”). Gospodarka z `world-economy.md` zostaje silnikiem. Ten dokument opisuje, jak wygląda na mapie i jak gracz w niej żyje.

## Decyzje autora (19.11.2026)

1. **Jedna ciągła mapa**, jak w Foxhole. Miasta leżą na terenie, drogi biegną przez pola i lasy, a ciężarówka jedzie drogą.
2. **Sterowanie jak w Cultures.** Gracz daje ogólne zadanie (pracuj tu, handluj, buduj), a ludzie i pojazdy wykonują je sami. Można przejąć sterowanie ręcznie (PPM: idź / jedź tam).
3. **Cudze ciężarówki to takie same jednostki** na tej samej mapie. „Nie jestem wyjątkowy jako gracz, jestem częścią tego świata.” Gracz to zwykły aktor gospodarki (`EconActor`), tyle że to on podejmuje decyzje zamiast AI.

## Propozycje Claude'a (do potwierdzenia w playteście)

4. **Skala.** Mapa ok. 48 × 32 km, 20 miast co ok. 6–10 km. Miasto to skupisko budynków o średnicy od kilkuset metrów do 2 km. Ludność dalej liczymy zbiorczo, a budynek mieszkalny reprezentuje wielu ludzi. Wszystkie liczby siedzą w `data/economy.json`.
5. **Czas.** Doba trwa ok. 4 minut przy 1× (wcześniej 10 minut). Gospodarka liczy się raz na dobę, a jednostki (ciężarówki, ludzie gracza) poruszają się płynnie. Ciężarówka jedzie ok. 100 km na dobę gry, czyli kurs 10 km trwa ok. 25 s przy 1×. Człowiek idzie ok. 3× wolniej.
6. **Ludzie gracza to jednostki, reszta ludności zbiorczo.** Gracz zaczyna z dwiema osobami (wąski krąg) i niewielką kasą w jednym mieście. Osoba z zadaniem „pracuj w firmie X” idzie tam, a w środku liczy się jako pracownik tej firmy. Pensja trafia do kasy gracza, a nie do kasy miasta.
7. **Firma gracza to zwykła `EconBusiness`** z właścicielem-graczem. AI aktorów jej nie dotyka. Gracz buduje z menu budowy w wybranym mieście, budowa zużywa prawdziwe materiały, a ludzi zatrudnia z szarej masy miasta.
8. **Ciężarówki gracza** należą do jego firmy przewozowej. Rozkazy: „handluj sam” (ta sama logika co u przewoźników AI), „trasa stała” (kup X w A, wieź do B, powtarzaj), ręcznie „jedź do” i „kup / sprzedaj tutaj”.
9. **Render.** 3D z kamerą ortogonalną izo (jak w starej wsi, ADR-0006): teren z polami i lasami, drogi, budynki firm wg rodzaju, bloki mieszkalne, ciężarówki w kolorach firm. Przy oddaleniu jednostki rosną, żeby były widoczne. Nazwy miast to napisy 2D.
