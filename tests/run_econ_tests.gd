# Testy gospodarki świata (sim/econ/, docs/design/world-economy.md).
# Uruchomienie: godot --headless --script res://tests/run_econ_tests.gd
extends SceneTree


var failures := 0
var checks := 0
var data: Dictionary


func _initialize() -> void:
	data = DataLoader.load_json("res://data/economy.json")
	var t0 := Time.get_ticks_msec()
	_run_all()
	print("czas: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if failures == 0:
		print("ECON TESTS OK (%d checks)" % checks)
		quit(0)
	else:
		printerr("ECON TESTS FAILED: %d/%d" % [failures, checks])
		quit(1)


func check(name: String, cond: bool) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: %s" % name)


func _world(seed: int = 3, warmup: bool = false) -> EconWorld:
	return EconWorld.new(seed, data, warmup)


func _run_all() -> void:
	_test_map_connected_and_resources()
	_test_deterministic()
	_test_market_price_reacts()
	_test_market_pays_sellers()
	_test_money_conserved()
	_test_chain_produces()
	_test_trucks_carry()
	_test_actor_heirs()
	_test_actor_invests()
	_test_fire_and_cause()
	_test_road_closure_reroutes()
	_test_gazette()
	_test_two_states()
	_test_housing_and_land()


# E1: sieć miast jest spójna, każdy zasób jest w kilku miastach.
func _test_map_connected_and_resources() -> void:
	var w := _world()
	check("E1 liczba miast", w.cities.size() == int(data["world"]["city_count"]))
	var all_finite := true
	for row: PackedFloat32Array in w.dist:
		for v: float in row:
			if v == INF:
				all_finite = false
	check("E1 graf dróg spójny", all_finite)
	for res: String in (data["world"]["resources"] as Dictionary).keys():
		var n := w.cities.filter(func(c: EconCity) -> bool: return c.resources.has(res)).size()
		check("E1 zasób %s w >= 2 miastach" % res, n >= 2)
	var p := EconMap.path(w, 0, w.cities.size() - 1)
	check("E1 ścieżka istnieje", not p.is_empty())


# E1: ten sam seed -> ten sam świat i ten sam przebieg.
func _test_deterministic() -> void:
	var a := _world(11)
	var b := _world(11)
	for i in 30:
		a.step_day()
		b.step_day()
	var same := a.cities.size() == b.cities.size() and absf(a.money_total() - b.money_total()) < 1e-6
	for i in a.cities.size():
		same = same and a.cities[i].pos == b.cities[i].pos and absf(a.cities[i].market("bread").price - b.cities[i].market("bread").price) < 1e-9
	same = same and a.businesses.size() == b.businesses.size() and a.news.entries.size() == b.news.entries.size()
	check("E1 determinizm 30 dób", same)
	var c := _world(12)
	check("E1 inny seed -> inny świat", c.cities[0].pos != a.cities[0].pos)


# E2: brak towaru podnosi cenę, nadmiar ją obniża.
func _test_market_price_reacts() -> void:
	var mp: Dictionary = data["market"]
	var m := EconMarket.new("bread", 6.0)
	m.demand_ema = 100.0
	for i in 10:
		m.buy(100.0, 1e9, func(_s: int, _a: float) -> void: pass)
		m.end_day(mp, false)
	check("E2 brak towaru -> cena rośnie", m.price > 6.0 * 1.3)
	var n := EconMarket.new("bread", 6.0)
	n.demand_ema = 100.0
	n.add(1, 100000.0)
	for i in 10:
		n.buy(100.0, 1e9, func(_s: int, _a: float) -> void: pass)
		n.end_day(mp, false)
	check("E2 nadmiar -> cena spada", n.price < 6.0 * 0.7)
	check("E2 widełki ceny", n.price >= 6.0 * float(mp["min_mult"]) - 1e-9)


# E2: kupno płaci sprzedawcom proporcjonalnie i co do grosza.
func _test_market_pays_sellers() -> void:
	var m := EconMarket.new("bread", 5.0)
	m.add(1, 30.0)
	m.add(2, 10.0)
	var got := {1: 0.0, 2: 0.0}
	var res: Array = m.buy(20.0, 1e9, func(s: int, a: float) -> void: got[s] = float(got[s]) + a)
	check("E2 kupiono 20", absf(float(res[0]) - 20.0) < 1e-6)
	check("E2 koszt = suma wpłat", absf(float(res[1]) - (float(got[1]) + float(got[2]))) < 1e-6)
	check("E2 proporcjonalnie 3:1", absf(float(got[1]) - 3.0 * float(got[2])) < 1e-6)
	var budget_res: Array = m.buy(100.0, 25.0, func(_s: int, _a: float) -> void: pass)
	check("E2 budżet ogranicza", absf(float(budget_res[1]) - 25.0) < 1e-6)


# E2: suma pieniędzy w świecie stała przez 120 dób.
func _test_money_conserved() -> void:
	var w := _world(5)
	var start := w.money_total()
	var ok := true
	for i in 120:
		w.step_day()
		if absf(w.money_total() - start) > start * 1e-7:
			ok = false
			printerr("  dzień %d: %.2f vs %.2f" % [w.day, w.money_total(), start])
			break
	check("E2 suma pieniędzy stała 120 dób", ok)


# E3: łańcuch zboże → mąka → chleb działa, firmy płacą pensje.
func _test_chain_produces() -> void:
	var w := _world(4)
	for i in 10:
		w.step_day()
	var made := {}
	for b: EconBusiness in w.businesses.values():
		if b.type != "haulage" and b.is_open():
			var out: String = w.recipe(b.type)["out"]
			made[out] = float(made.get(out, 0.0)) + b.produced_today
	check("E3 zboże powstaje", float(made.get("grain", 0.0)) > 0.0)
	check("E3 mąka powstaje", float(made.get("flour", 0.0)) > 0.0)
	check("E3 chleb powstaje", float(made.get("bread", 0.0)) > 0.0)
	var wages := 0.0
	for c: EconCity in w.cities:
		wages += c.income_ema
	check("E3 ludność zarabia", wages > 0.0)


# E4: ciężarówki wiozą towar między miastami (kursy, ładunek dojeżdża do celu).
func _test_trucks_carry() -> void:
	var w := _world(4)
	for i in 20:
		w.step_day()
	check("E4 kursy się odbywają", int(w.stats["trips"]) > 50)
	var moving := w.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving and t.qty > 0.0)
	check("E4 ciężarówki jadą z ładunkiem", moving.size() > 0)
	if not moving.is_empty():
		var t: EconTruck = moving[0]
		var p0 := w.truck_pos(t, t.depart_time)
		var p1 := w.truck_pos(t, t.arrive_time)
		check("E4 pozycja: start w punkcie wyjazdu, koniec u odbiorcy", p0.distance_to(t.pts[0]) < 0.01 and p1.distance_to(t.dest_spot["pos"]) < 0.01)
	# Ładunki jadą od budynku do budynku, a nie od centrum do centrum.
	var to_firm := 0
	var off_center := 0
	for t: EconTruck in moving:
		if t.to_bid != -1:
			to_firm += 1
		if (t.dest_spot["pos"] as Vector2).distance_to(w.cities[t.to_city].pos) > 0.05:
			off_center += 1
	check("E4 kursy kończą się pod firmą odbiorcy", to_firm > moving.size() * 0.8 and off_center > moving.size() * 0.8)


# E5: śmierć aktora — spadkobierca z tego samego rodu przejmuje firmy i kasę.
func _test_actor_heirs() -> void:
	var w := _world(6)
	var rich: EconActor = null
	for a: EconActor in w.living_actors():
		if a.businesses.size() >= 1 and (rich == null or a.businesses.size() > rich.businesses.size()):
			rich = a
	var firms := rich.businesses.duplicate()
	var money := w.money_total()
	rich.death_day = w.day
	w.step_day()
	check("E5 aktor zmarł", not rich.alive and rich.businesses.is_empty())
	var heirs := w.living_actors().filter(func(a: EconActor) -> bool: return a.parent_id == rich.id)
	check("E5 jest spadkobierca z rodu", heirs.size() >= 1 and heirs.all(func(h: EconActor) -> bool: return h.family_id == rich.family_id))
	var owned := 0
	for h: EconActor in heirs:
		owned += h.businesses.size()
	check("E5 firmy przeszły na spadkobierców", owned == firms.size())
	check("E5 pieniądze bez zmian przy dziedziczeniu", absf(w.money_total() - money) < money * 1e-7)


# E5: aktor z kapitałem coś buduje albo kupuje (to, czym się zajmuje, jest wymienne).
func _test_actor_invests() -> void:
	var w := _world(8)
	for i in 60:
		w.step_day()
	check("E5 aktorzy zakładają firmy", int(w.stats["founded"]) > 0)


# E6 + E7: pożar zatrzymuje firmę, a kronika podaje przyczynę skoku ceny.
func _test_fire_and_cause() -> void:
	var d2: Dictionary = data.duplicate(true)
	d2["events"]["fire_chance"] = 1.0
	var w := EconWorld.new(9, d2, false)
	EconEvents.step(w)
	var burned := w.businesses.values().filter(func(b: EconBusiness) -> bool: return b.status == "burned")
	check("E6 pożar zatrzymuje firmy", burned.size() > 0)
	check("E6 kronika pisze o pożarze", w.news.entries.any(func(e: Dictionary) -> bool: return e["kind"] == "fire"))
	var c: EconCity = w.cities[0]
	var m := c.market("bread")
	w.news.tag_shock(c, "bread", "po pożarze: Piekarnia Testowa", 30)
	m.price = m.price_ema * 3.0
	w.day = 10
	w.news.step()
	var hit := w.news.entries.filter(func(e: Dictionary) -> bool: return e["kind"] == "spike" and str(e["text"]).contains("Piekarnia Testowa"))
	check("E7 skok ceny z przyczyną", hit.size() == 1)


# E6: zamknięta droga — trasa ją omija (albo nie ma trasy).
func _test_road_closure_reroutes() -> void:
	var w := _world(3)
	var r: EconRoute = w.routes[0]
	var direct := EconMap.path(w, r.a, r.b)
	r.closed_until = w.day + 10
	var around := EconMap.path(w, r.a, r.b)
	check("E6 objazd nie używa zamkniętej drogi", not around.has(r.id))
	check("E6 bez zamknięcia trasa bywa bezpośrednia", direct.size() >= 1)


# Kurier: numer za miesiąc ma nagłówek i cztery kolumny, nic nie zmienia w świecie.
func _test_gazette() -> void:
	var w := _world(5)
	for i in 65:
		w.step_day()
	var money := w.money_total()
	var issue := EconGazette.issue(w, 60)
	check("Kurier ma nagłówek", str(issue["headline"]) != "")
	check("Kurier ma 4 kolumny", (issue["columns"] as Array).size() == 4)
	check("Kurier: ranking rodów", ((issue["columns"] as Array)[3]["lines"] as Array).size() > 0)
	check("Kurier nie zmienia świata", absf(w.money_total() - money) < 1e-6)


# Państwa: trzy z danych, zwarte obszary, cła na granicy, pieniądze się zgadzają.
func _test_two_states() -> void:
	var d2: Dictionary = data.duplicate(true)
	(d2["states"][1] as Dictionary)["policies"] = [{"type": "dividend_tax", "rate": 0.3}, {"type": "import_tariff", "rate": 0.12}, {"type": "pensions", "share": "rest"}]
	var w := EconWorld.new(12, d2, false)
	check("Państwa: trzy z danych", w.states.size() == 3 and w.capitals.size() == 3)
	var count := [0, 0, 0]
	for c: EconCity in w.cities:
		count[c.state_id] += 1
	check("Państwa: każde ma kilka miast %s" % str(count), count.min() >= 4)
	# Zwartość: z każdego miasta da się dojść do stolicy, nie wychodząc z państwa.
	var compact := true
	for i in 3:
		var seen := {w.capitals[i]: true}
		var queue: Array = [w.capitals[i]]
		while not queue.is_empty():
			var cid: int = queue.pop_back()
			for rid: int in w.cities[cid].routes:
				var o := w.routes[rid].other(cid)
				if w.cities[o].state_id == i and not seen.has(o):
					seen[o] = true
					queue.append(o)
		if seen.size() != count[i]:
			compact = false
	check("Państwa: zwarte obszary", compact)
	var money := w.money_total()
	for i in 60:
		w.step_day()
	check("Państwa: pieniądze stałe", absf(w.money_total() - money) < money * 1e-7)
	var public_in_second := 0.0
	for c: EconCity in w.cities:
		if c.state_id == 1:
			public_in_second += c.public_workers
	check("Państwa: bez budżetówki w państwie bez tej polityki", public_in_second == 0.0)
	check("Państwa: wszystkie zbierają podatki", w.states.all(func(st: EconState) -> bool: return st.income_ema > 0.0))
	check("Państwa: cła pobrane na granicach", float(w.stats.get("tariffs", 0.0)) > 0.0 and w.states.all(func(st: EconState) -> bool: return st.tariffs_total > 0.0))
	check("Cło: w kraju 0, za granicą stawka państwa celu", w.tariff_rate(w.capitals[0], w.capitals[0]) == 0.0 and absf(w.tariff_rate(w.capitals[0], w.capitals[1]) - 0.12) < 1e-6)


# Nieruchomości: działka droższa w dużym mieście i płacona państwu; czynsz z ciasnoty.
func _test_housing_and_land() -> void:
	var w := _world(14)
	var order: Array = w.cities.duplicate()
	order.sort_custom(func(a: EconCity, b: EconCity) -> bool: return a.population > b.population)
	var big: EconCity = order[0]
	var small: EconCity = order[order.size() - 1]
	check("Działka: w dużym mieście droższa", EconHousing.land_cost(w, "bakery", big) > EconHousing.land_cost(w, "bakery", small) * 3.0)
	check("Działka: pole za miastem tanie", EconHousing.land_cost(w, "grain_farm", big) < EconHousing.land_cost(w, "refinery", big))
	var flats := w.businesses.values().filter(func(b: EconBusiness) -> bool: return b.type == "apartments" and b.city_id == big.id)
	check("Mieszkania: kamienice na start", not flats.is_empty() and big.homes_owned > 0.0)
	var money := w.money_total()
	var st := w.state_of_city(big.id)
	var a: EconActor = w.living_actors()[0]
	a.cash += 500000.0
	big.cash -= 500000.0
	var st_cash := st.cash
	var b := EconInvest.found(w, a, "bakery", big, EconInvest.build_cost(w, "bakery", big))
	check("Działka: zapłacona państwu", st.cash - st_cash >= EconHousing.land_cost(w, "bakery", big) * 0.99 and b.status == "building")
	w.step_day()
	var rent_income := 0.0
	for f: EconBusiness in flats:
		rent_income += f.revenue_today
	check("Mieszkania: czynsz płynie do kamienic", big.rent_paid_today > 0.0)
	check("Mieszkania: pieniądze stałe", absf(w.money_total() - money) < money * 1e-7)
	# Napływ ludzi bez nowych mieszkań: ciasnota i rosnący czynsz.
	var r0 := big.rent_mult
	big.population *= 1.3
	for i in 30:
		w.step_day()
	check("Mieszkania: ciasnota po napływie", big.crowded > 0.0)
	check("Mieszkania: czynsz rośnie przy ciasnocie", big.rent_mult > r0 + 0.1)
	var crowded_news := w.news.entries.filter(func(e: Dictionary) -> bool: return e["kind"] == "housing" and e["city"] == big.id)
	check("Mieszkania: kronika o braku mieszkań", not crowded_news.is_empty())
