# EconRoute — droga między dwoma miastami (km). Może być zamknięta (powódź,
# osuwisko) albo niebezpieczna (zbójcy: danger 0..1, opada z czasem).
class_name EconRoute
extends RefCounted


var id: int
var a: int
var b: int
var length: float
var points: PackedVector2Array = PackedVector2Array()   # łamana od miasta a do b (km)
var closed_until: int = -1
var closed_reason: String = ""
var danger: float = 0.0


func _init(id_: int, a_: int, b_: int, length_: float) -> void:
	id = id_
	a = a_
	b = b_
	length = length_


func other(city_id: int) -> int:
	return b if city_id == a else a


# Punkt na drodze po przejechaniu `km` od miasta `from_id`.
func point_at(from_id: int, km: float) -> Vector2:
	var pts := points if from_id == a else _reversed()
	var left := km
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg:
			return pts[i].lerp(pts[i + 1], left / maxf(seg, 1e-6))
		left -= seg
	return pts[pts.size() - 1]


var _rev: PackedVector2Array = PackedVector2Array()   # łamana od b do a (liczona raz)


func _reversed() -> PackedVector2Array:
	if _rev.size() != points.size():
		_rev = points.duplicate()
		_rev.reverse()
	return _rev


func is_closed(day: int) -> bool:
	return day < closed_until


# Punkty łamanej od km `k0` do km `k1` (liczone od miasta `from_id`), w kolejności
# jazdy — także wstecz, gdy k1 < k0. Z oboma końcami.
func segment(from_id: int, k0: float, k1: float) -> PackedVector2Array:
	var out := PackedVector2Array([point_at(from_id, k0)])
	var pts := points if from_id == a else _reversed()
	var acc := 0.0
	var inner := PackedVector2Array()
	for i in range(1, pts.size() - 1):
		acc += pts[i - 1].distance_to(pts[i])
		if acc > minf(k0, k1) and acc < maxf(k0, k1):
			inner.append(pts[i])
	if k1 < k0:
		inner.reverse()
	out.append_array(inner)
	out.append(point_at(from_id, k1))
	return out
