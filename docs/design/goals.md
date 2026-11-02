# Dynastia — cele długoterminowe

Notatki autora z 02.11.2026 (po iteracji 1). To są **cele, nie plan**: nic z tego nie jest teraz implementowane, ale model danych i architektura nie mogą tego blokować. Kolejność i zakres ustalamy z autorem przed każdą iteracją. Uzupełnia `intro` (ścieżki rozwoju §7, pracownicy §3–5, epoki §9) i `vision.md`.

## Zagrożenia ze świata

- **Dzikie zwierzęta.** W lesie są wilki i niedźwiedzie; mogą zaatakować i zabić kogoś z rodu.
- **Przestępcy w mieście.** Napady, porwania, zabójstwa.
- **Obrona.** Każdy umie się bronić w innym stopniu (umiejętność, cechy, wiek); wynik spotkania nie jest z góry przesądzony.
- **Pożary i kataklizmy.** Niszczą budynki, zapasy, ludzi.

## Zaginięcia i powroty

- Ktoś idzie do lasu i **zaginął**. Gracz nie wie, co się stało. Później ktoś może znaleźć jego ciało (nadjedzone przez zwierzęta) albo szkielet. To zamyka historię albo nie.
- **Porwane dziecko** zostaje siłą odłączone od rodu (zdarzenie przynależności, nie dryf). Może się kiedyś odnaleźć, już dorosłe i np. jako przestępca, z własnymi wspomnieniami, ale bez więzi z rodem, które zdążyłyby wyrosnąć.
- Mechanika zaawansowana. Model musi to unieść: osoba żyje poza mapą/poza rodem (LOD, ród AI), a jej historia jest śledzona.

## Ścieżki życia i kariera

- Ścieżki z `intro` §7: szare życie, rzemiosło (czeladnictwo → mistrz), własny interes, nauka, przestępczość, cwaniactwo.
- To część domyślnej rozgrywki i ma mocno wpływać na dynamikę rodu (różne drogi w jednej rodzinie, zderzenia celów, kto komu poświęca czas).

## Tradycja i płeć w preferencjach

- **Płeć dorosłych jest jednym z czynników** (nie jedynym), za kim dziecko chętniej chodzi: dziewczynki częściej spędzają czas z kobietami, chłopcy z mężczyznami.
- Tak przenoszą się **tradycje pokoleniowe**: jeśli w rodzie kobiety szyły w domu, dziewczynki to widzą i dorastają z przekonaniem, że to ich droga. W innym rodzie może być odwrotnie (kobiety w tartaku, mężczyźni w domu), a dzieci przejmą ten wzór.
- Zawsze może trafić się ktoś, kto uparcie chce czegoś innego niż jego płeć w tym rodzie. To ma być możliwe i ciekawe, a nie błąd.
- Implementacyjnie: składnik wagi w wyborze dorosłego do naśladowania (dziś `SimJobs.follow_target`, D5), plus ewentualnie skłonność z danych epoki.

## Budowanie, ziemia, majątek

- **Budowanie jak w Cultures:** stawianie budynków na mapie. Duże przedsięwzięcie (materiały, czas, ludzie), solidny budynek tym bardziej.
- **Ziemia trzeba posiadać.** Majątek ziemski jako aktywo rodu albo osoby.
- **Pracownicy** (`intro`): majętny ród zatrudnia ludzi do tartaku, budowy itd. Ród może nic nie robić, tylko bywać na salonach, a robotnicy budują mu majątek (np. ród deweloperów, ziemianie).

## Start gry i mapa

- **Mapa generowana proceduralnie**, nie stała.
- Gracz wybiera na starcie: **epokę**, **miejsce** (miasto, wieś, odludzie) i **rodzinę początkową** (jak w Simsach: singiel albo gotowa rodzina, np. z piątką dzieci i babcią).

## Rozważania do zaadresowania później (02.11.2026, w trakcie iteracji 2)

- **Prywatny ekwipunek.** Każdy ma bazowy, mały ekwipunek osobisty (gdzie trzyma jedzenie, pieniądze, drobiazgi). Akcesoria go powiększają: plecak, sakwa. Nie każdy je ma; można je kupić, ukraść, a wyrabia je konkretny rzemieślnik. Ważne zwłaszcza dla bezdomnych: zdobyte jedzenie trzeba gdzieś trzymać.
- **Szałas na dziko.** Bezdomny może postawić prowizoryczne schronienie. Bezdomność ma być trudna, ale nie niemożliwa.
- **Bezdomność rozbija ród.** Jeśli decyzje roota doprowadziły rodzinę na bruk, ludzie się od niego odwracają: kłótnie, córka desperacko wychodzi za mąż, żona odchodzi, rodzeństwo się wyrzeka, syn wyjeżdża albo idzie do roboty sam. Spirala w dół jak w życiu (wspomnienia o eksmisji, obwinianie roota, przyspieszony dryf).
- **Kupcy wędrowni pochodzą z konkretnych miejsc.** Docelowo świat to kraj albo wiele krajów; kupcy przyjeżdżają z różnych miast z różnym popytem i podażą. Mechanizm kupców (H3) ma to unieść: kupiec ma pochodzenie, a oferta wynika z jego miejsca, nie z losowania z powietrza.
- **Root odchodzi z rodu.** Pomysł: przełączam roota na awanturniczą córkę, odłączam się od bogatej rodziny i zakładam własny ród (ród rzezimieszków, rodzina mafijna, życie awanturnicze zamiast statycznego gospodarstwa). Otwarte: root nie powinien móc wżenić się w bogaty ród i przejąć nad nim kontroli (to by psuło sens); raczej zaczyna od zera albo z tym, co ma przy sobie.
