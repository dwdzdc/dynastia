# SimMarket — targ jako ludzie (S9, H1): kupiec z rodu kupieckiego ma własną kasę
# (gospodarstwo roota tego rodu) i zapas w budynku targu. Skupuje tylko, gdy ma
# pieniądze i zbyt; sprzedaje tylko to, co ma. Cena zależy od zapasu względem celu.
# Na razie wymiana z „miastem za mapą” jest dobowym zaworem (import/eksport po cenach
# z danych); kupcy wędrowni (H3) robią to fizycznie.
class_name SimMarket
extends RefCounted


var w: SimWorld
var building: SimBuilding
var _cfg: Dictionary
var _goods: Dictionary


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg
	_goods = cfg["goods"]
	building = w.building("market")
	for g in cfg["storage"]:
		building.capacity[g] = int(cfg["storage"][g])
		building.stock[g] = 0
	for g in cfg["start_stock"]:
		building.add(g, int(cfg["start_stock"][g]))


func merchant() -> SimPerson:
	var l := w.lineage_by_role("merchant")
	return w.family.persons.get(l.root_id) if l != null else null


# Kasa kupca: gospodarstwo roota rodu kupieckiego (nikt nie ma pieniędzy z powietrza).
func till() -> SimHousehold:
	var m := merchant()
	return w.households.get(m.household_id) if m != null else null


func trades(good: String) -> bool:
	return _goods.has(good)


# Mnożnik ceny z zapasu: mało towaru — drożej, dużo — taniej.
func _mult(good: String) -> float:
	var t := float(_goods[good]["target"])
	var s := float(building.amount(good))
	return clampf(1.0 + float(_cfg["elasticity"]) * (1.0 - s / t), float(_cfg["min_mult"]), float(_cfg["max_mult"]))


# Cena, po której kupiec sprzedaje.
func sell_price(good: String) -> float:
	return float(_goods[good]["base"]) * _mult(good)


# Cena, którą kupiec płaci (dla krzesła z jakością i reputacją sprzedawcy).
func buy_price(good: String, quality: float = 0.0, reputation: float = 0.0) -> float:
	var g: Dictionary = _goods[good]
	var base := float(g["base"])
	if g.has("quality_mult"):
		base += float(g["quality_mult"]) * quality
		base *= 1.0 + float(_cfg["reputation_price_mult"]) * reputation
	return base * _mult(good) * float(_cfg["buy_ratio"])


# Ile sztuk kupiec jeszcze weźmie: miejsce w składzie i sensowny zapas (zbyt).
func wants(good: String) -> int:
	if not trades(good):
		return 0
	var cap := int(float(_goods[good]["target"]) * float(_cfg["max_stock_ratio"]))
	return maxi(0, mini(building.space(good), cap - building.amount(good)))


# Sprzedawca oddaje towar kupcowi. Zwraca { qty, paid }; kupiec płaci z własnej kasy.
func buy_from(seller: SimHousehold, good: String, qty: int, qualities: Array) -> Dictionary:
	var t := till()
	var n := 0
	var paid := 0.0
	while n < qty and n < wants(good) and t != null:
		var q: float = float(qualities[n]) if n < qualities.size() else 0.0
		var price := buy_price(good, q, seller.reputation)
		if t.cash < price:
			break
		t.pay(price)
		seller.earn(price)
		paid += price
		building.add(good, 1)
		if good == "chair":
			building.chair_qualities.append(q)
			seller.reputation = maxf(seller.reputation + float(_cfg["reputation_per_chair"]) * (q - float(_cfg["reputation_neutral_quality"])) * 2.0,
				float(_cfg["reputation_min"]))
		n += 1
	return { "qty": n, "paid": paid }


# Kupujący bierze towar z zapasu kupca. Zwraca liczbę kupionych sztuk.
func sell_to(buyer: SimHousehold, good: String, qty: int) -> int:
	var n := 0
	var t := till()
	while n < qty and building.amount(good) > 0:
		var price := sell_price(good)
		if buyer.cash < price:
			break
		buyer.pay(price)
		if t != null:
			t.earn(price)
		building.take(good, 1)
		n += 1
	return n


# Zawór dobowy: braki dowiezione z miasta, nadwyżki wywiezione (płaci/dostaje kupiec).
func new_day() -> void:
	var t := till()
	if t == null:
		return
	for good in _goods:
		var g: Dictionary = _goods[good]
		var target := float(g["target"])
		var have := building.amount(good)
		if float(g["import_price"]) > 0.0 and have < target * float(_cfg["import_below"]):
			var unit := float(g["base"]) * float(g["import_price"])
			var n := mini(int(target) - have, int(floor(t.cash / unit)))
			if n > 0:
				t.pay(n * unit)
				building.add(good, n)
		elif float(g["export_price"]) > 0.0 and have > target * float(_cfg["export_above"]):
			var n := have - int(target)
			t.earn(n * float(g["base"]) * float(g["export_price"]))
			building.take(good, n)
			if good == "chair":
				building.chair_qualities = building.chair_qualities.slice(n)
