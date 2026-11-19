# Testy warstwy RTS (sim/rts/, docs/design/rts-world.md).
# Uruchomienie: godot --headless --script res://tests/run_rts_tests.gd
extends SceneTree


var failures := 0
var checks := 0
var econ_data: Dictionary
var rts_data: Dictionary


func _initialize() -> void:
	econ_data = DataLoader.load_json("res://data/economy.json")
	rts_data = DataLoader.load_json("res://data/rts.json")
	_run_all()
	if failures == 0:
		print("RTS TESTS OK (%d checks)" % checks)
		quit(0)
	else:
		printerr("RTS TESTS FAILED: %d/%d" % [failures, checks])
		quit(1)


func check(name: String, cond: bool) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: %s" % name)


func _world(seed: int = 3) -> RtsWorld:
	return RtsWorld.new(seed, econ_data, rts_data, false)


func _run_all() -> void:
	_test_time_and_money()
	_test_layout()
	_test_unit_works()
	_test_player_builds()
	_test_player_truck()
	_test_world_lives_with_idle_player()
	_test_family_needs()


# R2: płynny czas liczy doby gospodarki; gracz nie tworzy pieniędzy.
func _test_time_and_money() -> void:
	var w := _world()
	var money := w.econ.money_total()
	var d0 := w.econ.day
	for i in 250:
		w.advance(0.01)
	check("R2 2,5 doby -> 2–3 doby gospodarki", w.econ.day - d0 >= 2 and w.econ.day - d0 <= 3)
	check("R2 suma pieniędzy z graczem stała", absf(w.econ.money_total() - money) < money * 1e-7)
	check("R2 gracz ma ludzi i kasę", w.units.size() == int(rts_data["player"]["people"]) and w.player.cash > 0.0)


# R2: układ miasta deterministyczny i w granicach mapy.
func _test_layout() -> void:
	var w := _world(5)
	var w2 := _world(5)
	var b: EconBusiness = w.econ.businesses.values()[10]
	check("R2 pozycja firmy deterministyczna", w.business_pos(b) == w2.business_pos(w2.econ.business(b.id)))
	var ms: Array = econ_data["world"]["map_size"]
	var inside := true
	for bb: EconBusiness in w.econ.businesses.values():
		var p := w.business_pos(bb)
		if p.x < -3.0 or p.y < -3.0 or p.x > float(ms[0]) + 3.0 or p.y > float(ms[1]) + 3.0:
			inside = false
	check("R2 firmy na mapie", inside)
	var big: EconCity = w.econ.cities[0]
	var small: EconCity = w.econ.cities[w.econ.cities.size() - 1]
	var lp: Dictionary = rts_data["layout"]
	check("R2 większe miasto ma więcej bloków", RtsLayout.housing(w.econ, lp, big).size() > RtsLayout.housing(w.econ, lp, small).size())


# R5: człowiek gracza idzie do pracy, pracuje, a pensja trafia do gracza.
func _test_unit_works() -> void:
	var w := _world(6)
	var u: RtsUnit = w.units.values()[0]
	var home := w.home_city()
	var job: EconBusiness = null
	for b: EconBusiness in w.econ.businesses.values():
		if b.city_id == home.id and b.status == "active" and b.type == "services":
			job = b
			break
	check("R5 jest praca w mieście", job != null)
	if job == null:
		return
	check("R5 rozkaz pracy przyjęty", w.order_work(u.id, job.id) == "")
	var cash0 := w.player.cash
	for i in 400:
		w.advance(0.01)
	check("R5 doszedł i pracuje", u.inside == job.id and job.extra_workers >= 1.0)
	check("R5 zarabia dla rodu", w.player.cash > cash0 and u.earned > 0.0)
	w.order_move(u.id, home.pos + Vector2(0.5, 0.0))
	check("R5 nowy rozkaz zwalnia etat", u.inside == -1 and job.extra_workers == 0.0)


# R6: gracz buduje firmę z menu, a ta należy do niego i przechodzi przez budowę.
func _test_player_builds() -> void:
	var w := _world(7)
	var c := w.home_city()
	w.player.cash += 200000.0
	c.cash -= 200000.0
	check("R6 brak złoża blokuje", w.build_problem("oil_well", c.id) != "" or c.resources.has("oil"))
	check("R6 budowa ruszyła", w.build("bakery", c.id) == "")
	var mine := w.player_businesses().filter(func(b: EconBusiness) -> bool: return b.type == "bakery")
	check("R6 piekarnia gracza", mine.size() == 1 and (mine[0] as EconBusiness).status == "building")
	for i in 40:
		w.advance(1.0)
	check("R6 AI nie rusza firmy gracza", (mine[0] as EconBusiness).owner_id == w.player.id)
	check("R6 budowa skończona albo czeka na materiały", (mine[0] as EconBusiness).status in ["active", "building", "burned", "strike"])


# R7: ciężarówka gracza: kupno, kurs na rozkaz, trasa stała.
func _test_player_truck() -> void:
	var w := _world(8)
	w.player.cash += 50000.0
	w.home_city().cash -= 50000.0
	# Fabryka ma ciężarówkę na placu (żeby test nie zależał od losu produkcji).
	var plant: EconBusiness = null
	for b: EconBusiness in w.econ.businesses.values():
		if b.type == "vehicle_plant":
			plant = b
	if plant != null:
		w.econ.city_of(plant).market("trucks").add(plant.id, 2.0)
	var why := w.buy_truck()
	check("R7 kupno ciężarówki: %s" % why, why == "")
	var trucks := w.player_trucks()
	check("R7 gracz ma ciężarówkę", trucks.size() == 1)
	if trucks.is_empty():
		return
	var tr: EconTruck = trucks[0]
	var r: EconRoute = w.econ.routes[w.econ.cities[tr.city_id].routes[0]]
	var to := r.other(tr.city_id)
	check("R7 jedź do", w.truck_go(tr.id, to) == "" and tr.moving)
	for i in 3:
		w.advance(1.0)
	check("R7 dojechała", not tr.moving and tr.city_id == to)
	w.truck_route(tr.id, to, tr.city_id if tr.city_id != to else r.other(to), "grain")
	check("R7 trasa stała ustawiona", tr.mode == "route")


# R8: gracz nic nie robi, a świat żyje dalej (świat nie zależy od gracza).
func _test_world_lives_with_idle_player() -> void:
	var w := RtsWorld.new(11, econ_data, rts_data, true)
	var money := w.econ.money_total()
	for i in 200:
		w.advance(1.0)
	var moving := w.econ.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving).size()
	var unemp := 0.0
	for c: EconCity in w.econ.cities:
		unemp += c.unemployment() * c.population
	check("R8 pieniądze stałe po 200 dobach", absf(w.econ.money_total() - money) < money * 1e-6)
	check("R8 ciężarówki jeżdżą", moving > 100)
	check("R8 bezrobocie < 35%%", unemp / w.econ.total_population() < 0.35)
	check("R8 firm przybywa", int(w.econ.stats["founded"]) > 20)


# Ród żyje z kasy: z pieniędzmi ludzie są najedzeni, bez pieniędzy chodzą głodni.
func _test_family_needs() -> void:
	var w := _world(13)
	var money := w.econ.money_total()
	w.advance(1.0)
	var u: RtsUnit = w.units.values()[0]
	check("Ród: z kasą najedzony", u.fed > 0.5)
	check("Ród: zakupy nie tworzą pieniędzy", absf(w.econ.money_total() - money) < money * 1e-7)
	w.home_city().cash += w.player.cash
	w.player.cash = 0.0
	w.advance(1.0)
	check("Ród: bez kasy głodny", u.fed < 0.5)
