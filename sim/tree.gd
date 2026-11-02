# SimTree — drzewo w lesie: zasób drewna, rezerwacja przez drwala, odrost.
class_name SimTree
extends RefCounted


var id: int
var position: Vector2
var wood: int
var max_wood: int
var regrow_left: float = 0.0   # sekundy sim do odrostu (gdy ścięte)
var reserved_by: int = -1


func _init(p_id: int, p_pos: Vector2, p_wood: int) -> void:
	id = p_id
	position = p_pos
	wood = p_wood
	max_wood = p_wood


func available() -> bool:
	return wood > 0 and reserved_by < 0


# 0..1 do renderu (pień = 0, pełne drzewo = 1; podczas odrostu rośnie).
func growth(regrow_total: float) -> float:
	if wood > 0:
		return 0.55 + 0.45 * float(wood) / float(max_wood)
	if regrow_total <= 0.0:
		return 0.0
	return clampf(1.0 - regrow_left / regrow_total, 0.0, 1.0) * 0.5
