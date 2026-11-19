# Wzorce z X4: Foundations i Port Royale: jak działa ich gospodarka

Baza wiedzy pod gospodarkę bez gracza (`world-economy.md`). Zebrane 19.11.2026 z wiki Egosoftu, forów, poradników Steama i oficjalnego podręcznika Port Royale 3. Celem są mechanizmy do wdrożenia, a nie opis gier.

Oznaczenia:
- ✅ potwierdzone: oficjalny podręcznik/wiki albo wypowiedź dewelopera.
- ❓ niepewne: forum graczy, poradnik fanowski, moja wiedza ogólna albo wniosek.

Uwaga o źródłach: Egosoft nie opublikował wzorów cen ani logiki frakcji. To, co wiadomo, pochodzi od deweloperów na forach i od modderów, którzy czytają pliki gry (`god.xml`, `jobs.xml`, `factionlogic_*.xml`). Port Royale 2 to gra Ascaronu (twórców Patrycjusza), a PR3 i PR4 to Gaming Minds/Kalypso. Najlepszym źródłem jest podręcznik PR3, który opisuje mechanikę wprost.

## X4: Foundations

### Produkcja w stacjach

- Stacja to zestaw modułów: produkcyjne, magazyny (osobno na towary stałe, płynne i kontenerowe), habitaty, doki. Moduł produkcyjny ma przepis: wejścia, wyjścia, czas cyklu. ✅ [wiki: Wares](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Manual%20and%20Guides/Objects%20in%20the%20Game%20Universe/Wares/)
- Każdy towar ma objętość na jednostkę (m³) i typ ładowni. Ograniczeniem jest objętość, nie liczba sztuk. ✅ [wiki: Wares]
- **Siła robocza jest opcjonalnym bonusem, nie warunkiem.** Bez pracowników moduł pracuje na 100%. Habitaty dają miejsce dla pracowników rasy, a ci jedzą jedzenie danej rasy i leki. Pełna obsada daje bonus. Tabela Egosoftu dla starszej wersji: jedzenie +25%, leki +28% przy maksymalnej obsadzie 90 osób. ❓ (stara wersja) [Egosoft confluence](https://egosoft.com:8444/confluence/x/RoGMB). Gracze mierzą w praktyce ok. +20%, a część mówi, że karmienie pracowników często się nie opłaca w porównaniu z dołożeniem modułu. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/1844693670121829168/)
- Wniosek: pracownicy w X4 to drugi kanał popytu (jedzenie, leki), który zamyka pętlę gospodarki konsumpcją, a nie główne ograniczenie produkcji.

### Ceny: widełki i zapas

- Każdy towar ma stałą cenę minimalną i maksymalną. Średnia = (min + max) / 2. Rozpiętość jest zwykle ok. ±15–20% wokół średniej (Advanced Composites 432–540–648, Claytronics ok. ±15%). ✅ [wiki: Wares]
- Nie da się wyjść poza widełki. Wyjątkiem są rabaty i prowizje frakcyjne. ✅ (deweloper, 2020) [Steam](https://steamcommunity.com/app/392160/discussions/0/1742232339928886123)
- **Cena stacji zależy od zapełnienia jej własnego magazynu na ten towar.** Słowa dewelopera eMYNOCK: „im pełniejszy magazyn, tym niższa cena i na odwrót”, a „przy połowie przeznaczonego miejsca towar powinien iść po średniej cenie”. ✅ [Steam]. Z tego wynika liniowa (lub zbliżona) funkcja: `cena = max − (max − min) × zapas/pojemność_docelowa`. ❓ (dokładny kształt nieznany)
- Skutek uboczny: mniejszy magazyn = cena szybciej spada, bo ta sama liczba sztuk to większy procent. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/592890977576865839)
- Kupcy NPC zaczynają kupować u ciebie dopiero wtedy, gdy cena spadnie poniżej średniej. Za wysoka cena = zero klientów. ✅ (deweloper) [Steam](https://steamcommunity.com/app/392160/discussions/0/1742232339928886123)
- Cena nie bierze pod uwagę rynku, tylko własny zapas. Pełny magazyn ogniw energetycznych daje cenę bliską minimum. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/3154186375139686555)
- Znany problem: część stacji (czarne rynki, niektóre stacje handlowe) ma ceny „zamrożone” i nie reaguje na zapas. Gracze uważają to za jedną z przyczyn zastojów stoczni. ❓ [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=4788941)

### Oferty kupna i sprzedaży

- Stacja wystawia oferty: „kupię X” (wejścia, materiały budowy) i „sprzedam Y” (produkty). Plac budowy stacji (Build Storage) też wystawia oferty kupna, więc budowa jest zwykłym klientem rynku. ✅ [wiki: Trading And Mining](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Manual%20and%20Guides/X4%3A%20Foundations%20Manual/Trading%20And%20Mining/)
- **Wiedza o ofertach się starzeje.** Gracz widzi aktualne oferty tylko tam, gdzie ma statek, satelitę albo stację w zasięgu radaru. Poza tym informacja się dezaktualizuje. Można kupić subskrypcję handlową frakcji: ok. 10 mln Cr dla dużej frakcji, ok. 1 mln dla małej. ✅ [wiki: Trading And Mining]
- Rezerwacje: zlecenie kupna/sprzedaży w kolejce statku rezerwuje ilość w ofercie. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/3079873787843279896). Modderzy zgłaszają jednak, że kilka statków potrafi znaleźć tę samą ofertę i silnik jej nie odświeża, więc rzucają się na nią wszyscy. ❓ (tamże)

### Kupcy: jak statek wybiera interes

- Autohandel (AutoTrade) gracza: wymaga kapitana z odpowiednią liczbą gwiazdek, białej listy towarów i „smyczy” (zasięgu w sektorach). To zachowanie domyślne, nie jednorazowy rozkaz. ✅ [wiki: Trading And Mining]
- Statki przypisane do stacji słuchają menedżera stacji: dowożą wejścia i rozwożą produkty, zamiast szukać dowolnego zysku. ✅/❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/3079873787843279896)
- Cena ustawiona na stacji to dla jej kupców tylko próg minimalny przy wyborze interesu. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/592890977576865839). Gracze zgłaszają, że kupiec sprzedaje pierwszemu klientowi, który spełnia próg, a nie najlepszemu. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/1742232339928886123)
- Znany problem: gdy jedyny pozostały towar jest nasycony, kupcy stacji stoją bezczynnie. ❓

### Kto buduje statki i stacje (frakcje, „god”, joby)

- **`god.xml`** rozstawia stacje na starcie. Nie myśli liczbą stacji, tylko **ilością produkcji** towaru, którą potem rozkłada na tyle stacji, ile trzeba. Ma limity na galaktykę (`quota galaxy`) i wybiera sektory według ich „wartości gospodarczej” z mapy. Losowanie jest deterministyczne z seeda. ✅ (deweloper CBJ) [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=5223951)
- **`jobs.xml`** to zapotrzebowanie frakcji na statki: ilu kupców, górników, patroli ma być w galaktyce, klastrze, sektorze. Gdy statku z jobu brakuje (np. zniszczony), frakcja zamawia nowy w stoczni, a stocznia buduje go z prawdziwych towarów (części kadłuba, silniki, broń). Joby aktywowane skryptem „pojawiają się” bez budowy, co deweloper opisuje jako wyjątek. ✅/❓ [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=5215114)
- **Logika frakcji (`factionlogic_stations.xml`) stawia nowe fabryki, gdy wykryje niedobór towaru** w danym sektorze. Szczegóły są znane tylko z modów, m.in. Faction War/Economy Enhancer, który poprawia sprawdzanie par sektor–towar. ❓ [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=4836247)
- **Pętla wojna → popyt.** Zniszczone statki trzeba odbudować, więc wojna jest głównym ujściem towarów. Stocznie są „głównym zlewem” gospodarki. Spokojne frakcje mają mniejszy popyt. ❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/1642044369674391050)
- Xenon (wroga frakcja maszyn) nie handluje z resztą: wydobywa i buduje sam. Działa jako stała presja militarna, która niszczy statki i stacje i przez to napędza popyt. ❓ (wiedza ogólna)

### Jak gospodarka się zacina

- **Stocznie bez części.** Klasyka forów: stocznia ma wszystko poza jednym towarem (najczęściej częściami silnika) i przez to nie buduje statków. Nic jej tego nie dowiezie, bo producent jest za daleko, kupcy są zajęci czym innym albo stacja ma zamrożoną cenę. Egosoft przyznał, że „gospodarka ma problemy, części silników to jeden z nich”. ❓ [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=4882871)
- **„Studnia rozpaczy” z częściami kadłuba.** Do zbudowania fabryki części kadłuba trzeba części kadłuba. Gdy ich zabraknie, frakcja nie odbuduje ani statków, ani fabryki, która rozwiązałaby problem. Mod obniża to wymaganie właśnie po to. ❓ [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=4836247)
- Towar leży (23 tys. części kadłuba w fabryce), a stocznia obok go nie dostaje. Problemem jest logistyka, nie produkcja. ❓ (tamże). Wątek na forum Egosoftu wprost proponuje, żeby następny tryb gospodarki skupiał się na logistyce. [Egosoft forum](https://forum.egosoft.com/viewtopic.php?p=5045829)
- Kolejki budowy AI rosną bez końca, gdy plan budowy wymaga modułu, którego nie da się zbudować. ❓ [Steam](https://steamcommunity.com/sharedfiles/filedetails/comments/3255964595)

### Jak wchodzi gracz

- Stawia własną stację (moduły z planu, materiały kupuje plac budowy albo dowozi gracz), zatrudnia menedżera, który sam ustala ceny z zapasu albo trzyma ręczne. Deweloper radzi pierwszą stację wyceniać ręcznie, bo automat na starcie potrafi drenować kasę. ✅/❓ [Steam](https://steamcommunity.com/app/392160/discussions/0/1742232339928886123)
- Reguły handlu: kto może kupować i sprzedawać (wszyscy, tylko moja frakcja, czarna lista), limity ilości i cen. ✅/❓
- Górnictwo (zbieranie surowca z pól o różnej wydajności), autohandel, kontrakty handlowe, subskrypcje. Gracz konkuruje o te same oferty co NPC: jego stacja to po prostu kolejna stacja w sieci.

## Port Royale

### Miasto: produkcja, konsumpcja, ceny (PR3, podręcznik ✅)

Źródło: [oficjalny angielski podręcznik PR3](https://www.mogelpower.de/manuals/Port_Royale_3_English_Manual.pdf), s. 14–21, 33.

- 60 miast, 20 towarów. **Każde miasto może produkować 5 z 20 towarów** i zwykle robi ich znacznie więcej, niż samo zużywa. Dlatego każde miasto coś eksportuje i czegoś potrzebuje. Handel wynika z geografii, nie z losowania.
- Cały handel miasta idzie przez jeden rynek w porcie. Lokalne warsztaty sprzedają tam produkty i kupują tam surowce. Konwoje handlują tylko przez ten rynek.
- **Popyt = ile mieszkańcy i firmy miasta zużyją w najbliższych dniach.** Cena zależy od tego, na ile dni zapas wystarczy. Pięć stanów w oknie handlu:
  1. bardzo mało, cena maksymalna (kupując to, tracisz popularność w mieście; sprzedając, zyskujesz);
  2. zapas na ok. **30–40 dni**: cena „nieatrakcyjna”, nie kupuj i nie sprzedawaj;
  3. zapas niekrytyczny, towar tani (zwykle produkowany lokalnie): kupuj;
  4. nadmiar nawet jak na miasto-producenta: cena spada dalej;
  5. cena minimalna, **poniżej kosztu produkcji: lokalne firmy nie zarabiają i zwalniają ludzi**.
- Stan 5 to automatyczny hamulec nadprodukcji: niska cena → zwolnienia → mniejsza produkcja → zapas spada → cena wraca.
- Konsumpcja na mieszkańca na dzień (szacunek gracza, PR3): drewno 0,00137; cegły i pszenica 0,00275; owoce 0,0022; kukurydza, cukier, konopie, bawełna, liny, chleb 0,0011; tkaniny, metal, narzędzia, kawa, kakao, tytoń, odzież, mięso, rum 0,00054; barwniki 0,00027. Miasto 2000 osób zjada więc ok. 5,5 beczki pszenicy dziennie. ❓ [steamah](https://steamah.com/port-royale-3-goods-suply-formula-consuption-per-capita/)
- Opcja „dynamiczny popyt”: bogate miasta zaczynają chcieć więcej towarów luksusowych. ❓ (tamże)

### Ludzie, praca i wzrost miasta (PR3 ✅)

- **Wielkość miasta zależy wyłącznie od liczby miejsc pracy** (i mieszkań). Osadnicy szukający pracy przypływają z Europy flotami skarbowymi do stolic, a dalej rozwożą ich konwoje handlowe.
- Wolne stanowisko obsadza się, gdy w mieście jest 4 osadników: pracownik z rodziną. Ludność rośnie wtedy o 4. Warsztat zatrudnia 25 pracowników. Brak miejsc w domach = brak nowych mieszkańców.
- **Dobrobyt** rośnie z zaopatrzenia, spada przez braki i zdarzenia, ale **powoli**, więc jest czas na reakcję. Za niski dobrobyt sprawia, że pracownicy porzucają pracę i wracają do puli osadników. Bardzo wysoki daje bonus: tańsza praca, większa produkcja, miasto samo rodzi osadników.
- Progi z forów: poniżej 50% zadowolenia osadnicy nie przyjmują pracy, poniżej 40% pracownicy odchodzą, „prosperujące” od ok. 75–80%. ❓ [Steam](https://steamcommunity.com/app/205610/discussions/0/3070873683586368291). W PR4 próg obsadzania to 40%. ❓ [gamewatcher](https://www.gamewatcher.com/port-royale-4-production-and-town-management)
- Szkoła (1 na 2500 mieszkańców) daje osadników, gdy miasto prosperuje. Szpital (1 na 2000) zmniejsza szansę epidemii. ✅
- **Floty skarbowe:** stolice codziennie odkładają część kawy, tytoniu, kakao i barwników do magazynu eksportowego. Flota zabiera towar i zostawia osadników. Im więcej towaru, tym więcej osadników. Eksport kupuje więc wzrost ludności. ✅
- Zaniedbane miasta kurczą się (nawet poniżej ok. 1000), ale nie znikają. ❓ [Steam]

### Zdarzenia (PR3 ✅)

Każde zdarzenie ma konkretny, liczbowy skutek dla produkcji albo konsumpcji, więc rozchodzi się cenami:
- **Huragan** (kwiecień–wrzesień): widać go na mapie, niszczy statki, zatrzymuje produkcję w mieście, nad którym przechodzi.
- **Szarańcza** (październik–marzec): wędruje od miasta do miasta, zatrzymuje produkcję, mieszkańcy zjadają 4× więcej towarów nietrwałych.
- **Susza**: po kilku tygodniach bez deszczu, −30% produkcji upraw.
- **Epidemia**: tym bardziej prawdopodobna, im większe miasto i mniej szpitali, 2× zużycie odzieży i tkanin.
- **Pożar**: przy suszy, gdy w mieście są „ogniowe” zakłady (odlewnia, kuźnia, gorzelnia), 2× zużycie drewna i cegieł.
- **Niedobór i głód nie są losowe**: przychodzą tylko po dłuższym złym zaopatrzeniu. Przy niedoborze **cena maksymalna brakującego towaru rośnie o 50%**.
- W czasie zdarzeń zwykle nie da się budować. Podręcznik wprost zachęca gracza do grania na zdarzeniach („spadek produkcji = brak w regionie = wyższe ceny”).
- Do tego wojny narodów (silny naród wypowiada wojnę groźnemu sąsiadowi, słabe zawierają sojusze), konwoje wojskowe atakują konwoje i miasta wroga, a piraci polują na handlarzy. W PR2 piratów jest zawsze ok. pięciu, nawet gdy jakichś zatopisz. ❓ [cheatbook](https://www.cheatbook.de/wfiles/portroyale2a.htm)

### Handlarze i konwoje

- „Setki konwojów handlowych” kupują tam, gdzie jest nadwyżka, i sprzedają tam, gdzie jest popyt. To one rozprowadzają towar po świecie. ✅ [podręcznik PR3]. Jak dokładnie wybierają trasy, nie jest opisane. AI-kupcy rzadko budują firmy. ❓ [Steam]
- Gracz automatyzuje trasy: konwój szacuje popyt na kolejnych przystankach i kupuje tyle, żeby go pokryć, a priorytety (1–5 gwiazdek) decydują, kto dostaje towar pierwszy (PR4). ❓ [steamah PR4](https://steamah.com/port-royale-4-soup-to-nuts-the-economy-guide/)
- Zarządca magazynu gracza (PR3) sam sprzedaje, gdy cena przekroczy próg w % ceny produkcji, chroni surowce własnych warsztatów na N dni i trzyma bezwzględne minima. ✅ [podręcznik PR3]
- Kupując całą partię naraz, płacisz coraz więcej za sztukę, bo cena rośnie z każdą zabraną beczką. ❓ [GOG](https://gog.com/forum/port_royale_series/any_tips_on_setting_up_trade_routes)

### Firmy gracza i wpływ na miasto

- Budowa wymaga licencji. Mistrz budowlany daje ją tylko przy dobrej reputacji u narodu i popularności w mieście, a każda kolejna licencja kosztuje więcej. Popularność rośnie, gdy sprzedajesz to, czego brakuje, i spada, gdy wykupujesz deficytowe. ✅ [podręcznik PR3]
- Warsztat gracza bierze surowce z jego magazynu w mieście. Bez nich stoi, ale **koszty biegną dalej**. ✅. W PR4: bawełna kosztuje 2880 zł dziennie, a przy cenie spadłej do 64 zysk to ok. 500 dziennie. Za duża produkcja sama zjada marżę. AI-konkurenci zamykają nierentowne firmy. ❓ [gamewatcher]
- Każda firma gracza tworzy miejsca pracy, a więc **sprawia, że miasto rośnie** (o ile są osadnicy i domy). Gracz staje się dosłownie właścicielem kawałka miasta. PR2: dom dla robotników przynosi czynsz, który pokrywa część podatków od firm. ❓ [cheatbook]
- W PR4 surowce przy domach obniżają zadowolenie mieszkańców (−10% na zakład w promieniu 2 pól). ❓ [steamah PR4]
- Gdy naród cię znienawidzi, przejmuje twoje firmy i magazyny w swoich miastach (PR2). ❓ [cheatbook]

### Co sprawiało frajdę

- Czytelna mapa nadwyżek i braków: każde miasto ma 5 towarów eksportowych, więc pierwsze trasy widać od razu, a potem zmieniają je zdarzenia i wojny.
- Okazje są chwilowe (susza, szarańcza, blokada piracka), więc trzeba reagować, a nie tylko optymalizować raz.
- Rosnąca skala: jeden statek → konwój → sieć tras → własne warsztaty → miasto, które rośnie dzięki tobie.
- Gracz widzi skutek: miasto rośnie, bo je zaopatrujesz, i kurczy się, gdy blokują je piraci.

## Wspólne lekcje

Co sprawia, że gospodarka wygląda na żywą dla obserwatora:
- **Widoczni nośnicy.** Każdy towar przewozi konkretny statek lub konwój, który można zobaczyć, napaść albo zablokować. Bez tego ceny są tylko liczbami.
- **Ceny z lokalnego zapasu w dniach popytu** (PR) albo w procencie magazynu (X4), zawsze w widełkach. Proste, czytelne i stabilne.
- **Ujście (sink) jest konieczne.** W X4 zlewem są wojna i stocznie, w PR konsumpcja ludności, flota skarbowa i zdarzenia mnożące zużycie. Bez stałego zużycia magazyny się zapychają, ceny siadają na minimum i wszystko staje.
- **Zdarzenie modyfikuje współczynnik, a nie wynik.** −30% upraw, 2× zużycie drewna, zatrzymana produkcja. Kryzys rodzi się z łańcucha, a nie ze skryptu.
- **Wolna inercja dobrobytu** (PR) daje czas na reakcję i czytelną historię („miasto podupada od miesiąca”).

Typowe awarie i jak je łagodzić:
- **Deflacja i nadprodukcja:** cena spada do minimum. Mechanizm z PR: poniżej kosztu produkcji firmy zwalniają ludzi. W X4 cena przy pełnym magazynie jest najniższa, a produkcja staje, gdy magazyn się zapełni.
- **Zator logistyczny i brak jednego ogniwa:** stocznia czeka na jeden towar (X4). Łagodzenie: kupiec przypisany do zakładu dowozi brakujące wejścia, brakujący towar podnosi ofertę do maksimum, a z czasem ktoś stawia brakującą fabrykę.
- **Pętla samoblokująca:** do zbudowania producenta X potrzeba X. Unikać takich przepisów albo zapewnić rezerwę lub awaryjny import.
- **Stado kupców na jednej trasie:** wiele statków reaguje na tę samą ofertę. Łagodzenie: rezerwacje ilości w ofercie i liczenie tego, co już jest w drodze do miasta (nasz model już to ma).
- **Zamrożone ceny i zastałe oferty:** stacja, która nie reaguje na zapas, psuje sygnał dla całej sieci. Każdy rynek musi reagować.
- **Gromadzenie (hoarding):** magazyn bez limitu chłonie towar bez końca. W X4 cena zależy od zapełnienia skończonego magazynu, a w PR zarządca ma progi i minima. Pojemność musi być skończona.
- **Galopujące ceny:** twarde widełki min/max. PR podnosi maksimum o 50% tylko w czasie niedoboru, czyli ograniczony, uzasadniony wyjątek.
- **Świat zależny od gracza:** w obu grach NPC zapewniają rdzeń przepływów, a gracz jest jednym z wielu. Zastój gospodarki X4 na forach to zwykle sytuacja, w której tylko gracz mógłby dowieźć brakujące ogniwo. Tego mamy unikać (sonda `solo`).

## Co bierzemy do Dynastii

1. **Cena z „dni zapasu”, nie z surowej ilości.** `dni = zapas / dzienne_zużycie_miasta` (ludność + firmy, z ostatnich N dób). Pasma jak w PR3: poniżej kilku dni cena maksymalna, ok. 30 dni średnia, wyraźna nadwyżka cena minimalna. Progi w `data/economy.json`. Pasuje do `EconMarket` (już mamy „zapas mniejszy niż kilka dób popytu”).
2. **Widełki min/max na towar** (±15–25% albo szerzej dla żywności). Wyjątek: przy przedłużającym się niedoborze maksimum rośnie o +50% (PR3). Daje to ograniczony, czytelny skok w kryzysie zamiast galopady.
3. **Cena minimalna < koszt produkcji = firmy tną zatrudnienie** (PR3). To naturalny hamulec nadprodukcji w `EconBusiness`. Firma produkuje tylko wtedy, gdy się opłaca, a dodatkowo zwalnia, gdy cena przez kilka dób jest poniżej kosztu.
4. **Pojemność magazynu jako drugi sygnał** (X4). Firma z pełnym magazynem wyjść obniża cenę wystawienia, a z pustym magazynem wejść podnosi ofertę kupna. Skończone magazyny w każdej firmie, żeby nie dało się gromadzić towaru bez końca.
5. **Każde zdarzenie jako mnożnik na współczynnik**, z czasem trwania i powodem dla kroniki: pożar zakładu = produkcja 0 + 2× popyt na materiały budowlane w mieście; nieurodzaj = −30% upraw w regionie; strajk = 0 pracowników w jednej firmie; zamknięta droga = czas przejazdu ∞. Liczby w JSON-ie.
6. **Niedobory i „głód” nie są losowe**: wykrywa się je z długotrwałego braku i dopiero wtedy obniżają dobrobyt i dają wpis w kronice (PR3).
7. **Ludność rośnie z miejsc pracy i mieszkań, dobrobyt z zaopatrzenia, wolno** (PR3). Migracja do sąsiednich miast, gdy dobrobyt spada poniżej progu (np. 40%). Pracownicy odchodzą z firm, gdy dobrobyt jest niski. Progi w JSON-ie.
8. **Specjalizacja miast ze złóż**, w stylu „5 z 20” w PR: każde miasto ma kilka towarów, które robi tanio, i resztę musi sprowadzić. To gwarantuje ruch ciężarówek bez skryptu.
9. **Ujście musi być zawsze**: zużycie ludności, zużycie ciężarówek i budynków (amortyzacja zjada stal i plastik), budowy aktorów i odbudowa po pożarach. Odpowiednik „wojny jako popytu” z X4 to u nas wstrząsy i amortyzacja. Sonda ma pilnować, że magazyny nie rosną w nieskończoność.
10. **Inwestycja aktora z wykrytego niedoboru** (`factionlogic` z X4): aktor raz w tygodniu szuka par miasto–towar z ceną trwale przy maksimum i stawia tam firmę. W `god.xml` X4 myśli się ilością produkcji, nie liczbą firm, więc start świata generujmy tak samo: docelowa produkcja towaru → tyle firm, ile trzeba, z seeda.
11. **Brak pętli samoblokujących w przepisach.** Sprawdzać test-em, że żaden towar nie jest niezbędny do zbudowania własnego jedynego producenta (lekcja ze „studni” części kadłuba w X4).
12. **Rezerwacje i ładunek w drodze.** Ciężarówka rezerwuje ilość w ofercie kupna/sprzedaży i dopisuje swój ładunek do „w drodze do miasta Y”. Inni przewoźnicy odejmują to od popytu (już w modelu, warto dodać jawne rezerwacje).
13. **Przewoźnicy przypisani do firmy obok wolnych przewoźników** (X4: statki stacji vs autohandel). Duża firma może mieć własną ciężarówkę, która dowozi jej brakujące wejście, nawet gdy wolny rynek woli inne trasy. To leczy zator „stoczni bez jednej części”.
14. **Wiedza o cenach się starzeje** (X4). Aktor lub przewoźnik decyduje na podstawie cen, które widział lub usłyszał, z wiekiem informacji. Później gracz może kupić „subskrypcję” (gazetę, informatora). Na start wystarczy pełna wiedza z opóźnieniem, a model nie powinien tego blokować.
15. **Gracz jako zwykła firma w tej samej sieci** (obie gry): jego firma wystawia oferty na tym samym rynku, a jego popularność w mieście (PR) rośnie, gdy dowozi brakujące towary. To naturalna droga wspinania się bez osobnych mechanik.
