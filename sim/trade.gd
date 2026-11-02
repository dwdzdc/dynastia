# SimTrade — handel jako miejsce (S16, faza M). Stragany stoją na placu targowym
# albo przy domach; za ladą stoi sprzedawca. Kupujący to ludzie z potrzebami, którzy
# wybierają stragan (cena, droga, sympatia) i targują się. Cena wychodzi między
# granicami obu stron: minimalną ceną sprzedaży sprzedającego i maksymalną ceną kupna
# kupującego (gracz ustawia swoje, AI liczy z potrzeb). Pieniądze przechodzą z sakwy
# do sakwy, towar z lady do rąk — tylko gdy obie osoby stoją przy ladzie.
# Kupiec to po prostu ród ze straganem, który skupuje taniej, a sprzedaje drożej.
class_name SimTrade
extends RefCounted


var w: SimWorld
var stalls: Dictionary = {}    # id -> SimStall
var _cfg: Dictionary

const REACH := 2.0             # jak blisko lady trzeba stać, żeby handlować


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func ref(good: String) -> float:
	return float(_cfg["ref"][good])


# Granice cen gospodarstwa dla towaru (z jakością dla krzeseł).
func sell_min(h: SimHousehold, good: String, quality: float = 0.0) -> float:
	return _limit(h, good, "sell_min") + _quality_bonus(good, quality)


func buy_max(h: SimHousehold, good: String, quality: float = 0.0) -> float:
	return _limit(h, good, "buy_max") + _quality_bonus(good, quality)


func _limit(h: SimHousehold, good: String, key: String) -> float:
	var p: Dictionary = h.prices.get(good, {})
	if p.has(key):
		return float(p[key])
	return ref(good) * float(_cfg["default_" + key])


func _quality_bonus(good: String, quality: float) -> float:
	return float(_cfg["quality_bonus"].get(good, 0.0)) * quality


func set_limit(h: SimHousehold, good: String, key: String, value: float) -> void:
	if not h.prices.has(good):
		h.prices[good] = {}
	h.prices[good][key] = maxf(0.0, value)


# --- Stragany ---

func add_stall(b: SimBuilding, stock: SimBuilding, owner: int, goods: Array) -> SimStall:
	var st := SimStall.new(b, stock, owner, goods)
	stalls[st.id] = st
	return st


func remove_stall(st: SimStall) -> void:
	stalls.erase(st.id)
	w.buildings.erase(st.building.id)


func stalls_of(hid: int) -> Array:
	return stalls.values().filter(func(s): return s.owner == hid)


func stall_of_keeper(a: SimAgent) -> SimStall:
	if stalls.has(a.workplace):
		return stalls[a.workplace]
	var p := w.person_of(a)
	var own := stalls_of(p.household_id) if p != null else []
	return own[0] if not own.is_empty() else null


# Postaw stragan przy domu (M1): kosztuje deski z własnego składu.
func build_stall(h: SimHousehold, from: SimBuilding) -> SimStall:
	var home: SimBuilding = w.buildings.get(h.home_id)
	var cost := int(_cfg["stall_cost_planks"])
	if home == null or from == null or from.amount("plank") < cost or not stalls_of(h.id).filter(func(s): return not s.temporary).is_empty():
		return null
	from.take("plank", cost)
	var off: Array = _cfg["home_stall_offset"]
	var b := SimBuilding.new("stall_h%d" % h.id, "Stragan przy domu", "stall",
		home.position + Vector2(float(off[0]), float(off[1])), w.balance["storage"]["stall"])
	w.buildings[b.id] = b
	return add_stall(b, b, h.id, _cfg["home_stall_goods"])


# Wolne miejsce na placu targowym (dla wozów kupców wędrownych).
func free_slot() -> Vector2:
	for s: Array in _cfg["slots"]:
		var at := Vector2(float(s[0]), float(s[1]))
		var taken := false
		for st: SimStall in stalls.values():
			if st.building.position.distance_to(at) < 1.0:
				taken = true
		if not taken:
			return at
	return Vector2(INF, INF)


# --- Wybór straganu ---

# Gdzie kupić: otwarty stragan z towarem, cena w granicach kupującego; liczy się cena,
# droga i sympatia do sprzedawcy. null = nigdzie.
func best_seller(buyer: SimAgent, good: String) -> SimStall:
	var bp := w.person_of(buyer)
	var bh := w.household_of(buyer)
	var best: SimStall = null
	var best_score := INF
	for st: SimStall in stalls.values():
		if not st.is_open() or not st.deals_in(good) or st.owner == bh.id or st.stock.amount(good) <= 0:
			continue
		if st.temporary and good in st.buys:
			continue   # wóz wywozi to, co skupił
		var oh: SimHousehold = w.households.get(st.owner)
		if oh == null or sell_min(oh, good) > buy_max(bh, good):
			continue
		var score := quote(st, buyer, good) + float(_cfg["price_per_distance"]) * buyer.position.distance_to(st.counter())
		var ka := w.agent_by_id(st.keeper)
		if bp != null and ka != null:
			score -= float(_cfg["price_per_bond"]) * w.bonds.value(bp.id, SimBonds.person(ka.person_id))
		if score < best_score:
			best_score = score
			best = st
	return best


# Komu sprzedać: otwarty stragan, który skupuje ten towar powyżej minimum sprzedającego.
func best_buyer(seller: SimAgent, good: String) -> SimStall:
	var sh := w.household_of(seller)
	var best: SimStall = null
	var best_score := -INF
	for st: SimStall in stalls.values():
		if not st.is_open() or not good in st.buys or st.owner == sh.id or st.stock.space(good) <= 0 or int(st.wants.get(good, 1)) <= 0:
			continue
		var oh: SimHousehold = w.households.get(st.owner)
		if oh == null or buy_max(oh, good) < sell_min(sh, good):
			continue
		var ka := w.agent_by_id(st.keeper)
		var keeper_cash := w.person_of(ka).purse if ka != null and w.person_of(ka) != null else 0.0
		if keeper_cash < sell_min(sh, good):
			continue
		var score := buy_max(oh, good) - float(_cfg["price_per_distance"]) * seller.position.distance_to(st.counter())
		if score > best_score:
			best_score = score
			best = st
	return best


# Spodziewana cena u straganu dla tego kupującego (do planowania ilości).
func quote(st: SimStall, buyer: SimAgent, good: String) -> float:
	var oh: SimHousehold = w.households.get(st.owner)
	var lo := sell_min(oh, good)
	var hi := maxf(lo, buy_max(w.household_of(buyer), good))
	return lo + (hi - lo) * _split(w.agent_by_id(st.keeper), buyer)


# Targowanie: kto lepiej się targuje (umiejętność „trade”), ten przesuwa cenę w swoją stronę.
func _split(seller: SimAgent, buyer: SimAgent) -> float:
	var ds := (seller.skill("trade") if seller != null else 0.0) - (buyer.skill("trade") if buyer != null else 0.0)
	return clampf(0.5 + float(_cfg["haggle_per_skill"]) * ds, float(_cfg["haggle_min"]), float(_cfg["haggle_max"]))


func _at_counter(st: SimStall, a: SimAgent) -> bool:
	return a != null and a.position.distance_to(st.counter()) <= REACH


func _keeper_here(st: SimStall) -> SimAgent:
	var ka := w.agent_by_id(st.keeper)
	if ka == null or not st.is_open() or ka.position.distance_to(st.building.position) > REACH * 2.0:
		return null
	return ka


# Pieniądze gospodarstwa do ręki: sakwa, do oddania w domu (S14).
static func hand_to(p: SimPerson, amount: float) -> void:
	p.purse += amount
	p.held += amount


# --- Transakcje ---

# Stragan sprzedaje kupującemu. Zwraca { qty, paid }.
func sell_to(st: SimStall, buyer: SimAgent, good: String, qty: int) -> Dictionary:
	var ka := _keeper_here(st)
	var bp := w.person_of(buyer)
	var out := { "qty": 0, "paid": 0.0 }
	if ka == null or bp == null or not _at_counter(st, buyer):
		return out
	var oh: SimHousehold = w.households.get(st.owner)
	var bh := w.household_of(buyer)
	var kp := w.person_of(ka)
	var split := _split(ka, buyer)
	while int(out["qty"]) < qty and st.stock.amount(good) > 0:
		var q := float(st.stock.chair_qualities[0]) if good == "chair" and not st.stock.chair_qualities.is_empty() else 0.0
		var lo := sell_min(oh, good, q)
		var hi := buy_max(bh, good, q)
		if lo > hi:
			break
		var price := lo + (hi - lo) * split
		if bp.purse < price:
			break
		bp.purse -= price
		hand_to(kp, price)
		st.stock.take(good, 1)
		if good == "chair" and not st.stock.chair_qualities.is_empty():
			buyer.carrying_qualities.append(st.stock.chair_qualities.pop_front())
		out["qty"] = int(out["qty"]) + 1
		out["paid"] = float(out["paid"]) + price
	bp.held = minf(bp.held, bp.purse)
	kp.held = minf(kp.held, kp.purse)
	if int(out["qty"]) > 0:
		st.last_deal = w.clock.now()
		buyer.carrying = good
		buyer.carrying_qty += int(out["qty"])
		_learn(ka, buyer)
	return out


# Stragan skupuje od sprzedającego (np. kupiec bierze deski). Zwraca { qty, paid }.
func buy_from(st: SimStall, seller: SimAgent, good: String, qty: int, qualities: Array) -> Dictionary:
	var ka := _keeper_here(st)
	var sp := w.person_of(seller)
	var out := { "qty": 0, "paid": 0.0 }
	if ka == null or sp == null or not _at_counter(st, seller):
		return out
	var oh: SimHousehold = w.households.get(st.owner)
	var sh := w.household_of(seller)
	var kp := w.person_of(ka)
	var split := _split(ka, seller)
	var limit := mini(qty, int(st.wants.get(good, qty)))
	while int(out["qty"]) < limit and st.stock.space(good) > 0:
		var n := int(out["qty"])
		var q: float = float(qualities[n]) if n < qualities.size() else 0.0
		var lo := sell_min(sh, good, q)
		var hi := buy_max(oh, good, q)
		if lo > hi:
			break
		# Tu stragan kupuje: lepszy targujący się sprzedawca ciągnie cenę w górę.
		var price := hi - (hi - lo) * split
		if kp.purse < price:
			break
		kp.purse -= price
		hand_to(sp, price)
		st.stock.add(good, 1)
		if good == "chair":
			st.stock.chair_qualities.append(q)
		out["qty"] = n + 1
		out["paid"] = float(out["paid"]) + price
	kp.held = minf(kp.held, kp.purse)
	if st.wants.has(good):
		st.wants[good] = int(st.wants[good]) - int(out["qty"])
	if int(out["qty"]) > 0:
		st.last_deal = w.clock.now()
		_learn(ka, seller)
	return out


func _learn(a: SimAgent, b: SimAgent) -> void:
	for x in [a, b]:
		x.skills["trade"] = minf(float(w.balance["skills"]["max"]), x.skill("trade") + float(_cfg["skill_per_deal"]))
