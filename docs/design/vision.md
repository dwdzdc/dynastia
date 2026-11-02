# Dynastia — wizja gry

Najwyższe źródło prawdy o tym, czym ta gra jest. Kolejność pierwszeństwa: ten plik → `docs/design/family-dynamics.md` (model rodu) → `intro` (pierwotny szkic, nadal ważny tam, gdzie nic go nie nadpisuje).

## Skąd ta gra

Autor jako dziecko grał w Cultures (8th Wonder of the World) i lubił wybrać jedną rodzinę w osadzie i śledzić jej losy. Było to trudne, bo w Cultures dorosły człowiek nie miał żadnego związku ze swoją rodziną. Dynastia ma drapać dokładnie to miejsce: **survival rodziny w społeczeństwie**. Blisko, ale nie w punkt, były Simsy, Bannerlord, RimWorld i klony Dwarf Fortress.

**Wzór dla społeczeństwa: Port Royale i X4: Foundations.** Świat jest większy niż gracz i działa bez niego: ludzie i rody produkują, konsumują, handlują i budują z własnych potrzeb, a ceny i popyt biorą się z tego, co się w nim faktycznie dzieje. Gracz jest jedną z wielu części tego społeczeństwa, a nie jego osią. Wniosek dla projektu: każde źródło pieniędzy i popytu ma mieć w świecie konkretnego konsumenta albo producenta (żadnego „kupca z nieskończoną kasą”), a gospodarka bez gracza ma żyć sama. Słowa autora: „cały wielki zamknięty system, którego gracz jest opcjonalną częścią i któremu gra oferuje możliwość wspięcia się na coraz wyższe szczeble sukcesu przez branie udziału w tej mechanice”.

## O czym jest ta gra (słowa autora)

To gra o rodzinie próbującej utrzymać się i wyjść wyżej w świecie, który jej nic nie jest winien. Nie o bohaterze, nie o państwie, nie o frakcji. O kilku konkretnych ludziach, którzy się znają, kochają, wkurzają i od siebie zależą, i o tym, co z nimi robi czas.

Najprościej: RimWorld, tylko zamiast dzikiej planety masz społeczeństwo. Presja nie przychodzi od niedźwiedzia i mrozu, tylko od czynszu, szefa, sąsiada, prawa, rywali i od własnej rodziny, która może się rozejść. Wygląda to jak Cultures: osada na żywo, ludzie chodzą, noszą deski, idą do roboty i wracają. Ale w Cultures człowiek był etykietą „drwal”. Tu ma imię, ojca, wiek, charakter i historię z konkretnymi osobami.

**Klimat.** Surowy, ale nie okrutny dla zabawy. Bez lukru Simsów i bez cynizmu grimdarku. Życie jest kruche (wypadek w pracy, ciężki poród, więzienie, wojna), więc śmierć kogoś z rodziny ma znaczyć. Ale gra nie jest o cierpieniu, tylko o tym, że da się wyjść wyżej: rodzina z szeregowca może po trzech pokoleniach mieć warsztat, markę, nazwisko, które coś znaczy. Albo nie, i to też jest historia. Napięcie jest codzienne i przyziemne: ktoś się rozchorował w złym tygodniu i brakuje na opał. To jest horror tej gry, nie potwory.

**Sedno.**
- **Uwaga gracza jest zasobem.** Kogo zaniedbasz, ten się oddala i w końcu odchodzi. Główny wybór gry: komu poświęcasz czas, czyją drogę wspierasz kosztem czyjej.
- **Rodzina to graf, nie lista.** Kto jest „nasz”, wynika z więzi (skierowanych: ona może kochać brata, który ma ją za nic), a nie z nazwiska. Małżonek jest przyłączony, jego rodzina nie. Duża, rozproszona rodzina rozpada się sama.
- **Wiele dróg, żadna nie jest „tą właściwą”.** Szare życie, rzemiosło, własny interes, przestępczość, nauka, cwaniactwo. W jednej rodzinie różni ludzie idą różnymi drogami, a ich cele się zderzają.
- **Świat jest ten sam dla wszystkich.** Inne rody to ludzie z tych samych danych co twoi; różni je tylko dokładność symulacji (LOD).
- **Ryzyko to proces, w który możesz wchodzić** (przygotowanie, wykonanie, następstwa). Złapany nie znaczy skazany.

**Czego nie robić.**
- Nie Simsy: nikt nie myje się pod prysznicem dla zabawy.
- Nie Crusader Kings w tabelkach: ludzie fizycznie chodzą po mapie.
- Nie Settlers ani gra o optymalizacji osady.
- Nie okna wyskakujące co chwilę: informacja jest w świecie.
- Nie „wynajdź silnik parowy” jednym klikiem.

**Gdy masz wątpliwość przy implementacji.**
- Wybierz opcję, która tworzy historię, a nie tę wygodniejszą w tabelce.
- Jeśli coś może być liczbą w UI albo zachowaniem postaci, wybierz zachowanie.
- Każdy agent umie powiedzieć, dlaczego stoi.
- Wszystko, co można nastroić, trzymaj w danych.
- Jak coś wydaje się „dodatkiem”, sprawdź, czy to nie jest właśnie ta rzecz, dla której ta gra istnieje.

**Test, czy to działa.** Po dwóch, trzech pokoleniach gracz ma opowieści: „Ten idiota przepuścił tartak, a jego siostra odbudowała firmę, choć nie rozmawiali od lat.” Jeśli ktoś z rdzenia umiera, a gracz wzrusza ramionami, postać była za płytka i trzeba ją dopracować, zanim dojdzie następny system.

## Ustalenia z rozmów z autorem (02.11.2026)

- **Sandbox i eksperyment.** Szczegóły nie są przesądzone. Mechaniki mają się dać łatwo podmieniać i porównywać.
- **Dynamika rodu jest rdzeniem** i ma być dopięta przed społeczeństwem. Model: `docs/design/family-dynamics.md`.
- **Root to kotwica grafu rodu, nie awatar.** Nie ma osobnego sterowania; root rozstrzyga, kto jest „nasz” i z którą częścią zostaje gracz przy rozpadzie. Na razie swobodnie przełączany w obrębie rodu, zawsze wyraźnie oznaczony.
- **Gracz steruje członkami rodu, ale klik nie jest uwagą.** Uwaga to czas, który ludzie spędzają ze sobą w świecie. Rozkaz wbrew woli zostawia wspomnienie.
- **Społeczeństwo to ludzie, nie systemy.** Targ to konkretny kupiec z innego rodu, który wycenia towar. Popyt mają konkretni ludzie z ich pieniędzy: w głodującej wsi nikt nie kupi desek. Praca to praca u kogoś, lokum wynajmuje się od kogoś.
- **Czynsz nie jest osią gry.** Istnieje tylko przy wynajmie, jako jeden z wielu kosztów. Budynki to aktywa (0..n) rodu albo osoby. Własny dom, wynajem, przeprowadzka daleko, bezdomność i życie w drodze to równorzędne stany, a nie koniec gry.
- **Świat domyślnie wielki** (LOD, agregaty, materializacja na żądanie, `intro` §10). MVP to mały wycinek tej samej architektury.
- **Wiele epok:** średniowiecze, rewolucja przemysłowa, nowoczesność. Epoka może zmieniać się w trakcie gry (nauka, `intro` §9). Wszystko, co od niej zależy (zawody, prawo, środki kontaktu: list kontra telefon), siedzi w danych epoki.
- **Czas jak w Simsach:** długa doba (teraz 10 min przy 1×), codzienność i wiele pokoleń. Długość każdego procesu ustawiona osobno w danych w dobach (ciąża ok. 3 doby), a wiek w latach to etykieta. Dwa niezależne zegary: **kalendarz** (pory roku, `time.days_per_season`) steruje pogodą, światłem i opałem; **życie** (etapy w dobach, `aging.stages`) steruje dorastaniem, płodnością i starością. Pora roku trwa kilka lat życia, a rok kalendarzowy to mniej więcej jedno pokolenie (jak w Simsach). UI nie zestawia ich jako jednej osi.
- **Fazy dnia płynne** (poranek, dzień, zmierzch, noc), z długościami zależnymi od pory roku, bez nagłego przełączenia w ciemność.
- **Wygląd:** rzut izometryczny jak Cultures. Low-poly 3D z kamerą ortogonalną jest akceptowane (ADR-0006).
- **Rozkazy ręczne** to kolejka (PPM zastępuje, Shift+PPM dopisuje). Po wykonaniu postać sama wraca do autopilota.
- **Scenariusz „sami na odludziu”** ma być możliwy, ale bardzo trudny (jak przetrwanie na biegunie w RimWorldzie). Domyślnie gra toczy się w społeczeństwie.
- **Na później:**
  - wnętrza budynków (półotwarte albo podgląd po kliknięciu, żeby toczyć grę w środku);
  - śluby między krewnymi;
  - dzieci poza małżeństwem;
  - koszt przełączenia roota.
- **Proces w świecie, nie funkcja** (playtest iteracji 2): każdy skutek ma wynikać z tego, co fizycznie wydarzyło się między konkretnymi ludźmi w konkretnym miejscu. Szczegóły i ustalenia: `docs/design/living-village.md`.
- **Cele długoterminowe** (zagrożenia, zaginięcia, ścieżki kariery, tradycja i płeć w preferencjach, budowanie, ziemia, pracownicy, mapa proceduralna, wybór startu): `docs/design/goals.md`.
- **Budowa to osobne menu** (02.11.2026): katalog z danych — na razie dom, potem tartak, stragan, młyn i cała reszta, także droga. Gracz wybiera z menu i wskazuje miejsce na mapie.
- **Wyższe warstwy chcą się pokazać:** towary luksusowe, służba, widoczne bogactwo. To ich popyt.
- **Szczeble pozycji to jedna z dróg, nie jedyna.** Ścieżki z `intro` §7 zostają równorzędne: wżenienie się wyżej (cwaniactwo), wynalazca, który naprawdę wynajduje rzeczy (nauka, zmiana epoki), złodziej i półświatek (przestępczość), rzemiosło, przedsięwzięcia, szare życie. Każda ma własną „walutę” sukcesu (majątek, reputacja, wiedza, respekt, dostęp); model nie może zakładać jednej osi.
- **Świat nie zależy od gracza** (02.11.2026): wygaśnięcie rodu gracza to game over dla gracza, ale świat bez gracza ma się sam rozwijać — rody powstają i upadają, miasta rosną i maleją, ludzie przychodzą i odchodzą. Gracz nie jest centralnym elementem; może być choćby pojedynczym robotnikiem, który tylko orze pole, a świat da radę bez niego.
- **Pieniądze:** wartość gospodarki rośnie z produkcji (nowe zboże, domy, wydobycie). Nowe monety mogą przybywać, ale tylko z konkretnego procesu (kopalnia, mennica) i ubywać przez konkretny proces (podatek do króla) — nigdy z powietrza.
