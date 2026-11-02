# SimTraders — kupcy wędrowni (S9, H3): wóz z kupcem przyjeżdża zza krawędzi mapy
# z konkretnego miejsca (data/traders.json), z ofertą kupna i sprzedaży, własną kasą
# i terminem odjazdu. Towar fizycznie donosi się na targ; po odjeździe oferta przepada,
# a sprzedane rzeczy wyjeżdżają razem z nim. Kupiec to stała osoba (z więziami),
# która między wizytami jest „w drodze” (status agenta „away”).
class_name SimTraders
extends RefCounted


var w: SimWorld
var visits: Array = []          # aktywne wizyty: { origin, person, cash, buys, sells, leave_at }
var _cfg: Dictionary
var _people: Dictionary = {}    # origin id -> id osoby kupca
var _next_day := 0
var _origin_i := 0


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg
	_next_day = int(cfg["every_days"]) - 1


func tick() -> void:
	var now := w.clock.now()
	if w.clock.day_index() >= _next_day and w.clock.time_of_day() >= float(_cfg["arrive_at"]):
		_next_day = w.clock.day_index() + int(_cfg["every_days"])
		var origins: Array = _cfg["origins"]
		arrive(origins[_origin_i % origins.size()])
		_origin_i += 1
	for v: Dictionary in visits.duplicate():
		if now >= float(v["leave_at"]) and not v.get("leaving", false):
			_depart(v)


func _trader_person(o: Dictionary) -> SimPerson:
	if _people.has(o["id"]):
		return w.family.persons[_people[o["id"]]]
	var l := w.family.new_lineage(String(o["name"]), String(o["trader"]["surname"]))
	l.role = "trader"
	var spec: Dictionary = o["trader"].duplicate()
	spec["key"] = "t"
	spec["root"] = true
	var ids: Array = w.family.spawn_family([spec], l, w.market.building)
	_people[o["id"]] = ids[0]
	return w.family.persons[ids[0]]


func arrive(o: Dictionary) -> Dictionary:
	var p := _trader_person(o)
	var a := w.agent_by_id(p.agent_id)
	var rng := w.rng
	var cash_r: Array = o["cash"]
	var v := {
		"origin": String(o["id"]), "origin_name": String(o["name"]), "person": p.id,
		"cash": rng.next_float(float(cash_r[0]), float(cash_r[1])),
		"buys": {}, "sells": {}, "leave_at": w.clock.now() + float(_cfg["stay"]),
	}
	for g in o["buys"]:
		var q: Array = o["buys"][g]["qty"]
		v["buys"][g] = { "qty": rng.next_int(int(q[0]), int(q[1])), "price": float(o["buys"][g].get("price", 0.0)),
			"price_mult": float(o["buys"][g].get("price_mult", 1.0)) }
	for g in o["sells"]:
		var q2: Array = o["sells"][g]["qty"]
		v["sells"][g] = { "qty": rng.next_int(int(q2[0]), int(q2[1])), "price": float(o["sells"][g]["price"]) }
	visits.append(v)
	# Wóz wjeżdża z krawędzi mapy i staje przy targu.
	var e: Array = _cfg["entry"]
	var st: Array = _cfg["stand"]
	a.status = "active"
	a.hidden = false
	a.position = Vector2(float(e[0]), float(e[1]))
	a.needs["food"] = 100.0
	a.controlled = true
	a.plan_kind = "manual"
	a.steps.clear()
	a.steps.append({ "t": "walk", "to": w.market.building.door() + Vector2(float(st[0]), float(st[1])), "why": "wjeżdża wozem na targ" })
	# Postój dłuższy niż oferta: odjazd zawsze zarządza _depart (żeby autopilot nie przejął wozu).
	a.steps.append({ "t": "act", "act": "trade", "left": 2.0 * float(_cfg["stay"]) * w.clock.day_seconds, "why": "handluje z wozu: " + offer_text(v), "inside": "", "alert": false, "work": false })
	_merchant_deals(v)
	w.note("Na targ przyjechał kupiec %s z %s: %s." % [p.full_name(), v["origin_name"], offer_text(v)], "info", w.market.building.door())
	return v


func offer_text(v: Dictionary) -> String:
	var parts: Array = []
	for g in v["buys"]:
		if int(v["buys"][g]["qty"]) > 0:
			parts.append("kupi %d× %s" % [int(v["buys"][g]["qty"]), w.good_label(g)])
	for g in v["sells"]:
		if int(v["sells"][g]["qty"]) > 0:
			parts.append("sprzeda %d× %s" % [int(v["sells"][g]["qty"]), w.good_label(g)])
	return ", ".join(parts) if not parts.is_empty() else "nic już nie ma"


# Miejscowy kupiec od razu robi z wozem interes: dokupuje brakujący towar i pozbywa
# się nadwyżek (zamiast abstrakcyjnego zaworu).
func _merchant_deals(v: Dictionary) -> void:
	var mk := w.market
	var t := mk.till()
	if t == null:
		return
	for g in v["sells"]:
		if not mk.trades(g):
			continue
		var gap := mk.target(g) - mk.building.amount(g)
		var n := mini(gap, int(v["sells"][g]["qty"]))
		n = mini(n, int(floor(t.cash / float(v["sells"][g]["price"])))) if float(v["sells"][g]["price"]) > 0.0 else 0
		n = mini(n, mk.building.space(g))
		if n > 0:
			t.pay(n * float(v["sells"][g]["price"]))
			v["cash"] = float(v["cash"]) + n * float(v["sells"][g]["price"])
			v["sells"][g]["qty"] = int(v["sells"][g]["qty"]) - n
			mk.building.add(g, n)
	for g in v["buys"]:
		if not mk.trades(g):
			continue
		var surplus := mk.building.amount(g) - mk.target(g)
		var n2 := mini(surplus, int(v["buys"][g]["qty"]))
		var taken := 0
		while taken < n2:
			var q := 0.0
			if g == "chair" and not mk.building.chair_qualities.is_empty():
				q = float(mk.building.chair_qualities[0])
			var price := buy_price(v, g, q)
			if float(v["cash"]) < price:
				break
			v["cash"] = float(v["cash"]) - price
			t.earn(price)
			mk.building.take(g, 1)
			if g == "chair" and not mk.building.chair_qualities.is_empty():
				mk.building.chair_qualities.pop_front()
			taken += 1
		v["buys"][g]["qty"] = int(v["buys"][g]["qty"]) - taken


func buy_price(v: Dictionary, good: String, quality: float = 0.0) -> float:
	var b: Dictionary = v["buys"][good]
	if good == "chair":
		return w.market.buy_price("chair", quality) * float(b["price_mult"])
	return float(b["price"])


# Ile sztuk tego towaru kupią wszystkie stojące wozy (do decyzji nosiciela).
func wants(good: String) -> int:
	var n := 0
	for v: Dictionary in visits:
		if not v.get("leaving", false) and v["buys"].has(good):
			n += int(v["buys"][good]["qty"])
	return n


# Sprzedaż prosto na wóz (lepsza cena niż u miejscowego). Zwraca { qty, paid }.
func sell_to_wagon(seller: SimHousehold, good: String, qty: int, qualities: Array) -> Dictionary:
	var n := 0
	var paid := 0.0
	for v: Dictionary in visits:
		if v.get("leaving", false) or not v["buys"].has(good):
			continue
		while n < qty and int(v["buys"][good]["qty"]) > 0:
			var q: float = float(qualities[n]) if n < qualities.size() else 0.0
			var price := buy_price(v, good, q)
			if float(v["cash"]) < price:
				break
			v["cash"] = float(v["cash"]) - price
			v["buys"][good]["qty"] = int(v["buys"][good]["qty"]) - 1
			seller.earn(price)
			paid += price
			n += 1
	return { "qty": n, "paid": paid }


func _depart(v: Dictionary) -> void:
	v["leaving"] = true
	var a := w.agent_by_id(w.family.persons[int(v["person"])].agent_id)
	var e: Array = _cfg["entry"]
	a.steps.clear()
	a.controlled = true
	a.plan_kind = "manual"
	a.steps.append({ "t": "walk", "to": Vector2(float(e[0]), float(e[1])), "why": "odjeżdża do: %s" % v["origin_name"] })
	a.steps.append({ "t": "do", "fn": "trader_gone", "arg": v["origin"] })


# Wóz za krawędzią mapy: oferta przepada, towar i pieniądze wyjeżdżają z nim.
func gone(a: SimAgent, origin: String) -> void:
	visits = visits.filter(func(v): return v["origin"] != origin)
	a.status = "away"
	a.hidden = true
	a.steps.clear()
