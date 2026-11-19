# RtsWorld — gra na mapie (iteracja 6, docs/design/rts-world.md). Trzyma gospodarkę
# świata (EconWorld), płynny czas, gracza (zwykły EconActor z is_player) i jego ludzi
# (RtsUnit). Czas płynie w ułamkach doby; gdy minie doba, liczy się doba gospodarki.
# Rozkazy gracza to komendy tutaj — game/ i ui/ tylko czytają stan i je wołają.
class_name RtsWorld
extends RefCounted


var econ: EconWorld
var data: Dictionary          # data/rts.json
var time: float = 0.0         # czas świata w dobach (z ułamkiem)
var player: EconActor
var units: Dictionary = {}    # id -> RtsUnit
var notes: Array[String] = [] # meldunki dla gracza (ostatnie)
var _pos_cache: Dictionary = {}


func _init(seed: int, econ_data: Dictionary, rts_data: Dictionary, warmup: bool = true) -> void:
	data = rts_data
	econ = EconWorld.new(seed, econ_data, warmup)
	time = float(econ.day)
	_make_player()


# --- gracz -------------------------------------------------------------------

func _make_player() -> void:
	var pp: Dictionary = data["player"]
	var order: Array = econ.cities.duplicate()
	order.sort_custom(func(a: EconCity, b: EconCity) -> bool: return a.population > b.population)
	var home: EconCity = order[mini(int(pp["start_city_rank"]), order.size() - 1)]
	player = EconPopulation.new_actor(econ, home.id, -1, "")
	player.is_player = true
	player.death_day = 1 << 30
	# Kapitał na start to oszczędności z kasy miasta (pieniądze się nie biorą z powietrza).
	var cash := minf(float(pp["cash"]), home.cash * 0.5)
	home.cash -= cash
	player.cash = cash
	var family_last := EconPopulation.family_last(player)
	for i in int(pp["people"]):
		var u := RtsUnit.new(econ.new_id())
		if i == 0:
			u.first = player.first
			u.female = player.female
		else:
			u.first = str(econ.rng.choice(econ.data["names"]["first"]))
			u.female = EconNames.is_female_first(u.first)
		u.last = EconNames.surname_for(family_last, u.female)
		u.pos = home_pos() + Vector2(0.02 * i, 0.015)
		u.reason = "w domu, czeka na zadanie"
		units[u.id] = u


func home_city() -> EconCity:
	return econ.cities[player.city_id]


# Dom rodu: stałe miejsce w mieście startowym (deterministycznie z seeda).
func home_pos() -> Vector2:
	var c := home_city()
	var r := RtsLayout.city_radius(data["layout"], c) * 0.3
	var ang := float(SimRng.hash3(econ.world_seed, player.id, "home") % 1000) / 1000.0 * TAU
	return c.pos + Vector2(cos(ang), sin(ang)) * r


func player_businesses() -> Array:
	return player.businesses.map(func(id: int) -> EconBusiness: return econ.business(id)).filter(func(b: EconBusiness) -> bool: return b != null and b.status != "closed")


func haulage() -> EconBusiness:
	for b: EconBusiness in player_businesses():
		if b.type == "haulage":
			return b
	return null


func player_trucks() -> Array:
	var comp := haulage()
	if comp == null:
		return []
	return comp.trucks.map(func(id: int) -> EconTruck: return econ.trucks.get(id)).filter(func(t: EconTruck) -> bool: return t != null)


func note(text: String) -> void:
	notes.append("d%d  %s" % [econ.day, text])
	if notes.size() > 40:
		notes.remove_at(0)


# --- czas --------------------------------------------------------------------

func advance(dt_days: float) -> void:
	time += dt_days
	while time >= float(econ.day):
		econ.step_day()
		_after_day()
	_update_units(dt_days)


func _after_day() -> void:
	for tr: EconTruck in player_trucks():
		if tr.mode == "route" and not tr.moving:
			_route_step(tr)
	for u: RtsUnit in units.values():
		if u.inside >= 0:
			var b: EconBusiness = econ.business(u.inside)
			if b == null or b.status == "closed":
				_leave(u)
				u.order = {"kind": "idle"}
				u.reason = "firma upadła, czeka na zadanie"
				note("%s: firma, w której pracował%s, upadła." % [u.full_name(), "a" if u.female else ""])
			elif b.status != "active":
				u.reason = "firma stoi (%s)" % ("pożar" if b.status == "burned" else "strajk")
			elif not b.extra_paid:
				u.reason = "pracuje, ale %s nie ma z czego płacić" % b.name
			else:
				u.earned += econ.city_of(b).wage
				u.reason = "pracuje: %s (%.0f zł dziennie)" % [b.name, econ.city_of(b).wage]


# --- ludzie gracza ------------------------------------------------------------

func business_pos(b: EconBusiness) -> Vector2:
	if not _pos_cache.has(b.id):
		_pos_cache[b.id] = RtsLayout.business_pos(econ, data["layout"], b)
	return _pos_cache[b.id]


func order_move(unit_id: int, to: Vector2) -> void:
	var u: RtsUnit = units.get(unit_id)
	if u == null:
		return
	_leave(u)
	u.order = {"kind": "move", "to": to}
	u.target = to
	u.walking = true
	u.reason = "idzie we wskazane miejsce"


func order_work(unit_id: int, business_id: int) -> String:
	var u: RtsUnit = units.get(unit_id)
	var b: EconBusiness = econ.business(business_id)
	if u == null or b == null or b.status == "closed":
		return "nie ma takiej firmy"
	if b.type == "haulage":
		return "w firmie przewozowej pracują kierowcy ciężarówek"
	if b.status == "building":
		return "firma jest jeszcze w budowie"
	_leave(u)
	u.order = {"kind": "work", "business": business_id}
	u.target = business_pos(b)
	u.walking = true
	u.reason = "idzie do pracy: %s" % b.name
	return ""


func order_idle(unit_id: int) -> void:
	var u: RtsUnit = units.get(unit_id)
	if u == null:
		return
	_leave(u)
	u.order = {"kind": "home"}
	u.target = home_pos()
	u.walking = true
	u.reason = "wraca do domu"


func _leave(u: RtsUnit) -> void:
	if u.inside >= 0:
		var b: EconBusiness = econ.business(u.inside)
		if b != null:
			b.extra_workers = maxf(0.0, b.extra_workers - 1.0)
		u.inside = -1


func _update_units(dt: float) -> void:
	var step := float(data["walk_km_per_day"]) * dt
	var near := float(data["arrive_km"])
	for u: RtsUnit in units.values():
		if not u.walking:
			continue
		var d := u.pos.distance_to(u.target)
		if d <= maxf(step, near):
			u.pos = u.target
			u.walking = false
			_arrived(u)
		else:
			u.pos += (u.target - u.pos) / d * step


func _arrived(u: RtsUnit) -> void:
	match str(u.order.get("kind", "idle")):
		"work":
			var b: EconBusiness = econ.business(int(u.order["business"]))
			if b == null or b.status == "closed":
				u.order = {"kind": "idle"}
				u.reason = "firma zniknęła, czeka na zadanie"
				return
			u.inside = b.id
			b.extra_workers += 1.0
			b.extra_payee = player.id
			u.reason = "pracuje: %s" % b.name
		"move":
			u.order = {"kind": "idle"}
			u.reason = "stoi tam, gdzie kazano"
		"home":
			u.order = {"kind": "idle"}
			u.reason = "w domu, czeka na zadanie"


# --- firmy gracza -------------------------------------------------------------

# Czego brakuje, żeby postawić tę firmę w tym mieście ("" = można).
func build_problem(type: String, city_id: int) -> String:
	var r: Dictionary = econ.recipe(type)
	var c: EconCity = econ.cities[city_id]
	var res: String = r.get("resource", "")
	if res != "" and float(c.resources.get(res, 0.0)) < 0.1:
		return "w okolicy nie ma złoża (%s)" % res
	var cost := EconInvest.build_cost(econ, type, c) * 1.25
	if player.cash < cost:
		return "za mało pieniędzy: potrzeba %.0f zł" % cost
	return ""


func build(type: String, city_id: int) -> String:
	var why := build_problem(type, city_id)
	if why != "":
		return why
	var c: EconCity = econ.cities[city_id]
	var b := EconInvest.found(econ, player, type, c, EconInvest.build_cost(econ, type, c))
	note("Budowa ruszyła: %s (%s)." % [b.name, c.name])
	return ""


# Dopłata do firmy albo wypłata z niej (gracz sam pilnuje kasy swoich firm).
func move_cash(business_id: int, amount: float) -> void:
	var b: EconBusiness = econ.business(business_id)
	if b == null:
		return
	if amount > 0.0:
		amount = minf(amount, player.cash)
	else:
		amount = -minf(-amount, maxf(b.cash, 0.0))
	player.cash -= amount
	b.cash += amount


# --- ciężarówki gracza --------------------------------------------------------

func buy_truck() -> String:
	var comp := haulage()
	var c := home_city()
	if comp == null:
		comp = EconBusiness.new(econ.new_id(), "haulage", c.id, player.id)
		comp.name = EconNames.business_name(str(econ.recipe("haulage")["name"]), EconPopulation.family_last(player))
		comp.founded_day = econ.day
		econ.businesses[comp.id] = comp
		player.businesses.append(comp.id)
	var price := INF
	for city: EconCity in econ.cities:
		if city.market("trucks").stock() >= 1.0:
			price = minf(price, city.market("trucks").price)
	if price == INF:
		return "nikt nie ma teraz ciężarówek na sprzedaż (fabryka nie nadąża)"
	var need := price * 1.05 + 3000.0 - comp.cash
	if need > player.cash:
		return "za mało pieniędzy: ciężarówka kosztuje ok. %.0f zł" % price
	if need > 0.0:
		move_cash(comp.id, need)
	var before := comp.trucks.size()
	EconLogistics.buy_truck(econ, comp)
	if comp.trucks.size() == before:
		return "zakup się nie udał"
	var tr: EconTruck = econ.trucks[comp.trucks[comp.trucks.size() - 1]]
	note("Kupiono ciężarówkę (stoi w: %s)." % econ.cities[tr.city_id].name)
	return ""


func truck_auto(truck_id: int) -> void:
	var tr: EconTruck = econ.trucks.get(truck_id)
	if tr != null:
		tr.mode = "auto"
		tr.route = {}
		tr.next_plan_day = econ.day


# Jednorazowy kurs: jedź do miasta, opcjonalnie z towarem kupionym tutaj.
func truck_go(truck_id: int, to_id: int, good: String = "") -> String:
	var tr: EconTruck = econ.trucks.get(truck_id)
	if tr == null:
		return "nie ma takiej ciężarówki"
	if tr.moving:
		return "ciężarówka jest w drodze"
	tr.mode = "manual"
	tr.route = {}
	var qty := 0.0
	if good != "":
		qty = float(econ.data["transport"]["truck_capacity"]) / maxf(float(econ.goods[good]["weight"]), 0.01)
	if not EconLogistics.depart(econ, tr, to_id, good, qty):
		return "nie da się wyjechać (brak drogi albo paliwa)"
	return ""


# Trasa stała: kupuj towar w A, wieź do B, wracaj — aż do odwołania.
func truck_route(truck_id: int, from_id: int, to_id: int, good: String) -> void:
	var tr: EconTruck = econ.trucks.get(truck_id)
	if tr == null:
		return
	tr.mode = "route"
	tr.route = {"from": from_id, "to": to_id, "good": good}
	if not tr.moving:
		_route_step(tr)


func _route_step(tr: EconTruck) -> void:
	var from_id := int(tr.route["from"])
	var to_id := int(tr.route["to"])
	var good := str(tr.route["good"])
	if tr.city_id == from_id:
		var qty := float(econ.data["transport"]["truck_capacity"]) / maxf(float(econ.goods[good]["weight"]), 0.01)
		EconLogistics.depart(econ, tr, to_id, good, qty)
	else:
		EconLogistics.depart(econ, tr, from_id, "", 0.0)


func truck_status(tr: EconTruck) -> String:
	if tr.moving:
		var what := "pusta" if tr.good == "" else "%s, %.0f j." % [econ.good_name(tr.good), tr.qty]
		return "jedzie do: %s (%s)" % [econ.cities[tr.to_city].name, what]
	match tr.mode:
		"route":
			return "trasa stała, czeka na załadunek w: %s" % econ.cities[tr.city_id].name
		"manual":
			return "stoi w: %s, czeka na rozkaz" % econ.cities[tr.city_id].name
		_:
			return "stoi w: %s, szuka kursu" % econ.cities[tr.city_id].name
