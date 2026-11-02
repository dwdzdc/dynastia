# SimTown — miasto okolicy jako agregat (S25, U1): nie ludziki, tylko liczby —
# ilu ma ludzi, co i ile dziennie wytwarza, ile zjada i zużywa, co ma w spichrzu
# i w kasie. Z tego biorą się jego braki, nadwyżki i ceny (S26). Pieniądze miasta
# zmieniają się tylko przez handel z wsią (wozy), więc obieg świata jest zamknięty
# (S22). To agregat LOD tej samej ciągłej mapy (ADR-0003), nie targ w UI.
class_name SimTown
extends RefCounted


var id: String
var name: String
var population: int
var cash: float
var stock: Dictionary = {}        # towar -> ilość
var shortage: Dictionary = {}     # towar -> ile wczoraj zabrakło (niezaspokojony popyt)

var _cfg: Dictionary
var _refs: Dictionary
var _acc: Dictionary = {}         # ułamki produkcji i zużycia


func _init(spec: Dictionary, refs: Dictionary, cfg: Dictionary) -> void:
	id = String(spec["id"])
	name = String(spec["name"])
	_cfg = cfg
	_refs = refs
	var t: Dictionary = spec["town"]
	population = int(t["population"])
	cash = float(spec["town_cash"])
	for g in t.get("start_stock", {}):
		stock[g] = int(t["start_stock"][g])
	_produce = t.get("produce", {})
	_consume = t.get("consume_per_person", {})
	mint_per_day = float(t.get("mint_per_day", 0.0))


var _produce: Dictionary
var _consume: Dictionary
var mint_per_day := 0.0           # nowe monety z kopalni i mennicy (S34): jedyne źródło monet


func amount(g: String) -> int:
	return int(stock.get(g, 0))


func add(g: String, n: int) -> void:
	stock[g] = amount(g) + n


func take(g: String, n: int) -> int:
	var k := mini(n, amount(g))
	stock[g] = amount(g) - k
	return k


func daily_need(g: String) -> float:
	return float(_consume.get(g, 0.0)) * float(population)


# Zapas, przy którym miasto czuje się spokojnie: na tyle dni zużycia.
func buffer(g: String) -> float:
	return daily_need(g) * float(_cfg["buffer_days"])


# Doba w mieście: wytwarza swoje, zużywa, co ma; braki zapamiętuje. Mennica bije
# monety (zwraca ile — do księgi świata, S34).
func new_day() -> float:
	cash += mint_per_day
	for g in _produce:
		_acc["p:" + g] = float(_acc.get("p:" + g, 0.0)) + float(_produce[g])
		var n := int(floor(float(_acc["p:" + g])))
		_acc["p:" + g] = float(_acc["p:" + g]) - n
		add(g, n)
	for g in _consume:
		_acc["c:" + g] = float(_acc.get("c:" + g, 0.0)) + daily_need(g)
		var want := int(floor(float(_acc["c:" + g])))
		_acc["c:" + g] = float(_acc["c:" + g]) - want
		shortage[g] = want - take(g, want)
	return mint_per_day


# Cena w mieście: im mniej względem zapasu, którego potrzebuje, tym drożej.
func price(g: String) -> float:
	var ref := float(_refs.get(g, 1.0))
	var buf := buffer(g)
	if buf <= 0.0:
		return ref * float(_cfg["min_mult"])
	var m := 1.0 + float(_cfg["scarcity"]) * (1.0 - float(amount(g)) / buf)
	return ref * clampf(m, float(_cfg["min_mult"]), float(_cfg["max_mult"]))


# Nadwyżka do wywiezienia: ponad zapas spokoju.
func surplus(g: String) -> int:
	return maxi(0, amount(g) - int(ceil(buffer(g))))


# Brak do przywiezienia: do zapasu spokoju.
func lack(g: String) -> int:
	return maxi(0, int(ceil(buffer(g))) - amount(g))
