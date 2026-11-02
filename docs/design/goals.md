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
