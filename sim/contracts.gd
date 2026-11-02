# SimContracts — praca u kogoś jako umowa (S15, L3). Pracodawca (gospodarstwo) wystawia
# ofertę: ile osób, do jakiej roboty, w jakim miejscu i za ile na dobę. Ludzie przyjmują
# najlepszą ofertę, która ich zadowala; za niską stawkę nikt nie przyjdzie.
# Płaca narasta z czasem pracy (`owed`), a wręcza ją płatnik — ktoś z gospodarstwa
# pracodawcy — który po robocie przychodzi z sakwą pod miejsce pracy. Kto nie dostał
# zapłaty, pamięta to i odchodzi.
class_name SimContracts
extends RefCounted


var w: SimWorld
var offers: Array = []      # { id, employer (gosp.), place (budynek), job, slots, wage }
var list: Array = []        # { offer, employer, worker (osoba), job, place, wage, owed, until }
var _cfg: Dictionary
var _next_offer := 1


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


# Wystaw albo zmień ofertę (jedna na pracodawcę, miejsce i zawód). slots = 0 wycofuje.
func post(employer: int, place: String, job: String, slots: int, wage: float) -> Dictionary:
	var o := find_offer(employer, place, job)
	if o.is_empty():
		if slots <= 0:
			return {}
		o = { "id": _next_offer, "employer": employer, "place": place, "job": job, "slots": slots, "wage": wage }
		_next_offer += 1
		offers.append(o)
	o["slots"] = slots
	o["wage"] = wage
	return o


func find_offer(employer: int, place: String, job: String) -> Dictionary:
	for o: Dictionary in offers:
		if int(o["employer"]) == employer and o["place"] == place and o["job"] == job:
			return o
	return {}


# Oferta w miejscu na dany zawód (dowolnego pracodawcy; jedna na miejsce).
func find_offer_at(place: String, job: String) -> Dictionary:
	for o: Dictionary in offers:
		if o["place"] == place and o["job"] == job and int(o["slots"]) > 0:
			return o
	return {}


func taken(o: Dictionary) -> int:
	var n := 0
	for c: Dictionary in list:
		if int(c["offer"]) == int(o["id"]):
			n += 1
	return n


func free_slots(o: Dictionary) -> int:
	return int(o["slots"]) - taken(o)


func of_worker(pid: int) -> Dictionary:
	for c: Dictionary in list:
		if int(c["worker"]) == pid:
			return c
	return {}


func of_employer(hid: int) -> Array:
	return list.filter(func(c): return int(c["employer"]) == hid)


# Najlepsza oferta dla osoby: stawka minus koszt drogi plus sympatia do pracodawcy.
# Pusta, gdy żadna nie przebija stawki, za którą w ogóle warto iść (`min_wage`).
func best_offer_for(p: SimPerson, job: String = "") -> Dictionary:
	var a: SimAgent = w.agent_by_id(p.agent_id)
	var best := {}
	var best_score := -INF
	for o: Dictionary in offers:
		if (job != "" and o["job"] != job) or free_slots(o) <= 0 or int(o["employer"]) == p.household_id:
			continue
		if float(o["wage"]) < float(_cfg["min_wage"]):
			continue
		var score := float(o["wage"])
		var place: SimBuilding = w.buildings.get(o["place"])
		if a != null and place != null and w.buildings.has(a.home_id):
			score -= float(_cfg["wage_per_distance"]) * w.buildings[a.home_id].door().distance_to(place.door())
		var boss := _boss(int(o["employer"]))
		if boss != null:
			score += float(_cfg["wage_per_bond"]) * w.bonds.value(p.id, SimBonds.person(boss.id))
		if score > best_score:
			best_score = score
			best = o
	return best


func hire(o: Dictionary, p: SimPerson) -> Dictionary:
	quit(p, "")
	var c := { "offer": int(o["id"]), "employer": int(o["employer"]), "worker": p.id, "job": o["job"],
		"place": o["place"], "wage": float(o["wage"]), "owed": 0.0,
		"until": w.clock.day_index() + int(_cfg["days"]) }
	list.append(c)
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a != null:
		a.job = String(o["job"])
		a.workplace = String(o["place"])
	return c


# Koniec umowy. `why` niepuste = zapis w dzienniku (dla ludzi gracza).
func quit(p: SimPerson, why: String) -> void:
	var c := of_worker(p.id)
	if c.is_empty():
		return
	list.erase(c)
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a != null and a.workplace == c["place"]:
		a.workplace = ""
	if why != "" and w.family.is_ours(p):
		w.note("%s: koniec pracy u obcych (%s)." % [p.name, why], "warn", a.position if a != null else null)


# Narastanie płacy za czas pracy (wołane z SimWorld przy każdej czynności pracy).
func accrue(a: SimAgent, s: Dictionary, dt: float) -> void:
	var c := of_worker(a.person_id)
	if c.is_empty() or a.workplace != c["place"]:
		return
	var sch: Dictionary = w.balance["schedule"]
	var work_day := (float(sch["work_end"]) - float(sch["work_start"])) * w.clock.day_seconds
	c["owed"] = float(c["owed"]) + float(c["wage"]) * dt / work_day * float(s.get("will", 1.0))


# Płatnik: dorosły z gospodarstwa pracodawcy, który jest na chodzie (nie pracuje
# u innych). Najpierw głowa gospodarstwa, potem reszta po kolei.
func payer(hid: int) -> SimAgent:
	var h: SimHousehold = w.households.get(hid)
	if h == null:
		return null
	for pid in h.members:
		var p: SimPerson = w.family.persons[pid]
		var a: SimAgent = w.agent_by_id(p.agent_id)
		if a != null and a.is_active() and not a.is_child and not a.disabled() and of_worker(pid).is_empty():
			return a
	return null


func _boss(hid: int) -> SimPerson:
	var a := payer(hid)
	return w.person_of(a) if a != null else null


# Gdzie wręcza się wypłatę: pod drzwiami miejsca pracy.
func pay_spot(place: String) -> Vector2:
	var b: SimBuilding = w.buildings.get(place)
	return b.door() + Vector2(float(_cfg["pay_offset"][0]), float(_cfg["pay_offset"][1])) if b != null else Vector2.ZERO


func in_pay_window() -> bool:
	var sch: Dictionary = w.balance["schedule"]
	var t := w.clock.time_of_day()
	return t >= float(sch["work_end"]) - float(_cfg["pay_lead"]) and t < float(sch["work_end"]) + float(_cfg["pay_wait"])


func owed_total(hid: int, place: String) -> float:
	var s := 0.0
	for c: Dictionary in of_employer(hid):
		if c["place"] == place:
			s += float(c["owed"])
	return s


# Miejsca, w których gospodarstwo ma dziś coś do wypłacenia.
func pay_places(hid: int) -> Array:
	var out: Array = []
	for c: Dictionary in of_employer(hid):
		if float(c["owed"]) > 0.0 and not c["place"] in out:
			out.append(c["place"])
	return out


# Płatnik pod miejscem pracy wręcza z sakwy tym, którzy stoją obok. Zwraca wypłaconą sumę.
func hand_out(payer_a: SimAgent, place: String) -> float:
	var pp := w.person_of(payer_a)
	if pp == null:
		return 0.0
	var spot := pay_spot(place)
	var paid := 0.0
	for c: Dictionary in of_employer(pp.household_id):
		if c["place"] != place or float(c["owed"]) <= 0.0:
			continue
		var wp: SimPerson = w.family.persons.get(int(c["worker"]))
		var wa: SimAgent = w.agent_by_id(wp.agent_id) if wp != null else null
		if wa == null or wa.position.distance_to(spot) > float(_cfg["pay_radius"]):
			continue
		var amt := minf(float(c["owed"]), maxf(pp.purse, 0.0))
		if amt <= 0.0:
			break
		pp.purse -= amt
		pp.held = minf(pp.held, pp.purse)
		c["owed"] = float(c["owed"]) - amt
		w.earn_for(wa, amt)
		paid += amt
		w.events.float_text(wa.position, "+%d zł (wypłata)" % int(round(amt)), "money")
	return paid


# Koniec okna wypłat: kto nie dostał całości, pamięta to i odchodzi. Umowy wygasają.
func settle_day() -> void:
	for c: Dictionary in list.duplicate():
		var wp: SimPerson = w.family.persons.get(int(c["worker"]))
		if wp == null or not wp.alive():
			list.erase(c)
			continue
		if float(c["owed"]) >= float(_cfg["unpaid_tolerance"]):
			var boss := _boss(int(c["employer"]))
			if boss != null:
				w.bonds.remember(wp.id, SimBonds.person(boss.id), "unpaid_wage", [boss.id])
			quit(wp, "nie zapłacili %d zł" % int(round(float(c["owed"]))))
			continue
		c["owed"] = 0.0
		if w.clock.day_index() >= int(c["until"]):
			quit(wp, "")
