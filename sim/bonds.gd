# SimBonds — jeden rzadki magazyn więzi dla ludzi i czynności (S2). Klucz to (od, cel),
# gdzie cel to osoba („p:12”) albo czynność/miejsce („act:saw”, „place:sawmill”).
# Więź nie ma zapisanej wartości: to suma wag wspomnień z blaknięciem (S3), liczona
# na żądanie. Brak kontaktu sprowadza więź ku zeru („obcy”), nigdy niżej.
class_name SimBonds
extends RefCounted


var w: SimWorld
var bonds: Dictionary = {}      # "od>cel" -> Array wspomnień { kind, day, weight, permanent, with, at }

var _kinds: Dictionary
var _mods: Dictionary
var _stage_mult: Dictionary
var _prune_below: float


func _init(world: SimWorld, memories: Dictionary) -> void:
	w = world
	_kinds = memories["kinds"]
	_mods = memories["character_mods"]
	_stage_mult = memories["stage_weight_mult"]
	_prune_below = float(memories["prune_below"])


static func person(pid: int) -> String:
	return "p:%d" % pid


static func act(name: String) -> String:
	return "act:%s" % name


static func place(name: String) -> String:
	return "place:%s" % name


func _key(from: int, target: String) -> String:
	return "%d>%s" % [from, target]


# Wspomnienie przeżywa osoba `from`. Siła zależy od rodzaju (dane), etapu życia
# przeżywającego (dzieci mocniej) i jego charakteru.
# `at` to miejsce (id budynku), jeśli wspomnienie jest z nim związane.
func remember(from: int, target: String, kind: String, with: Array = [], scale: float = 1.0, at: String = "") -> Dictionary:
	var k: Dictionary = _kinds[kind]
	var p: SimPerson = w.family.persons.get(from)
	var weight := float(k["weight"]) * scale
	if p != null:
		weight *= float(_stage_mult.get(w.family.stage_of(p), 1.0))
		weight *= _char_mult(p, kind, weight, "weight_mult")
	var m := {
		"kind": kind,
		"day": w.clock.now(),
		"weight": weight,
		"permanent": bool(k["permanent"]),
		"with": with.duplicate(),
		"at": at,
	}
	var key := _key(from, target)
	if not bonds.has(key):
		bonds[key] = []
	(bonds[key] as Array).append(m)
	return m


func memories(from: int, target: String) -> Array:
	return bonds.get(_key(from, target), [])


# Dryf (B4): samo blaknięcie prowadzi ku „obcy” (0), ale nie zmienia znaku tego,
# co ustaliły zdarzenia — wrogość wymaga zdarzenia, nie upływu czasu.
func value(from: int, target: String) -> float:
	var p: SimPerson = w.family.persons.get(from)
	var sum := 0.0
	var raw := 0.0
	for m: Dictionary in memories(from, target):
		sum += faded(p, m)
		raw += float(m["weight"])
	return maxf(sum, 0.0) if raw >= 0.0 else minf(sum, 0.0)


# Bieżąca waga wspomnienia: trwałe nie blakną, reszta zanika wykładniczo
# (okres połowicznego zaniku z danych, wydłużany przez charakter).
func faded(p: SimPerson, m: Dictionary) -> float:
	var weight := float(m["weight"])
	if bool(m["permanent"]):
		return weight
	var half := float(_kinds[String(m["kind"])]["half_life_days"])
	if p != null:
		half *= _char_mult(p, String(m["kind"]), weight, "half_life_mult")
	if half <= 0.0:
		return 0.0
	var age := maxf(0.0, w.clock.now() - float(m["day"]))
	return weight * pow(0.5, age / half)


# Mnożnik z charakteru: selektor to nazwa rodzaju, „positive”, „negative” albo „all”.
func _char_mult(p: SimPerson, kind: String, weight: float, field: String) -> float:
	var mult := 1.0
	for c in p.character:
		var sel: Dictionary = _mods.get(c, {}).get(field, {})
		for s in sel:
			if s == kind or s == "all" or (s == "positive" and weight > 0.0) or (s == "negative" and weight < 0.0):
				mult *= float(sel[s])
	return mult


# Tekst wspomnienia z szablonu w danych: {with} → imiona, {act} → czynność, {place} → budynek.
func describe(m: Dictionary, target: String = "") -> String:
	var text := String(_kinds[String(m["kind"])]["text"])
	var names: Array = []
	for id in m["with"]:
		var o: SimPerson = w.family.persons.get(int(id))
		if o != null:
			names.append(o.name)
	text = text.replace("{with}", ", ".join(names))
	var act_name := target.substr(4) if target.begins_with("act:") else ""
	text = text.replace("{act}", String(w.memories["act_labels"].get(act_name, act_name)))
	var b: SimBuilding = w.buildings.get(String(m.get("at", "")))
	text = text.replace("{place}", b.name if b != null else "")
	return text


# Najmocniej odczuwane (co do wartości bezwzględnej) wspomnienia osoby o podanych celach.
func strongest(from: int, targets: Array, count: int) -> Array:
	var p: SimPerson = w.family.persons.get(from)
	var all: Array = []
	for t in targets:
		for m: Dictionary in memories(from, String(t)):
			all.append({ "m": m, "t": String(t), "v": faded(p, m) })
	all.sort_custom(func(x, y): return absf(float(x["v"])) > absf(float(y["v"])))
	return all.slice(0, count)


# Preferencje (D3): więź z każdą czynnością plus skłonność z charakteru, z informacją
# skąd się wzięła. Zwraca [{ act, value, from: [teksty] }] od najbardziej lubianej.
func preferences(pid: int) -> Array:
	var p: SimPerson = w.family.persons.get(pid)
	var out: Array = []
	for act_name in w.memories["act_labels"]:
		var target := SimBonds.act(String(act_name))
		var v := value(pid, target)
		var src: Array = []
		for e in strongest(pid, [target], int(w.memories["pref_sources"])):
			var txt := describe(e["m"], target)
			if not txt in src:
				src.append(txt)
		if p != null:
			for c in p.character:
				var bias := float(w.memories["character_prefs"].get(c, {}).get(act_name, 0.0))
				if bias != 0.0:
					v += bias
					src.append("charakter: %s" % w.family.character_label(c))
		if not src.is_empty():
			out.append({ "act": String(act_name), "value": v, "from": src })
	out.sort_custom(func(x, y): return float(x["value"]) > float(y["value"]))
	return out


func preference(pid: int, act_name: String) -> float:
	for e in preferences(pid):
		if e["act"] == act_name:
			return float(e["value"])
	return 0.0


# Cele, do których `from` ma jakąkolwiek więź (z prefiksem, np. „p:” albo „act:”).
func targets_of(from: int, prefix: String = "") -> Array:
	var out: Array = []
	var head := "%d>" % from
	for key: String in bonds:
		if key.begins_with(head):
			var t := key.substr(head.length())
			if prefix == "" or t.begins_with(prefix):
				out.append(t)
	return out


# Raz na dobę: wyrzuca wyblakłe do zera wspomnienia, żeby magazyn nie rósł bez końca.
func prune() -> void:
	for key: String in bonds.keys():
		var from := int(key.get_slice(">", 0))
		var p: SimPerson = w.family.persons.get(from)
		var kept: Array = []
		for m: Dictionary in bonds[key]:
			if bool(m["permanent"]) or absf(faded(p, m)) >= _prune_below:
				kept.append(m)
		if kept.is_empty():
			bonds.erase(key)
		else:
			bonds[key] = kept
