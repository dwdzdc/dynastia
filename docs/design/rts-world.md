# Świat na mapie: RTS

Ustalenia z autorem z 19.11.2026, po pierwszym podglądzie gospodarki („to są jakieś grafy, a ja chciałem RTS z kontrolą jednostek”). Gospodarka z `world-economy.md` zostaje silnikiem. Ten dokument opisuje, jak wygląda na mapie i jak gracz w niej żyje.

## Decyzje autora (19.11.2026)

1. **Jedna ciągła mapa**, jak w Foxhole. Miasta leżą na terenie, drogi biegną przez pola i lasy, a ciężarówka jedzie drogą.
2. **Sterowanie jak w Cultures.** Gracz daje ogólne zadanie (pracuj tu, handluj, buduj), a ludzie i pojazdy wykonują je sami. Można przejąć sterowanie ręcznie (PPM: idź / jedź tam).
3. **Cudze ciężarówki to takie same jednostki** na tej samej mapie. „Nie jestem wyjątkowy jako gracz, jestem częścią tego świata.” Gracz to zwykły aktor gospodarki (`EconActor`), tyle że to on podejmuje decyzje zamiast AI.

## Decyzje autora, druga rozmowa (19.11.2026)

4. **Logistyka jest między firmami, a nie między centrami miast.** Ciężarówka bierze ładunek spod budynku sprzedawcy i wiezie go pod budynek odbiorcy: dojazdem do drogi, obwodnicą (w większych miastach), drogami między miastami i dojazdem do odbiorcy. Rynek miasta zostaje cennikiem i księgowością (kto ma ile towaru i po ile), ale towar fizycznie jedzie od budynku do budynku. Gracz wozi wprost z firmy do firmy, a towar dla własnej firmy trafia od razu do jej magazynu. Tak buduje się własne łańcuchy dostaw.
5. **Nieruchomości.** Działki i mieszkania to zasób, który kosztuje (model w `world-economy.md`, sekcja „Nieruchomości”). Dzięki temu rozrost największych miast jest trudniejszy.
6. **Trzy państwa** na mapie, z cłami na granicach, na razie ze wspólną walutą (model w `world-economy.md`, sekcja „Państwo”).

## Propozycje Claude'a (do potwierdzenia w playteście)

4. **Skala.** Mapa ok. 48 × 32 km, 20 miast co ok. 6–10 km. Miasto to skupisko budynków o średnicy od kilkuset metrów do 2 km. Ludność dalej liczymy zbiorczo, a budynek mieszkalny reprezentuje wielu ludzi. Wszystkie liczby siedzą w `data/economy.json`.
5. **Czas.** Doba trwa ok. 4 minut przy 1× (wcześniej 10 minut). Gospodarka liczy się raz na dobę, a jednostki (ciężarówki, ludzie gracza) poruszają się płynnie. Ciężarówka jedzie ok. 100 km na dobę gry, czyli kurs 10 km trwa ok. 25 s przy 1×. Człowiek idzie ok. 3× wolniej.
6. **Ludzie gracza to jednostki, reszta ludności zbiorczo.** Gracz zaczyna z dwiema osobami (wąski krąg) i niewielką kasą w jednym mieście. Osoba z zadaniem „pracuj w firmie X” idzie tam, a w środku liczy się jako pracownik tej firmy. Pensja trafia do kasy gracza, a nie do kasy miasta.
7. **Firma gracza to zwykła `EconBusiness`** z właścicielem-graczem. AI aktorów jej nie dotyka. Gracz buduje z menu budowy w wybranym mieście, budowa zużywa prawdziwe materiały, a ludzi zatrudnia z szarej masy miasta.
8. **Ciężarówki gracza** należą do jego firmy przewozowej. Rozkazy: „handluj sama” (ta sama logika co u przewoźników AI), „kurs z firmy do firmy” (jednorazowo), „trasa stała firma → firma” (powtarza aż do odwołania), „kup tu i wieź do miasta” oraz ręcznie: PPM na budynek („jedź pod tę firmę”) albo na miasto.
10. **Jak jedzie ciężarówka** (`sim/econ/econ_layout.gd`). Każda firma ma stałe miejsce i dojazd do najbliższej drogi swojego miasta. Kurs AI: ładunek z magazynu największego sprzedawcy na rynku, dostawa do firmy, która towar przerabia (wg wielkości), a dobra konsumpcyjne do sklepu (firma usługowa). Materiały budowlane jadą także na place budów. Pusta jazda kończy się na parkingu na skraju miasta. Czas kursu liczy się z długości całej trasy od budynku do budynku.
9. **Render.** 3D z kamerą ortogonalną izo (jak w starej wsi, ADR-0006): teren z polami i lasami, drogi, budynki firm wg rodzaju, bloki mieszkalne, ciężarówki w kolorach firm. Przy oddaleniu jednostki rosną, żeby były widoczne. Nazwy miast to napisy 2D.
