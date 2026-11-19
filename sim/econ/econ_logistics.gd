# EconLogistics — ciężarówki firm przewozowych. Kurs prowadzi od budynku do budynku:
# ładunek bierze się z magazynu sprzedawcy (największa partia na rynku miasta), a
# zostawia u odbiorcy (firma, która go przerabia, a dobra konsumpcyjne — sklep, czyli
# firma usługowa). Rynek miasta zostaje cennikiem i księgowością: kto ma ile i po ile.
# Doba: przyjazdy (rabunek na niebezpiecznej drodze, rozładunek jako partia
# przewoźnika albo prosto do magazynu własnej firmy), pensje
# kierowców, złomowanie, a wolne ciężarówki szukają kursu: kupić tu, sprzedać
# tam, po odliczeniu paliwa, kierowcy, ryzyka i tego, co już tam jedzie
# (market.incoming — żeby wszystkie nie rzucały się na jedną trasę).
class_name EconLogistics
extends RefCounted


const BUILD_GOODS := ["lumber", "cement", "steel"]


static func step(w: EconWorld) -> void:
	var tp: Dictionary = w.data["transport"]
	var now := float(w.day)
	# 1. Przyjazdy.
	for tr: EconTruck in w.trucks.values():
		if tr.moving and tr.arrive_time <= now:
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
	var tg := _targets(w, tp)
	var best_from: Array = []
	for c: EconCity in w.cities:
		best_from.append(_best_trip(w, c, -1, INF, tp, tg))
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
		if comp.status != "active" or w.day < tr.next_plan_day or tr.mode != "auto":
			continue
		if not _plan(w, tr, comp, best_from, tp, tg):
			var wait: Array = tp["idle_wait_days"]
			tr.next_plan_day = w.day + w.rng.next_int(int(wait[0]), int(wait[1]))


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
		var own: EconBusiness = w.business(tr.deliver_to)
		if own != null and own.is_open() and (w.recipe(own.type)["inputs"] as Dictionary).has(tr.good):
			# Dostawa do magazynu własnej firmy (łańcuch gracza): bez sprzedaży na rynku.
			own.inputs[tr.good] = float(own.inputs.get(tr.good, 0.0)) + tr.qty
		else:
			m.add(tr.company_id, tr.qty)
		expected = tr.qty * m.price * float(tp["sell_discount"])
	var profit := expected - tr.cost_basis
	tr.profit_total += profit
	w.truck_profit_ema = lerpf(w.truck_profit_ema, profit, 0.02)
	tr.moving = false
	tr.city_id = tr.to_city
	tr.spot = tr.dest_spot
	tr.pts = PackedVector2Array()
	tr.cum = PackedFloat32Array()
	tr.deliver_to = -1
	tr.path.clear()
	tr.good = ""
	tr.qty = 0.0
	tr.cost_basis = 0.0
	tr.trips += 1
	w.stats["trips"] += 1


static func fuel_price(c: EconCity) -> float:
	return c.market("fuel").price


# Tablice celów na dobę: cena sprzedaży (po upuście) i wolne miejsce na rynku
# celu dla każdej pary (miasto, towar). Miejsce maleje, gdy ciężarówka wyrusza.
static func _targets(w: EconWorld, tp: Dictionary) -> Dictionary:
	var gn := w.tradable.size()
	var sell := PackedFloat32Array()
	var room := PackedFloat32Array()
	sell.resize(w.cities.size() * gn)
	room.resize(w.cities.size() * gn)
	var discount := float(tp["sell_discount"])
	var max_days := float(tp["max_days_of_demand"])
	for d: EconCity in w.cities:
		for gi in gn:
			var md := d.market(w.tradable[gi])
			sell[d.id * gn + gi] = md.price * discount
			room[d.id * gn + gi] = md.demand_ema * max_days - md.stock() - md.incoming
	return {"sell": sell, "room": room, "gn": gn}


# Najlepszy kurs z miasta c: [zysk, towar, cel, ilość]. exclude = własna firma.
static func _best_trip(w: EconWorld, c: EconCity, exclude: int, cash: float, tp: Dictionary, tg: Dictionary) -> Array:
	var best: Array = [0.0, "", -1, 0.0]
	var cap := float(tp["truck_capacity"])
	var per_km := float(tp["fuel_per_km"]) * fuel_price(c) + c.wage * float(tp["driver_wage_mult"]) / float(tp["speed_km_per_day"])
	var sell: PackedFloat32Array = tg["sell"]
	var room: PackedFloat32Array = tg["room"]
	var gn: int = tg["gn"]
	var row: PackedFloat32Array = w.dist[c.id]
	var n := w.cities.size()
	for gi in gn:
		var g: String = w.tradable[gi]
		var m := c.market(g)
		var avail := m.stock() - m.stock_of(exclude)
		if avail < 1.0:
			continue
		var p := m.price
		var qty_cap := minf(minf(cap / float(w.goods[g]["weight"]), avail), cash * 0.9 / p)
		for d in n:
			var idx := d * gn + gi
			var margin := sell[idx] - p
			if margin <= 0.0 or d == c.id:
				continue
			var r := room[idx]
			if r <= 1.0:
				continue
			var qty := minf(qty_cap, r)
			var gain := qty * margin - row[d] * per_km
			if gain > float(best[0]):
				best = [gain, g, d, qty]
	return best


static func _plan(w: EconWorld, tr: EconTruck, comp: EconBusiness, best_from: Array, tp: Dictionary, tg: Dictionary) -> bool:
	var c: EconCity = w.cities[tr.city_id]
	# Na ładunek idzie tylko część kasy: reszta na paliwo i pensje pozostałych ciężarówek
	# (pieniądze wracają dopiero, gdy towar się sprzeda).
	var reserve := comp.trucks.size() * c.wage * float(tp["driver_wage_mult"]) * 10.0
	var budget := maxf(0.0, comp.cash - reserve) / maxf(1.0, comp.trucks.size() * 0.5)
	var best := _best_trip(w, c, comp.id, budget, tp, tg)
	if float(best[0]) > float(tp["min_profit"]):
		if _depart(w, tr, comp, int(best[2]), str(best[1]), float(best[3]), tp):
			# Miejsce na rynku celu zajęte przez ten ładunek.
			var idx := int(best[2]) * int(tg["gn"]) + w.tradable.find(str(best[1]))
			var room: PackedFloat32Array = tg["room"]
			room[idx] -= tr.qty
			tg["room"] = room
			return true
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
		return _depart(w, tr, comp, go, "", 0.0, tp)
	return false


static func _depart(w: EconWorld, tr: EconTruck, comp: EconBusiness, to_id: int, good: String, qty: float, tp: Dictionary, force: bool = false, pickup_bid: int = -1, drop_bid: int = -1) -> bool:
	var c: EconCity = w.cities[tr.city_id]
	var dest: EconCity = w.cities[to_id]
	var path: Array[int] = []
	if to_id != tr.city_id:
		path = EconMap.path(w, tr.city_id, to_id)
		if path.is_empty():
			return false
	elif drop_bid == -1:
		return false
	# Skąd ładunek i dokąd: budynek sprzedawcy, budynek odbiorcy (albo parking przy drodze).
	if tr.spot.is_empty():
		tr.spot = home_spot(w, comp, c)
	var pickup: Dictionary = {}
	if good != "":
		var pb := pickup_bid if pickup_bid != -1 else c.market(good).top_seller(comp.id)
		var seller: EconBusiness = w.business(pb)
		pickup = EconLayout.spot_of(seller) if seller != null and seller.city_id == c.id else shop_spot(w, c)
	var drop: Dictionary
	var drop_b: EconBusiness = w.business(drop_bid)
	if drop_b != null:
		drop = EconLayout.spot_of(drop_b)
	elif good != "":
		drop = consumer_spot(w, dest, good)
	else:
		drop = EconLayout.parking(w, dest, path[path.size() - 1] if not path.is_empty() else -1)
	var pts := PackedVector2Array()
	if not pickup.is_empty():
		pts = EconLayout.in_city(w, c, tr.spot, pickup)
		pts.append_array(EconLayout.trip(w, c, pickup, path, dest, drop))
	else:
		pts = EconLayout.trip(w, c, tr.spot, path, dest, drop)
	var cum := EconLayout.cumulative(pts)
	var km := cum[cum.size() - 1]
	var danger := 0.0
	for rid: int in path:
		danger += w.routes[rid].danger
	# Ryzyko: na niebezpiecznej trasie towar musi być wart zachodu.
	if good != "" and danger > 0.0 and not force:
		var risk := minf(1.0, danger * float(tp["robbery_base"]))
		var md: EconMarket = dest.market(good)
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
	if dest.market("fuel").stock() > tank_max * 3.0:
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
		var seller: EconBusiness = w.business(pickup_bid)
		var res: Array
		if seller != null and seller.owner_id == comp.owner_id:
			# Towar z własnej firmy: bez płacenia samemu sobie.
			res = [gm.take_from(seller.id, qty), 0.0]
		elif seller != null:
			res = gm.buy_from(seller.id, qty, maxf(comp.cash * 0.9, 0.0), w.pay_seller)
		else:
			res = gm.buy(qty, maxf(comp.cash * 0.9, 0.0), w.pay_seller, comp.id, true)
		got = float(res[0])
		comp.cash -= float(res[1])
		comp.cost_today += float(res[1])
		cost += float(res[1])
		dest.market(good).incoming += got
		if got <= 0.0 and pickup_bid != -1:
			tr.tank += fuel_need  # nie było czego załadować: kurs się nie odbywa
			return false
	tr.moving = true
	tr.path = path
	tr.to_city = to_id
	tr.good = good if got > 0.0 else ""
	tr.qty = got
	tr.cost_basis = cost
	tr.pts = pts
	tr.cum = cum
	tr.from_bid = int(pickup.get("bid", -1)) if got > 0.0 else -1
	tr.to_bid = int(drop.get("bid", -1))
	tr.dest_spot = drop
	tr.depart_time = float(w.day) + w.rng.next_float(0.0, 0.5)
	tr.arrive_time = tr.depart_time + km / float(tp["speed_km_per_day"])
	return true


# Gdzie stoi ciężarówka bez zadania: baza firmy w jej mieście, a gdzie indziej parking przy drodze.
static func home_spot(w: EconWorld, comp: EconBusiness, c: EconCity) -> Dictionary:
	if comp.city_id == c.id:
		return EconLayout.spot_of(comp)
	return EconLayout.parking(w, c, c.routes[0] if not c.routes.is_empty() else -1)


# Sklep / hurtownia w mieście: firma usługowa (dobra konsumpcyjne trafiają do handlu).
static func shop_spot(w: EconWorld, c: EconCity) -> Dictionary:
	var shops: Array = []
	var weights: Array = []
	for b: EconBusiness in w.firms_in(c.id):
		if b.type == "services":
			shops.append(b)
			weights.append(float(b.level))
	if shops.is_empty():
		return EconLayout.parking(w, c, c.routes[0] if not c.routes.is_empty() else -1)
	return EconLayout.spot_of(shops[EconSetup._pick(w, weights)])


# Odbiorca towaru w mieście: firma, która go przerabia (wg wielkości), a jak nikt — sklep.
static func consumer_spot(w: EconWorld, c: EconCity, good: String) -> Dictionary:
	var list: Array = []
	var weights: Array = []
	for b: EconBusiness in w.firms_in(c.id):
		var uses := false
		if good == "trucks":
			uses = b.type == "haulage"
		else:
			# Budowa też odbiera: deski, cement i stal jadą na plac budowy.
			uses = (w.recipe(b.type)["inputs"] as Dictionary).has(good) or (not b.project.is_empty() and good in BUILD_GOODS)
		if uses:
			list.append(b)
			weights.append(float(maxi(b.level, 1)))
	if list.is_empty():
		return shop_spot(w, c)
	return EconLayout.spot_of(list[EconSetup._pick(w, weights)])


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


# Wyjazd na rozkaz (gracz): opcjonalnie z ładunkiem kupionym tu na miejscu.
static func depart(w: EconWorld, tr: EconTruck, to_id: int, good: String, qty: float) -> bool:
	var comp: EconBusiness = w.business(tr.company_id)
	if comp == null or tr.moving or to_id == tr.city_id:
		return false
	return _depart(w, tr, comp, to_id, good, qty, w.data["transport"], true)


# Pusty dojazd pod budynek firmy (także w tym samym mieście).
static func go_to(w: EconWorld, tr: EconTruck, b: EconBusiness) -> bool:
	var comp: EconBusiness = w.business(tr.company_id)
	if comp == null or tr.moving or b == null:
		return false
	return _depart(w, tr, comp, b.city_id, "", 0.0, w.data["transport"], true, -1, b.id)


# Kurs z firmy do firmy: ładunek to wyrób firmy-źródła (z jej magazynu), dostawa pod
# budynek odbiorcy. Własna firma odbiorcy dostaje towar prosto do magazynu wejść.
static func haul(w: EconWorld, tr: EconTruck, from_b: EconBusiness, to_b: EconBusiness) -> bool:
	var comp: EconBusiness = w.business(tr.company_id)
	if comp == null or tr.moving or from_b == null or to_b == null or from_b.city_id != tr.city_id:
		return false
	var good: String = w.recipe(from_b.type)["out"]
	if good == "" or not good in w.tradable:
		return false
	var qty := float(w.data["transport"]["truck_capacity"]) / maxf(float(w.goods[good]["weight"]), 0.01)
	if not _depart(w, tr, comp, to_b.city_id, good, qty, w.data["transport"], true, from_b.id, to_b.id):
		return false
	if to_b.owner_id == comp.owner_id:
		tr.deliver_to = to_b.id
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
	var tr := add_truck(w, comp, best.id)
	var maker: EconBusiness = w.business(m.top_seller()) if m.stock() > 0.0 else null
	for b: EconBusiness in w.firms_in(best.id):
		if b.type == "vehicle_plant":
			maker = b
	if maker != null:
		tr.spot = EconLayout.spot_of(maker)  # odbiór spod fabryki
	w.stats["trucks_bought"] += 1
	return true


static func add_truck(w: EconWorld, comp: EconBusiness, city_id: int) -> EconTruck:
	var tr := EconTruck.new(w.new_id(), comp.id, city_id)
	tr.tank = float(w.data["transport"]["tank_km"]) * float(w.data["transport"]["fuel_per_km"])
	var life: Array = w.data["transport"]["truck_life_days"]
	tr.retire_day = w.day + w.rng.next_int(int(life[0]), int(life[1]))
	tr.spot = home_spot(w, comp, w.cities[city_id])
	w.trucks[tr.id] = tr
	comp.trucks.append(tr.id)
	return tr
