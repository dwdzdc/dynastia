# SimNeeds — potrzeby gospodarstw (S23, R2): warstwy przetrwanie → wygoda → prestiż.
# Warstwa zależy od zamożności (pieniądze na osobę); im wyżej, tym więcej rzeczy ród
# chce mieć w domu. Braki to realny popyt we wsi (zakupy w R3), a nie liczba z tabeli.
# Jedzenie i opał (przetrwanie) obsługują cele zapasów gospodarstwa.
class_name SimNeeds
extends RefCounted


var w: SimWorld
var _cfg: Dictionary


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func label(good: String) -> String:
	return String(_cfg["labels"].get(good, good))


# Zamożność: pieniądze gospodarstwa (skrzynia + sakwy) na osobę.
func wealth(h: SimHousehold) -> float:
	var s := h.cash - h.debt
	var n := 0
	for pid in h.members:
		var p: SimPerson = w.family.persons[pid]
		if p.alive():
			s += p.purse
			n += 1
	return s / maxf(1.0, float(n))


func tier_index(h: SimHousehold) -> int:
	var tiers: Array = _cfg["tiers"]
	var wl := wealth(h)
	var idx := 0
	for i in tiers.size():
		if wl >= float(tiers[i]["min_wealth"]):
			idx = i
	return idx


func tier_label(h: SimHousehold) -> String:
	return String(_cfg["tiers"][tier_index(h)]["label"])


func _tier_of(tier_id: String) -> int:
	var tiers: Array = _cfg["tiers"]
	for i in tiers.size():
		if tiers[i]["id"] == tier_id:
			return i
	return 0


# Ile sztuk danego dobra gospodarstwo chce mieć w domu (według swojej warstwy).
func target(h: SimHousehold, good: String) -> int:
	var n: Dictionary = _cfg["needs"].get(good, {})
	if n.is_empty() or _tier_of(String(n["tier"])) > tier_index(h):
		return 0
	var mult := 1
	match String(n["per"]):
		"person":
			mult = h.members.filter(func(pid): return w.family.persons[pid].alive()).size()
		"adult":
			mult = h.members.filter(func(pid): return w.family.persons[pid].alive() and w.family.stage_of(w.family.persons[pid]) in ["adult", "elder"]).size()
	return int(n["qty"]) * mult


# Braki: towar -> ile brakuje w domu.
func wants(h: SimHousehold) -> Dictionary:
	var out := {}
	var home: SimBuilding = w.buildings.get(h.home_id)
	if home == null:
		return out
	for good in _cfg["needs"]:
		var miss := target(h, good) - home.amount(good)
		if miss > 0:
			out[good] = miss
	return out


func goods() -> Array:
	return _cfg["needs"].keys()


# Zużycie (R3): rzeczy w domu zużywają się z czasem, dom niszczeje. Raz na dobę.
func wear_day(h: SimHousehold) -> void:
	var home: SimBuilding = w.buildings.get(h.home_id)
	if home == null:
		return
	for good in _cfg["needs"]:
		var have := home.amount(good)
		if have <= 0:
			continue
		var acc := float(h.wear_acc.get(good, 0.0)) + float(have) / float(_cfg["needs"][good]["wear_days"])
		var n := int(floor(acc))
		h.wear_acc[good] = acc - n
		if n > 0:
			home.take(good, n)
	home.condition = maxf(0.0, home.condition - float(_cfg["house"]["decay_per_day"]))


func needs_repair(home: SimBuilding) -> bool:
	return home != null and home.condition < float(_cfg["house"]["repair_below"])


# Ile desek trzeba, żeby dom był jak nowy.
func repair_planks(home: SimBuilding) -> int:
	return int(ceil((1.0 - home.condition) * float(_cfg["house"]["planks_per_full"])))


func repair(home: SimBuilding, planks: int) -> void:
	home.condition = minf(1.0, home.condition + float(planks) / float(_cfg["house"]["planks_per_full"]))


func house_cfg() -> Dictionary:
	return _cfg["house"]


func reserve_meals() -> int:
	return int(_cfg["reserve_meals"])
