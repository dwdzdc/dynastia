# SimJobs — planowanie i wykonanie pracy agentów: harmonogram dnia, przydziały
# (drwal, tracz, stolarz, nosiciel, dniówka), obowiązki domowe i logistyka towarów.
# Każda ścieżka planu kończy się krokiem z widocznym powodem (idle_reason) — żaden
# agent nie stoi bez wyjaśnienia (intro §6).
class_name SimJobs
extends RefCounted


const JOB_LABELS := {
	"none": "bez przydziału",
	"woodcutter": "drwal",
	"sawyer": "tracz",
	"carpenter": "stolarz",
	"carrier": "nosiciel",
	"laborer": "dniówka w dworze",
	"forager": "zbieracz (las)",
	"thief": "złodziej (targ)",
}

var w: SimWorld
var _cfg: Dictionary


func _init(world: SimWorld) -> void:
	w = world
	_cfg = world.balance["jobs"]


# --- Harmonogram ---

func block_at(tod: float) -> String:
	var s: Dictionary = w.balance["schedule"]
	if tod >= float(s["sleep"]) or tod < float(s["wake"]):
		return "sleep"
	if tod >= float(s["work_start"]) and tod < float(s["work_end"]):
		return "work"
	if tod >= float(s["dinner_start"]) and tod < float(s["dinner_end"]):
		return "dinner"
	return "free"


# Jaki rodzaj planu agent powinien teraz wykonywać.
func desired_kind(a: SimAgent) -> String:
	if a.controlled:
		return "manual"
	if a.disabled():
		return "sick"
	var food_low := float(w.balance["needs"]["food"]["low"])
	if a.needs["food"] < food_low:
		return "eat"
	var block := block_at(w.clock.time_of_day())
	if block == "sleep" or a.needs["sleep"] < float(w.balance["needs"]["sleep"]["low"]):
		return "sleep"
	if block == "dinner" and not w.is_independent(a):
		return "dinner"
	if a.is_child:
		return "child"
	if block == "work" and a.can_work() and a.job != "none":
		return "work"
	return "chore"


# Nowy plan z autopilota. Kończy też sterowanie ręczne (np. po wypadku, zmianie pracy).
func replan(a: SimAgent) -> void:
	a.controlled = false
	release(a)
	a.steps.clear()
	a.alert = false
	a.hungry_no_food = false
	var kind := desired_kind(a)
	if w.is_independent(a):
		a.plan_kind = kind
		_plan_independent(a, kind)
		return
	# Przed wyjściem z domu zjedz, jeśli już trochę burczy w brzuchu — inaczej agent
	# zawraca w pół drogi.
	var low := float(w.balance["needs"]["food"]["low"])
	if kind in ["work", "chore", "child"] and a.needs["food"] < low * 1.6 and w.home().amount("food") > 0:
		kind = "eat"
	a.plan_kind = kind
	match kind:
		"sick":
			_go_inside(a, w.home(), "rest", 3.0,
				"ranny — leży w chacie" if a.injured_days > 0.0 else "chory — leży w chacie")
		"eat":
			_plan_eat(a)
		"sleep":
			_go_inside(a, w.home(), "sleep", 4.0, "śpi")
		"child":
			_plan_child(a)
		"dinner":
			_plan_dinner(a)
		"work":
			_plan_work(a)
		"chore":
			if not _plan_chore(a):
				_go_inside(a, w.home(), "rest", 3.0, _rest_reason(a))


func release(a: SimAgent) -> void:
	for c in a.claims:
		var parts := String(c).split(":")
		if parts[0] == "tree":
			var t: SimTree = w.tree_by_id(int(parts[1]))
			if t != null and t.reserved_by == a.id:
				t.reserved_by = -1
		elif parts[0] == "chore":
			if w.chore_claims.get(parts[1], -1) == a.id:
				w.chore_claims.erase(parts[1])
	a.claims.clear()


func _rest_reason(a: SimAgent) -> String:
	if a.is_child:
		return "bawi się w chacie"
	if not a.can_work():
		return "odpoczywa (nie może pracować)"
	if block_at(w.clock.time_of_day()) == "work":
		return "wolne — bez przydziału pracy"
	return "odpoczywa wieczorem"


# --- Kroki ---

func _walk(a: SimAgent, to: Vector2, why: String) -> void:
	a.steps.append({ "t": "walk", "to": to, "why": why })


func _act(a: SimAgent, act: String, secs: float, why: String, inside: String = "", alert := false) -> void:
	a.steps.append({ "t": "act", "act": act, "left": secs, "why": why, "inside": inside, "alert": alert })


func _do(a: SimAgent, fn: String, arg: Variant = null) -> void:
	a.steps.append({ "t": "do", "fn": fn, "arg": arg })


func _wait(a: SimAgent, why: String, act := "wait", alert := false) -> void:
	_act(a, act, float(_cfg["wait_seconds"]), why, "", alert)


func _go_inside(a: SimAgent, b: SimBuilding, act: String, secs: float, why: String) -> void:
	_walk(a, b.door(), "idzie do: %s" % b.name)
	_act(a, act, secs, why, b.id)


# --- Plany ---

# Minimalny autopilot osoby spoza rodu (C4): mieszka u siebie, chodzi na dniówkę,
# zarobek trzyma w sakiewce, a jedzenie kupuje i zjada na targu.
func _plan_independent(a: SimAgent, kind: String) -> void:
	var home: SimBuilding = w.home_of(a)
	var p := w.person_of(a)
	match kind:
		"sick":
			_go_inside(a, home, "rest", 3.0, "chory — leży u siebie")
		"sleep":
			_go_inside(a, home, "sleep", 4.0, "śpi u siebie")
		"eat":
			var price := float(w.balance["economy"]["meal_away_price"])
			if p.purse >= price:
				var market: SimBuilding = w.building("market")
				_walk(a, market.door(), "idzie coś zjeść na targu")
				_do(a, "meal_away", price)
				_act(a, "eat", 1.5, "je na targu za swoje", market.id)
			elif a.can_work():
				_plan_forage(a)
				_do(a, "eat_carried")
			else:
				a.hungry_no_food = true
				_go_inside(a, home, "wait", float(_cfg["wait_seconds"]), "GŁODNY — bez grosza")
		"work":
			_plan_work(a)
		_:
			_go_inside(a, home, "rest", 3.0, "odpoczywa u siebie")

func _plan_eat(a: SimAgent) -> void:
	var home: SimBuilding = w.home()
	if home.amount("food") > 0:
		_walk(a, home.door(), "głodny — idzie coś zjeść")
		_do(a, "eat")
		_act(a, "eat", 1.5, "je posiłek", home.id)
		return
	# Pusta spiżarnia: dorosły sam kupi jedzenie, jeśli są pieniądze, a jak nie —
	# idzie do lasu szukać jagód i grzybów.
	if a.can_work() and _food_trip(a, true):
		return
	if a.can_work() and not w.chore_claims.has("food"):
		_plan_forage(a)
		return
	a.hungry_no_food = true
	var why := "GŁODNY — pusta spiżarnia"
	if not w.household.can_afford(w.household.food_price()):
		why += " i brak pieniędzy"
	elif w.chore_claims.has("food"):
		why += " (ktoś już idzie po jedzenie)"
	_walk(a, home.door(), why)
	_act(a, "wait", float(_cfg["wait_seconds"]), why, home.id, true)


# Kolacja: ród schodzi się do chaty i siedzi razem przy stole do końca bloku (B2).
# Je tylko ten, kto jest choć trochę głodny; przy pustej spiżarni siedzą przy pustym stole.
func _plan_dinner(a: SimAgent) -> void:
	var home: SimBuilding = w.home()
	var left := (float(w.balance["schedule"]["dinner_end"]) - w.clock.time_of_day()) * w.clock.day_seconds
	_walk(a, home.door(), "wraca do chaty na kolację")
	_do(a, "dinner")
	var why := "je kolację z rodziną"
	if home.amount("food") <= 0:
		why = "siedzi z rodziną przy pustym stole"
	_act(a, "dine", maxf(left, float(_cfg["wait_seconds"])), why, home.id)


func _plan_child(a: SimAgent) -> void:
	var home: SimBuilding = w.home()
	var k := w.rng.next_float(0.0, TAU)
	var r := w.rng.next_float(1.5, 4.5)
	var spot: Vector2 = home.door() + Vector2(cos(k), sin(k) * 0.6 + 0.8) * r
	_walk(a, spot, "bawi się przy chacie")
	_act(a, "play", w.rng.next_float(2.0, 4.0), "bawi się przy chacie")


func _plan_work(a: SimAgent) -> void:
	match a.job:
		"woodcutter":
			_plan_woodcutter(a)
		"sawyer":
			_plan_producer(a, w.building("sawmill"), "saw")
		"carpenter":
			_plan_producer(a, w.building("workshop"), "craft")
		"carrier":
			if not _plan_carrier(a):
				_walk(a, w.home().door() + Vector2(1.5, 1.0), "nosiciel — nic do noszenia")
				_wait(a, "nosiciel — nic do noszenia")
		"laborer":
			_plan_laborer(a)
		"forager":
			_plan_forage(a)
		"thief":
			_plan_thief(a)
		_:
			_go_inside(a, w.home(), "rest", 3.0, _rest_reason(a))


func _plan_woodcutter(a: SimAgent) -> void:
	var mill: SimBuilding = w.building("sawmill")
	var cap := int(w.balance["carry"]["log"])
	if a.carrying == "log" and a.carrying_qty < cap and mill.space("log") > a.carrying_qty:
		var near: SimTree = w.nearest_tree(a.position)
		if near != null and near.position.distance_to(a.position) < 6.0:
			_chop(a, near, mill)
			return
	if a.carrying == "log":
		if mill.space("log") <= 0:
			_walk(a, mill.door(), "niesie kłodę do tartaku")
			_wait(a, "skład kłód w tartaku pełny — potrzebny tracz", "wait", true)
			return
		_walk(a, mill.door() + Vector2(-1.5, 0.0), "niesie kłodę do tartaku")
		_do(a, "deposit", "sawmill")
		return
	if a.carrying != "":
		_plan_deliver_carried(a)
		return
	if mill.space("log") <= 0:
		_walk(a, mill.door() + Vector2(-2.0, 1.0), "skład kłód pełny")
		_wait(a, "skład kłód w tartaku pełny — potrzebny tracz", "wait", true)
		return
	var t: SimTree = w.nearest_tree(mill.position)
	if t == null:
		_walk(a, mill.door() + Vector2(-3.0, 0.0), "brak drzew")
		_wait(a, "brak drzew do ścięcia — las odrasta", "wait", true)
		return
	_chop(a, t, mill)


func _chop(a: SimAgent, t: SimTree, mill: SimBuilding) -> void:
	t.reserved_by = a.id
	a.claims.append("tree:%d" % t.id)
	var approach := t.position + (mill.position - t.position).normalized() * 0.9
	_walk(a, approach, "idzie do drzewa")
	_act(a, "chop", _dur(a, "chop", float(_cfg["chop_seconds"])), "rąbie drzewo")
	_do(a, "chop_done", t.id)


func _plan_thief(a: SimAgent) -> void:
	if a.carrying != "":
		_plan_deliver_carried(a)
		return
	var market: SimBuilding = w.building("market")
	var spot := market.door() + Vector2(w.rng.next_float(-4.0, 4.0), w.rng.next_float(-0.5, 1.5))
	var c: Dictionary = w.balance["crime"]
	_walk(a, spot, "idzie na targ (podejrzanie)")
	_act(a, "steal", _dur(a, "steal", float(c["steal_seconds"])), "kręci się przy straganach")
	_do(a, "steal_done")


func _plan_forage(a: SimAgent) -> void:
	var cap := int(_cfg["forage_carry"])
	if a.carrying != "" and (a.carrying != "food" or a.carrying_qty >= cap):
		_plan_deliver_carried(a)
		return
	var f: Dictionary = w.map["forest"]
	var spot := Vector2(float(f["x"]) + w.rng.next_float(0.6, 1.0) * float(f["w"]), float(f["y"]) + w.rng.next_float(0.2, 0.9) * float(f["h"]))
	var season := w.clock.current_season()
	var why := "zbiera jagody i grzyby"
	if season == "winter":
		why = "szuka czegokolwiek do jedzenia (zima — las prawie pusty)"
	_walk(a, spot, "idzie do lasu po jedzenie")
	_act(a, "forage", _dur(a, "forage", float(_cfg["forage_seconds"])), why)
	_do(a, "forage_done")


func _plan_producer(a: SimAgent, b: SimBuilding, act: String) -> void:
	if a.carrying != "" and a.carrying != "plank":
		_plan_deliver_carried(a)
		return
	var spot := b.door() + (Vector2(1.6, 0.4) if act == "saw" else Vector2(-1.6, 0.4))
	var input := "log" if act == "saw" else "plank"
	var output := "plank" if act == "saw" else "chair"
	var need := 1 if act == "saw" else int(_cfg["craft_planks"])
	var out_n := int(_cfg["saw_planks_per_log"]) if act == "saw" else 1
	# Stolarz, który sam niesie deski (zadanie z wieczora), najpierw je odkłada.
	if a.carrying == "plank":
		_walk(a, spot, "niesie deski do warsztatu")
		_do(a, "deposit", b.id)
		return
	if b.amount(input) < need:
		_walk(a, spot, "idzie do warsztatu")
		var who := "drwal" if act == "saw" else "nosiciel"
		var what := "kłody" if act == "saw" else "deski"
		_wait(a, "czeka na %s — potrzebny %s" % [what, who], "wait", true)
		return
	if b.space(output) < out_n:
		_walk(a, spot, "idzie do warsztatu")
		var what2 := "desek" if act == "saw" else "krzeseł"
		_wait(a, "skład %s pełny — potrzebny nosiciel" % what2, "wait", true)
		return
	var base := float(_cfg["saw_seconds"]) if act == "saw" else float(_cfg["craft_seconds"])
	_walk(a, spot, "idzie do warsztatu")
	_act(a, act, _dur(a, act, base), "tnie kłody na deski" if act == "saw" else "robi krzesło")
	_do(a, "produce", { "b": b.id, "act": act })


func _plan_laborer(a: SimAgent) -> void:
	if a.carrying != "":
		_plan_deliver_carried(a)
		return
	var manor: SimBuilding = w.building("manor")
	var s: Dictionary = w.balance["schedule"]
	var left := (float(s["work_end"]) - w.clock.time_of_day()) * w.clock.day_seconds
	_walk(a, manor.door(), "idzie na dniówkę do dworu")
	_act(a, "labor", maxf(left, 1.0), "pracuje na dniówce w dworze", manor.id)


# Obowiązki domowe (każdy dorosły po pracy i bez przydziału).
func _plan_chore(a: SimAgent) -> bool:
	if not a.can_work():
		return false
	if a.carrying != "":
		_plan_deliver_carried(a)
		return true
	if _food_trip(a, false):
		return true
	if _firewood_trip(a):
		return true
	# Bieda: spiżarnia pustoszeje, a nie ma za co kupić — las jest za darmo.
	var hh = w.household
	if w.home().amount("food") < hh.target_food / 2 and hh.cash < hh.food_price() * 4.0 \
			and w.clock.current_season() != "winter":
		_plan_forage(a)
		return true
	return false


func _food_trip(a: SimAgent, urgent: bool) -> bool:
	var hh = w.household
	var home: SimBuilding = w.home()
	var want: int = hh.target_food - home.amount("food")
	if urgent:
		want = maxi(want, 1)
	if want <= 0 or w.chore_claims.has("food"):
		return false
	var cap := int(w.balance["carry"]["food"])
	var afford := int(floor(hh.cash / hh.food_price()))
	var qty := mini(mini(want, cap), mini(afford, home.space("food")))
	if qty <= 0:
		return false
	w.chore_claims["food"] = a.id
	a.claims.append("chore:food")
	var market: SimBuilding = w.building("market")
	_walk(a, market.door(), "idzie na targ kupić jedzenie")
	_do(a, "buy_food", qty)
	_walk(a, home.door(), "niesie jedzenie do chaty")
	_do(a, "deposit", home.id)
	return true


func _firewood_trip(a: SimAgent) -> bool:
	var home: SimBuilding = w.home()
	var mill: SimBuilding = w.building("sawmill")
	if home.amount("log") >= w.household.target_firewood or home.space("log") <= 0:
		return false
	if w.chore_claims.has("firewood"):
		return false
	var hh = w.household
	if mill.amount("log") <= 0:
		# Bez własnego drewna opał trzeba kupić na targu.
		if not hh.can_afford(hh.firewood_price() * 2.0):
			return false
		w.chore_claims["firewood"] = a.id
		a.claims.append("chore:firewood")
		_walk(a, w.building("market").door(), "idzie kupić opał na targu")
		_do(a, "buy_firewood", 2)
		_walk(a, home.door(), "niesie opał do chaty")
		_do(a, "deposit", home.id)
		return true
	w.chore_claims["firewood"] = a.id
	a.claims.append("chore:firewood")
	_walk(a, mill.door() + Vector2(-1.5, 0.0), "idzie po opał do tartaku")
	_do(a, "pickup", { "b": "sawmill", "good": "log", "qty": mini(2, mill.amount("log")) })
	_walk(a, home.door(), "niesie opał do chaty")
	_do(a, "deposit", home.id)
	return true


func _carpenter_present() -> bool:
	for a in w.agents:
		if a.is_active() and a.job == "carpenter" and a.can_work():
			return true
	return false


func _plan_carrier(a: SimAgent) -> bool:
	if a.carrying != "":
		_plan_deliver_carried(a)
		return true
	if _food_trip(a, false):
		return true
	if _firewood_trip(a):
		return true
	var mill: SimBuilding = w.building("sawmill")
	var shop: SimBuilding = w.building("workshop")
	var market: SimBuilding = w.building("market")
	if shop.amount("chair") > 0:
		_pickup_and_deliver(a, shop, "chair", market, "niesie krzesła na targ")
		return true
	if _carpenter_present() and shop.space("plank") > 0 and mill.amount("plank") > 0:
		_pickup_and_deliver(a, mill, "plank", shop, "niesie deski do stolarni", shop.space("plank"))
		return true
	if w.household.sell_planks and mill.amount("plank") > 0:
		_pickup_and_deliver(a, mill, "plank", market, "niesie deski na targ")
		return true
	return false


func _pickup_and_deliver(a: SimAgent, from: SimBuilding, good: String, to: SimBuilding, why: String, limit := 999) -> void:
	var qty := mini(int(w.balance["carry"][good]), limit)
	_walk(a, from.door(), "idzie po towar: %s" % from.name)
	_do(a, "pickup", { "b": from.id, "good": good, "qty": qty })
	_walk(a, to.door(), why)
	_do(a, "deposit", to.id)


# Dokąd odnieść to, co agent ma w rękach (np. po przerwaniu planu).
func _plan_deliver_carried(a: SimAgent) -> void:
	var dest := ""
	match a.carrying:
		"food":
			dest = "home"
		"log":
			dest = "sawmill" if w.home().space("log") <= 0 else "home"
			if a.job == "woodcutter":
				dest = "sawmill"
		"plank":
			dest = "workshop" if (_carpenter_present() and w.building("workshop").space("plank") > 0) else "market"
		"chair":
			dest = "market"
	var b: SimBuilding = w.building(dest)
	_walk(a, b.door(), "odnosi: %s → %s" % [w.good_label(a.carrying), b.name])
	_do(a, "deposit", dest)


# Czas czynności z umiejętnością, wiekiem, traitami, zdrowiem i światłem.
func _dur(a: SimAgent, act: String, base: float) -> float:
	return base / efficiency(a, act)


func efficiency(a: SimAgent, act: String) -> float:
	var sk: Dictionary = w.balance["skills"]
	var e := float(sk["eff_base"]) + float(sk["eff_per_level"]) * a.skill(act)
	e *= a.age_eff * a.trait_mult(act)
	if a.health < 50.0:
		e *= 0.5 + a.health / 100.0
	if w.clock.light_factor() < 0.5:
		e *= float(_cfg["dark_work_mult"])
	return maxf(e, 0.15)


# --- Efekty natychmiastowe ("do") ---

func apply(a: SimAgent, step: Dictionary) -> bool:
	match String(step["fn"]):
		"eat":
			return _fx_eat(a)
		"dinner":
			_fx_dinner(a)
			return true
		"meal_away":
			return _fx_meal_away(a, float(step["arg"]))
		"eat_carried":
			if a.carrying == "food" and a.carrying_qty > 0:
				a.carrying_qty -= 1
				a.needs["food"] = minf(100.0, a.needs["food"] + float(w.balance["needs"]["food"]["meal"]))
				if a.carrying_qty <= 0:
					a.clear_carry()
			return true
		"deposit":
			return _fx_deposit(a, String(step["arg"]))
		"pickup":
			return _fx_pickup(a, step["arg"])
		"buy_food":
			return _fx_buy_food(a, int(step["arg"]))
		"buy_firewood":
			return _fx_buy_firewood(a, int(step["arg"]))
		"chop_done":
			return _fx_chop_done(a, int(step["arg"]))
		"produce":
			return _fx_produce(a, step["arg"])
		"forage_done":
			return _fx_forage(a)
		"steal_done":
			return _fx_steal(a)
	return false


func _fx_eat(a: SimAgent) -> bool:
	var home: SimBuilding = w.home()
	if home.take("food", 1) <= 0:
		return false
	a.needs["food"] = minf(100.0, a.needs["food"] + float(w.balance["needs"]["food"]["meal"]))
	return true


func _fx_meal_away(a: SimAgent, price: float) -> bool:
	var p := w.person_of(a)
	if p == null or p.purse < price:
		return false
	p.purse -= price
	a.needs["food"] = minf(100.0, a.needs["food"] + float(w.balance["needs"]["food"]["meal"]))
	return true


func _fx_dinner(a: SimAgent) -> void:
	if a.dinner_day == w.clock.day_index():
		return
	a.dinner_day = w.clock.day_index()
	if a.needs["food"] < float(w.balance["needs"]["food"]["dinner_eat_below"]):
		_fx_eat(a)


func _fx_deposit(a: SimAgent, bid: String) -> bool:
	if a.carrying == "":
		return true
	var b: SimBuilding = w.building(bid)
	if b.type == "market":
		var got: float = w.household.sell(a.carrying, a.carrying_qty, a.carrying_qualities)
		w.events.float_text(b.door(), "+%d zł" % int(round(got)), "money")
		w.stats["sold_" + a.carrying] = int(w.stats.get("sold_" + a.carrying, 0)) + a.carrying_qty
		a.clear_carry()
		return true
	var n := mini(a.carrying_qty, b.space(a.carrying))
	if n <= 0:
		return false
	b.add(a.carrying, n)
	if a.carrying == "chair":
		for i in n:
			b.chair_qualities.append(a.carrying_qualities.pop_front())
	a.carrying_qty -= n
	if a.carrying_qty <= 0:
		a.clear_carry()
	return true


func _fx_pickup(a: SimAgent, arg: Dictionary) -> bool:
	var b: SimBuilding = w.building(String(arg["b"]))
	var good := String(arg["good"])
	var n := b.take(good, int(arg["qty"]))
	if n <= 0:
		return false
	a.carrying = good
	a.carrying_qty = n
	a.carrying_qualities = []
	if good == "chair":
		for i in n:
			a.carrying_qualities.append(b.chair_qualities.pop_front())
	return true


func _fx_buy_food(a: SimAgent, qty: int) -> bool:
	var hh = w.household
	var n := mini(qty, int(floor(hh.cash / hh.food_price())))
	if n <= 0:
		return false
	hh.pay(n * hh.food_price())
	w.events.float_text(w.building("market").door(), "-%d zł" % int(round(n * hh.food_price())), "cost")
	a.carrying = "food"
	a.carrying_qty = n
	return true


func _fx_buy_firewood(a: SimAgent, qty: int) -> bool:
	var hh = w.household
	var n := mini(qty, int(floor(hh.cash / hh.firewood_price())))
	if n <= 0:
		return false
	hh.pay(n * hh.firewood_price())
	w.events.float_text(w.building("market").door(), "-%d zł" % int(round(n * hh.firewood_price())), "cost")
	a.carrying = "log"
	a.carrying_qty = n
	return true


func _fx_chop_done(a: SimAgent, tree_id: int) -> bool:
	var t: SimTree = w.tree_by_id(tree_id)
	if t == null or t.wood <= 0:
		return false
	t.wood -= 1
	t.reserved_by = -1
	a.claims.erase("tree:%d" % tree_id)
	if t.wood <= 0:
		t.regrow_left = float(w.balance["trees"]["regrow_days"]) * w.clock.day_seconds
	a.carrying = "log"
	a.carrying_qty += 1
	_gain_skill(a, "chop", float(_cfg["chop_seconds"]))
	w.roll_accident(a, "chop")
	return true


func _fx_steal(a: SimAgent) -> bool:
	var c: Dictionary = w.balance["crime"]
	var p := float(c["caught_base"]) * maxf(0.3, 1.0 - float(c["caught_skill_reduction"]) * a.skill("steal"))
	if w.clock.light_factor() < 0.5:
		p *= float(c["caught_dark_mult"])
	_gain_skill(a, "steal", float(c["steal_seconds"]))
	if w.rng.chance(p):
		w.arrest(a)
		return true
	if w.rng.chance(float(c["loot_food_chance"])):
		var fr: Array = c["loot_food"]
		a.carrying = "food"
		a.carrying_qty = w.rng.next_int(int(fr[0]), int(fr[1]))
		w.events.float_text(a.position, "+%d jedzenia (kradzione)" % a.carrying_qty, "info")
	else:
		var cr: Array = c["loot_coins"]
		var got := w.rng.next_int(int(cr[0]), int(cr[1]))
		w.earn_for(a, float(got))
		w.events.float_text(a.position, "+%d zł (kradzione)" % got, "money")
	w.stats["thefts"] = int(w.stats.get("thefts", 0)) + 1
	return true


func _fx_forage(a: SimAgent) -> bool:
	var y := float(_cfg["forage_yield"].get(w.clock.current_season(), 0.5))
	var n := int(floor(y)) + (1 if w.rng.chance(y - floor(y)) else 0)
	if n > 0:
		if a.carrying != "food":
			a.clear_carry()
			a.carrying = "food"
		a.carrying_qty += n
		w.events.float_text(a.position, "+%d jedzenia" % n, "info")
	_gain_skill(a, "forage", float(_cfg["forage_seconds"]))
	return true


func _fx_produce(a: SimAgent, arg: Dictionary) -> bool:
	var b: SimBuilding = w.building(String(arg["b"]))
	var act := String(arg["act"])
	if act == "saw":
		if b.take("log", 1) <= 0:
			return false
		b.add("plank", int(_cfg["saw_planks_per_log"]))
		_gain_skill(a, "saw", float(_cfg["saw_seconds"]))
	else:
		if b.amount("plank") < int(_cfg["craft_planks"]):
			return false
		b.take("plank", int(_cfg["craft_planks"]))
		var q := clampf(0.15 + 0.07 * a.skill("craft") + a.quality_bonus + w.rng.next_float(-0.1, 0.15), 0.05, 1.0)
		b.add("chair", 1)
		b.chair_qualities.append(q)
		w.events.float_text(b.door(), "krzesło (%s)" % quality_label(q), "info")
		_gain_skill(a, "craft", float(_cfg["craft_seconds"]))
	w.roll_accident(a, act)
	return true


func _gain_skill(a: SimAgent, s: String, secs: float) -> void:
	var sk: Dictionary = w.balance["skills"]
	var cur := a.skill(s)
	# Im wyżej, tym wolniej.
	var gain := float(sk["xp_per_work_second"]) * secs * (1.0 - cur / (float(sk["max"]) + 1.0))
	a.skills[s] = minf(float(sk["max"]), cur + gain)


static func quality_label(q: float) -> String:
	if q < 0.3:
		return "liche"
	if q < 0.5:
		return "zwykłe"
	if q < 0.7:
		return "dobre"
	return "mistrzowskie"
