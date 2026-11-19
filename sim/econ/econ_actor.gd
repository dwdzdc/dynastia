# EconActor — człowiek z kapitałem. Ma kasę i 0..n firm; to, czym się zajmuje,
# jest wymienne (sprzedaje, zamyka, kupuje, zakłada). Umiera, a firmy dziedziczy
# spadkobierca o tym samym nazwisku (ród = family_id).
class_name EconActor
extends RefCounted


var id: int
var first: String
var last: String
var female: bool
var family_id: int
var city_id: int
var cash: float = 0.0
var income_today: float = 0.0     # dywidendy dziś
var income_ema: float = 0.0
var businesses: Array[int] = []
var risk: float = 0.5
var born_day: int = 0
var death_day: int = 0
var alive: bool = true
var parent_id: int = -1
var idle_since: int = -1          # od kiedy nie ma żadnej firmy


func _init(id_: int) -> void:
	id = id_


func full_name() -> String:
	return "%s %s" % [first, last]
