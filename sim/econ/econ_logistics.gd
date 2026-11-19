# EconLogistics — ciężarówki firm przewozowych. Doba: przyjazdy (rabunek na
# niebezpiecznej drodze, rozładunek na rynek jako partia przewoźnika), pensje
# kierowców, złomowanie, a wolne ciężarówki szukają kursu: kupić tu, sprzedać
# tam, po odliczeniu paliwa, kierowcy, ryzyka i tego, co już tam jedzie
# (market.incoming — żeby wszystkie nie rzucały się na jedną trasę).
class_name EconLogistics
extends RefCounted


static func step(w: EconWorld) -> void:
	var tp: Dictionary = w.data["transport"]
	var now := float(w.day)
	# 1. Przyjazdy.
	for tr: EconTruck in w.trucks.values():
		if tr.moving and tr.arrive_time < now + 1.0:
			_arrive(w, tr, tp)
	# 2. Pensje kierowców.
	for b: EconBusiness in w.businesses.values():
		if b.type != "haulage" or b.status == "closed" or b.trucks.is_empty():
			continue
		var c := w.city_of(b)
		var bill := b.trucks.size() * c.wage * float(tp["driver_wage_mult"])
		var paid := minf(bill, maxf(b.cash, 0.0))
		b.cash -= paid
		b.cost_today += paid
		EconLabor.pay_wages(c, paid)
		b.broke_days = b.broke_days + 1 if paid < bill else 0
	# 3. Najlepszy kurs z każdego miasta (do jazdy na pusto).
	var best_from: Array = []
	for c: EconCity in w.cities:
		best_from.append(_best_trip(w, c, -1, INF, tp))
	# 4. Wolne ciężarówki.
	for tr: EconTruck in w.trucks.values().duplicate():
		if tr.moving:
			continue
		var comp: EconBusiness = w.business(tr.company_id)
		if comp == null or comp.status == "closed":
			continue
		if w.day >= tr.retire_day:
			scrap(w, tr)
			continue
		if comp.status != "active":
			continue
		_plan(w, tr, comp, best_from, tp)


static func _arrive(w: EconWorld, tr: EconTruck, tp: Dictionary) -> void:
	var dest: EconCity = w.cities[tr.to_city]
	var m := dest.market(tr.good) if tr.good != "" else null
	if m != null:
		m.incoming = maxf(0.0, m.incoming - tr.qty)
	var robbed := false
	if tr.qty > 0.0:
		var cur := tr.city_id
		for rid: int in tr.path:
			var r: EconRoute = w.routes[rid]
			if r.danger > 0.0 and w.rng.chance(r.danger * float(tp["robbery_base"])):
				robbed = true
				w.stats["robberies"] += 1
				var a: EconCity = w.cities[r.a]
				var b: EconCity = w.cities[r.b]
				w.news.add("robbery", tr.to_city, "Rabunek na drodze %s – %s: %s traci ładunek (%s, %.0f j.)." % [a.name, b.name, w.business(tr.company_id).name, w.good_name(tr.good), tr.qty], 1)
				break
			cur = r.other(cur)
	var expected := 0.0
	if m != null and not robbed:
		m.add(tr.company_id, tr.qty)
		expected = tr.qty * m.price * float(tp["sell_discount"])
	var profit := expected - tr.cost_basis
	tr.profit_total += profit
	w.truck_profit_ema = lerpf(w.truck_profit_ema, profit, 0.02)
	tr.moving = false
	tr.city_id = tr.to_city
	tr.path.clear()
	tr.good = ""
	tr.qty = 0.0
	tr.cost_basis = 0.0
	tr.trips += 1
	w.stats["trips"] += 1


static func fuel_price(c: EconCity) -> float:
	return c.market("fuel").price


# Najlepszy kurs z miasta c: [zysk, towar, cel, ilość]. exclude = własna firma.
static func _best_trip(w: EconWorld, c: EconCity, exclude: int, cash: float, tp: Dictionary) -> Array:
	var best: Array = [0.0, "", -1, 0.0]
	var cap := float(tp["truck_capacity"])
	var fp := fuel_price(c)
	var per_km := float(tp["fuel_per_km"]) * fp
	var speed := float(tp["speed_km_per_day"])
	var driver := c.wage * float(tp["driver_wage_mult"])
	var discount := float(tp["sell_discount"])
	var max_days := float(tp["max_days_of_demand"])
	for g: String in w.tradable:
		var m := c.market(g)
		var avail := m.stock() - m.stock_of(exclude)
		if avail < 1.0:
			continue
		var p := m.price
		var units_cap := cap / float(w.goods[g]["weight"])
		var by_cash := cash * 0.9 / p
		for d: EconCity in w.cities:
			if d.id == c.id:
				continue
			var km: float = w.dist[c.id][d.id]
			if km == INF:
				continue
			var md := d.market(g)
			var sell := md.price * discount
			if sell <= p:
				continue
			var room := md.demand_ema * max_days - md.stock() - md.incoming
			if room <= 1.0:
				continue
			var qty := minf(minf(units_cap, avail), minf(room, by_cash))
			var gain := qty * (sell - p) - km * per_km - km / speed * driver
			if gain > best[0]:
				best = [gain, g, d.id, qty]
	return best


static func _plan(w: EconWorld, tr: EconTruck, comp: EconBusiness, best_from: Array, tp: Dictionary) -> void:
	var c: EconCity = w.cities[tr.city_id]
	# Na ładunek idzie tylko część kasy: reszta na paliwo i pensje pozostałych ciężarówek
	# (pieniądze wracają dopiero, gdy towar się sprzeda).
	var reserve := comp.trucks.size() * c.wage * float(tp["driver_wage_mult"]) * 10.0
	var budget := maxf(0.0, comp.cash - reserve) / maxf(1.0, comp.trucks.size() * 0.5)
	var best := _best_trip(w, c, comp.id, budget, tp)
	if float(best[0]) > float(tp["min_profit"]):
		if _depart(w, tr, comp, int(best[2]), str(best[1]), float(best[3]), tp):
			return
	# Na pusto tam, skąd jest lepszy kurs.
	var per_km := float(tp["fuel_per_km"]) * fuel_price(c)
	var go := -1
	var go_gain := float(tp["empty_trip_min_gain"])
	for d: EconCity in w.cities:
		if d.id == c.id:
			continue
		var km: float = w.dist[c.id][d.id]
		if km == INF:
			continue
		var g := float(best_from[d.id][0]) - km * per_km * 1.5
		if g > go_gain:
			go_gain = g
			go = d.id
	if go != -1:
		_depart(w, tr, comp, go, "", 0.0, tp)


static func _depart(w: EconWorld, tr: EconTruck, comp: EconBusiness, to_id: int, good: String, qty: float, tp: Dictionary) -> bool:
	var path := EconMap.path(w, tr.city_id, to_id)
	if path.is_empty():
		return false
	var km := 0.0
	var danger := 0.0
	for rid: int in path:
		km += w.routes[rid].length
		danger += w.routes[rid].danger
	var c: EconCity = w.cities[tr.city_id]
	# Ryzyko: na niebezpiecznej trasie towar musi być wart zachodu.
	if good != "" and danger > 0.0:
		var risk := minf(1.0, danger * float(tp["robbery_base"]))
		var md: EconMarket = w.cities[to_id].market(good)
		var value := qty * md.price * float(tp["sell_discount"])
		var gain := value - qty * c.market(good).price
		if value * risk > gain * 0.5:
			return false
	# Bak: tankujemy do pełna tam, gdzie jest paliwo; bez paliwa w baku nie ma jazdy.
	var fuel_need := km * float(tp["fuel_per_km"])
	var tank_max := float(tp["tank_km"]) * float(tp["fuel_per_km"])
	var fuel_cost := 0.0
	if tr.tank < tank_max:
		var fm := c.market("fuel")
		var fres: Array = fm.buy(tank_max - tr.tank, maxf(comp.cash, 0.0), w.pay_seller, comp.id, true)
		comp.cash -= float(fres[1])
		comp.cost_today += float(fres[1])
		tr.tank += float(fres[0])
		fuel_cost = float(fres[1])
	# Rezerwa w baku na dojazd dalej, chyba że w celu jest paliwo.
	var reserve := float(tp["reserve_km"]) * float(tp["fuel_per_km"])
	if w.cities[to_id].market("fuel").stock() > tank_max * 3.0:
		reserve = 0.0
	if tr.tank < fuel_need + reserve:
		w.stats["no_fuel"] = int(w.stats.get("no_fuel", 0)) + 1
		tr.stuck_days += 1
		if tr.stuck_days > int(tp["stuck_days_to_canister"]):
			_canister(w, tr, comp, tank_max, tp)
		return false
	tr.stuck_days = 0
	tr.tank -= fuel_need
	var got := 0.0
	var cost := fuel_cost
	if good != "":
		var gm := c.market(good)
		var res: Array = gm.buy(qty, maxf(comp.cash * 0.9, 0.0), w.pay_seller, comp.id, true)
		got = float(res[0])
		comp.cash -= float(res[1])
		comp.cost_today += float(res[1])
		cost += float(res[1])
		w.cities[to_id].market(good).incoming += got
	tr.moving = true
	tr.path = path
	tr.to_city = to_id
	tr.good = good if got > 0.0 else ""
	tr.qty = got
	tr.cost_basis = cost
	tr.depart_time = float(w.day) + w.rng.next_float(0.0, 0.5)
	tr.arrive_time = tr.depart_time + km / float(tp["speed_km_per_day"])
	return true


# Utknęła bez paliwa: firma kupuje paliwo w najbliższym mieście, które je ma, i płaci
# kierowcy z tamtego miasta za dowóz kanistrami (paliwo fizycznie znika z tamtego rynku).
static func _canister(w: EconWorld, tr: EconTruck, comp: EconBusiness, tank_max: float, tp: Dictionary) -> void:
	var best: EconCity = null
	var best_km := INF
	for c: EconCity in w.cities:
		if c.id != tr.city_id and c.market("fuel").stock() > tank_max and w.dist[tr.city_id][c.id] < best_km:
			best_km = w.dist[tr.city_id][c.id]
			best = c
	if best == null:
		return
	var res: Array = best.market("fuel").buy(tank_max - tr.tank, maxf(comp.cash * 0.5, 0.0), w.pay_seller, comp.id, true)
	comp.cash -= float(res[1])
	comp.cost_today += float(res[1])
	var fee := minf(maxf(comp.cash, 0.0), best_km * float(tp["canister_fee_per_km"]))
	comp.cash -= fee
	comp.cost_today += fee
	EconLabor.pay_wages(best, fee)
	tr.tank += float(res[0])
	tr.stuck_days = 0
	w.stats["canisters"] = int(w.stats.get("canisters", 0)) + 1


# Ciężarówki upadającej firmy idą do innego przewoźnika (połowa ceny bazowej), a nie na złom.
static func sell_used(w: EconWorld, tr: EconTruck, from: EconBusiness) -> bool:
	var price := float(w.goods["trucks"]["base"]) * 0.5
	var buyer: EconBusiness = null
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage" and b.status == "active" and b.id != from.id and b.cash > price * 2.0:
			if buyer == null or b.cash > buyer.cash:
				buyer = b
	if buyer == null:
		return false
	buyer.cash -= price
	buyer.cost_today += price
	from.cash += price
	from.trucks.erase(tr.id)
	buyer.trucks.append(tr.id)
	tr.company_id = buyer.id
	w.stats["trucks_resold"] = int(w.stats.get("trucks_resold", 0)) + 1
	return true


static func scrap(w: EconWorld, tr: EconTruck) -> void:
	var comp: EconBusiness = w.business(tr.company_id)
	if comp != null:
		comp.trucks.erase(tr.id)
	w.trucks.erase(tr.id)
	w.stats["trucks_scrapped"] += 1


# Nowa ciężarówka dla firmy: kupiona na rynku miasta, które ją ma (fabryka).
static func buy_truck(w: EconWorld, comp: EconBusiness) -> bool:
	var best: EconCity = null
	var best_cost := INF
	for c: EconCity in w.cities:
		var m := c.market("trucks")
		if m.stock() < 1.0:
			continue
		var cost := m.price + w.dist[comp.city_id][c.id] * 2.0
		if cost < best_cost:
			best_cost = cost
			best = c
	if best == null:
		# Nikt nie ma ciężarówek na sprzedaż: popyt trafia do miast z fabryką (cena rośnie).
		for b: EconBusiness in w.businesses.values():
			if b.type == "vehicle_plant" and b.is_open():
				w.city_of(b).market("trucks").want(1.0, comp.cash)
		return false
	var m := best.market("trucks")
	if comp.cash < m.price:
		return false
	var res: Array = m.buy(1.0, comp.cash, w.pay_seller, comp.id)
	if float(res[0]) < 0.999:
		# Ułamek ciężarówki nie jeździ: oddajemy go na rynek jako partię firmy.
		if float(res[0]) > 0.0:
			m.add(comp.id, float(res[0]))
		comp.cash -= float(res[1])
		return false
	comp.cash -= float(res[1])
	comp.cost_today += float(res[1])
	add_truck(w, comp, best.id)
	w.stats["trucks_bought"] += 1
	return true


static func add_truck(w: EconWorld, comp: EconBusiness, city_id: int) -> EconTruck:
	var tr := EconTruck.new(w.new_id(), comp.id, city_id)
	tr.tank = float(w.data["transport"]["tank_km"]) * float(w.data["transport"]["fuel_per_km"])
	var life: Array = w.data["transport"]["truck_life_days"]
	tr.retire_day = w.day + w.rng.next_int(int(life[0]), int(life[1]))
	w.trucks[tr.id] = tr
	comp.trucks.append(tr.id)
	return tr
