# EconCity — miasto w sieci świata (docs/design/world-economy.md).
# Ludność liczona zbiorczo: jedna wspólna kasa gospodarstw, płaca, złoża i rynek
# (EconMarket na każdy towar). Imienne osoby pojawią się dopiero tam, gdzie gracz.
class_name EconCity
extends RefCounted


var id: int
var name: String
var pos: Vector2
var population: float
var cash: float = 0.0             # wspólne oszczędności gospodarstw domowych
var wage: float = 0.0             # dniówka w tym mieście
var resources: Dictionary = {}    # zasób -> bogactwo złoża (0 = wyczerpane)
var markets: Dictionary = {}      # towar -> EconMarket
var routes: Array[int] = []       # id dróg wychodzących

# Stan liczony co dobę (do decyzji, kroniki i podglądu).
var labor_force: float = 0.0
var employed: float = 0.0
var public_workers: float = 0.0   # budżetówka opłacana przez państwo (EconState)
var income_today: float = 0.0
var income_ema: float = 0.0
var satisfaction: float = 1.0     # EMA zaspokojenia potrzeb ważonych priorytetem (0..1)
var harvest_mult: float = 1.0     # mnożnik plonów w tym sezonie (nieurodzaj / urodzaj)
var history: Dictionary = {}      # "population"/"unemployment"/"satisfaction" -> Array[float]


func _init(id_: int, name_: String, pos_: Vector2, population_: float) -> void:
	id = id_
	name = name_
	pos = pos_
	population = population_


func unemployment() -> float:
	if labor_force <= 0.0:
		return 0.0
	return clampf(1.0 - employed / labor_force, 0.0, 1.0)


func free_workers() -> float:
	return maxf(0.0, labor_force - employed)


func prosperity() -> float:
	return clampf(satisfaction * 0.6 + (1.0 - unemployment()) * 0.4, 0.0, 1.0)


func market(good: String) -> EconMarket:
	return markets.get(good) as EconMarket
