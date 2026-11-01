# Leniwa materializacja danych relacyjnych

Relacje i więzi postaci LOD 0 wobec osób spoza ekranu pozostają nie-wygenerowane, dopóki gracz nie zdobędzie o nich wiedzy; powstają dopiero wtedy, deterministycznie i spójnie niezależnie od kolejności (`hash(world_seed, entity_id, purpose)`). Tożsamość wewnętrzna postaci (wiek, płeć, imię, traity, skille) jest ustalana w całości przy materializacji do LOD 0. Opcja odrzucona: pełny graf relacyjny budowany od razu — odrzucona, bo narzuca symulowanie relacji, o których gracz nic nie wie, i zaprzecza zasadzie „wiedza jako ujawnianie".
