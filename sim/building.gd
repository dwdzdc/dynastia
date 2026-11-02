# SimBuilding — budynek osady: pozycja, typ, zapasy towarów i ich pojemność.
# Część warstwy logistyki (ADR-0001): nic nie wie o rodzinach ani więziach.
class_name SimBuilding
extends RefCounted


var id: String
var name: String
var type: String
var position: Vector2
var stock: Dictionary = {}       # good -> int
var capacity: Dictionary = {}    # good -> int (brak klucza = brak miejsca na ten towar)
var chair_qualities: Array = []  # jakość każdego krzesła w zapasie (FIFO)


func _init(p_id: String, p_name: String, p_type: String, p_pos: Vector2, p_cap: Dictionary) -> void:
	id = p_id
	name = p_name
	type = p_type
	position = p_pos
	capacity = p_cap.duplicate()
	for g in capacity:
		stock[g] = 0


func amount(good: String) -> int:
	return int(stock.get(good, 0))


func space(good: String) -> int:
	if not capacity.has(good):
		return 0
	return int(capacity[good]) - amount(good)


func add(good: String, qty: int) -> void:
	stock[good] = amount(good) + qty


func take(good: String, qty: int) -> int:
	var n := mini(qty, amount(good))
	stock[good] = amount(good) - n
	return n


# Drzwi: punkt przed budynkiem, do którego chodzą ludzie (budynek stoi na środku).
func door() -> Vector2:
	return position + Vector2(0.0, 2.6)
