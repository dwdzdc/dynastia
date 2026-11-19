# EconRoute — droga między dwoma miastami (km). Może być zamknięta (powódź,
# osuwisko) albo niebezpieczna (zbójcy: danger 0..1, opada z czasem).
class_name EconRoute
extends RefCounted


var id: int
var a: int
var b: int
var length: float
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


func is_closed(day: int) -> bool:
	return day < closed_until
