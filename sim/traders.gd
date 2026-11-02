# SimTraders — kupcy wędrowni (S9, H3): wóz z kupcem przyjeżdża zza krawędzi mapy
# z konkretnego miejsca (data/traders.json), z ofertą kupna i sprzedaży, własną kasą
# i terminem odjazdu. Wóz staje na placu jako stragan (M7); towar fizycznie donosi się
# do lady, po odjeździe oferta przepada, a skupione rzeczy wyjeżdżają razem z nim. Kupiec to stała osoba (z więziami),
# która między wizytami jest „w drodze” (status agenta „away”).
class_name SimTraders
extends RefCounted


var w: SimWorld
var visits: Array = []          # aktywne wizyty: { origin, origin_name, person, stall, leave_at }
var _cfg: Dictionary
var _people: Dictionary = {}    # origin id -> id osoby kupca
var towns: Dictionary = {}      # origin id -> SimTown (S25): skąd jadą wozy, dokąd wracają pieniądze i towar
var _next_day := 0
var _origin_i := 0


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg
	_next_day = int(cfg["every_days"]) - 1
	for o: Dictionary in cfg["origins"]:
		towns[String(o["id"])] = SimTown.new(o, w.balance["trade"]["ref"], cfg["town"])


func town_cash_total() -> float:
	var s := 0.0
	for t: SimTown in towns.values():
		s += t.cash
	return s


func new_day() -> void:
	for t: SimTown in towns.values():
		w.money_minted += t.new_day()


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
	var ids: Array = w.family.spawn_family([spec], l, w.building("market"))
	var p: SimPerson = w.family.persons[ids[0]]
	# Własne „gospodarstwo w drodze”: bez domu, pieniądze w sakwie kupca.
	w.join_household(p, w.new_household("", 0.0))
	_people[o["id"]] = ids[0]
	return p


# Wóz staje na wolnym miejscu placu jako stragan (M7): sprzedaje to, co przywiózł,
# skupuje to, po co przyjechał, po cenach z oferty; kasa to sakwa kupca.
func arrive(o: Dictionary) -> Dictionary:
	var slot := w.trade.free_slot()
	if slot.x == INF:
		return {}
	var p := _trader_person(o)
	var a := w.agent_by_id(p.agent_id)
	var h: SimHousehold = w.households[p.household_id]
	var town: SimTown = towns[String(o["id"])]
	var tc: Dictionary = _cfg["town"]
	# Kasa wozu to pieniądze miasta: kupiec bierze część z domu i z nią wraca (S22).
	var take := town.cash * float(tc["wagon_cash_share"])
	town.cash -= take
	p.purse += take
	p.held = 0.0
	h.prices = {}
	var goods: Array = []
	var b := SimBuilding.new("wagon_" + String(o["id"]), "Wóz z: %s" % String(o["name"]), "stall", slot, {})
	var st := w.trade.add_stall(b, b, h.id, [])
	st.temporary = true
	# Wóz wiezie nadwyżki miasta i skupuje to, czego miastu brakuje (U2).
	var room := int(tc["wagon_capacity"])
	for g in tc["trade_goods"]:
		var n := mini(town.surplus(g), room)
		if n <= 0:
			continue
		n = town.take(g, n)
		room -= n
		b.capacity[g] = n
		b.add(g, n)
		w.trade.set_limit(h, g, "sell_min", town.price(g) * float(tc["export_markup"]))
		goods.append(g)
	for g in tc["trade_goods"]:
		var n := mini(town.lack(g), int(tc["wagon_capacity"]))
		if n <= 0 or g in goods:
			continue
		b.capacity[g] = n
		b.stock[g] = 0
		st.wants[g] = n
		st.buys.append(g)
		w.trade.set_limit(h, g, "buy_max", town.price(g) * float(tc["import_ratio"]))
		goods.append(g)
	st.goods = goods
	w.buildings[b.id] = b
	var v := { "origin": String(o["id"]), "origin_name": String(o["name"]), "person": p.id, "stall": st.id,
		"leave_at": w.clock.now() + float(_cfg["stay"]) }
	visits.append(v)
	# Wóz wjeżdża z krawędzi mapy, staje na placu i kupiec rozkłada towar.
	var e: Array = _cfg["entry"]
	a.status = "active"
	a.hidden = false
	a.position = Vector2(float(e[0]), float(e[1]))
	a.needs["food"] = 100.0
	a.controlled = true
	a.plan_kind = "manual"
	a.steps.clear()
	a.steps.append({ "t": "walk", "to": slot, "why": "wjeżdża wozem na targ" })
	a.steps.append({ "t": "do", "fn": "open_stall", "arg": st.id })
	# Postój dłuższy niż oferta: odjazd zawsze zarządza _depart (żeby autopilot nie przejął wozu).
	a.steps.append({ "t": "act", "act": "sell", "left": 2.0 * float(_cfg["stay"]) * w.clock.day_seconds, "why": "handluje z wozu: " + offer_text(v), "inside": "", "alert": false, "work": false })
	w.note("Na targ przyjechał kupiec %s z %s: %s." % [p.full_name(), v["origin_name"], offer_text(v)], "info", slot)
	return v


func stall_of(v: Dictionary) -> SimStall:
	return w.trade.stalls.get(String(v["stall"]))


func offer_text(v: Dictionary) -> String:
	var st := stall_of(v)
	if st == null:
		return "nic już nie ma"
	var h: SimHousehold = w.households[st.owner]
	var parts: Array = []
	for g in st.wants:
		if int(st.wants[g]) > 0:
			parts.append("kupi %d× %s po %.1f zł" % [int(st.wants[g]), w.good_label(g), w.trade.buy_max(h, g)])
	for g in st.goods:
		if st.stock.amount(g) > 0 and not st.wants.has(g):
			parts.append("sprzeda %d× %s po %.1f zł" % [st.stock.amount(g), w.good_label(g), w.trade.sell_min(h, g)])
	return ", ".join(parts) if not parts.is_empty() else "nic już nie ma"


# Ile sztuk tego towaru kupią jeszcze stojące wozy.
func wants(good: String) -> int:
	var n := 0
	for v: Dictionary in visits:
		var st := stall_of(v)
		if st != null and not v.get("leaving", false):
			n += maxi(0, int(st.wants.get(good, 0)))
	return n


# Odjazd: kupiec zwija wóz; czego nie sprzedał i co kupił, wyjeżdża razem z nim.
func _depart(v: Dictionary) -> void:
	v["leaving"] = true
	var st := stall_of(v)
	if st != null:
		v["cargo"] = st.stock.stock.duplicate()
		w.trade.remove_stall(st)
	var a := w.agent_by_id(w.family.persons[int(v["person"])].agent_id)
	var e: Array = _cfg["entry"]
	a.steps.clear()
	a.claims.clear()
	a.controlled = true
	a.plan_kind = "manual"
	a.steps.append({ "t": "walk", "to": Vector2(float(e[0]), float(e[1])), "why": "odjeżdża do: %s" % v["origin_name"] })
	a.steps.append({ "t": "do", "fn": "trader_gone", "arg": v["origin"] })


# Wóz za krawędzią mapy: oferta przepada, towar i pieniądze wyjeżdżają z nim.
func gone(a: SimAgent, origin: String) -> void:
	var town: SimTown = towns.get(origin)
	# Niesprzedane i skupione towary oraz kasa wracają do miasta.
	for v: Dictionary in visits:
		if v["origin"] == origin and town != null:
			var cargo: Dictionary = v.get("cargo", {})
			for g in cargo:
				town.add(g, int(cargo[g]))
	visits = visits.filter(func(v): return v["origin"] != origin)
	var p := w.person_of(a)
	if p != null and town != null:
		town.cash += p.purse
		p.purse = 0.0
	a.status = "away"
	a.hidden = true
	a.steps.clear()
