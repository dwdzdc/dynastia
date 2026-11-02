# SimBuilding — budynek osady: pozycja, typ, zapasy towarów i ich pojemność.
# Część warstwy logistyki (ADR-0001): nic nie wie o rodzinach ani więziach; właściciel
# to tylko id, a rozliczenia robi SimWorld.
class_name SimBuilding
extends RefCounted


var id: String
var name: String
var type: String
var position: Vector2
var stock: Dictionary = {}       # good -> int
var capacity: Dictionary = {}    # good -> int (brak klucza = brak miejsca na ten towar)
var chair_qualities: Array = []  # jakość każdego krzesła w zapasie (FIFO)
# Aktywo (S7): właściciel to osoba („person”), ród („lineage”) albo nikt spoza okolicy („none”).
var owner_kind: String = "none"
var owner_id: int = -1
var rent_per_day: float = 0.0
var condition: float = 1.0       # stan domu 0..1 (R3): niszczeje, remontuje się deskami
var last_output_day: int = -999   # warsztat: kiedy ostatnio coś wyprodukował (X8)
# Skrzynie (S14): id gospodarstwa -> pieniądze w jego skrzyni. Kilka gospodarstw może
# mieszkać pod jednym dachem (kąt u sąsiadów), każde ma swoją skrzynię.
var chests: Dictionary = {}

const DOOR_FRONT := 2.6    # drzwi budynku przed jego środkiem
const STALL_FRONT := 1.4   # przed ladą straganu


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


func coins() -> float:
	var s := 0.0
	for hid in chests:
		s += float(chests[hid])
	return s


# Drzwi: punkt przed budynkiem, do którego chodzą ludzie (budynek stoi na środku).
# Przy straganie to miejsce przed ladą.
func door() -> Vector2:
	return position + Vector2(0.0, STALL_FRONT if type == "stall" else DOOR_FRONT)
