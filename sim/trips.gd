# SimTrips — wyprawy do miast okolicy (U3). Osoba ładuje towar, którego miastu
# brakuje, idzie drogą za krawędź mapy, sprzedaje po cenie miasta, za utarg kupuje
# to, czego brakuje w domu (potrzeby, S23), i wraca. Na drodze grozi napad. To ta
# sama ścieżka dla gracza i dla kupców AI: zarobek z różnicy cen między miejscami.
class_name SimTrips
extends RefCounted


var w: SimWorld
var trips: Array = []     # { agent, town, cargo, bought, return_at, away }
var _cfg: Dictionary


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func on_trip(a: SimAgent) -> bool:
	for t: Dictionary in trips:
		if int(t["agent"]) == a.id:
			return true
	return false


# Co by się opłacało wziąć z tego składu do miasta: towary, których miastu brakuje.
func cargo_plan(town: SimTown, from: SimBuilding) -> Dictionary:
	var out := {}
	var room := int(_cfg["trip_capacity"])
	for g in from.stock:
		if room <= 0:
			break
		var n := mini(mini(from.amount(g), town.lack(g)), room)
		if n > 0:
			out[g] = n
			room -= n
	return out


# Start wyprawy: towar ze składu na plecy (wózek), droga na skraj mapy.
func start(a: SimAgent, town_id: String, from: SimBuilding) -> bool:
	var town: SimTown = w.traders.towns.get(town_id)
	if town == null or a == null or not a.is_active() or a.is_child or on_trip(a) or from == null:
		return false
	var plan := cargo_plan(town, from)
	var cargo := {}
	var quals: Array = []
	for g in plan:
		cargo[g] = from.take(g, int(plan[g]))
		if g == "chair":
			for i in int(cargo[g]):
				quals.append(from.chair_qualities.pop_front() if not from.chair_qualities.is_empty() else 0.0)
	w.jobs.release(a)
	a.steps.clear()
	a.controlled = true
	a.plan_kind = "manual"
	var e: Array = w.traders._cfg["entry"]
	a.steps.append({ "t": "walk", "to": Vector2(float(e[0]), float(e[1])), "why": "wyrusza z towarem do: %s" % town.name })
	a.steps.append({ "t": "do", "fn": "trip_leave", "arg": town_id })
	trips.append({ "agent": a.id, "town": town_id, "cargo": cargo, "quals": quals, "bought": {}, "return_at": -1.0, "away": false })
	return true


# Za krawędzią mapy: sprzedaż w mieście, zakupy, droga — wszystko w agregacie.
func leave(a: SimAgent, town_id: String) -> void:
	var t := _trip_of(a)
	var town: SimTown = w.traders.towns.get(town_id)
	var p := w.person_of(a)
	if t.is_empty() or town == null or p == null:
		return
	a.status = "away"
	a.hidden = true
	a.steps.clear()
	# Sprzedaż: miasto płaci swoją cenę, póki ma pieniądze.
	var cargo: Dictionary = t["cargo"]
	for g in cargo:
		var n := int(cargo[g])
		var price := town.price(g)
		var can := mini(n, int(floor(town.cash / maxf(price, 0.01))))
		town.cash -= price * can
		SimTrade.hand_to(p, price * can)
		town.add(g, can)
		cargo[g] = n - can
	# Zakupy: czego brakuje w domu, a miasto ma w nadmiarze.
	var bought := {}
	var hh := w.household_of(a)
	var room := int(_cfg["trip_capacity"])
	for g in w.needs.wants(hh):
		var n := mini(mini(int(w.needs.wants(hh)[g]), town.surplus(g)), room)
		var price := town.price(g) * float(w.traders._cfg["town"]["export_markup"])
		n = mini(n, int(floor(p.purse / maxf(price, 0.01))))
		if n <= 0:
			continue
		p.purse -= price * n
		p.held = minf(p.held, p.purse)
		town.cash += price * n
		bought[g] = town.take(g, n)
		room -= n
	t["bought"] = bought
	t["away"] = true
	t["return_at"] = w.clock.now() + 2.0 * float(_cfg["travel_days"])
	# Droga bywa niebezpieczna: napad zabiera część sakwy i towaru.
	if w.rng.chance(float(_cfg["robbery_chance"])):
		var lost := p.purse * float(_cfg["robbery_take"])
		p.purse -= lost
		town.cash += lost   # zrabowane pieniądze krążą dalej w okolicy
		t["robbed"] = true


func tick() -> void:
	var now := w.clock.now()
	for t: Dictionary in trips.duplicate():
		if not bool(t["away"]) or now < float(t["return_at"]):
			continue
		_return(t)


func _return(t: Dictionary) -> void:
	trips.erase(t)
	var a := w.agent_by_id(int(t["agent"]))
	if a == null or a.status != "away":
		return
	var p := w.person_of(a)
	var e: Array = w.traders._cfg["entry"]
	a.status = "active"
	a.hidden = false
	a.position = Vector2(float(e[0]), float(e[1]))
	a.needs["food"] = maxf(a.needs["food"], float(_cfg["return_food"]))
	var home: SimBuilding = w.home_of(a)
	var what := ", ".join((t["bought"] as Dictionary).keys().map(func(g): return "%d× %s" % [int(t["bought"][g]), w.good_label(g)]))
	var msg := "%s wraca z: %s%s%s." % [p.name, w.traders.towns[t["town"]].name, (" — przywozi " + what) if what != "" else "",
		" (napadnięty po drodze!)" if t.get("robbed", false) else ""]
	if w.family.is_ours(p):
		w.note(msg, "warn" if t.get("robbed", false) else "good", a.position)
	a.controlled = true
	a.plan_kind = "manual"
	a.steps.clear()
	if home != null:
		a.steps.append({ "t": "walk", "to": home.door(), "why": "wraca z wyprawy do domu" })
		a.steps.append({ "t": "do", "fn": "trip_unload", "arg": { "bought": t["bought"], "cargo": t["cargo"], "quals": t["quals"] } })


# W domu: zakupy do spiżarni i komór, a niesprzedany towar też.
func unload(a: SimAgent, arg: Dictionary) -> void:
	var home: SimBuilding = w.home_of(a)
	if home == null:
		return
	for src in ["bought", "cargo"]:
		var d: Dictionary = arg[src]
		for g in d:
			var n := mini(int(d[g]), maxi(home.space(g), 0))
			home.add(g, n)
	_return_coins(a)


func _return_coins(a: SimAgent) -> void:
	w.jobs._return_coins(a)


func _trip_of(a: SimAgent) -> Dictionary:
	for t: Dictionary in trips:
		if int(t["agent"]) == a.id:
			return t
	return {}
