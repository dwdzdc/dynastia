# SimMigration — ludzie przychodzą i odchodzą (S31, X3–X4). Wieś nie jest zamkniętą
# pulą: gdy brakuje rąk do pracy albo stoi wolny dom, z miasta okolicy przychodzi
# rodzina i zakłada nowy ród; bieda bez dachu wypycha ludzi do miasta. Ludzie
# i pieniądze tylko przechodzą między wsią a miastem (S22). Miasta rosną, gdy mają
# co jeść, i maleją przy głodzie.
class_name SimMigration
extends RefCounted


var w: SimWorld
var _cfg: Dictionary
var _poor_days: Dictionary = {}    # id gospodarstwa -> ile dób z rzędu w nędzy


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func village_adults() -> int:
	var n := 0
	for p in w.family.all_living():
		var l := w.family.lineage_of(p)
		var a := w.agent_by_id(p.agent_id)
		if l != null and l.role != "trader" and a != null and a.status == "active" and w.family.stage_of(p) in ["adult", "elder"]:
			n += 1
	return n


func _unfilled_jobs() -> int:
	var n := 0
	for o: Dictionary in w.contracts.offers:
		n += maxi(0, w.contracts.free_slots(o))
	return n


func _free_house() -> SimBuilding:
	for b: SimBuilding in w.buildings.values():
		if w.is_free_house(b) and b.type != "manor":
			return b
	return null


func new_day() -> void:
	_grow_towns()
	_departures()
	_arrivals()


# Miasto rośnie przy nadwyżce jedzenia, maleje przy głodzie (X4).
func _grow_towns() -> void:
	for t: SimTown in w.traders.towns.values():
		var lack := int(t.shortage.get("food", 0))
		if lack > 0:
			t.population = maxi(int(_cfg["town_min"]), t.population - maxi(1, int(round(float(t.population) * float(_cfg["town_decline"])))))
		elif t.amount("food") > int(t.buffer("food")):
			t.population += maxi(1, int(round(float(t.population) * float(_cfg["town_growth"]))))


# Przybysze (X3): gdy we wsi brakuje ludzi albo pracy nikt nie bierze, a jest gdzie
# mieszkać, rodzina z miasta zakłada tu nowy ród.
func _arrivals() -> void:
	var house := _free_house()
	if house == null and _unfilled_jobs() <= 0:
		return
	if village_adults() >= int(_cfg["target_adults"]) and _unfilled_jobs() <= 0:
		return
	if not w.rng.chance(float(_cfg["arrive_chance"])):
		return
	var towns: Array = w.traders.towns.values()
	var town: SimTown = towns[w.rng.next_int(0, towns.size() - 1)]
	settle(town, house)


func settle(town: SimTown, house: SimBuilding) -> SimLineage:
	var f := w.family
	var size_r: Array = _cfg["family_size"]
	var n := mini(w.rng.next_int(int(size_r[0]), int(size_r[1])), maxi(1, town.population - int(_cfg["town_min"])))
	var surname: String = String(w.rng.choice(f._people["surnames"]))
	var l := f.new_lineage(surname, surname)
	var specs: Array = []
	var stages: Dictionary = _cfg["ages"]
	for i in n:
		var sex := "m" if i == 0 else ("f" if i == 1 else String(w.rng.choice(["m", "f"])))
		var ages: Array = stages["adult"] if i < 2 else stages["child"]
		var spec := { "key": "k%d" % i, "name": f._pick_name(sex), "sex": sex,
			"age_days": w.rng.next_float(float(ages[0]), float(ages[1])), "job": "none",
			"traits": [w.rng.choice(f._people["traits"].keys())] if w.rng.chance(float(_cfg["trait_chance"])) else [],
			"character": [w.rng.choice(f._people["character"].keys())] if w.rng.chance(float(_cfg["trait_chance"])) else [] }
		if i == 0:
			spec["root"] = true
		if i == 1:
			spec["spouse"] = "k0"
			spec["attached"] = true
			spec["surname"] = String(w.rng.choice(f._people["surnames"]))
		if i >= 2 and n >= 2:
			spec["mother"] = "k1"
			spec["father"] = "k0"
		specs.append(spec)
	var spawn_at: SimBuilding = house if house != null else w.building("market")
	var ids: Array = f.spawn_family(specs, l, spawn_at)
	# Pieniądze na start przychodzą z miasta (S22) — tyle, ile miasto może dać.
	var cash := minf(float(_cfg["start_cash"]), town.cash)
	town.cash -= cash
	town.population = maxi(int(_cfg["town_min"]), town.population - n)
	var h := w.new_household(house.id if house != null else "", cash)
	var e: Array = w.traders._cfg["entry"]
	for id in ids:
		w.join_household(f.persons[id], h)
		var a := w.agent_by_id(f.persons[id].agent_id)
		a.position = Vector2(float(e[0]), float(e[1])) + Vector2(w.rng.next_float(-1.0, 1.0), w.rng.next_float(-1.0, 1.0))
		a.controlled = true
		a.plan_kind = "manual"
		a.steps = [{ "t": "walk", "to": spawn_at.door(), "why": "przybywa z: %s, szuka swojego miejsca" % town.name }]
	var text := "Do wsi przybywa ród %s z %s (%d os.)%s." % [l.name, town.name, n, (", zajmuje: " + house.name) if house != null else ", bez dachu"]
	w.chronicle.add(w.clock.now(), "arrival", text, ids, l.id)
	w.note(text, "info", spawn_at.door())
	return l


# Odpływ (X3): ród AI bez dachu i bez grosza przez kilka dób odchodzi do miasta,
# zabierając to, co ma; miasto zyskuje ludzi.
func _departures() -> void:
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.home_id != "":
			_poor_days.erase(h.id)
			continue
		var p0: SimPerson = w.family.persons[h.members[0]]
		var l := w.family.lineage_of(p0)
		if l == null or l.role == "trader" or l.id == w.family.player_lineage_id:
			continue
		var purse := h.cash
		for pid in h.members:
			purse += w.family.persons[pid].purse
		if purse >= float(_cfg["poor_below"]):
			_poor_days[h.id] = 0
			continue
		_poor_days[h.id] = int(_poor_days.get(h.id, 0)) + 1
		if int(_poor_days[h.id]) >= int(_cfg["leave_after_days"]) and w.rng.chance(float(_cfg["leave_chance"])):
			leave(h)


func leave(h: SimHousehold) -> void:
	var towns: Array = w.traders.towns.values()
	var town: SimTown = towns[w.rng.next_int(0, towns.size() - 1)]
	var names: Array = []
	var lid := -1
	for pid in h.members.duplicate():
		var p: SimPerson = w.family.persons[pid]
		var a := w.agent_by_id(p.agent_id)
		if a == null or not p.alive():
			continue
		names.append(p.name)
		lid = p.lineage_id
		town.cash += p.purse
		p.purse = 0.0
		w.contracts.quit(p, "")
		w.jobs.release(a)
		a.steps.clear()
		a.status = "away"
		a.hidden = true
		town.population += 1
	town.cash += maxf(h.cash, 0.0)
	h.cash = 0.0
	_poor_days.erase(h.id)
	if lid >= 0:
		var l: SimLineage = w.family.lineages[lid]
		w.chronicle.add(w.clock.now(), "emigration", "Ród %s odchodzi do: %s (%s)." % [l.name, town.name, ", ".join(names)], [], lid)
		w.note("Ród %s nie dał rady — odchodzi do: %s." % [l.name, town.name], "info", null)
