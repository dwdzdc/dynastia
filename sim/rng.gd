# SimRng — deterministyczny generator losowy dla warstwy sim/.
#
# Zasady (patrz docs/adr/0002-deterministic-sim.md):
#   * ten sam seed -> ten sam ciąg wartości,
#   * zero zależności od globalnego randi() i od czasu zegarowego,
#   * hash3(seed, id, purpose) daje stabilną, content-adresowalną liczbę
#     dla materializacji (ta sama osoba zawsze wychodzi taka sama).
class_name SimRng
extends RefCounted


var _rng := RandomNumberGenerator.new()


func _init(seed: int) -> void:
	_rng.seed = seed


func next_int(from_: int, to_: int) -> int:
	return _rng.randi_range(from_, to_)


func next_float(from_: float = 0.0, to_: float = 1.0) -> float:
	return _rng.randf_range(from_, to_)


func chance(p: float) -> bool:
	return _rng.randf() < p


func choice(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


func choice_i(items: Array) -> int:
	if items.is_empty():
		return -1
	return _rng.randi_range(0, items.size() - 1)


func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


# Stabilny hash łączący seed świata, id bytu i cel generowania.
# Determinizm: FNV-1a 32 nad kanoniczną reprezentacją wejść (bez hash() silnika).
static func hash3(seed: int, id: int, purpose: String) -> int:
	var h: int = 2166136261
	h = _fnv(h, seed)
	h = _fnv(h, id)
	for c in purpose:
		h = _fnv(h, c.unicode_at(0))
	return h & 0xFFFFFFFF


static func _fnv(h: int, v: int) -> int:
	for i in 4:
		var b := (v >> (i * 8)) & 0xFF
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h
