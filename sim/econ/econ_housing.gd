# EconHousing — nieruchomości (docs/design/world-economy.md, „Nieruchomości”).
# Działka: każda budowa i rozbudowa kupuje grunt od gminy (pieniądze idą do skarbu
# państwa). W mieście cena rośnie z liczbą mieszkańców, a za miastem (pola, kopalnie)
# jest stała i niska. Dlatego rozrost największych miast jest droższy.
# Mieszkania: część ludzi ma własne (city.homes_owned), reszta wynajmuje w kamienicach
# (firmy typu "apartments", właściciele to aktorzy). Czynsz idzie za obłożeniem: przy
# ciasnocie rośnie, przy pustostanach spada. Kto nie ma gdzie mieszkać, jest „w
# ciasnocie”: spada zadowolenie i przyrost, a ludzie wyjeżdżają. Drogi czynsz pcha płace w górę.
class_name EconHousing
extends RefCounted


const NEWS_EVERY := 30            # co ile dób kronika sprawdza brak mieszkań
const CROWD_NEWS_SHARE := 0.03    # od jakiej części ludności bez mieszkania to wiadomość


static func hp(w: EconWorld) -> Dictionary:
	return w.data["housing"]


static func is_housing(w: EconWorld, type: String) -> bool:
	return bool(w.recipe(type).get("housing", false))


# Cena jednej działki w mieście (zł).
static func land_price(w: EconWorld, c: EconCity) -> float:
	var lp: Dictionary = w.data["land"]
	var urban := float(lp["urban_base"]) * pow(c.population / float(lp["ref_pop"]), float(lp["pop_exp"]))
	return maxf(urban, float(lp["rural"]))


# Grunt pod budowę (jeden poziom) danego rodzaju w mieście: firmy wydobywcze i rolne stoją za miastem.
static func land_cost(w: EconWorld, type: String, c: EconCity) -> float:
	var lp: Dictionary = w.data["land"]
	var plots := float((lp["plots"] as Dictionary).get(type, lp["default_plot"]))
	var rural: bool = w.recipe(type).get("resource", "") != ""
	return plots * (float(lp["rural"]) if rural else land_price(w, c))


static func base_rent(w: EconWorld, c: EconCity) -> float:
	return float(hp(w)["rent_of_wage"]) * c.wage


static func capacity(w: EconWorld, b: EconBusiness) -> float:
	return float(b.level) * float(hp(w)["homes_per_level"])


# Doba mieszkań w każdym mieście: obłożenie, czynsz, ciasnota. Czynsz płacą gospodarstwa
# z kasy miasta właścicielom kamienic (proporcjonalnie do liczby mieszkań).
static func step(w: EconWorld) -> void:
	var p := hp(w)
	var caps: Array[float] = []
	var lists: Array = []
	for c: EconCity in w.cities:
		caps.append(0.0)
		lists.append([])
		c.rental_pending = 0.0
	for b: EconBusiness in w.businesses.values():
		if not is_housing(w, b.type) or not b.is_open():
			continue
		if not b.project.is_empty():
			w.cities[b.city_id].rental_pending += float(int(b.project["to_level"]) - b.level) * float(p["homes_per_level"])
		if b.is_running():
			caps[b.city_id] += capacity(w, b)
			(lists[b.city_id] as Array).append(b)
	var full := float(p["full_occupancy"])
	for c: EconCity in w.cities:
		var demand := maxf(0.0, c.population - c.homes_owned)
		var cap: float = caps[c.id]
		c.rental_capacity = cap
		c.renters = minf(demand, cap)
		c.crowded = demand - c.renters
		var occ := demand / maxf(cap, 1.0)
		var mult := 1.0
		if occ > full:
			mult = minf(float(p["rent_max_mult"]), 1.0 + float(p["rent_up"]) * (occ - full))
		else:
			mult = maxf(float(p["rent_min_mult"]), 1.0 - float(p["rent_down"]) * (full - occ))
		c.rent_mult = lerpf(c.rent_mult, mult, float(p["rent_speed"]))
		c.rent = base_rent(w, c) * c.rent_mult
		c.rent_paid_today = 0.0
		if w.day % int(p["self_build_every"]) == 0:
			_self_build(w, c, p)
		if c.renters <= 0.0 or cap <= 0.0:
			continue
		if w.day % NEWS_EVERY == NEWS_EVERY / 2 and c.crowded > maxf(c.population * CROWD_NEWS_SHARE, 200.0):
			w.news.add("housing", c.id, "%s: brakuje mieszkań dla %.0f osób, czynsz %.0f%% ponad zwykły." % [c.name, c.crowded, (c.rent_mult - 1.0) * 100.0], 1)
		var bill := minf(c.rent * c.renters, maxf(c.cash, 0.0) * float(p["max_share_of_cash"]))
		c.cash -= bill
		c.rent_paid_today = bill
		for b: EconBusiness in lists[c.id]:
			var part := bill * capacity(w, b) / cap
			b.cash += part
			b.revenue_today += part


# Budownictwo indywidualne: raz na jakiś czas część ludzi bez mieszkania buduje własne
# z oszczędności miasta — kupuje materiały na rynku, działkę od gminy, płaci robotnikom.
# Ile powstanie, tyle, ile starczy materiałów i pieniędzy.
static func _self_build(w: EconWorld, c: EconCity, p: Dictionary) -> void:
	if c.crowded < 1.0:
		return
	var mats: Dictionary = p["self_build_materials"]
	var per_home := float(p["self_build_money"]) + float(p["self_build_plot"]) * land_price(w, c)
	for g: String in mats.keys():
		per_home += float(mats[g]) * c.market(g).price
	var budget := maxf(c.cash, 0.0) * float(p["self_build_max_of_cash"])
	var homes := minf(c.crowded * float(p["self_build_share"]), budget / maxf(per_home, 1e-3))
	for g: String in mats.keys():
		var need := homes * float(mats[g])
		if need <= 0.0:
			continue
		var res: Array = c.market(g).buy(need, maxf(c.cash, 0.0), w.pay_seller)
		c.cash -= float(res[1])
		homes = minf(homes, float(res[0]) / float(mats[g]))
	if homes <= 0.0:
		return
	var wages := homes * float(p["self_build_money"])
	var land := homes * float(p["self_build_plot"]) * land_price(w, c)
	wages = minf(wages, maxf(c.cash, 0.0))
	c.cash -= wages
	EconLabor.pay_wages(c, wages)
	land = minf(land, maxf(c.cash, 0.0))
	c.cash -= land
	w.state_of_city(c.id).collect(land)
	c.homes_owned += homes
	w.stats["self_built"] = float(w.stats.get("self_built", 0.0)) + homes


# Doba kamienicy: dozorcy z miasta i ich pensje (bez produkcji).
static func upkeep(w: EconWorld, b: EconBusiness, c: EconCity) -> void:
	var r: Dictionary = w.recipe(b.type)
	var want := float(r["workers"]) * b.level
	if b.workers < want:
		var hire := minf(want - b.workers, c.free_workers())
		b.workers += hire
		c.employed += hire
	var bill := b.workers * c.wage
	var paid := minf(bill, maxf(b.cash, 0.0))
	b.cash -= paid
	b.cost_today += paid
	EconLabor.pay_wages(c, paid)
	b.broke_days = b.broke_days + 1 if paid < bill else 0
	b.produced_today = 0.0


# Szacunek dziennego zysku `levels` nowych poziomów kamienic w mieście.
static func estimate(w: EconWorld, c: EconCity, levels: int) -> float:
	var homes := float(hp(w)["homes_per_level"]) * levels
	var demand := maxf(0.0, c.population - c.homes_owned)
	var free_demand := demand - (c.rental_capacity + c.rental_pending) * float(hp(w)["full_occupancy"])
	var util := clampf(free_demand / homes, 0.0, 1.0)
	var upkeep_cost := float(w.recipe("apartments")["workers"]) * levels * c.wage
	return c.rent * homes * util - upkeep_cost


# Czy kamienica się utrzymuje przy dzisiejszym czynszu i obłożeniu.
static func viable(w: EconWorld, b: EconBusiness) -> bool:
	var c := w.city_of(b)
	var occ := c.renters / maxf(c.rental_capacity, 1.0)
	return c.rent * capacity(w, b) * occ > float(w.recipe(b.type)["workers"]) * b.level * c.wage


# Start: część ludzi ma własne mieszkania, reszta wynajmuje w kamienicach (kilka w mieście).
static func setup(w: EconWorld) -> void:
	var p := hp(w)
	var per := float(p["homes_per_level"])
	var max_l := int(p["start_level_max"])
	var r: Dictionary = w.recipe("apartments")
	for c: EconCity in w.cities:
		c.homes_owned = c.population * float(p["owned_share"])
		c.rent_mult = 1.0
		var need := (c.population - c.homes_owned) * (1.0 + float(p["start_vacancy"]))
		var levels := ceili(need / per)
		while levels > 0:
			var lvl := mini(levels, w.rng.next_int(maxi(1, max_l / 3), max_l))
			var b := EconBusiness.new(w.new_id(), "apartments", c.id, -1)
			b.level = lvl
			b.workers = float(r["workers"]) * lvl
			c.employed += b.workers
			w.add_business(b)
			levels -= lvl
