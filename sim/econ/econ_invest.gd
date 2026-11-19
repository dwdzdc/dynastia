# EconInvest — księgowość firm i decyzje aktorów. Codziennie: zysk dnia, dywidendy,
# sprzątanie zamkniętych firm. Raz w tygodniu każdy aktor przegląda interesy:
# ratuje dobre firmy w kłopocie, wystawia na sprzedaż i zamyka stratne, kupuje
# cudze tanio, dokupuje ciężarówki, rozbudowuje i zakłada nowe tam, gdzie
# lokalne ceny obiecują zysk. To, czym aktor się zajmuje, jest wymienne.
class_name EconInvest
extends RefCounted


const WORKING_DAYS := 10.0   # kapitał obrotowy, który właściciel trzyma w firmie


static func step(w: EconWorld) -> void:
	_accounting(w)
	var every := int(w.data["actors"]["review_every"])
	for a: EconActor in w.actors.values():
		if a.alive and not a.is_player and (a.id + w.day) % every == 0:
			_review(w, a)


# --- księgowość --------------------------------------------------------------

static func _accounting(w: EconWorld) -> void:
	var bp: Dictionary = w.data["business"]
	var k := float(bp["profit_ema"])
	var div_every := int(bp["dividend_every"])
	for b: EconBusiness in w.businesses.values().duplicate():
		var profit := b.revenue_today - b.cost_today
		b.profit_ema = lerpf(b.profit_ema, profit, k)
		b.cost_ema = lerpf(b.cost_ema, b.cost_today, k)
		b.revenue_today = 0.0
		b.cost_today = 0.0
		if b.status == "building":
			continue
		b.loss_days = b.loss_days + 1 if b.profit_ema < 0.0 else 0
		var owner := w.actor(b.owner_id)
		if b.status == "closed":
			if b.cash > 0.0:
				_to_owner(w, b, b.cash)
			if not _has_lots(w, b) and b.trucks.is_empty():
				_remove(w, b)
			continue
		if (b.id + w.day) % div_every == 0 and owner != null:
			var reserve := b.cost_ema * float(bp["reserve_days"])
			if not b.project.is_empty():
				reserve += float(b.project["money_per_day"]) * int(b.project["days"]) + build_cost(w, b.type, w.city_of(b))
			var excess := b.cash - reserve
			if excess > 0.0:
				_to_owner(w, b, excess * float(bp["dividend_share"]))


static func _to_owner(w: EconWorld, b: EconBusiness, amount: float) -> void:
	var owner := w.actor(b.owner_id)
	b.cash -= amount
	if owner != null and owner.alive:
		var tax := w.state_of_city(owner.city_id).tax_dividend(w, amount)
		owner.cash += amount - tax
		owner.income_today += amount - tax
	else:
		w.cities[b.city_id].cash += amount


static func _has_lots(w: EconWorld, b: EconBusiness) -> bool:
	if b.type == "haulage":
		for c: EconCity in w.cities:
			for m: EconMarket in c.markets.values():
				if m.lots.has(b.id):
					return true
		return false
	var out: String = w.recipe(b.type)["out"]
	return w.city_of(b).market(out).lots.has(b.id)


static func _remove(w: EconWorld, b: EconBusiness) -> void:
	var owner := w.actor(b.owner_id)
	if owner != null:
		owner.businesses.erase(b.id)
	if b.cash != 0.0:
		w.cities[b.city_id].cash += b.cash
		b.cash = 0.0
	w.businesses.erase(b.id)


# --- wycena ------------------------------------------------------------------

static func build_cost(w: EconWorld, type: String, c: EconCity) -> float:
	var bd: Dictionary = w.recipe(type)["build"]
	var cost := float(bd["money"])
	for g: String in ["lumber", "cement", "steel"]:
		cost += float(bd.get(g, 0.0)) * c.market(g).price
	return cost


static func book_value(w: EconWorld, b: EconBusiness) -> float:
	if b.status == "closed":
		return 0.0
	var c := w.city_of(b)
	if b.type == "haulage":
		return b.trucks.size() * float(w.goods["trucks"]["base"]) * 0.5
	return build_cost(w, b.type, c) * b.level * 0.5 + maxf(b.profit_ema, 0.0) * 120.0


# Koszt przewozu jednostki towaru między miastami (paliwo + kierowca) — do szacunków.
static func transport_unit(w: EconWorld, g: String, from_id: int, to_id: int) -> float:
	var tp: Dictionary = w.data["transport"]
	var km: float = w.dist[from_id][to_id]
	if km == INF:
		return INF
	var units := float(tp["truck_capacity"]) / maxf(float(w.goods[g]["weight"]), 0.01)
	var fp := float(w.goods["fuel"]["base"])
	var per_trip := km * float(tp["fuel_per_km"]) * fp + km / float(tp["speed_km_per_day"]) * float(w.data["labor"]["base_wage"]) * 1.5
	return per_trip / units * 2.0  # w obie strony (powrót często na pusto)


# Cena, po jakiej da się sprzedać towar wyprodukowany w c (lokalnie albo wywieźć).
static func _sell_price(w: EconWorld, g: String, c: EconCity) -> float:
	var best := c.market(g).price
	if not g in w.tradable:
		return best
	for d: EconCity in w.cities:
		if d.id != c.id:
			var p := d.market(g).price * (1.0 - w.tariff_rate(c.id, d.id))
			best = maxf(best, (p - transport_unit(w, g, c.id, d.id)) * 0.9)
	return best


# Cena, po jakiej da się mieć towar w c (lokalnie, jeśli jest, albo przywieźć).
static func _buy_price(w: EconWorld, g: String, c: EconCity) -> float:
	var m := c.market(g)
	var best := m.price if m.stock() > m.use_ema else INF
	if g in w.tradable:
		for d: EconCity in w.cities:
			if d.id != c.id and d.market(g).stock() > 1.0:
				var duty := c.market(g).price * w.tariff_rate(d.id, c.id)
				best = minf(best, d.market(g).price + transport_unit(w, g, d.id, c.id) + duty)
	if best == INF:
		best = m.price * 1.5
	return best


# Szacunek dziennego zysku `levels` poziomów przepisu w mieście. Uwzględnia
# nasycenie: jeśli świat już produkuje tyle, ile potrzebuje, nowa moc się nie sprzeda.
static func estimate(w: EconWorld, type: String, c: EconCity, levels: int) -> float:
	var r: Dictionary = w.recipe(type)
	var res: String = r.get("resource", "")
	if res != "" and float(c.resources.get(res, 0.0)) < 0.1:
		return -INF
	var out: String = r["out"]
	var eff := float(r["per_worker"])
	if res != "":
		eff *= float(c.resources[res])
	var new_cap := eff * float(r["workers"]) * levels
	var margin := _sell_price(w, out, c)
	var ins: Dictionary = r["inputs"]
	for g: String in ins.keys():
		margin -= float(ins[g]) * _buy_price(w, g, c)
	margin -= c.wage / maxf(eff, 1e-6)
	if margin <= 0.0:
		return margin * new_cap
	# Nasycenie: popyt vs bieżąca produkcja (usługi — lokalnie, reszta — cały świat).
	var demand := 0.0
	var supply := 0.0
	var cache := _supply_cache(w)
	if bool(w.goods[out].get("local_only", false)):
		demand = c.market(out).use_ema
		supply = float(cache.get("%s:%d" % [type, c.id], 0.0))
	else:
		for d: EconCity in w.cities:
			demand += d.market(out).use_ema
		supply = float(cache.get(type, 0.0))
	var price_signal := clampf(c.market(out).price / c.market(out).base - 1.0, 0.0, 1.0)
	var util := clampf((demand * 1.05 - supply * 0.9) / new_cap + price_signal * 0.3, 0.0, 1.0)
	return margin * new_cap * util


# Moc produkcyjna wg przepisu (cały świat) i wg przepisu w mieście — liczona raz na dobę.
static func _supply_cache(w: EconWorld) -> Dictionary:
	if w.supply_cache_day == w.day:
		return w.supply_cache
	w.supply_cache.clear()
	w.supply_cache_day = w.day
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage" or not b.is_open():
			continue
		var cap := _capacity(w, b)
		w.supply_cache[b.type] = float(w.supply_cache.get(b.type, 0.0)) + cap
		var k := "%s:%d" % [b.type, b.city_id]
		w.supply_cache[k] = float(w.supply_cache.get(k, 0.0)) + cap
	return w.supply_cache


# Moc produkcyjna firmy (jednostek na dobę przy pełnym zatrudnieniu).
static func _capacity(w: EconWorld, b: EconBusiness) -> float:
	var lvl := b.level
	if not b.project.is_empty():
		lvl = int(b.project.get("to_level", b.level))
	return EconProduction.effective_per_worker(w, b.type, w.city_of(b)) * float(w.recipe(b.type)["workers"]) * lvl


# --- przegląd aktora ---------------------------------------------------------

static func _review(w: EconWorld, a: EconActor) -> void:
	var ap: Dictionary = w.data["actors"]
	var bp: Dictionary = w.data["business"]
	for bid: int in a.businesses.duplicate():
		var b: EconBusiness = w.business(bid)
		if b == null or b.status in ["closed", "building"]:
			continue
		# Firma bez gotówki, która przy dzisiejszych cenach zarabiałaby na produkcji:
		# właściciel dokłada kapitał obrotowy (patrzy w przyszłość, nie na stare straty).
		top_up(w, a, b)
		var losing := b.loss_days > int(bp["loss_days_to_review"]) or b.broke_days > int(bp["broke_days_to_close"])
		if b.type == "haulage" and b.trucks.is_empty() and w.day - b.founded_day > 30:
			losing = true
		if losing:
			if not b.for_sale:
				b.for_sale = true
				b.listed_day = w.day
				b.ask_price = book_value(w, b) * float(ap["sale_discount"])
			elif w.day - b.listed_day > int(ap["listing_days"]):
				close(w, b, "nikt nie chciał kupić")
		elif b.for_sale and b.profit_ema > 0.0:
			b.for_sale = false
		if b.type == "haulage" and b.status == "active":
			_maybe_buy_trucks(w, a, b)
	_buy_listed(w, a)
	var busy := a.businesses.any(func(id: int) -> bool:
		var b: EconBusiness = w.business(id)
		return b != null and not b.project.is_empty())
	if a.cash > float(ap["min_invest_cash"]) and not busy:
		_invest(w, a)


# Ile firma potrzebuje na ~WORKING_DAYS dób pełnej pracy (pensje + wejścia przy dzisiejszych cenach).
static func working_need(w: EconWorld, b: EconBusiness) -> float:
	if b.type == "haulage":
		return b.trucks.size() * (w.city_of(b).wage * 1.2 + 4000.0) * WORKING_DAYS
	var c := w.city_of(b)
	var r: Dictionary = w.recipe(b.type)
	var workers := float(r["workers"]) * b.level
	var eff := EconProduction.effective_per_worker(w, b.type, c)
	var per_day := workers * c.wage
	var ins: Dictionary = r["inputs"]
	for g: String in ins.keys():
		per_day += workers * eff * float(ins[g]) * c.market(g).price
	return per_day * WORKING_DAYS


# Czy produkcja opłaca się przy dzisiejszych cenach (sprzedaż lokalnie albo wywóz).
static func viable(w: EconWorld, b: EconBusiness) -> bool:
	if b.type == "haulage":
		return w.truck_profit_ema > 0.0
	var c := w.city_of(b)
	var out: String = w.recipe(b.type)["out"]
	var eff := EconProduction.effective_per_worker(w, b.type, c)
	return eff > 0.0 and _sell_price(w, out, c) > EconProduction.unit_cost(w, b.type, c, eff) * 1.02


static func top_up(w: EconWorld, a: EconActor, b: EconBusiness) -> void:
	var need := working_need(w, b)
	if b.cash >= need * 0.5 or a.cash <= 0.0 or not viable(w, b):
		return
	var add := minf(a.cash * 0.6, need - b.cash)
	if add > 0.0:
		a.cash -= add
		b.cash += add


static func _maybe_buy_trucks(w: EconWorld, a: EconActor, comp: EconBusiness) -> void:
	var ap: Dictionary = w.data["actors"]
	var price := float(w.goods["trucks"]["base"])
	for c: EconCity in w.cities:
		if c.market("trucks").stock() >= 1.0:
			price = minf(price, c.market("trucks").price)
	# Zysk ciężarówki na dobę ≈ średni zysk z kursu (kurs ~1,5 doby) minus kierowca.
	var daily := w.truck_profit_ema / 1.5 * fleet_use(w) - w.city_of(comp).wage * float(w.data["transport"]["driver_wage_mult"])
	var roi := daily * float(ap["payback_horizon_days"]) / price
	if roi < float(ap["truck_purchase_roi"]) / lerpf(0.8, 1.2, a.risk) and not comp.trucks.is_empty():
		return
	# Własne ciężarówki stoją: po co kolejna.
	var idle := 0
	for tid: int in comp.trucks:
		var tr: EconTruck = w.trucks.get(tid)
		if tr != null and not tr.moving:
			idle += 1
	if comp.trucks.size() > 0 and float(idle) / comp.trucks.size() > float(ap["max_idle_fleet"]):
		return
	var budget := comp.cash + a.cash * 0.5
	if budget < price * 1.3:
		return
	var need := price * 1.3 - comp.cash
	if need > 0.0:
		a.cash -= need
		comp.cash += need
	EconLogistics.buy_truck(w, comp)


# Jaka część wszystkich ciężarówek jest w drodze (liczone raz na dobę).
static func fleet_use(w: EconWorld) -> float:
	if w.fleet_use_day != w.day:
		w.fleet_use_day = w.day
		var moving := 0
		for tr: EconTruck in w.trucks.values():
			if tr.moving:
				moving += 1
		w.fleet_use_cache = float(moving) / maxf(1.0, w.trucks.size())
	return w.fleet_use_cache


static func _buy_listed(w: EconWorld, a: EconActor) -> void:
	var ap: Dictionary = w.data["actors"]
	for b: EconBusiness in w.businesses.values():
		if not b.for_sale or b.owner_id == a.id or b.status == "closed":
			continue
		if b.ask_price > a.cash * 0.6:
			continue
		var c := w.city_of(b)
		var prospect := 0.0
		if b.type == "haulage":
			prospect = w.truck_profit_ema / 1.5 * b.trucks.size()
		else:
			prospect = estimate(w, b.type, c, b.level)
		var roi := prospect * float(ap["payback_horizon_days"]) / maxf(b.ask_price, 1.0)
		if roi > float(ap["min_roi"]) * lerpf(1.3, 0.8, a.risk):
			transfer(w, b, a, b.ask_price)
			top_up(w, a, b)
			return


# Sprzedaż firmy: kupujący płaci sprzedającemu, firma zmienia właściciela.
static func transfer(w: EconWorld, b: EconBusiness, buyer: EconActor, price: float) -> void:
	var seller := w.actor(b.owner_id)
	buyer.cash -= price
	if seller != null and seller.alive:
		seller.cash += price
		seller.businesses.erase(b.id)
	else:
		w.cities[b.city_id].cash += price
	buyer.businesses.append(b.id)
	b.owner_id = buyer.id
	b.for_sale = false
	b.loss_days = 0
	b.broke_days = 0
	w.stats["sold"] += 1
	var who := seller.full_name() if seller != null else "spadkobiercy"
	w.news.add("takeover", b.city_id, "Przejęcie: %s (%s), %s → %s, %.0f tys. zł." % [b.name, w.cities[b.city_id].name, who, buyer.full_name(), price / 1000.0], 1 if price > 200000.0 else 0)


static func close(w: EconWorld, b: EconBusiness, why: String) -> void:
	var c := w.city_of(b)
	if b.type != "haulage":
		c.employed -= b.workers
	b.workers = 0.0
	b.status = "closed"
	b.for_sale = false
	b.project.clear()
	for tid: int in b.trucks.duplicate():
		var tr: EconTruck = w.trucks.get(tid)
		if tr != null and not tr.moving and not EconLogistics.sell_used(w, tr, b):
			EconLogistics.scrap(w, tr)
	# Ciężarówki w drodze dojadą i zostaną zezłomowane przy następnym postoju.
	for g: String in b.inputs.keys():
		b.inputs[g] = 0.0
	w.stats["closed"] += 1
	w.news.add("closed", b.city_id, "Upada: %s (%s), %s." % [b.name, c.name, why], 1 if b.level >= 3 else 0)


# --- inwestycje --------------------------------------------------------------

static func _invest(w: EconWorld, a: EconActor) -> void:
	var ap: Dictionary = w.data["actors"]
	var best_roi := float(ap["min_roi"]) * lerpf(1.3, 0.8, a.risk)
	var best: Dictionary = {}
	# Rozbudowa własnych, dobrze idących firm.
	for bid: int in a.businesses:
		var b: EconBusiness = w.business(bid)
		if b == null or b.status != "active" or b.type == "haulage" or not b.project.is_empty():
			continue
		var r: Dictionary = w.recipe(b.type)
		if b.level >= int(r["max_level"]) or b.workers < float(r["workers"]) * b.level * 0.9:
			continue
		var c := w.city_of(b)
		var cost := build_cost(w, b.type, c)
		var gain := estimate(w, b.type, c, 1)
		var roi := gain * float(ap["payback_horizon_days"]) / cost
		if roi > best_roi * 0.9 and cost * 1.2 < a.cash:
			best_roi = roi
			best = {"kind": "expand", "b": b, "cost": cost}
	# Nowe firmy w losowych miejscach.
	var types: Array = w.recipes.keys().filter(func(t: String) -> bool: return t != "haulage")
	for i in int(ap["invest_candidates"]):
		var type: String = w.rng.choice(types)
		var c: EconCity = w.rng.choice(w.cities)
		var cost := build_cost(w, type, c)
		if cost * 1.2 > a.cash:
			continue
		var gain := estimate(w, type, c, 1)
		var roi := gain * float(ap["payback_horizon_days"]) / cost
		if roi > best_roi:
			best_roi = roi
			best = {"kind": "found", "type": type, "c": c, "cost": cost}
	# Firma przewozowa, gdy kursy się opłacają, a aktor jeszcze jej nie ma.
	var has_haulage := a.businesses.any(func(id: int) -> bool:
		var b: EconBusiness = w.business(id)
		return b != null and b.type == "haulage" and b.is_open())
	if not has_haulage:
		var price := float(w.goods["trucks"]["base"]) * 1.4
		var daily := w.truck_profit_ema / 1.5 * fleet_use(w) - float(w.data["labor"]["base_wage"]) * 1.2
		var roi := daily * float(ap["payback_horizon_days"]) / price
		if roi > best_roi and a.cash > price * 1.5:
			best = {"kind": "found", "type": "haulage", "c": w.cities[a.city_id], "cost": price}
	if best.is_empty():
		return
	if best["kind"] == "expand":
		start_project(w, best["b"], a, float(best["cost"]))
	else:
		var b := found(w, a, str(best["type"]), best["c"], float(best["cost"]))
		if b.type == "haulage":
			EconLogistics.buy_truck(w, b)


static func found(w: EconWorld, a: EconActor, type: String, c: EconCity, cost: float) -> EconBusiness:
	var b := EconBusiness.new(w.new_id(), type, c.id, a.id)
	var r: Dictionary = w.recipe(type)
	b.name = EconNames.business_name(str(r["name"]), a.last)
	b.founded_day = w.day
	b.level = 0
	w.add_business(b)
	a.businesses.append(b.id)
	w.stats["founded"] += 1
	if type == "haulage":
		b.level = 1
		var fund := minf(a.cash, cost * 1.3)
		a.cash -= fund
		b.cash += fund
		w.news.add("founded", c.id, "%s zakłada firmę przewozową (%s)." % [a.full_name(), c.name], 0)
		return b
	b.status = "building"
	start_project(w, b, a, cost)
	var sev := 1 if float(r["build"]["money"]) >= 40000.0 else 0
	w.news.add("founded", c.id, "%s buduje: %s (%s)." % [a.full_name(), str(r["name"]), c.name], sev)
	return b


static func start_project(w: EconWorld, b: EconBusiness, a: EconActor, cost: float) -> void:
	var bd: Dictionary = w.recipe(b.type)["build"]
	var mats := {}
	for g: String in ["lumber", "cement", "steel"]:
		if float(bd.get(g, 0.0)) > 0.0:
			mats[g] = float(bd[g])
	b.project = {"materials": mats, "days": int(bd["days"]), "money_per_day": float(bd["money"]) / maxf(float(bd["days"]), 1.0), "to_level": b.level + 1, "started": w.day}
	var fund := minf(a.cash, cost * 1.25)
	a.cash -= fund
	b.cash += fund


# Budowa: najpierw materiały z lokalnego rynku (prawdziwy popyt na deski,
# cement i stal), potem dni pracy opłacane do kasy miasta.
static func progress_project(w: EconWorld, b: EconBusiness) -> void:
	var c := w.city_of(b)
	var mats: Dictionary = b.project["materials"]
	var missing := false
	for g: String in mats.keys():
		var need: float = mats[g]
		if need <= 1e-6:
			continue
		var res: Array = c.market(g).buy(need, maxf(b.cash, 0.0), w.pay_seller, b.id)
		b.cash -= float(res[1])
		b.cost_today += float(res[1])
		mats[g] = need - float(res[0])
		if float(mats[g]) > 1e-3:
			missing = true
	if missing:
		# Za długo bez materiałów: właściciel odpuszcza.
		if w.day - int(b.project["started"]) > 240:
			if b.status == "building":
				close(w, b, "budowa stanęła bez materiałów")
			else:
				b.project.clear()
		return
	var pay := minf(float(b.project["money_per_day"]), maxf(b.cash, 0.0))
	b.cash -= pay
	b.cost_today += pay
	EconLabor.pay_wages(c, pay)
	b.project["days"] = int(b.project["days"]) - 1
	if int(b.project["days"]) <= 0:
		b.level = int(b.project["to_level"])
		var was_building := b.status == "building"
		b.project.clear()
		if was_building:
			b.status = "active"
			b.profit_ema = 0.0
			b.cost_ema = 0.0
			w.news.add("opened", b.city_id, "Otwarto: %s (%s)." % [b.name, c.name], 0)
