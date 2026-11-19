# EconSetup — świat na start (jak god.xml w X4: rozmieszczamy moc produkcyjną
# według tego, ile czego świat potrzebuje, a nie liczby fabryk). Popyt końcowy
# ludności liczony w tył przez przepisy daje potrzebną moc każdego przepisu;
# firmy stawiamy przy złożach albo tam, gdzie mieszka dużo ludzi, i rozdajemy
# aktorom (bogatsi mają więcej). Potem zapasy na rynkach i firmy przewozowe.
class_name EconSetup
extends RefCounted


# Przetwórstwo, które na starcie chętniej staje przy złożu swojego surowca.
const INPUT_RESOURCE := {"mill": "fertile", "livestock_farm": "fertile", "refinery": "oil", "chemical_plant": "oil",
	"sawmill": "forest", "cement_works": "limestone", "steelworks": "iron"}
const NEAR_RESOURCE_BONUS := 6.0
const START_LABOR_USE := 0.9
const CONSTRUCTION_PER_CAPITA := 0.01  # zapas mocy materiałów budowlanych na budowy aktorów   # jaką część siły roboczej miasta firmy mogą zająć na starcie


static func populate(w: EconWorld) -> void:
	var wp: Dictionary = w.data["world"]
	var lp: Dictionary = w.data["labor"]
	for c: EconCity in w.cities:
		c.wage = float(lp["base_wage"])
		c.labor_force = c.population * float(lp["participation"])
	var req := _requirements(w)
	_place_businesses(w, req, float(wp["start_coverage"]))
	EconHousing.setup(w)
	for c: EconCity in w.cities:
		c.rent = EconHousing.base_rent(w, c)
	for c: EconCity in w.cities:
		c.employed = 0.0
	_actors(w, wp)
	_haulage(w, wp)
	_money_and_stock(w, wp)


# Ile czego świat potrzebuje na dobę (popyt końcowy + wejścia producentów + paliwo ciężarówek).
static func _requirements(w: EconWorld) -> Dictionary:
	var pop := w.total_population()
	var final := {}
	for g: String in w.goods.keys():
		final[g] = 0.0
	for n: Dictionary in w.data["needs"]:
		final[n["good"]] = float(final[n["good"]]) + float(n["per_capita"]) * pop
	var tp: Dictionary = w.data["transport"]
	final["fuel"] = float(final["fuel"]) + float(w.data["world"]["start_trucks"]) * 0.6 * 300.0 * float(tp["fuel_per_km"])
	var req := final.duplicate()
	for _i in 8:
		var nxt := final.duplicate()
		for rid: String in w.recipes.keys():
			var r: Dictionary = w.recipes[rid]
			var out: String = r["out"]
			if out == "":
				continue
			var ins: Dictionary = r["inputs"]
			for g: String in ins.keys():
				nxt[g] = float(nxt[g]) + float(req[out]) * float(ins[g])
		req = nxt
	# Materiały budowlane: trochę na start, żeby budowy nie stały.
	for g: String in ["lumber", "cement", "steel"]:
		req[g] = float(req[g]) + pop * CONSTRUCTION_PER_CAPITA
	return req


static func _place_businesses(w: EconWorld, req: Dictionary, coverage: float) -> void:
	for rid: String in w.recipes.keys():
		if rid == "haulage" or EconHousing.is_housing(w, rid):
			continue
		var r: Dictionary = w.recipes[rid]
		var out: String = r["out"]
		var res: String = r.get("resource", "")
		var max_l := int(r["max_level"])
		if out == "services":
			for c: EconCity in w.cities:
				var need := float(req["services"]) * c.population / w.total_population() * coverage
				_fill(w, rid, need, [c], [1.0], max_l)
			continue
		var need := float(req[out]) * coverage
		if out == "trucks":
			need = 1.0
		var cands: Array = []
		var weights: Array = []
		var near: String = INPUT_RESOURCE.get(rid, "")
		for c: EconCity in w.cities:
			if res != "":
				if c.resources.has(res):
					cands.append(c)
					weights.append(float(c.resources[res]))
			else:
				cands.append(c)
				# Przetwórstwo chętniej przy złożu swojego surowca (rafineria przy ropie).
				var bonus := NEAR_RESOURCE_BONUS if near != "" and c.resources.has(near) else 1.0
				weights.append(pow(c.population, 0.8) * bonus)
		_fill(w, rid, need, cands, weights, max_l)


static func _fill(w: EconWorld, rid: String, need: float, cands: Array, weights: Array, max_l: int) -> void:
	if cands.is_empty():
		return
	var r: Dictionary = w.recipes[rid]
	var have := 0.0
	var guard := 0
	while have < need and guard < 600:
		guard += 1
		var c: EconCity = cands[_pick(w, weights)]
		var eff := EconProduction.effective_per_worker(w, rid, c)
		if eff <= 0.0:
			continue
		var per_level := eff * float(r["workers"])
		var lvl := clampi(ceili((need - have) / per_level), 1, w.rng.next_int(1, maxi(1, max_l / 2 + 1)))
		# Nie więcej miejsc pracy, niż miasto ma ludzi (poza ostatnimi próbami).
		var free := c.labor_force * START_LABOR_USE - c.employed
		var fit := int(free / float(r["workers"]))
		if fit < 1 and guard < 500:
			continue
		lvl = mini(lvl, maxi(fit, 1))
		c.employed += float(r["workers"]) * lvl * 0.9
		var b := EconBusiness.new(w.new_id(), rid, c.id, -1)
		b.level = lvl
		b.workers = float(r["workers"]) * lvl * 0.9
		w.add_business(b)
		have += per_level * lvl


static func _pick(w: EconWorld, weights: Array) -> int:
	var total := 0.0
	for x: float in weights:
		total += x
	var roll := w.rng.next_float(0.0, total)
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1


static func _actors(w: EconWorld, wp: Dictionary) -> void:
	var cash_r: Array = wp["start_actor_cash"]
	var list: Array[EconActor] = []
	var weights: Array = []
	var life: Array = w.data["actors"]["life_days"]
	for i in int(wp["start_actor_count"]):
		var a := EconPopulation.new_actor(w, w.rng.next_int(0, w.cities.size() - 1), -1, "")
		var u := w.rng.next_float()
		a.cash = float(cash_r[0]) + (float(cash_r[1]) - float(cash_r[0])) * u * u * u
		a.death_day = w.rng.next_int(200, int(life[1]))
		list.append(a)
		weights.append(a.cash)
	for b: EconBusiness in w.businesses.values():
		var a: EconActor = list[_pick(w, weights)]
		b.owner_id = a.id
		if a.businesses.is_empty():
			a.city_id = b.city_id
		a.businesses.append(b.id)
		b.name = EconNames.business_name(str(w.recipe(b.type)["name"]), a.last)
		b.founded_day = -w.rng.next_int(100, 3000)


static func _haulage(w: EconWorld, wp: Dictionary) -> void:
	var n_trucks := int(wp["start_trucks"])
	var n_comp := maxi(8, n_trucks / 10)
	var actors: Array = w.actors.values()
	var pops: Array = []
	for c: EconCity in w.cities:
		pops.append(c.population)
	var comps: Array[EconBusiness] = []
	for i in n_comp:
		var a: EconActor = w.rng.choice(actors)
		var c: EconCity = w.cities[_pick(w, pops)]
		var b := EconBusiness.new(w.new_id(), "haulage", c.id, a.id)
		b.name = EconNames.business_name(str(w.recipe("haulage")["name"]), a.last)
		b.founded_day = -w.rng.next_int(100, 3000)
		w.add_business(b)
		a.businesses.append(b.id)
		comps.append(b)
	for i in n_trucks:
		var comp: EconBusiness = w.rng.choice(comps)
		var city_id: int = comp.city_id if w.rng.chance(0.5) else _pick(w, pops)
		var tr := EconLogistics.add_truck(w, comp, city_id)
		tr.retire_day = w.rng.next_int(30, int(w.data["transport"]["truck_life_days"][1]))


static func _money_and_stock(w: EconWorld, wp: Dictionary) -> void:
	var lp: Dictionary = w.data["labor"]
	var wage := float(lp["base_wage"])
	var mp: Dictionary = w.data["market"]
	# Lokalny popyt na start: ludność + wejścia firm w mieście.
	var local: Array = []
	for c: EconCity in w.cities:
		var d := {}
		for n: Dictionary in w.data["needs"]:
			d[n["good"]] = float(n["per_capita"]) * c.population
		local.append(d)
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage":
			continue
		var r: Dictionary = w.recipe(b.type)
		var units := b.workers * EconProduction.effective_per_worker(w, b.type, w.city_of(b))
		var ins: Dictionary = r["inputs"]
		var d: Dictionary = local[b.city_id]
		for g: String in ins.keys():
			d[g] = float(d.get(g, 0.0)) + units * float(ins[g])
			b.inputs[g] = units * float(ins[g]) * 2.0
		b.cash = b.workers * wage * float(wp["start_business_cash_days"]) + b.level * 2000.0
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage":
			b.cash = b.trucks.size() * (wage * 60.0 + 6000.0) + 20000.0
	var producers := {}  # towar -> [firmy]
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage":
			continue
		var out: String = w.recipe(b.type)["out"]
		if out == "":
			continue
		if not producers.has(out):
			producers[out] = []
		(producers[out] as Array).append(b)
	var spend_per_capita := 0.0
	for n: Dictionary in w.data["needs"]:
		spend_per_capita += float(n["per_capita"]) * float(w.goods[n["good"]]["base"])
	for c: EconCity in w.cities:
		c.cash = c.population * spend_per_capita * float(wp["start_household_cash_days"])
		c.income_ema = c.labor_force * 0.85 * wage
		var d: Dictionary = local[c.id]
		for g: String in d.keys():
			var m := c.market(g)
			m.demand_ema = float(d[g])
			m.use_ema = float(d[g])
			if not producers.has(g):
				continue
			var list: Array = producers[g]
			var here: Array = list.filter(func(b: EconBusiness) -> bool: return b.city_id == c.id)
			var seller: EconBusiness = w.rng.choice(here) if not here.is_empty() else w.rng.choice(list)
			m.add(seller.id, float(d[g]) * float(mp["target_days"]) * 0.7)
			m.supplied_today = 0.0
