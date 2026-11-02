# Dynamika rodu — model projektowy

Stan: uzgodnione w rozmowie z autorem (02.11.2026). To jest rdzeń gry i ma być przemyślany, zanim powstanie kod. Tam, gdzie ten dokument różni się od `intro` §5, obowiązuje ten dokument.

## Zasada nadrzędna

Gra jest o rodzie, a ród ma koszt. Nie może być tak jak w Bannerlordzie, gdzie można mieć ród na 1000 osób, nie pamiętać kto jest kim, a wszyscy zostają wierni. Koszt utrzymania rodu nie jest prostym licznikiem. Wynika z wyborów gracza: na kogo idzie skończony czas ludzi w świecie.

## Trzy warstwy

1. **Pokrewieństwo (fakty).** Rodzice (`parent_of`) i małżeństwa (`Union` ze startem i końcem) są niezmienne i nigdy nie znikają. Działają niezależnie od przynależności do rodu.
2. **Więzi (emocje).** `Bond(A→B)` jest skierowany: wartość plus lista powodów-wspomnień. Istnieje niezależnie od tego, czy A i B są w jednym rodzie. Rozdzielone rodzeństwo nie spotyka się po latach „jak obcy”, tylko z tym, co do siebie czuli, wyblakłym przez czas.
3. **Przynależność (stan prawny i społeczny).** Kto jest w rodzie. Zmienia się tylko przez konkretne zdarzenia (patrz niżej).

## Świat jako jeden graf podzielony na rody

- Wszyscy ludzie świata tworzą jeden graf (krawędzie to pokrewieństwo i więzi). Graf jest podzielony na rody, a każdy ród, także ród AI, ma swojego **roota**.
- **Root** to kotwica rodu, nie awatar. Od niego liczy się spójność (`strength`) i on rozstrzyga, z którą częścią zostaje gracz, gdy ród się rozpada. Nie ma osobnego sterowania.
- Gracz może przełączyć roota, ale tylko na członka własnego rodu (na razie swobodnie, później może z kosztem albo warunkiem). Kto jest rootem, ma być zawsze wyraźnie widoczne.
- Osoba na styku dwóch rodów, np. z silniejszą więzią z rodem B, nie staje się przez to częścią B ani tym bardziej rootem B.

## Wejście do rodu to rytuał, wyjście to proces

**Wejście** tylko przez zdarzenie:
- narodziny w rodzie;
- małżeństwo (małżonek przechodzi do rodu, jego krewni nie);
- adopcja lub przyjęcie;
- pojednanie, np. powrót brata, który kiedyś odszedł (jawne zdarzenie, nie automat).

Dobre relacje z innym rodem dają co najwyżej przyjaźń, a nie członkostwo.

**Wyjście** przez:
- powolną degradację: siła przynależności (`strength` liczona od roota) spada poniżej progu;
- albo zdarzenie: spór, kłótnia o pieniądze, ślub wbrew rodowi, wydziedziczenie, zdrada.

Konsekwencja względem `intro` §5: przynależność nie jest już wyliczana na bieżąco z siły. Siła mierzy spójność i może tylko **wyzwolić odejście**. Dzięki temu nie trzeba histerezy, a wejście zawsze jest historią.

Kto odpada, przede wszystkim **wychodzi spod kontroli gracza**. Może wejść do innego rodu (np. przez ślub) albo założyć własny, ze sobą jako rootem. Zwykle wiąże się to z wyprowadzką, ale nie musi.

## Ród to nie dom

- Budynki (dom, warsztat, pole) to **aktywa** rodu albo osoby: od 0 do n. Żaden budynek nie jest na stałe związany z rodem.
- Ród może mieć kilka gospodarstw (syn mieszka osobno i dalej jest w rdzeniu), może przejść na wynajem, przeprowadzić się daleko, zostać bezdomny albo wędrowny.
- Czynsz istnieje tylko wtedy, gdy ktoś wynajmuje lokum od kogoś. Jest jednym z wielu kosztów, a nie osią gry.

## Kontrola i uwaga

- **Klik gracza nie jest interakcją w świecie.** Postać nie wie, że ktoś nią sterował. Wydawanie rozkazów nie buduje więzi.
- **Uwaga to czas, który ludzie rodu spędzają ze sobą w świecie:** wspólna praca, posiłek, wieczór przy stole, nauka rzemiosła, opieka w chorobie, pomoc w potrzebie. Nie ma pola „uwaga” ani paska w UI (ADR-0004).
- **Koszt wynika z wyborów, a nie ze wzoru:**
  1. *Czas jest skończony.* Wieczór ma kilka godzin, każdy jest w jednym miejscu naraz. Żeby utrzymać kuzyna z drugiego końca wsi, ktoś musi poświęcić mu wieczory zamiast dzieciom albo pracy. Dużego rodu nie da się fizycznie dopilnować i rozpada się sam.
  2. *Rozkaz wbrew woli zostaje we wspomnieniach.* Każdy ma preferencje. Kazać można zawsze, ale rozkaz sprzeczny z tym, czego ktoś chce, zostawia ślad w więzi („ojciec kazał mi rzucić warsztat”). Przy słabej więzi postać się ociąga albo odmawia.
- Czas spędzony z kimś mocno związanym z rdzeniem (blisko roota w grafie) liczy się bardziej niż czas z kimś na obrzeżach, bo siła propaguje się od roota.

## Więzi

- `Bond(A→B)`: wartość od −100 do 100 plus wspomnienia (zdarzenie, data, waga). Lekkie wspomnienia blakną, ciężkie zostają na zawsze.
- Na plus: wspólny czas (wspólna praca, rozmowa, posiłek — interakcje pozytywne i neutralne), pomoc, nauka od kogoś, dzielenie się, wspólny sukces. Kłótnia to też czas razem, ale nie buduje lojalności.
- Na minus: krzywda, kłótnia, zdrada, decyzja rodu wbrew komuś, rozkaz wbrew woli.
- Zaniedbanie: brak kontaktu powoli sprowadza więź ku „obcy”, nigdy do wrogości. Wrogość wymaga zdarzenia.
- Cechy charakteru modyfikują siłę i kierunek zmian (np. pamiętliwy, lojalny, porywczy).

## Sygnały dryfu i odejście

- Odejście przez degradację poprzedza faza **subtelnych sygnałów w zachowaniu**: zatrzymuje wypłatę, je osobno, wraca późno, unika wspólnych wieczorów, mniej mówi przy stole. Nie ma alertów, liczników ani komunikatów typu „za dwie doby Staś odejdzie”. Wartości liczbowe są ukryte przed graczem (widoczne tylko w trybie debug).
- To jest część mechaniki: kto poświęca komuś tak mało uwagi, że nie zauważa sygnałów, ten może przegapić też samo odejście.
- Samo odejście jest zawsze **zapisane w kronice rodu** (kto, kiedy, dlaczego, z jakimi wspomnieniami odszedł), żeby gracz mógł potem dojść, co się stało z daną osobą. Wpis w kronice nie wyskakuje jako okno.

## Pieniądze

- Każdy ma **własną sakiewkę**, a gospodarstwo ma **wspólną kasę**.
- Ile kto oddaje do wspólnej, zależy od jego więzi z rodem. Oddalający się członek zaczyna zatrzymywać wypłatę, zanim formalnie odejdzie. To pierwszy widoczny sygnał dryfu i naturalne źródło kłótni o pieniądze.

## Czas

- Jak w Simsach: długa doba (codzienność) i wiele pokoleń.
- Długość każdego procesu ustawiona osobno w danych w dobach (np. ciąża ok. 3 doby, dzieciństwo kilkanaście, dorosłość kilkadziesiąt), a nie wyliczana z „lat”. Wiek w latach to tylko etykieta.

## Na później (świadomie poza pierwszą iteracją)

- Śluby między krewnymi jako możliwość (z konsekwencjami społecznymi i zdrowotnymi).
- Dzieci poza małżeństwem (bękarty): pokrewieństwo jest faktem niezależnym od ślubu, a przynależność dziecka do rodu jest osobną sprawą (uznanie albo nie) i źródłem historii.
- Warunki albo koszt przełączenia roota.
- Spór o spadek między rodami, które się rozeszły.

## Otwarte pytania

1. **Pojednanie.** Jak wygląda rytuał powrotu do rodu? Kto go inicjuje, gracz czy postać, i co jest warunkiem: więź, wspólny wróg, potrzeba?
2. **Preferencje.** Skąd postać wie, czego chce? Z cech, z umiejętności, z wzorców (syn chce być jak ojciec), z historii?
3. **Odmowa.** Od jakiego poziomu więzi postać odmawia rozkazu i co się wtedy dzieje (robi co innego, kłótnia, odejście)?
4. **Ród gracza po podziale.** Kiedy ród pęka na dwie części, czy druga staje się rodem AI w tym samym świecie (z własnym rootem) i można z nią potem wchodzić w relacje: pojednanie, rywalizacja, spór o spadek?
