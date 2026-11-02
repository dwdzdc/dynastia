# SimStanding — pozycja rodu (S28, V1–V2). Liczona, nie przechowywana: z kilku „walut”
# naraz — majątek (skrzynie, domy, warsztaty, ziemia), reputacja w zawodzie i opinia
# ludzi z innych rodów. Szczeble z danych opisują drogę majątku i urzędu; to jedna
# z dróg sukcesu (intro §7), a nie jedyna oś. Szczebel daje konkretne możliwości:
# kredyt u ludzi, a najwyżej stojący ród trzyma urząd sołtysa.
class_name SimStanding
extends RefCounted


var w: SimWorld
var _cfg: Dictionary
var rank_of: Dictionary = {}      # id rodu -> indeks szczebla (raz na dobę, do kroniki awansów)


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func _households(l: SimLineage) -> Array:
	var out := {}
	for p in w.family.living_members(l.id):
		var h: SimHousehold = w.households.get(p.household_id)
		if h != null:
			out[h.id] = h
	return out.values()


# Majątek: pieniądze minus długi plus wartość budynków i ziemi rodu.
func wealth(l: SimLineage) -> float:
	var s := 0.0
	for h: SimHousehold in _households(l):
		s += h.cash - h.debt
		for pid in h.members:
			s += w.family.persons[pid].purse
	var bv: Dictionary = _cfg["building_value"]
	for b: SimBuilding in w.buildings.values():
		if b.owner_kind == "lineage" and b.owner_id == l.id:
			s += float(bv.get(b.type, bv["default"]))
	return s


func owns_type(l: SimLineage, types: Array) -> bool:
	for b: SimBuilding in w.buildings.values():
		if b.owner_kind == "lineage" and b.owner_id == l.id and b.type in types:
			return true
	return false


func owns_land(l: SimLineage) -> bool:
	for f: SimField in w.fields:
		var b: SimBuilding = w.buildings.get(f.owner_building)
		if b != null and b.owner_kind == "lineage" and b.owner_id == l.id:
			return true
	return false


# Opinia: średnia sympatia ludzi z innych rodów do członków tego rodu.
func opinion(l: SimLineage) -> float:
	var mem := w.family.living_members(l.id)
	var s := 0.0
	var n := 0
	for o in w.family.all_living():
		if o.lineage_id == l.id:
			continue
		for m: SimPerson in mem:
			s += w.bonds.value(o.id, SimBonds.person(m.id))
			n += 1
	return s / maxf(1.0, float(n))


func reputation(l: SimLineage) -> float:
	var r := 0.0
	for h: SimHousehold in _households(l):
		r = maxf(r, h.reputation)
	return r


# Szczebel: najwyższy, którego warunki ród spełnia.
func rank(l: SimLineage) -> int:
	var ranks: Array = _cfg["ranks"]
	var best := 0
	var wl := wealth(l)
	var op := opinion(l)
	for i in ranks.size():
		var r: Dictionary = ranks[i]
		if wl < float(r.get("wealth", 0.0)) or op < float(r.get("opinion", -INF)):
			continue
		if r.has("owns") and not owns_type(l, r["owns"]):
			continue
		if bool(r.get("land", false)) and not owns_land(l):
			continue
		best = i
	return best


func rank_label(l: SimLineage) -> String:
	return String(_cfg["ranks"][rank(l)]["label"])


# Co ludzie mówią o rodzie i dlaczego (V1): opisowo, bez liczb.
func describe(l: SimLineage) -> Array:
	var out: Array = []
	var d: Dictionary = _cfg["words"]
	var wl := wealth(l)
	out.append(String(d["rich"]) if wl >= float(d["rich_above"]) else (String(d["poor"]) if wl < float(d["poor_below"]) else String(d["modest"])))
	var op := opinion(l)
	if op >= float(d["liked_above"]):
		out.append(String(d["liked"]))
	elif op <= float(d["disliked_below"]):
		out.append(String(d["disliked"]))
	else:
		out.append(String(d["unknown"]))
	if reputation(l) >= float(d["craft_above"]):
		out.append(String(d["craft"]))
	if owns_type(l, ["sawmill", "workshop"]):
		out.append(String(d["enterprise"]))
	if owns_land(l):
		out.append(String(d["land"]))
	if office_holder() == l:
		out.append(String(d["office"]))
	return out


# Ród na urzędzie (sołtys): najwyżej stojący, przy remisie bogatszy.
func office_holder() -> SimLineage:
	var best: SimLineage = null
	var best_key := -INF
	for l: SimLineage in w.family.lineages.values():
		if l.role == "trader" or w.family.living_members(l.id).is_empty():
			continue
		var key := float(rank(l)) * RANK_WEIGHT + wealth(l)
		if key > best_key:
			best_key = key
			best = l
	return best


# Kredyt u ludzi (V2): ile długu znosi się rodowi na tym szczeblu.
func credit_limit(l: SimLineage) -> float:
	return float(_cfg["ranks"][rank(l)]["credit"])


const RANK_WEIGHT := 100000.0   # szczebel ważniejszy niż pieniądze przy wyborze sołtysa


# Raz na dobę: kredyt według szczebla, awanse i upadki do kroniki.
func new_day() -> void:
	for l: SimLineage in w.family.lineages.values():
		if l.role == "trader" or w.family.living_members(l.id).is_empty():
			continue
		var r := rank(l)
		for h: SimHousehold in _households(l):
			h.debt_limit = credit_limit(l)
		var prev := int(rank_of.get(l.id, r))
		rank_of[l.id] = r
		if r != prev:
			var up := r > prev
			var text := "Ród %s %s: %s." % [l.name, "awansuje" if up else "podupada", rank_label(l)]
			w.chronicle.add(w.clock.now(), "rank", text, [], l.id)
			if l.id == w.family.player_lineage_id or up:
				w.note(text, "good" if up else "warn", null)
