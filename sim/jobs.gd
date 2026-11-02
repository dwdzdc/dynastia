# SimJobs — planowanie i wykonanie pracy agentów: harmonogram dnia, przydziały
# (drwal, tracz, stolarz, tragarz, dniówka), obowiązki domowe i logistyka towarów.
# Każda ścieżka planu kończy się krokiem z widocznym powodem (idle_reason) — żaden
# agent nie stoi bez wyjaśnienia (intro §6).
class_name SimJobs
extends RefCounted


const JOB_LABELS := {
	"none": "bez przydziału",
	"woodcutter": "drwal",
	"sawyer": "tracz",
	"carpenter": "stolarz",
	"carrier": "tragarz",
	"laborer": "robotnik w polu",
	"forager": "zbieracz (las)",
	"overseer": "nadzorca (pilnuje najętych)",
	"thief": "złodziej (targ)",
}

var w: SimWorld
var _cfg: Dictionary
var recipes: Dictionary          # data/recipes.json (S13): produkcja w budynkach jako dane
var work_acts: Array = ["chop", "forage", "labor"]  # czynności, które są pracą (+ z receptur)

const BASE_WORK_ACTS := ["chop", "forage", "labor"]
const OVERSEE_OFFSET := Vector2(1.2, 1.2)     # nadzorca staje obok pilnowanego
const OVERSEE_WAITS := 4.0                    # jak długo stoi przy jednym miejscu
const PAY_QUEUE_SPREAD := 6                  # ilu ludzi stoi obok siebie po wypłatę
const FREE_SPOT_RADIUS := Vector2(1.5, 4.0)  # wolne: jak daleko od drzwi domu (min, max)
const FREE_TIME_WAITS := 3.0                  # wolne trwa tyle „czekań”, potem nowy plan
const AT_DOOR := 1.0   # skrzynia: trzeba stać przy drzwiach domu (albo w środku)


func _init(world: SimWorld, p_recipes: Dictionary) -> void:
	w = world
	_cfg = world.balance["jobs"]
	recipes = p_recipes
	work_acts = BASE_WORK_ACTS.duplicate()
	for id in recipes:
		var act := String(recipes[id]["act"])
		if not act in work_acts:
			work_acts.append(act)


func is_work(act: String) -> bool:
	return act in work_acts


# Receptura przypisana do zawodu (np. tracz → piłowanie), albo pusty słownik.
func recipe_for_job(job: String) -> Dictionary:
	for id in recipes:
		if String(recipes[id]["job"]) == job:
			return recipes[id]
	return {}


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
	var food_low := float(w.balance["needs"]["food"]["low"])
	if a.disabled():
		# Chory też je, jeśli w domu jest co (inaczej umiera z głodu w łóżku).
		var h := _home(a)
		if a.needs["food"] < food_low and h != null and h.amount("food") > 0:
			return "eat"
		return "sick"
	if a.needs["food"] < food_low:
		return "eat"
	var block := block_at(w.clock.time_of_day())
	var sl: Dictionary = w.balance["needs"]["sleep"]
	if block == "sleep" or a.needs["sleep"] < float(sl["low"]):
		return "sleep"
	# Kto zasnął ze zmęczenia, śpi, aż się wyśpi (inaczej budzi się i zasypia co chwilę).
	if a.plan_kind == "sleep" and a.needs["sleep"] < float(sl["rested"]):
		return "sleep"
	if block in ["dinner", "free"] and not a.is_child and aloof_today(a):
		return "aloof"
	# Wypłata (L3): płatnik idzie z sakwą pod miejsce pracy, pracownicy czekają na pieniądze.
	if not a.is_child and w.contracts.in_pay_window():
		var p := w.person_of(a)
		if p != null and w.contracts.payer(p.household_id) == a and not w.contracts.pay_places(p.household_id).is_empty():
			return "payday"
		var c: Dictionary = w.contracts.of_worker(a.person_id) if p != null else {}
		if not c.is_empty() and float(c["owed"]) > 0.0 and block != "work":
			return "collect"
	if block == "dinner":
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
	if _home(a) == null:
		a.plan_kind = kind
		_plan_homeless(a, kind)
		return
	# Przed wyjściem z domu zjedz, jeśli już trochę burczy w brzuchu — inaczej agent
	# zawraca w pół drogi.
	var low := float(w.balance["needs"]["food"]["low"])
	if kind in ["work", "chore", "child"] and a.needs["food"] < low * 1.6 and _home(a).amount("food") > 0:
		kind = "eat"
	a.plan_kind = kind
	match kind:
		"sick":
			_go_inside(a, _home(a), "rest", 3.0,
				"ranny — leży w chacie" if a.injured_days > 0.0 else "chory — leży w chacie")
		"eat":
			_plan_eat(a)
		"sleep":
			_walk(a, _home(a).door(), "idzie spać")
			_do(a, "return_coins")
			_act(a, "sleep", 4.0, "śpi", _home(a).id)
		"child":
			_plan_child(a)
		"dinner":
			_plan_dinner(a)
		"aloof":
			_plan_aloof(a)
		"work":
			_plan_work(a)
		"payday":
			_plan_payday(a)
		"collect":
			_plan_collect(a)
		"chore":
			if not _plan_chore(a):
				# W dzień wolne wśród ludzi przed domem, wieczorem odpoczynek w środku.
				if block_at(w.clock.time_of_day()) == "work" and not a.is_child:
					_free_time(a, _rest_reason(a).trim_prefix("wolne — "))
				else:
					_go_inside(a, _home(a), "rest", 3.0, _rest_reason(a))


func release(a: SimAgent) -> void:
	for c in a.claims:
		var parts := String(c).split(":")
		if parts[0] == "tree":
			var t: SimTree = w.tree_by_id(int(parts[1]))
			if t != null and t.reserved_by == a.id:
				t.reserved_by = -1
		elif parts[0] == "cell":
			var f := w.field_by_id(parts[1])
			if f != null:
				f.release(int(parts[2]), a.id)
		elif parts[0] == "chore":
			var key := String(c).substr(6)
			if w.chore_claims.get(key, -1) == a.id:
				w.chore_claims.erase(key)
	a.claims.clear()


func _rest_reason(a: SimAgent) -> String:
	if a.is_child:
		return "bawi się w chacie"
	if not a.can_work():
		return "odpoczywa (nie może pracować)"
	if block_at(w.clock.time_of_day()) == "work":
		return "wolne — bez przydziału pracy"
	return "odpoczywa wieczorem"


# Dom i gospodarstwo agenta (F2): każdy planuje dla swojego, nie dla „chaty gracza”.
func _home(a: SimAgent) -> SimBuilding:
	return w.home_of(a)


func _hh(a: SimAgent) -> SimHousehold:
	return w.household_of(a)


# Rezerwacja obowiązku domowego jest per gospodarstwo („food:3”).
func _claim(a: SimAgent, kind: String) -> String:
	return "%s:%d" % [kind, _hh(a).id]


# --- Kroki ---

func _walk(a: SimAgent, to: Vector2, why: String) -> void:
	a.steps.append({ "t": "walk", "to": to, "why": why })


func _act(a: SimAgent, act: String, secs: float, why: String, inside: String = "", alert := false) -> void:
	a.steps.append({ "t": "act", "act": act, "left": secs, "why": why, "inside": inside, "alert": alert, "work": is_work(act) })


func _do(a: SimAgent, fn: String, arg: Variant = null) -> void:
	a.steps.append({ "t": "do", "fn": fn, "arg": arg })


func _wait(a: SimAgent, why: String, act := "wait", alert := false) -> void:
	_act(a, act, float(_cfg["wait_seconds"]), why, "", alert)


func _go_inside(a: SimAgent, b: SimBuilding, act: String, secs: float, why: String) -> void:
	_walk(a, b.door(), "idzie do: %s" % b.name)
	_act(a, act, secs, why, b.id)


# --- Plany ---

# Bez domu (S7): śpi, je i spędza wieczory w miejscu noclegu pod gołym niebem;
# jedzenie kupuje gotowe na targu, a pracuje jak zwykle.
func _homeless_spot(a: SimAgent) -> Vector2:
	var s: Array = w.balance["economy"]["homeless_spot"]
	return Vector2(float(s[0]), float(s[1])) + Vector2(float(a.id % 5) - 2.0, float(a.id % 3)) * 0.8


func _plan_homeless(a: SimAgent, kind: String) -> void:
	var spot := _homeless_spot(a)
	match kind:
		"sick":
			_walk(a, spot, "chory — wlecze się na swoje legowisko")
			_act(a, "rest", 3.0, "chory — leży pod gołym niebem")
		"sleep":
			_walk(a, spot, "idzie spać pod gołym niebem")
			_act(a, "sleep", 4.0, "śpi pod gołym niebem (bez domu)")
		"eat":
			_plan_eat_away(a)
		"dinner":
			_walk(a, spot, "wraca na kolację tam, gdzie śpią")
			_act(a, "dine", float(_cfg["wait_seconds"]) * 2.0, "kolacja pod gołym niebem")
		"work":
			_plan_work(a)
		"child":
			var t := follow_target(a) if block_at(w.clock.time_of_day()) == "work" else null
			if t != null:
				_plan_follow(a, t)
			else:
				_walk(a, spot + Vector2(1.0, 1.0), "bawi się przy legowisku")
				_act(a, "play", 3.0, "bawi się przy legowisku (bez domu)")
		_:
			_walk(a, spot, "wraca na legowisko")
			_act(a, "rest", 3.0, "siedzi bezczynnie — bez domu")


# Posiłek kupiony gotowy na targu (bez spiżarni), a bez pieniędzy — las.
func _plan_eat_away(a: SimAgent) -> void:
	var price := float(w.balance["economy"]["meal_away_price"])
	var p := w.person_of(a)
	if p.purse >= price or (_hh(a).chest == null and _hh(a).cash >= price):
		var market: SimBuilding = w.building("market")
		_walk(a, market.door(), "idzie coś zjeść na targu")
		_do(a, "meal_away", price)
		_act(a, "eat", 1.5, "je na targu", market.id)
	elif a.can_work():
		_plan_forage(a)
		_do(a, "eat_carried")
	else:
		a.hungry_no_food = true
		_walk(a, _homeless_spot(a), "GŁODNY — bez grosza")
		_wait(a, "GŁODNY — bez grosza i bez domu", "wait", true)


func _plan_eat(a: SimAgent) -> void:
	var home: SimBuilding = _home(a)
	if home.amount("food") > 0:
		_walk(a, home.door(), "głodny — idzie coś zjeść")
		_do(a, "eat")
		_act(a, "eat", 1.5, "je posiłek", home.id)
		return
	# Pusta spiżarnia: dorosły sam kupi jedzenie, jeśli są pieniądze, a jak nie —
	# idzie do lasu szukać jagód i grzybów.
	if a.can_work() and _food_trip(a, true):
		return
	if a.can_work() and not w.chore_claims.has(_claim(a, "food")):
		_plan_forage(a)
		return
	a.hungry_no_food = true
	var why := "GŁODNY — pusta spiżarnia"
	if w.market.building.amount("food") <= 0:
		why += ", a na targu nie ma jedzenia"
	elif not _hh(a).can_afford(w.market.sell_price("food")):
		why += " i brak pieniędzy"
	elif w.chore_claims.has(_claim(a, "food")):
		why += " (ktoś już idzie po jedzenie)"
	_walk(a, home.door(), why)
	_act(a, "wait", float(_cfg["wait_seconds"]), why, home.id, true)


# Kolacja: ród schodzi się do chaty i siedzi razem przy stole do końca bloku (B2).
# Je tylko ten, kto jest choć trochę głodny; przy pustej spiżarni siedzą przy pustym stole.
func _plan_dinner(a: SimAgent) -> void:
	var home: SimBuilding = _home(a)
	var left := (float(w.balance["schedule"]["dinner_end"]) - w.clock.time_of_day()) * w.clock.day_seconds
	_walk(a, home.door(), "wraca do chaty na kolację")
	_do(a, "dinner")
	var why := "je kolację z rodziną"
	if home.amount("food") <= 0:
		why = "siedzi z rodziną przy pustym stole"
	_act(a, "dine", maxf(left, float(_cfg["wait_seconds"])), why, home.id)


# Sygnały dryfu (D2): kto słabo należy do rodu, w niektóre dni omija kolację i wieczór
# spędza poza domem. Im słabsza siła, tym częściej. Losowanie z hasha (osoba, doba),
# żeby decyzja była stała przez całą dobę i nie ruszała głównego strumienia RNG.
func aloof_today(a: SimAgent) -> bool:
	if w.is_independent(a):
		return false
	var p := w.person_of(a)
	if p == null or p.id == w.family.root_id:
		return false
	var cfg: Dictionary = w.balance["belonging"]
	var below := float(cfg["aloof_below"])
	var s := float(w.family.strength.get(p.id, 1.0))
	if s >= below:
		return false
	var intensity := clampf((below - s) / (below - float(cfg["leave_below"])), 0.0, 1.0)
	# Rzut stały przez całą dobę: liczony raz i trzymany przy osobie.
	var day := w.clock.day_index()
	if int(p.get_meta("aloof_day", -1)) != day:
		p.set_meta("aloof_day", day)
		p.set_meta("aloof_roll", SimRng.new(SimRng.hash3(int(w.balance["world_seed"]), p.id * 100000 + day, "aloof")).next_float())
	return float(p.get_meta("aloof_roll")) < intensity


func _plan_aloof(a: SimAgent) -> void:
	var cfg: Dictionary = w.balance["belonging"]
	var place: SimBuilding = w.building(String(cfg["aloof_place"]))
	var r := float(cfg["aloof_spread"])
	var spot: Vector2 = place.door() + Vector2(w.rng.next_float(-r, r), w.rng.next_float(0.5, r))
	var dinner := block_at(w.clock.time_of_day()) == "dinner"
	var why := "nie przyszedł na kolację — siedzi sam" if dinner else "wieczór spędza poza domem"
	if a.needs["food"] < float(w.balance["needs"]["food"]["dinner_eat_below"]) and dinner:
		why = "je osobno, z dala od reszty"
	_walk(a, spot, "idzie gdzieś sam")
	_act(a, "rest", float(_cfg["wait_seconds"]) * 2.0, why)


# Za kim dziecko chodzi w godzinach pracy (D5): nakaz gracza, a bez niego najbardziej
# lubiany dorosły z rodu, który właśnie pracuje.
func follow_target(a: SimAgent) -> SimAgent:
	var p := w.person_of(a)
	if p == null:
		return null
	var mine: Array = w.family.living_members(p.lineage_id)
	if a.follow_id >= 0:
		var fp: SimPerson = w.family.persons.get(a.follow_id)
		var fa: SimAgent = w.agent_by_id(fp.agent_id) if fp != null and fp.alive() else null
		return fa if fa != null and fa.status == "active" else null
	var best: SimAgent = null
	var best_v := float(w.balance["children"]["follow_min_bond"])
	for o: SimPerson in mine:
		var oa: SimAgent = w.agent_by_id(o.agent_id)
		if oa == null or oa.status != "active" or oa.is_child or oa.plan_kind != "work":
			continue
		var v := w.bonds.value(p.id, SimBonds.person(o.id))
		if v > best_v:
			best_v = v
			best = oa
	return best


func _plan_follow(a: SimAgent, t: SimAgent) -> void:
	var cfg: Dictionary = w.balance["children"]
	var tp := w.person_of(t)
	var off := float(cfg["watch_offset"])
	if t.inside != "":
		var b: SimBuilding = w.building(t.inside)
		_walk(a, b.door() + Vector2(off, off * 0.5), "idzie za: %s" % tp.name)
		_act(a, "watch", float(cfg["watch_seconds"]), "patrzy, jak %s pracuje" % tp.name, b.id)
		return
	_walk(a, t.position + Vector2(off, off * 0.5), "idzie za: %s" % tp.name)
	_act(a, "watch", float(cfg["watch_seconds"]), "patrzy, jak %s pracuje" % tp.name)


func _plan_child(a: SimAgent) -> void:
	if block_at(w.clock.time_of_day()) == "work":
		var t := follow_target(a)
		if t != null:
			_plan_follow(a, t)
			return
	var home: SimBuilding = _home(a)
	var k := w.rng.next_float(0.0, TAU)
	var r := w.rng.next_float(1.5, 4.5)
	var spot: Vector2 = home.door() + Vector2(cos(k), sin(k) * 0.6 + 0.8) * r
	_walk(a, spot, "bawi się przy chacie")
	_act(a, "play", w.rng.next_float(2.0, 4.0), "bawi się przy chacie")


func _plan_work(a: SimAgent) -> void:
	var r := recipe_for_job(a.job)
	if not r.is_empty():
		_plan_producer(a, r)
		return
	match a.job:
		"woodcutter":
			_plan_woodcutter(a)
		"carrier":
			if not _plan_carrier(a):
				_free_time(a, "nie ma nic do noszenia")
		"laborer":
			_plan_laborer(a)
		"overseer":
			_plan_oversee(a)
		"forager":
			_plan_forage(a)
		"thief":
			_plan_thief(a)
		_:
			if _home(a) == null:
				_plan_homeless(a, "chore")
			else:
				_go_inside(a, _home(a), "rest", 3.0, _rest_reason(a))


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


# Praca w budynku według receptury (S13): wejścia → wyjścia, czas, umiejętność.
func _plan_producer(a: SimAgent, r: Dictionary) -> void:
	var b: SimBuilding = w.building(String(r["building"]))
	var inputs: Dictionary = r["inputs"]
	var outputs: Dictionary = r["outputs"]
	if a.carrying != "" and not inputs.has(a.carrying):
		_plan_deliver_carried(a)
		return
	var sp: Array = r["spot"]
	var spot := b.door() + Vector2(float(sp[0]), float(sp[1]))
	# Kto sam niesie wsad (np. stolarz z deskami z wieczora), najpierw go odkłada.
	if a.carrying != "":
		_walk(a, spot, "niesie %s do: %s" % [w.good_label(a.carrying), b.name])
		_do(a, "deposit", b.id)
		return
	for g in inputs:
		if b.amount(g) < int(inputs[g]):
			_walk(a, spot, "idzie do: %s" % b.name)
			_wait(a, String(r["wait_input"]), "wait", true)
			return
	for g in outputs:
		if b.space(g) < int(outputs[g]):
			_walk(a, spot, "idzie do: %s" % b.name)
			_wait(a, String(r["full"]), "wait", true)
			return
	var act := String(r["act"])
	_walk(a, spot, "idzie do: %s" % b.name)
	_act(a, act, _dur(a, String(r["skill"]), float(r["seconds"])), String(r["doing"]))
	_do(a, "produce", r)


func _plan_laborer(a: SimAgent) -> void:
	if a.carrying != "":
		_plan_deliver_carried(a)
		return
	# Robota w polu (L2) u kogoś na umowie (L3): orka, siew, żniwa na zagonach
	# pracodawcy, snopy do jego spichrza.
	var p := w.person_of(a)
	if p != null and w.contracts.of_worker(p.id).is_empty():
		var o := w.contracts.best_offer_for(p, "laborer")
		if o.is_empty():
			_free_time(a, "nikt nie najmie do pola (albo płacą za mało)")
			return
		w.contracts.hire(o, p)
	var manor: SimBuilding = w.buildings.get(a.workplace)
	var f := w.field_with_work(manor.id) if manor != null else null
	if f == null:
		_free_time(a, "%s nie ma dziś roboty w polu" % (manor.name if manor != null else "pracodawca"))
		return
	var season := w.clock.current_season()
	var i := f.free_cell(season)
	if f.heap > 0 and (i < 0 or f.heap >= int(w.balance["carry"]["food"])):
		_walk(a, f.heap_spot(), "idzie po snopy na pole")
		_do(a, "field_pickup", f.id)
		_walk(a, manor.door(), "niesie snopy do spichrza: %s" % manor.name)
		_do(a, "deposit", manor.id)
		return
	var s: Dictionary = w.balance["schedule"]
	var left := (float(s["work_end"]) - w.clock.time_of_day()) * w.clock.day_seconds
	# Jeden zagon na raz: rezerwacja, przejście wzdłuż, potem następny (L2).
	var t := f.cell_task(i, season)
	var label := String(SimField.TASK_LABELS[t])
	f.claim(i, a.id)
	a.claims.append("cell:%s:%d" % [f.id, i])
	var c: Dictionary = f.cells[i]
	var from: Vector2 = c["start"]
	_walk(a, from.lerp(c["end"], f.progress(i, season)), "idzie w pole dworu: %s" % label)
	_act(a, "labor", maxf(left, 1.0), "%s na polu dworu (dniówka)" % label)
	var st: Dictionary = a.steps[a.steps.size() - 1]
	st["field"] = f.id
	st["cell"] = i
	st["task"] = t


# Obowiązki domowe (każdy dorosły po pracy i bez przydziału).
func _plan_chore(a: SimAgent) -> bool:
	if not a.can_work() or _home(a) == null:
		return false
	if a.carrying != "":
		_plan_deliver_carried(a)
		return true
	if _food_trip(a, false):
		return true
	if _firewood_trip(a):
		return true
	# Bieda: spiżarnia pustoszeje, a nie ma za co kupić — las jest za darmo.
	var hh = _hh(a)
	if _home(a).amount("food") < hh.target_food / 2 and hh.cash < w.market.sell_price("food") * 4.0 \
			and w.clock.current_season() != "winter":
		_plan_forage(a)
		return true
	return false


func _food_trip(a: SimAgent, urgent: bool) -> bool:
	if _home(a) == null:
		return false
	var hh = _hh(a)
	var home: SimBuilding = _home(a)
	var want: int = hh.target_food - home.amount("food")
	if urgent:
		want = maxi(want, 1)
	if want <= 0 or w.chore_claims.has(_claim(a, "food")):
		return false
	var cap := int(w.balance["carry"]["food"])
	var afford := int(floor(_budget(a) / w.market.sell_price("food")))
	var qty := mini(mini(want, cap), mini(mini(afford, home.space("food")), w.market.building.amount("food")))
	if qty <= 0:
		return false
	w.chore_claims[_claim(a, "food")] = a.id
	a.claims.append("chore:" + _claim(a, "food"))
	_fetch_coins(a, w.market.sell_price("food") * qty)
	var market: SimBuilding = w.building("market")
	_walk(a, market.door(), "idzie na targ kupić jedzenie")
	_do(a, "buy_food", qty)
	_walk(a, home.door(), "niesie jedzenie do chaty")
	_do(a, "deposit", home.id)
	return true


func _firewood_trip(a: SimAgent) -> bool:
	if _home(a) == null:
		return false
	var home: SimBuilding = _home(a)
	var mill: SimBuilding = w.building("sawmill")
	if home.amount("log") >= _hh(a).target_firewood or home.space("log") <= 0:
		return false
	if w.chore_claims.has(_claim(a, "firewood")):
		return false
	var hh = _hh(a)
	if mill.amount("log") <= 0:
		# Bez własnego drewna opał trzeba kupić na targu.
		if _budget(a) < w.market.sell_price("log") * 2.0 or w.market.building.amount("log") <= 0:
			return false
		w.chore_claims[_claim(a, "firewood")] = a.id
		a.claims.append("chore:" + _claim(a, "firewood"))
		_fetch_coins(a, w.market.sell_price("log") * 2.0)
		_walk(a, w.building("market").door(), "idzie kupić opał na targu")
		_do(a, "buy_firewood", 2)
		_walk(a, home.door(), "niesie opał do chaty")
		_do(a, "deposit", home.id)
		return true
	w.chore_claims[_claim(a, "firewood")] = a.id
	a.claims.append("chore:" + _claim(a, "firewood"))
	_walk(a, mill.door() + Vector2(-1.5, 0.0), "idzie po opał do tartaku")
	_do(a, "pickup", { "b": "sawmill", "good": "log", "qty": mini(2, mill.amount("log")) })
	_walk(a, home.door(), "niesie opał do chaty")
	_do(a, "deposit", home.id)
	return true


# Na zakupy dla domu: sakwa i skrzynia (albo tobołek, gdy bez domu).
func _budget(a: SimAgent) -> float:
	var p := w.person_of(a)
	return (p.purse if p != null else 0.0) + _hh(a).cash


# Pieniądze mają miejsce (S14, K2): komu w sakwie brakuje, ten najpierw idzie do skrzyni
# w domu i bierze z zapasem (kieszonkowe zostaje na okazję).
func _fetch_coins(a: SimAgent, need: float) -> void:
	var p := w.person_of(a)
	var hh := _hh(a)
	if p == null or hh.chest == null or p.purse >= need:
		return
	var pc: Dictionary = w.balance["purse"]
	var amt := need * (1.0 + float(pc["fetch_margin"])) + float(pc["pocket_money"]) - p.purse
	_go_inside(a, hh.chest, "fetch", float(pc["fetch_seconds"]), "bierze pieniądze ze skrzyni")
	_do(a, "take_coins", amt)


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
	if shop.amount("chair") > 0 and w.market.wants("chair") + w.traders.wants("chair") > 0:
		_pickup_and_deliver(a, shop, "chair", market, "niesie krzesła na targ")
		return true
	if _carpenter_present() and shop.space("plank") > 0 and mill.amount("plank") > 0:
		_pickup_and_deliver(a, mill, "plank", shop, "niesie deski do stolarni", shop.space("plank"))
		return true
	if _hh(a).sell_planks and mill.amount("plank") > 0 and w.market.wants("plank") + w.traders.wants("plank") > 0:
		_pickup_and_deliver(a, mill, "plank", market, "niesie deski na targ")
		return true
	return false


func _pickup_and_deliver(a: SimAgent, from: SimBuilding, good: String, to: SimBuilding, why: String, limit := 999) -> void:
	var qty := mini(int(w.balance["carry"][good]), limit)
	_walk(a, from.door(), "idzie po towar: %s" % from.name)
	_do(a, "pickup", { "b": from.id, "good": good, "qty": qty })
	_walk(a, to.door(), why)
	_do(a, "deposit", to.id)


# Płatnik (L3): bierze ze skrzyni, ile trzeba, idzie pod miejsce pracy i wręcza
# wypłaty tym, którzy czekają. Póki ktoś czeka, a okno trwa — zostaje.
func _plan_payday(a: SimAgent) -> void:
	var p := w.person_of(a)
	var places := w.contracts.pay_places(p.household_id)
	var place := String(places[0])
	_fetch_coins(a, w.contracts.owed_total(p.household_id, place))
	_walk(a, w.contracts.pay_spot(place), "idzie z wypłatą dla ludzi")
	_act(a, "pay", float(_cfg["wait_seconds"]), "wypłaca ludziom za robotę")
	_do(a, "hand_out", place)


# Nadzorca (L6): chodzi między najętymi ludźmi swojego gospodarstwa i ich pilnuje.
# Przy nim nikt się nie miga; jeden nadzorca ogarnia kilku ludzi (dane).
func _plan_oversee(a: SimAgent) -> void:
	var p := w.person_of(a)
	var crew: Array = []
	for c: Dictionary in w.contracts.of_employer(p.household_id):
		var wa: SimAgent = w.agent_by_id(w.family.persons[int(c["worker"])].agent_id)
		if wa != null and wa.is_active() and w.jobs.is_work(wa.activity):
			crew.append(wa)
	if crew.is_empty():
		_free_time(a, "nikogo dziś nie trzeba pilnować")
		return
	var target: SimAgent = crew[w.rng.next_int(0, crew.size() - 1)]
	_walk(a, target.position + OVERSEE_OFFSET, "idzie doglądnąć ludzi przy robocie")
	_act(a, "oversee", float(_cfg["wait_seconds"]) * OVERSEE_WAITS, "pilnuje najętych przy robocie (%d)" % crew.size())


# Pracownik po robocie czeka pod miejscem pracy na płatnika.
func _plan_collect(a: SimAgent) -> void:
	var c := w.contracts.of_worker(a.person_id)
	var spot := w.contracts.pay_spot(String(c["place"]))
	var k := float(a.id % PAY_QUEUE_SPREAD) - PAY_QUEUE_SPREAD * 0.5
	_walk(a, spot + Vector2(k * 0.7, 1.0), "idzie po wypłatę")
	_wait(a, "czeka na wypłatę (%d zł)" % int(round(float(c["owed"]))))


# Gdy nie da się robić swojej roboty (nic do noszenia, brak zbytu, brak roboty w polu):
# czas wolny przed domem, wśród ludzi, zamiast stania w miejscu (jak w Cultures).
# Kto obsadza stanowisko (tartak, później stragan), ten czeka przy nim.
func _free_time(a: SimAgent, why: String) -> void:
	var base: Vector2 = _home(a).door() if _home(a) != null else _homeless_spot(a)
	var k := w.rng.next_float(0.0, TAU)
	var r := w.rng.next_float(FREE_SPOT_RADIUS.x, FREE_SPOT_RADIUS.y)
	_walk(a, base + Vector2(cos(k), absf(sin(k)) * 0.6 + 0.6) * r, "wolne — %s" % why)
	_act(a, "rest", float(_cfg["wait_seconds"]) * FREE_TIME_WAITS, "wolne — %s" % why)


# Dokąd odnieść to, co agent ma w rękach (np. po przerwaniu planu).
func _plan_deliver_carried(a: SimAgent) -> void:
	if _home(a) == null and a.carrying in ["food", "log"]:
		a.clear_carry()
		_wait(a, "nie ma dokąd tego zanieść — bez domu")
		return
	if a.carry_to != "":
		var owner: SimBuilding = w.building(a.carry_to)
		_walk(a, owner.door(), "odnosi cudzy towar: %s → %s" % [w.good_label(a.carrying), owner.name])
		_do(a, "deposit", owner.id)
		return
	var dest := ""
	match a.carrying:
		"food":
			dest = _home(a).id
		"log":
			dest = "sawmill" if _home(a).space("log") <= 0 else _home(a).id
			if a.job == "woodcutter":
				dest = "sawmill"
		"plank":
			dest = "workshop" if (_carpenter_present() and w.building("workshop").space("plank") > 0) else "market"
			if dest == "market" and w.market.wants("plank") + w.traders.wants("plank") <= 0:
				dest = "sawmill"   # bez zbytu wraca do składu
		"chair":
			dest = "market" if w.market.wants("chair") + w.traders.wants("chair") > 0 else "workshop"
	var b: SimBuilding = w.building(dest)
	_walk(a, b.door(), "odnosi: %s → %s" % [w.good_label(a.carrying), b.name])
	_do(a, "deposit", dest)


# Czas czynności z umiejętnością, wiekiem, traitami, zdrowiem i światłem.
func _dur(a: SimAgent, act: String, base: float) -> float:
	# `act` to tu umiejętność (dla receptur pole „skill”), której używa efektywność.
	return base / efficiency(a, act)


func efficiency(a: SimAgent, act: String) -> float:
	var sk: Dictionary = w.balance["skills"]
	var e := float(sk["eff_base"]) + float(sk["eff_per_level"]) * a.skill(act)
	e *= a.age_eff * a.trait_mult(act)
	if a.health < float(sk["weak_health"]):
		e *= float(sk["weak_base"]) + a.health / 100.0
	if w.clock.light_factor() < float(w.balance["risk"]["dark_light_below"]):
		e *= float(_cfg["dark_work_mult"])
	e *= willingness(a, act)
	return maxf(e, float(sk["eff_min"]))


# Chęć do pracy (D4): nielubiana czynność albo słaba przynależność do rodu spowalnia.
# 1.0 = pełna chęć; osoby spoza rodu pracują dla siebie, więc zawsze 1.0.
func willingness(a: SimAgent, act: String) -> float:
	var p := w.person_of(a)
	# Na cudzej robocie bez nadzoru ludzie się migają (L6).
	var hired := 1.0
	if p != null and not w.contracts.of_worker(p.id).is_empty() and not w.contracts.supervised(a):
		hired = float(w.balance["contracts"]["unsupervised_will"])
	if p == null or w.is_independent(a):
		return hired
	var cfg: Dictionary = w.balance["will"]
	var pref := w.bonds.preference(p.id, act)
	var s := float(w.family.strength.get(p.id, 1.0))
	var below := float(w.balance["belonging"]["aloof_below"])
	var e := 1.0
	e -= clampf(-pref / float(cfg["pref_scale"]), 0.0, 1.0) * float(cfg["pref_penalty"])
	e -= clampf((below - s) / below, 0.0, 1.0) * float(cfg["weak_penalty"])
	return maxf(e * hired, float(cfg["min"]))


# Opisowy powód niechęci: najmocniejsze złe wspomnienie o czynności albo brak serca do rodu.
func reluctance_reason(a: SimAgent, act: String) -> String:
	var p := w.person_of(a)
	for e in w.bonds.preferences(p.id):
		if e["act"] == act and float(e["value"]) < 0.0:
			return "nie znosi tej roboty (%s)" % String(e["from"][0])
	if not w.contracts.of_worker(p.id).is_empty() and not w.contracts.supervised(w.agent_by_id(p.agent_id)):
		return "nikt nie pilnuje"
	return "nie ma serca do roboty dla rodziny"


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
		"trader_gone":
			w.traders.gone(a, String(step["arg"]))
			return true
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
		"return_coins":
			_return_coins(a)
			return true
		"hand_out":
			w.contracts.hand_out(a, String(step["arg"]))
			return true
		"field_pickup":
			return _fx_field_pickup(a, String(step["arg"]))
		"take_coins":
			return _fx_take_coins(a, float(step["arg"]))
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
	var home: SimBuilding = _home(a)
	if home.take("food", 1) <= 0:
		return false
	a.needs["food"] = minf(100.0, a.needs["food"] + float(w.balance["needs"]["food"]["meal"]))
	return true


func _fx_meal_away(a: SimAgent, price: float) -> bool:
	var p := w.person_of(a)
	if p == null:
		return false
	if p.purse >= price:
		p.purse -= price
		p.held = minf(p.held, p.purse)
	elif _hh(a).chest == null and _hh(a).cash >= price:
		_hh(a).pay(price)
	else:
		return false
	a.needs["food"] = minf(100.0, a.needs["food"] + float(w.balance["needs"]["food"]["meal"]))
	return true


func _fx_dinner(a: SimAgent) -> void:
	_return_coins(a)
	if a.dinner_day == w.clock.day_index():
		return
	a.dinner_day = w.clock.day_index()
	if a.needs["food"] < float(w.balance["needs"]["food"]["dinner_eat_below"]):
		_fx_eat(a)


# Snopy z pola: towar właściciela pola, idzie do jego spichrza (nie do domu robotnika).
func _fx_field_pickup(a: SimAgent, field_id: String) -> bool:
	var f := w.field_by_id(field_id)
	if f == null or f.heap <= 0 or a.position.distance_to(f.heap_spot()) > AT_DOOR:
		return false
	var n := mini(f.heap, int(w.balance["carry"]["food"]))
	f.heap -= n
	a.carrying = "food"
	a.carrying_qty = n
	a.carrying_qualities = []
	a.carry_to = f.owner_building
	return true


func _fx_take_coins(a: SimAgent, amt: float) -> bool:
	var p := w.person_of(a)
	var hh := _hh(a)
	if p == null or hh.chest == null or a.position.distance_to(hh.chest.door()) > AT_DOOR:
		return false
	var n := clampf(amt, 0.0, maxf(hh.cash, 0.0))
	hh.pay(n)
	p.purse += n
	p.held += n
	return true


# W domu (zostawia towar, kolacja, sen): pieniądze gospodarstwa ponad kieszonkowe
# wracają do skrzyni (K2, K3). Kto ich nie oddaje, ten je chowa.
func _return_coins(a: SimAgent) -> void:
	var p := w.person_of(a)
	var hh := _hh(a)
	if p == null or hh.chest == null:
		return
	var back := maxf(0.0, minf(p.held, p.purse) - float(w.balance["purse"]["pocket_money"]))
	p.purse -= back
	p.held = minf(p.held - back, p.purse)
	hh.earn(back)


func _fx_deposit(a: SimAgent, bid: String) -> bool:
	var b: SimBuilding = w.building(bid)
	if _hh(a).chest == b:
		_return_coins(a)
	if a.carrying == "":
		return true
	if b.type == "market":
		# Najpierw na wóz kupca wędrownego (lepsza cena), resztę miejscowemu kupcowi (H1, H3).
		var rw: Dictionary = w.traders.sell_to_wagon(_hh(a), a.carrying, a.carrying_qty, a.carrying_qualities, w.person_of(a))
		if int(rw["qty"]) > 0:
			w.events.float_text(b.door() + Vector2(2, 0), "+%d zł (wóz)" % int(round(float(rw["paid"]))), "money")
			w.stats["sold_" + a.carrying] = int(w.stats.get("sold_" + a.carrying, 0)) + int(rw["qty"])
			a.carrying_qty -= int(rw["qty"])
			a.carrying_qualities = a.carrying_qualities.slice(int(rw["qty"]))
			if a.carrying_qty <= 0:
				a.clear_carry()
				return true
		var r: Dictionary = w.market.buy_from(_hh(a), a.carrying, a.carrying_qty, a.carrying_qualities, w.person_of(a))
		var n := int(r["qty"])
		if n > 0:
			w.events.float_text(b.door(), "+%d zł" % int(round(float(r["paid"]))), "money")
			w.stats["sold_" + a.carrying] = int(w.stats.get("sold_" + a.carrying, 0)) + n
			a.carrying_qty -= n
			a.carrying_qualities = a.carrying_qualities.slice(n)
		if a.carrying_qty <= 0:
			a.clear_carry()
			return true
		# Reszty kupiec nie weźmie: odnosi ją tam, skąd wziął, i idzie na wolne.
		w.events.float_text(b.door(), "kupiec nie bierze: %s" % w.good_label(a.carrying), "info")
		a.steps.clear()
		_plan_deliver_carried(a)
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
	return _buy(a, "food", qty)


func _fx_buy_firewood(a: SimAgent, qty: int) -> bool:
	return _buy(a, "log", qty)


# Zakup u kupca za pieniądze gospodarstwa (H2): tylko to, co ma w zapasie.
func _buy(a: SimAgent, good: String, qty: int) -> bool:
	var p := w.person_of(a)
	var hh := _hh(a)
	if p == null:
		return false
	# Bez domu tobołek gospodarstwa jest przy nich: płacą z niego jak z sakwy.
	var bundle := 0.0
	if hh.chest == null:
		bundle = maxf(hh.cash, 0.0)
		hh.cash -= bundle
		p.purse += bundle
	var purse0 := p.purse
	var n := w.market.sell_to(p, good, qty)
	var spent := purse0 - p.purse
	if hh.chest == null:
		var back := minf(bundle, p.purse)
		p.purse -= back
		hh.cash += back
	p.held = minf(p.held, p.purse)
	if n <= 0:
		return false
	w.events.float_text(w.market.building.door(), "-%d zł" % int(round(spent)), "cost")
	a.carrying = good
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


func _fx_produce(a: SimAgent, r: Dictionary) -> bool:
	var b: SimBuilding = w.building(String(r["building"]))
	var inputs: Dictionary = r["inputs"]
	for g in inputs:
		if b.amount(g) < int(inputs[g]):
			return false
	for g in inputs:
		b.take(g, int(inputs[g]))
	var outputs: Dictionary = r["outputs"]
	for g in outputs:
		b.add(g, int(outputs[g]))
		# Jakość wyrobu (np. krzesła) z umiejętności, cech i odrobiny losu.
		if r.has("quality") and g == "chair":
			var qc: Dictionary = r["quality"]
			var jit: Array = qc["jitter"]
			for i in int(outputs[g]):
				var q := clampf(float(qc["base"]) + float(qc["per_skill"]) * a.skill(String(r["skill"])) + a.quality_bonus
					+ w.rng.next_float(float(jit[0]), float(jit[1])), float(qc["min"]), float(qc["max"]))
				b.chair_qualities.append(q)
				w.events.float_text(b.door(), "krzesło (%s)" % quality_label(q), "info")
	_gain_skill(a, String(r["skill"]), float(r["seconds"]))
	w.roll_accident(a, String(r["act"]))
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
