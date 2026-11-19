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
		check("E4 pozycja: start w mieście, koniec w celu", p0.distance_to(w.cities[t.city_id].pos) < 1.0 and p1.distance_to(w.cities[t.to_city].pos) < 1.0)


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
