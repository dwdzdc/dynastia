# SimAI — decyzje rodów spoza gracza (G2). Model, potrzeby i plan dnia mają ten sam
# kod co ród gracza (SimJobs); tu jest tylko to, co gracz robi ręcznie: przydział pracy.
# Raz na dobę każde gospodarstwo AI patrzy na spiżarnię i kasę i rozdziela ludzi.
class_name SimAI
extends RefCounted


var w: SimWorld

const FOUND_RINGS := 4    # ile pierścieni wokół domu przeszukać pod budowę
const FOUND_DIRS := 8     # ile kierunków na pierścień


func _init(world: SimWorld) -> void:
	w = world


func new_day() -> void:
	var cfg: Dictionary = w.balance["ai"]
	post_offers()
	set_prices()
	found_enterprises()
	_merchant_trips()
	_sell_when_broke()
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty():
			continue
		var workers: Array = []
		for pid in h.members:
			var p: SimPerson = w.family.persons[pid]
			var a := w.agent_by_id(p.agent_id)
			if a == null or a.status != "active" or not a.can_work() or w.family.is_ours(p):
				continue
			workers.append(a)
		# Bez klas (S20): kogo stać, ten nie najmuje się do cudzej roboty — żyje z majątku,
		# płaci, nadzoruje, bywa. Decyduje skrzynia, nie rola w danych.
		var ent_jobs := enterprise_jobs(h)
		if not workers.is_empty() and h.cash / float(workers.size()) >= float(cfg["wealthy_cash_per_adult"]):
			# Bogaty właściciel warsztatów najmuje do nich ludzi (T2).
			_post_enterprise_offers(h, ent_jobs)
			# Role z majątku: kramarz za ladą własnego straganu (M2), zaopatrzeniowiec, gdy
			# stragan skupuje i dokupuje (kupiec, M5), nadzorca, gdy mają najętych (L6).
			var roles: Array = []
			var own: Array = w.trade.stalls_of(h.id).filter(func(x): return not x.temporary)
			if not own.is_empty():
				roles.append("stallkeeper")
				if not own[0].buys.is_empty():
					roles.append("carrier")
			if not w.contracts.of_employer(h.id).is_empty():
				roles.append("overseer")
			for i in workers.size():
				var wa: SimAgent = workers[i]
				w.contracts.quit(w.person_of(wa), "")
				var job: String = roles[i] if i < roles.size() else "none"
				_assign(wa, job)
				wa.workplace = own[0].id if job == "stallkeeper" else ""
			continue
		_post_enterprise_offers(h, [])
		# Biedniejszy właściciel warsztatu (T2): domownicy najpierw do swojej roboty.
		var own_jobs: Array = ent_jobs.duplicate()
		var home: SimBuilding = w.buildings.get(h.home_id)
		var hungry := home != null and home.amount("food") < int(cfg["forage_when_food_below"]) \
			and h.cash < float(cfg["forage_when_cash_below"])
		var winter := w.clock.current_season() == "winter"
		# Pusta spiżarnia, a pieniądze są: ktoś idzie w dzień na zakupy (tragarz domu).
		var shop_run := home != null and home.amount("food") < h.target_food / 2 and not hungry
		# Praca u kogoś (L3): kto ma umowę, robi swoje; reszta bierze najlepszą ofertę,
		# a jak żadna się nie opłaca — las (poza zimą) albo wolne.
		var foragers := 0
		for a: SimAgent in workers:
			var p := w.person_of(a)
			if hungry and foragers < int(cfg["max_foragers"]) and not winter:
				w.contracts.quit(p, "")
				_assign(a, "forager")
				foragers += 1
				continue
			if shop_run:
				w.contracts.quit(p, "")
				_assign(a, "carrier")
				shop_run = false
				continue
			if not own_jobs.is_empty():
				w.contracts.quit(p, "")
				var oj: Dictionary = own_jobs.pop_front()
				_assign(a, String(oj["job"]))
				a.workplace = ""
				continue
			if not w.contracts.of_worker(p.id).is_empty():
				continue
			var o := w.contracts.best_offer_for(p)
			if not o.is_empty():
				w.contracts.hire(o, p)
				w.jobs.replan(a)
			else:
				_assign(a, "none" if winter else "forager")
	_shelter_homeless()   # po przydziałach: bezdomni budują szałas (X5)


# Granice cen rodów AI (M3, R4): z zapasu i potrzeb. Czego brakuje — za to zapłacą
# więcej; czego mają za dużo — sprzedadzą taniej. Ród ze straganem, który skupuje
# (kupiec), kupuje tanio i sprzedaje drogo, a przy pustej półce podnosi cenę.
func set_prices() -> void:
	var tc: Dictionary = w.balance["trade"]
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.home_id == "":
			continue
		var own: Array = w.trade.stalls_of(h.id).filter(func(x): return not x.temporary)
		var merchant: bool = own.any(func(x): return not x.buys.is_empty())
		var home: SimBuilding = w.buildings.get(h.home_id)
		for g in tc["ref"]:
			var r := w.trade.ref(g)
			if merchant:
				var st: SimStall = own[0]
				var target := maxf(1.0, float(tc["restock_target"].get(g, 1)))
				var scarce := clampf(1.0 - float(st.stock.amount(g)) / target, -1.0, 1.0)
				w.trade.set_limit(h, g, "sell_min", r * float(tc["stall_sell_min"]) * (1.0 + float(tc["scarcity_price"]) * scarce))
				w.trade.set_limit(h, g, "buy_max", r * float(tc["stall_buy_max"]) * (1.0 + float(tc["scarcity_price"]) * scarce))
				continue
			var shortage := _shortage(h, home, g)
			var surplus := _surplus(h, g)
			var bmax := r * float(tc["ai_buy_max"]) * (1.0 + float(tc["need_price"]) * shortage)
			# Wsad do własnego warsztatu: najwyżej tyle, żeby wyrób się jeszcze opłacał (T2).
			var be := _input_break_even(h, g)
			if be > 0.0:
				bmax = be
			w.trade.set_limit(h, g, "buy_max", bmax)
			w.trade.set_limit(h, g, "sell_min", r * float(tc["ai_sell_min"]) * (1.0 - float(tc["glut_price"]) * surplus))


# Cena wsadu, przy której warsztat rodu wychodzi jeszcze na swoje (0 = to nie wsad).
func _input_break_even(h: SimHousehold, g: String) -> float:
	for e: Dictionary in w.enterprises.values():
		if int(e["owner"]) != h.id:
			continue
		for r: Dictionary in w.jobs.recipes.values():
			if String(r["type"]) != e["type"] or not r["inputs"].has(g):
				continue
			var out := 0.0
			for o in r["outputs"]:
				out += float(r["outputs"][o]) * w.trade.ref(o)
			var qty := 0.0
			for i in r["inputs"]:
				qty += float(r["inputs"][i])
			return out / maxf(qty, 1.0) * float(w.balance["ai"]["input_margin_keep"])
	return 0.0


# Brak 0..1: jak bardzo czegoś brakuje w domu względem tego, co dom chce mieć.
func _shortage(h: SimHousehold, home: SimBuilding, g: String) -> float:
	if home == null:
		return 1.0
	var target := 0
	match g:
		"food":
			target = h.target_food
		"log":
			target = h.target_firewood
		"plank":
			target = w.needs.repair_planks(home) if w.needs.needs_repair(home) else 0
		_:
			target = w.needs.target(h, g)
	if target <= 0:
		return 0.0
	return clampf(1.0 - float(home.amount(g)) / float(target), 0.0, 1.0)


# Nadmiar 0..1: producent z pełnym składem (np. dwór z pełnym spichrzem) sprzedaje taniej.
func _surplus(h: SimHousehold, g: String) -> float:
	var best := 0.0
	for st: SimStall in w.trade.stalls_of(h.id):
		if st.temporary or not st.deals_in(g):
			continue
		var cap := float(st.stock.capacity.get(g, 0))
		if cap > 0.0:
			best = maxf(best, clampf(float(st.stock.amount(g)) / cap, 0.0, 1.0))
	return best


# Upadek (V3): ród AI, któremu dług przerósł kredyt, sprzedaje majątek (warsztat albo
# dom, w którym nie mieszka, a w ostateczności ten, w którym mieszka) temu, kogo stać.
func _sell_when_broke() -> void:
	var mult := float(w.balance["ai"]["fire_sale_mult"])
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.debt <= h.debt_limit:
			continue
		var lid: int = w.family.persons[h.members[0]].lineage_id
		var bv: Dictionary = w.standing._cfg["building_value"]
		var asset: SimBuilding = null
		for b: SimBuilding in w.buildings.values():
			if b.owner_kind == "lineage" and b.owner_id == lid and b.id != h.home_id and float(bv.get(b.type, bv["default"])) > 0.0 \
					and not w.trade.stalls.has(b.id):
				asset = b
				break
		if asset == null:
			continue
		var price: float = float(bv.get(asset.type, bv["default"])) * mult
		var buyer: SimHousehold = null
		for o: SimHousehold in w.households.values():
			if o == h or o.members.is_empty() or o.home_id == "" or o.cash < price:
				continue
			if buyer == null or o.cash > buyer.cash:
				buyer = o
		if buyer == null:
			continue
		buyer.pay(price)
		h.earn(price)
		asset.owner_id = w.family.persons[buyer.members[0]].lineage_id
		if w.enterprises.has(asset.id):
			w.enterprises[asset.id]["owner"] = buyer.id
		var sl: SimLineage = w.family.lineages[lid]
		var bl: SimLineage = w.family.lineages[asset.owner_id]
		var text := "Ród %s, zadłużony, sprzedaje %s rodowi %s za %d zł." % [sl.name, asset.name, bl.name, int(price)]
		w.chronicle.add(w.clock.now(), "sale", text, [], lid)
		w.note(text, "info", asset.door())


# Bezdomny ród AI stawia szałas na dziko i sam go buduje (X5); z niego dalej może
# się wybić (wynajem, dom), a w nędzy odejść do miasta (X3).
func _shelter_homeless() -> void:
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.home_id != "":
			continue
		var l := w.family.lineage_of(w.family.persons[h.members[0]])
		if l == null or l.role == "trader":
			continue
		var builders: Array = h.members.map(func(pid): return w.agent_by_id(w.family.persons[pid].agent_id)).filter(
			func(x): return x != null and x.is_active() and x.can_work())
		if builders.is_empty():
			continue
		var sid := ""
		for k in w.sites:
			if int(w.sites[k]["household"]) == h.id:
				sid = k
		if sid == "":
			var fr: Dictionary = w.map["forest"]
			var edge := Vector2(float(fr["x"]) + float(fr["w"]) + 4.0, float(fr["y"]) + float(fr["h"]) * 0.6)
			var at := _free_spot_near(edge, float(w.buildables["shack"]["clearance"]))
			if at.x == INF:
				continue
			sid = w.commission("shack", at, null, h)
			if sid == "":
				continue
			w.note("Ród %s stawia szałas na dziko." % l.name, "info", at)
		var wa: SimAgent = builders[0]
		w.contracts.quit(w.person_of(wa), "")
		wa.job = "builder"
		wa.workplace = sid
		w.jobs.replan(wa)


# Kupiec AI jeździ do miasta (U3), gdy ma na półce coś, czego miastu brakuje, a tam
# zapłacą więcej niż on sam bierze we wsi.
func _merchant_trips() -> void:
	var min_value := float(w.traders._cfg["trips"]["min_trip_value"])
	for h: SimHousehold in w.households.values():
		if h == w.household:
			continue
		var own: Array = w.trade.stalls_of(h.id).filter(func(x): return not x.temporary and not x.buys.is_empty())
		if own.is_empty():
			continue
		var st: SimStall = own[0]
		var traveler: SimAgent = null
		for pid in h.members:
			var a := w.agent_by_id(w.family.persons[pid].agent_id)
			if a != null and a.is_active() and a.job == "carrier" and not w.trips.on_trip(a):
				traveler = a
		if traveler == null:
			continue
		for tid in w.traders.towns:
			var town: SimTown = w.traders.towns[tid]
			var plan: Dictionary = w.trips.cargo_plan(town, st.stock)
			var value := 0.0
			for g in plan:
				if town.price(g) > w.trade.sell_min(h, g):
					value += float(plan[g]) * town.price(g)
			if value >= min_value:
				w.trips.start(traveler, tid, st.stock)
				break


# Zakładanie warsztatów (T3): zamożny ród AI, który widzi, że wyrobu brakuje u kupca
# (pusta półka, wysoka cena), a nikt we wsi go nie robi, zleca budowę z katalogu.
func found_enterprises() -> void:
	var cfg: Dictionary = w.balance["ai"]
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.home_id == "" or h.cash < float(cfg["found_cash"]):
			continue
		if w.sites.values().any(func(s): return int(s["household"]) == h.id):
			continue
		for kind in w.buildables:
			var bc: Dictionary = w.buildables[kind]
			if not bool(bc.get("enterprise", false)) or w.enterprise_building(h.id, String(bc["result"])) != null:
				continue
			if not _scarce_output(String(bc["result"])):
				continue
			var at := _free_spot_near(w.buildings[h.home_id].position, float(bc["clearance"]))
			if at.x != INF and w.commission(kind, at, null, h) != "":
				w.note("Ród %s zaczyna budować: %s." % [w.family.lineage_of(w.family.persons[h.members[0]]).name, String(bc["label"]).to_lower()], "info", at)
				break


# Czy wyrobu tego typu warsztatu brakuje na rynku: kupiec ma mało, a nikt go nie robi.
func _scarce_output(type: String) -> bool:
	var tc: Dictionary = w.balance["trade"]
	for e: Dictionary in w.enterprises.values():
		var oh: SimHousehold = w.households.get(int(e["owner"]))
		if e["type"] == type and oh != null and operating(oh, e["b"]):
			return false
	for r: Dictionary in w.jobs.recipes.values():
		if String(r["type"]) != type:
			continue
		for g in r["outputs"]:
			var stock := 0
			for st: SimStall in w.trade.stalls.values():
				if not st.temporary:
					stock += st.stock.amount(g)
			if float(stock) < float(tc["restock_target"].get(g, 1)) * float(w.balance["ai"]["found_when_stock_below"]):
				return true
	return false


# Wolne miejsce pod budowę w pobliżu domu (z dala od innych budynków i pól).
func _free_spot_near(center: Vector2, clearance: float) -> Vector2:
	var ws: Array = w.map["world_size"]
	for ring in range(1, FOUND_RINGS + 1):
		for k in FOUND_DIRS:
			var ang := TAU * float(k) / float(FOUND_DIRS)
			var p := center + Vector2(cos(ang), sin(ang)) * clearance * 1.2 * float(ring)
			if p.x < 2.0 or p.y < 2.0 or p.x > float(ws[0]) - 2.0 or p.y > float(ws[1]) - 2.0:
				continue
			var ok := true
			for b: SimBuilding in w.buildings.values():
				if b.position.distance_to(p) < clearance:
					ok = false
					break
			for f: SimField in w.fields:
				if f.rect.grow(clearance * 0.5).has_point(p):
					ok = false
			var fr: Dictionary = w.map["forest"]
			if Rect2(float(fr["x"]), float(fr["y"]), float(fr["w"]), float(fr["h"])).grow(2.0).has_point(p):
				ok = false
			if ok:
				return p
	return Vector2(INF, INF)


# Jakie stanowiska są dziś potrzebne w warsztatach rodu (T2): zawód z receptury,
# dostawca surowca z danych (np. kłody — drwal) i tragarz, który sprzedaje wyroby
# i dokupuje wsad. Warsztat, który się nie opłaca albo zawalony towarem, stoi.
func enterprise_jobs(h: SimHousehold) -> Array:
	var cfg: Dictionary = w.balance["ai"]
	var out: Array = []
	for e: Dictionary in w.enterprises.values():
		if int(e["owner"]) != h.id or not operating(h, e["b"]):
			continue
		var b: SimBuilding = e["b"]
		for r: Dictionary in w.jobs.recipes.values():
			if String(r["type"]) != b.type:
				continue
			out.append({ "job": String(r["job"]), "place": b.id })
			for g in r["inputs"]:
				if cfg["input_jobs"].has(g):
					out.append({ "job": String(cfg["input_jobs"][g]), "place": b.id })
	if not out.is_empty():
		out.append({ "job": "carrier", "place": "" })
	return out


# Czy warsztat ma sens dziś pracować: wyroby są warte więcej niż wsad, jest gdzie
# je składać, a w skrzyni starcza na wsad i dniówki.
func operating(h: SimHousehold, b: SimBuilding) -> bool:
	var cfg: Dictionary = w.balance["ai"]
	if h.cash < float(cfg["enterprise_min_cash"]):
		return false
	for r: Dictionary in w.jobs.recipes.values():
		if String(r["type"]) != b.type:
			continue
		var margin := 0.0
		for g in r["outputs"]:
			margin += float(r["outputs"][g]) * w.trade.ref(g)
			if b.space(g) < int(r["outputs"][g]):
				return false
		for g in r["inputs"]:
			margin -= float(r["inputs"][g]) * w.trade.ref(g)
		return margin > 0.0
	return false


func _post_enterprise_offers(h: SimHousehold, jobs_needed: Array) -> void:
	var wage := float(w.balance["ai"]["enterprise_wage"])
	var slots := {}
	for jn: Dictionary in jobs_needed:
		if jn["place"] == "":
			continue
		var k: String = "%s|%s" % [jn["place"], jn["job"]]
		slots[k] = int(slots.get(k, 0)) + 1
	for e: Dictionary in w.enterprises.values():
		if int(e["owner"]) != h.id:
			continue
		for r: Dictionary in w.jobs.recipes.values():
			if String(r["type"]) != e["type"]:
				continue
			var jobs_here: Array = [String(r["job"])]
			for g in r["inputs"]:
				if w.balance["ai"]["input_jobs"].has(g):
					jobs_here.append(String(w.balance["ai"]["input_jobs"][g]))
			for jb in jobs_here:
				var n := int(slots.get("%s|%s" % [e["b"].id, jb], 0))
				n = mini(n, int(floor(h.cash / maxf(wage, 1.0))))
				w.contracts.post(h.id, e["b"].id, jb, n, wage)


func _assign(a: SimAgent, job: String) -> void:
	if a.job != job:
		a.job = job
		w.jobs.replan(a)


# Właściciele pól wystawiają oferty pracy w polu (L3): tyle rąk, ile z danych i na ile
# ich stać na dziś; bez roboty w polu — brak oferty.
func post_offers() -> void:
	var est: Dictionary = w.balance["estate"]
	var wage := float(w.balance["jobs"]["laborer_wage_day"])
	var owners := {}
	for f: SimField in w.fields:
		owners[f.owner_building] = true
	for bid in owners:
		var h := w.household_at(bid)
		if h == null or h == w.household:
			continue
		var slots := 0
		if w.field_with_work(bid) != null:
			slots = mini(int(est["laborers"]), int(floor(h.cash / wage)))
		w.contracts.post(h.id, bid, "laborer", slots, wage)
