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


func _reversed() -> PackedVector2Array:
	var r := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		r.append(points[i])
	return r


func is_closed(day: int) -> bool:
	return day < closed_until
