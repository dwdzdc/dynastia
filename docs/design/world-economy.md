# Świat, który żyje sam: gospodarka

Ustalenia z autorem z 19.11.2026. Pierwszy kawałek pod nowy core (`vision.md`, sekcja „Core”). Najpierw powstaje wielka, żywa gospodarka bez gracza, a gracza wpychamy w nią później. Inspiracje (X4, Port Royale): `wzorce-x4-portroyale.md`.

## Decyzje szkieletowe (zatwierdzone 19.11.2026)

1. **Aktorzy, nie przypisane firmy.** W gospodarce działają aktorzy, czyli ludzie (później rody) z kapitałem. Aktor ma kasę i 0..n firm. To, czym się zajmuje, jest wymienne: może sprzedać piekarnię, zamknąć ją, kupić cudzą rafinerię albo założyć firmę przewozową. Firma to aktywo z właścicielem, które może zmienić właściciela. Ludność miast (pracownicy, konsumenci) jest liczona zbiorczo, a imienne osoby pojawią się tam, gdzie wejdzie gracz.
2. **Sieć miast**, nie jedna ciągła mapa. Miasta są połączone drogami, które mają długość i czas przejazdu. Szczegółowa mapa jednego miejsca to później przybliżenie tam, gdzie jest gracz.
3. **Towar fizycznie jedzie.** Firmy kupują i sprzedają tylko na rynku swojego miasta. Między miastami towar wożą konkretne ciężarówki konkretnych firm przewozowych. Ciężarówka tankuje paliwo, płaci kierowcy, może zostać okradziona albo utknąć przed zamkniętą drogą.
4. **Kryzysy i dobrobyt nie są oskryptowane.** Zdarzenia losowe dotyczą tylko pojedynczych rzeczy: pożar zakładu, strajk, nieurodzaj, zamknięta droga, zbójcy na trasie, nowe złoże. Skutki rozchodzą się same łańcuchami dostaw, cenami i migracją.
5. **Pieniądze w zamkniętym obiegu.** Nikt nie tworzy pieniędzy z powietrza. Suma pieniędzy w świecie jest stała, a test pilnuje tego co dobę. Kredyt i bank to osobny, późniejszy proces.
6. **Uproszczony współczesny katalog** około 17 towarów w kilku łańcuchach plus usługi (nie da się ich przewozić, zatrudniają większość ludzi). Wszystkie liczby siedzą w `data/economy.json`.
7. **Nowa warstwa `sim/econ/` obok starej wsi.** Bierzemy z niej deterministyczne losowanie (`SimRng`) i ładowanie danych. Stara wieś zostaje nietknięta. Do oglądania świata służą sonda headless i podgląd mapy (`game/economy_view.tscn`).

## Model

**Miasto** (`EconCity`): ludność, siła robocza, płaca (rośnie przy niskim bezrobociu, spada przy wysokim), wspólna kasa gospodarstw domowych, złoża (żyzna ziemia, las, ropa, ruda, wapień) i rynek z jednym `EconMarket` na towar.

**Rynek** (`EconMarket`): cena i partie towaru. Każda partia należy do konkretnej firmy (sprzedawcy). Kupujący płaci właścicielom partii proporcjonalnie, więc nie istnieje „kupiec z nieskończoną kasą”. Co dobę cena idzie w górę, gdy zapas jest mniejszy niż kilka dób popytu albo gdy popyt nie został zaspokojony, a w dół przy nadmiarze. Cena ma widełki wokół ceny bazowej (jak w X4).

**Firma** (`EconBusiness`): typ z przepisu (`recipes`), miasto, właściciel, kasa, poziom (skala), pracownicy, magazyn wejść. Co dobę kupuje wejścia na lokalnym rynku, zatrudnia z lokalnej puli, produkuje, wystawia towar i płaci pensje do kasy gospodarstw. Produkuje tylko wtedy, gdy się opłaca. Nadwyżkę kasy oddaje właścicielowi jako dywidendę. Bez kasy na pensje ludzie odchodzą, a długie straty kończą się zamknięciem albo sprzedażą firmy.

**Przewoźnik**: firma z ciężarówkami. Wolna ciężarówka szuka najlepszego interesu: kupić tu, sprzedać tam, odliczając paliwo, kierowcę i to, co inne ciężarówki już wiozą do tego miasta (żeby wszystkie nie rzucały się na jedną trasę). Czasem jedzie pusta tam, gdzie interes jest lepszy. Ciężarówki produkuje fabryka pojazdów ze stali i plastiku i z czasem się zużywają.

**Aktor** (`EconActor`): imię i nazwisko, miasto, kasa, firmy, skłonność do ryzyka, wiek. Raz w tygodniu przegląda interesy: zamyka albo wystawia na sprzedaż te, które przynoszą straty, kupuje tanie firmy innych, rozbudowuje dobre i zakłada nowe tam, gdzie lokalne ceny obiecują zysk. Budowa zużywa prawdziwe deski, cement i stal z rynku oraz trwa. Aktor wydaje część majątku na życie. Gdy umiera, firmy dziedziczy spadkobierca o tym samym nazwisku (czasem dwóch i ród się dzieli). Z oszczędności ludności co jakiś czas wyrasta nowy przedsiębiorca, a bankrut bez firm wraca do szarej masy.

**Ludność**: zbiorczo kupuje koszyk według priorytetów (jedzenie, paliwo, usługi, meble, AGD). Im więcej zarabia, tym więcej kupuje dóbr wyższych. Zaspokojenie potrzeb i zatrudnienie dają dobrobyt miasta. Od dobrobytu zależą przyrost i migracja do sąsiednich miast, a ludzie zabierają ze sobą oszczędności.

**Wstrząsy** (`EconEvents`): pożar zakładu (przestój, utracony towar, naprawa z materiałów), strajk, nieurodzaj albo urodzaj w regionie, zamknięta droga, zbójcy na trasie (rabunek ładunku), nowe złoże albo wyczerpanie złoża.

**Kronika** (`EconNews`): gazeta świata. Wykrywa skoki i krachy cen, braki, bankructwa, przejęcia, fale migracji, kryzys i boom w mieście oraz nowych krezusów. Tam, gdzie to możliwe, podaje przyczynę („po pożarze rafinerii w Wilkowie”).

## Kryteria „żyje”

Sprawdzają je sonda `tools/probe_economy.gd` i testy `tests/run_econ_tests.gd`. Po 2–3 latach bez gracza:

- suma pieniędzy się nie zmienia;
- ludność nie wymiera ani nie eksploduje;
- firmy powstają i padają;
- ceny się ruszają, ale nie przyklejają do widełek;
- ciężarówki jeżdżą;
- w kronice są kryzysy, które mijają.
