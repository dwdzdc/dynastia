# Minimalny runner testów sim/ (własny, bez GUT) — patrz ADR-0002.
# Uruchomienie: godot --headless --script res://tests/run_tests.gd
extends SceneTree


const RNG_SCRIPT := preload("res://sim/rng.gd")
const LOADER_SCRIPT := preload("res://sim/data_loader.gd")
const CLOCK_SCRIPT := preload("res://sim/time.gd")
const WORLD_SCRIPT := preload("res://sim/world.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run_all()
	if failures == 0:
		print("TESTS OK (%d checks)" % checks)
		quit(0)
	else:
		printerr("TESTS FAILED: %d/%d" % [failures, checks])
		quit(1)


func check(name: String, cond: bool) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: %s" % name)


func _run_all() -> void:
	# Etap 0
	_test_rng_deterministic()
	_test_rng_range_and_distribution()
	_test_hash3_stable()
	_test_hash3_sensitive_to_inputs()
	_test_data_loader()
	# Etap 1
	_test_clock_advance_10_years()
	_test_clock_season_rotation()
	_test_clock_pause_and_speed()
	_test_winter_shorter_day()
	_test_light_factor_day_night()
	# Świat (osada + ród)
	_test_world_start_family()
	_test_life_stages_in_days()
	_test_pregnancy_lasts_data_days()
	_test_traits_and_character_split()
	_test_lineage_start()
	_test_bonds_asymmetric_and_fading()
	_test_memories_character_mods()
	_test_start_bonds()
	_test_together_builds_bonds()
	_test_dinner_gathers_family()
	_test_activity_bonds_child_and_accident()
	_test_drift_never_below_stranger()
	_test_strength_scenarios()
	_test_switch_root()
	_test_departure_and_ai_life()
	_test_purse_share_by_strength()
	_test_drift_signals()
	_test_preferences_from_memories()
	_test_reluctance_and_orders()
	_test_child_follows_adult()
	_test_ai_lineage_lives_independently()
	_test_households_separate()
	_test_rent_eviction_homeless()
	_test_recipe_from_data()
	_test_society_from_data()
	_test_ai_households_live()
	_test_bonds_across_lineages()
	_test_marriage_with_existing_people()
	_test_merchant_is_a_person()
	_test_money_in_chest()
	_test_buy_through_purse()
	_test_buyers_pay_from_own_money()
	_test_traveling_traders()
	_test_estate_pays_wages()
	_test_world_deterministic()
	_test_world_30_days_autonomous()
	_test_economy_chain_produces_income()
	_test_no_income_goes_into_debt()
	_test_succession_and_game_over()
	_test_marriage_and_birth()
	_test_manual_queue_auto_release()
	_test_long_run_no_crash()


# --- Etap 0 ---

func _test_rng_deterministic() -> void:
	var a := RNG_SCRIPT.new(12345)
	var b := RNG_SCRIPT.new(12345)
	var same := true
	for i in 100:
		if a.next_int(0, 1000) != b.next_int(0, 1000):
			same = false
			break
	check("same seed -> same sequence", same)

	var c := RNG_SCRIPT.new(99999)
	var differs := false
	for i in 100:
		if a.next_int(0, 1000) != c.next_int(0, 1000):
			differs = true
			break
	check("different seed -> different sequence", differs)


func _test_rng_range_and_distribution() -> void:
	var r := RNG_SCRIPT.new(42)
	var hits := {}
	for i in 1000:
		var v := r.next_int(0, 9)
		hits[v] = int(hits.get(v, 0)) + 1
	var all_in_range := true
	for k in hits:
		if int(k) < 0 or int(k) > 9:
			all_in_range = false
	check("next_int stays in [0,9]", all_in_range)
	check("next_int covers all buckets", hits.size() > 3)


func _test_hash3_stable() -> void:
	check("hash3 stable across calls", RNG_SCRIPT.hash3(1, 2, "face") == RNG_SCRIPT.hash3(1, 2, "face"))
	check("hash3 non-negative", RNG_SCRIPT.hash3(1, 2, "face") >= 0)


func _test_hash3_sensitive_to_inputs() -> void:
	var base := RNG_SCRIPT.hash3(1, 2, "face")
	check("hash3 seed-sensitive", base != RNG_SCRIPT.hash3(2, 2, "face"))
	check("hash3 id-sensitive", base != RNG_SCRIPT.hash3(1, 3, "face"))
	check("hash3 purpose-sensitive", base != RNG_SCRIPT.hash3(1, 2, "head"))


func _test_data_loader() -> void:
	var data: Dictionary = LOADER_SCRIPT.load_json("res://data/balance.json")
	check("balance.json loads non-empty", not data.is_empty())
	var day_seconds: Variant = LOADER_SCRIPT.get_nested(data, "time.day_seconds")
	check("time.day_seconds is float", typeof(day_seconds) == TYPE_FLOAT)
	check("time.day_seconds > 0", float(day_seconds) > 0.0)
	check("days_per_year == 4 * days_per_season",
		int(LOADER_SCRIPT.get_nested(data, "time.days_per_year")) ==
		4 * int(LOADER_SCRIPT.get_nested(data, "time.days_per_season")))


# --- Etap 1 ---

func _balance() -> Dictionary:
	return LOADER_SCRIPT.load_json("res://data/balance.json")


func _new_clock() -> RefCounted:
	return CLOCK_SCRIPT.new(_balance())


func _test_clock_advance_10_years() -> void:
	var data := _balance()
	var days_per_year := int(LOADER_SCRIPT.get_nested(data, "time.days_per_year"))
	var day_seconds := float(LOADER_SCRIPT.get_nested(data, "time.day_seconds"))
	var c := _new_clock()
	c.speed = 1
	for i in days_per_year * 10:
		c.advance(day_seconds)
	check("10 years -> correct day count", c.day_index() == days_per_year * 10)
	check("10 years -> year == 10", c.current_year() == 10)


func _test_clock_season_rotation() -> void:
	var data := _balance()
	var days_per_season := int(LOADER_SCRIPT.get_nested(data, "time.days_per_season"))
	var day_seconds := float(LOADER_SCRIPT.get_nested(data, "time.day_seconds"))
	var c := _new_clock()
	c.speed = 1
	check("starts in spring", c.current_season() == "spring")
	for i in days_per_season:
		c.advance(day_seconds)
	check("after one season -> summer", c.current_season() == "summer")


func _test_clock_pause_and_speed() -> void:
	var data := _balance()
	var day_seconds := float(LOADER_SCRIPT.get_nested(data, "time.day_seconds"))
	var c := _new_clock()
	c.speed = 3
	c.advance(day_seconds)
	check("3x covers 3 days", c.day_index() >= 2)
	var d0: int = c.day_index()
	c.toggle_pause()
	check("toggle -> paused", c.speed == 0)
	c.advance(day_seconds * 100)
	check("paused clock frozen", c.day_index() == d0)
	c.toggle_pause()
	check("toggle resumes to 3x", c.speed == 3)


func _test_winter_shorter_day() -> void:
	var data := _balance()
	var dl: Dictionary = LOADER_SCRIPT.get_nested(data, "time.daylight")
	var summer := float(dl["summer"]["sunset"]) - float(dl["summer"]["sunrise"])
	var winter := float(dl["winter"]["sunset"]) - float(dl["winter"]["sunrise"])
	check("winter day window shorter than summer", winter < summer)


func _test_light_factor_day_night() -> void:
	var c := _new_clock()
	c.set_time(0, 0.5)   # południe wiosną (sunrise 0.25, sunset 0.75)
	check("noon is full daylight", is_equal_approx(c.light_factor(), 1.0))
	c.set_time(0, 0.02)  # głęboka noc
	check("deep night is dark", c.light_factor() < 0.01)


# --- Świat ---

func _people() -> Dictionary:
	return LOADER_SCRIPT.load_json("res://data/people.json")


func _map() -> Dictionary:
	return LOADER_SCRIPT.load_json("res://data/map.json")


func _new_world(seed := 12345) -> RefCounted:
	return WORLD_SCRIPT.new(seed, _balance(), _map(), _people(), LOADER_SCRIPT.load_json("res://data/memories.json"), LOADER_SCRIPT.load_json("res://data/recipes.json"), LOADER_SCRIPT.load_json("res://data/traders.json"))


func _run_days(world, days: float) -> void:
	world.step_sim(days * world.clock.day_seconds)


# Odpowiada na każde pytanie pierwszą opcją (autopilot gracza w testach).
func _run_days_auto(world, days: float) -> void:
	var end: float = world.clock.now() + days
	var guard := 0
	while world.clock.now() < end and not world.family.game_over and guard < 10000:
		guard += 1
		world.step_sim(minf(world.clock.day_seconds * 0.25, (end - world.clock.now()) * world.clock.day_seconds + 0.01))
		while world.events.blocking():
			var p: Dictionary = world.events.prompts[0]
			world.resolve_prompt(int(p["id"]), p["options"][0]["value"])
			if world.family.game_over:
				return


func _test_world_start_family() -> void:
	var w = _new_world()
	check("start family has 6 people", w.family.living().size() == 6)
	check("root set", w.family.root() != null and w.family.root().name == "Jan")
	check("spouse is attached, not blood", w.family.persons[w.family.root().spouse_id].attached)
	var kid_child := false
	for p in w.family.living():
		if p.name == "Kuba":
			kid_child = w.family.stage_of(p) == "child"
	check("Kuba is a child", kid_child)
	check("trees generated", w.trees.size() > 20)


func _test_life_stages_in_days() -> void:
	var w = _new_world()
	var f = w.family
	var stages: Array = w.balance["aging"]["stages"]
	var start := 0.0
	var ok := true
	for st: Dictionary in stages:
		var id := String(st["id"])
		if f.stage_start(id) != start or f.stage_at(start) != id:
			ok = false
		if start > 0.0 and f.stage_at(start - 0.01) == id:
			ok = false
		if absf(f.years_label(start) - float(st["years"][0])) > 0.001:
			ok = false
		start += float(st["days"])
	check("stage boundaries come from data days", ok)
	var adult: Dictionary = stages[2]
	var mid: float = f.stage_start("adult") + float(adult["days"]) * 0.5
	var mid_years: float = (float(adult["years"][0]) + float(adult["years"][1])) * 0.5
	check("age in years interpolated within stage", absf(f.years_label(mid) - mid_years) < 0.001)
	var last: Dictionary = stages[stages.size() - 1]
	check("last stage extrapolates past its days", f.years_label(start + float(last["days"])) > float(last["years"][1]))
	check("start ages read as days", absf(f.age_of(f.root()) - 38.0) < 1.5)


func _test_pregnancy_lasts_data_days() -> void:
	var w = _new_world()
	var f = w.family
	var mother = f.persons[f.root().spouse_id]
	var days := int(w.balance["family"]["pregnancy_days"])
	mother.pregnant_left = float(days)
	var n0: int = f.persons.size()
	for i in days - 1:
		f.new_day()
	var before_term: bool = f.persons.size() == n0 and mother.pregnant_left > 0.0
	f.new_day()
	check("no birth before pregnancy_days", before_term)
	check("birth exactly after pregnancy_days", f.persons.size() == n0 + 1)


func _test_traits_and_character_split() -> void:
	var w = _new_world()
	var f = w.family
	var people: Dictionary = w.people
	var root = f.root()
	check("start traits and character loaded separately", root.traits == ["silny"] and root.character == ["lojalny"])
	var ok := true
	for p in f.living():
		for c in p.character:
			if not people["character"].has(c) or people["traits"].has(c):
				ok = false
		for t in p.traits:
			if not people["traits"].has(t):
				ok = false
	check("character keys never mix with traits", ok)
	# Dziedziczenie: przy pewnej szansie dziecko bierze charakter rodziców, a sprzeczności odpadają.
	people["inheritance"]["character"]["inherit_chance"] = 1.0
	people["inheritance"]["character"]["random_chance"] = 0.0
	people["inheritance"]["traits"]["inherit_chance"] = 1.0
	people["inheritance"]["traits"]["random_chance"] = 0.0
	var kid: Array = f._inherit("character", ["lojalny"], ["porywczy"])
	check("character inherited from both parents", kid.has("lojalny") and kid.has("porywczy"))
	var tr: Array = f._inherit("traits", ["pracowity"], ["leniwy", "kulawy"])
	check("trait conflicts resolved from data, injuries not inherited", tr == ["pracowity"])


func _test_lineage_start() -> void:
	var w = _new_world()
	var f = w.family
	var l = f.player_lineage()
	check("player lineage exists with dynasty name", l != null and l.name == "Wilk")
	var all_in := true
	for p in f.living():
		if p.lineage_id != l.id or not l.has(p.id):
			all_in = false
	check("all starting people belong to player lineage", all_in and l.members.size() == 6)
	check("lineage root is Jan", l.root_id == f.root().id and f.root().name == "Jan")
	f.set_root(f.living()[3].id)
	check("root lives in lineage", l.root_id == f.living()[3].id)


# Świat bez wspomnień startowych, z dorosłymi Janem i Marią (charakter ustawiany w teście).
func _bond_world():
	var w = _new_world()
	w.bonds.bonds.clear()
	return w


func _test_bonds_asymmetric_and_fading() -> void:
	var w = _bond_world()
	var b = w.bonds
	var jan = w.family.root()
	var maria = w.family.persons[jan.spouse_id]
	jan.character = []
	maria.character = []
	var day0: int = w.clock.day_index()
	b.remember(jan.id, SimBonds.person(maria.id), "quarrel", [maria.id])
	b.remember(maria.id, SimBonds.person(jan.id), "worked_together", [jan.id])
	check("bond is directed (asymmetric)", b.value(jan.id, SimBonds.person(maria.id)) < 0.0 and b.value(maria.id, SimBonds.person(jan.id)) > 0.0)
	var fresh: float = b.value(maria.id, SimBonds.person(jan.id))
	b.remember(jan.id, SimBonds.act("chop"), "accident")
	w.clock.set_time(day0 + 10, 0.5)
	var later: float = b.value(maria.id, SimBonds.person(jan.id))
	check("ordinary memories fade toward zero", later > 0.0 and later < fresh * 0.5)
	check("permanent memories never fade", is_equal_approx(b.value(jan.id, SimBonds.act("chop")), float(w.memories["kinds"]["accident"]["weight"])))
	w.clock.set_time(day0 + 200, 0.5)
	b.prune()
	check("faded memories are pruned, permanent kept", b.memories(maria.id, SimBonds.person(jan.id)).is_empty() and b.memories(jan.id, SimBonds.act("chop")).size() == 1)
	check("bond targets listed by prefix", b.targets_of(jan.id, "act:") == ["act:chop"])


func _test_memories_character_mods() -> void:
	var w = _bond_world()
	var b = w.bonds
	var jan = w.family.root()
	var maria = w.family.persons[jan.spouse_id]
	var day0: int = w.clock.day_index()
	jan.character = ["pamietliwy"]
	maria.character = []
	b.remember(jan.id, SimBonds.person(maria.id), "quarrel", [maria.id])
	b.remember(maria.id, SimBonds.person(jan.id), "quarrel", [jan.id])
	w.clock.set_time(day0 + 15, 0.5)
	check("pamiętliwy remembers grudges longer", b.value(jan.id, SimBonds.person(maria.id)) < b.value(maria.id, SimBonds.person(jan.id)))
	jan.character = ["porywczy"]
	var hot: Dictionary = b.remember(jan.id, SimBonds.person(maria.id), "quarrel", [maria.id])
	var calm: Dictionary = b.remember(maria.id, SimBonds.person(jan.id), "quarrel", [jan.id])
	check("porywczy feels a quarrel harder", float(hot["weight"]) < float(calm["weight"]))
	w.clock.set_time(day0, 0.5)
	var kid = null
	for p in w.family.living():
		if w.family.stage_of(p) == "child":
			kid = p
	kid.character = []
	var kid_m: Dictionary = b.remember(kid.id, SimBonds.act("saw"), "did_work")
	var adult_m: Dictionary = b.remember(maria.id, SimBonds.act("saw"), "did_work")
	check("children feel memories more strongly", float(kid_m["weight"]) > float(adult_m["weight"]))


func _test_start_bonds() -> void:
	var w = _new_world()
	var f = w.family
	var ok := true
	var pairs := 0
	for c in f.living():
		for pid in [c.mother_id, c.father_id]:
			if pid < 0:
				continue
			pairs += 1
			if w.bonds.value(c.id, SimBonds.person(pid)) <= 0.0 or w.bonds.value(pid, SimBonds.person(c.id)) <= 0.0:
				ok = false
	check("children and parents start with positive bonds both ways", ok and pairs >= 7)
	var jan = f.root()
	check("spouses start bonded", w.bonds.value(jan.id, SimBonds.person(jan.spouse_id)) > 0.0)
	var piotr = null
	var zofia = null
	for p in f.living():
		if p.name == "Piotr":
			piotr = p
		if p.name == "Zofia":
			zofia = p
	check("siblings start bonded", w.bonds.value(piotr.id, SimBonds.person(zofia.id)) > 0.0)
	var maria = f.persons[jan.spouse_id]
	var gran = f.persons[jan.mother_id]
	check("in-law has no bond from the past", w.bonds.memories(maria.id, SimBonds.person(gran.id)).is_empty())


func _test_together_builds_bonds() -> void:
	var w = _bond_world()
	var f = w.family
	var jan = f.root()
	var piotr = null
	var maria = f.persons[jan.spouse_id]
	for p in f.living():
		if p.name == "Piotr":
			piotr = p
	var aj = w.agent_by_id(jan.agent_id)
	var ap = w.agent_by_id(piotr.agent_id)
	var am = w.agent_by_id(maria.agent_id)
	for a in w.agents:
		a.activity = "idle"
	aj.activity = "saw"
	aj.inside = "sawmill"
	ap.activity = "saw"
	ap.inside = "sawmill"
	am.activity = "craft"
	am.inside = "workshop"
	for i in 200:
		w.together.sample(1.0)
	w.together.end_day()
	var m: Array = w.bonds.memories(piotr.id, SimBonds.person(jan.id))
	check("two at the sawmill gain a bond", w.bonds.value(jan.id, SimBonds.person(piotr.id)) > 0.0 and m.size() == 1)
	check("shared-work memory remembers the place", not m.is_empty() and m[0]["kind"] == "worked_together" and m[0]["at"] == "sawmill")
	check("separated people gain nothing", w.bonds.memories(maria.id, SimBonds.person(jan.id)).is_empty())
	am.inside = ""
	am.position = Vector2(500, 500)
	aj.inside = ""
	aj.activity = "chop"
	for i in 200:
		w.together.sample(1.0)
	w.together.end_day()
	check("far apart outdoors is not together", w.bonds.memories(maria.id, SimBonds.person(jan.id)).is_empty())


func _test_dinner_gathers_family() -> void:
	var w = _new_world()
	var s: Dictionary = w.balance["schedule"]
	# Jedna pełna doba, potem zatrzymanie w środku kolacji następnej.
	_run_days_auto(w, 1.0)
	var mid := (float(s["dinner_start"]) + float(s["dinner_end"])) * 0.5
	var target: float = float(w.clock.day_index()) + mid
	_run_days_auto(w, target - w.clock.now())
	var dining := 0
	var active := 0
	for p in w.family.living():
		var a = w.agent_by_id(p.agent_id)
		if a.status == "active" and not a.disabled():
			active += 1
			if a.activity == "dine":
				dining += 1
	check("family gathers for dinner (%d/%d at the table)" % [dining, active], dining >= active - 1 and dining >= 2)
	w.bonds.bonds.clear()
	_run_days_auto(w, 1.0 - mid + 0.01)
	var jan = w.family.root()
	var had := false
	for m in w.bonds.memories(jan.id, SimBonds.person(jan.spouse_id)):
		if m["kind"] == "meal_together":
			had = true
	check("those at dinner have a shared-meal memory", had)


func _test_activity_bonds_child_and_accident() -> void:
	var w = _new_world()   # z więziami startowymi: Kuba lubi ojca
	var f = w.family
	var jan = f.root()
	var kuba = null
	for p in f.living():
		if p.name == "Kuba":
			kuba = p
	var aj = w.agent_by_id(jan.agent_id)
	var ak = w.agent_by_id(kuba.agent_id)
	for a in w.agents:
		a.activity = "idle"
	aj.activity = "saw"
	aj.inside = "sawmill"
	ak.activity = "watch"
	ak.inside = "sawmill"
	for i in 200:
		w.together.sample(1.0)
	w.together.end_day()
	var saw := SimBonds.act("saw")
	var kinds := []
	for m in w.bonds.memories(kuba.id, saw):
		kinds.append(m["kind"])
	check("child at the sawmill with father likes the sawmill", w.bonds.value(kuba.id, saw) > 0.0 and "work_with_liked" in kinds)
	check("father's own work builds a bond with the work", w.bonds.value(jan.id, saw) > 0.0)
	w.remember_accident(aj, "saw", "severe")
	check("after witnessing an accident the child dislikes the sawmill", w.bonds.value(kuba.id, saw) < 0.0)
	check("victim remembers the accident permanently", w.bonds.value(jan.id, saw) < 0.0)


func _test_drift_never_below_stranger() -> void:
	var w = _new_world()
	var f = w.family
	var jan = f.root()
	var piotr = null
	for p in f.living():
		if p.name == "Piotr":
			piotr = p
	var target := SimBonds.person(jan.id)
	var start: float = w.bonds.value(piotr.id, target)
	var day0: int = w.clock.day_index()
	w.clock.set_time(day0 + 60, 0.5)
	var later: float = w.bonds.value(piotr.id, target)
	check("isolated person's bond drifts toward stranger", later < start * 0.5 and later >= 0.0)
	# Pamiętliwy: kłótnia blaknie wolniej niż wspólna praca, ale bez nowego zdarzenia nie ma wrogości.
	w.bonds.bonds.clear()
	piotr.character = ["pamietliwy"]
	w.clock.set_time(day0, 0.5)
	w.bonds.remember(piotr.id, target, "worked_together", [jan.id], 5.0)
	w.bonds.remember(piotr.id, target, "quarrel", [jan.id])
	var ok := true
	for d in 40:
		w.clock.set_time(day0 + d, 0.5)
		if w.bonds.value(piotr.id, target) < 0.0:
			ok = false
	check("fading never turns a friendly bond hostile", ok)


func _named(f, nm: String):
	for p in f.living():
		if p.name == nm:
			return p
	return null


func _bond(w, a, b, amount: float) -> void:
	w.bonds.remember(a.id, SimBonds.person(b.id), "married", [b.id], amount / float(w.memories["kinds"]["married"]["weight"]))


func _test_strength_scenarios() -> void:
	var w = _new_world()
	var f = w.family
	check("start: root has strength 1, everyone else above zero", is_equal_approx(float(f.strength[f.root_id]), 1.0) and f.strength.values().min() > 0.0)
	var jan = f.root()
	var maria = f.persons[jan.spouse_id]
	var piotr = _named(f, "Piotr")
	var kuba = _named(f, "Kuba")
	var zofia = _named(f, "Zofia")
	# Łańcuch: Kuba trzyma się tylko Piotra, Piotr tylko ojca.
	w.bonds.bonds.clear()
	_bond(w, piotr, jan, 50.0)
	_bond(w, kuba, piotr, 50.0)
	f.update_strength()
	var chain_p: float = f.strength[piotr.id]
	var chain_k: float = f.strength[kuba.id]
	check("chain weakens with distance from root", chain_k < chain_p * 0.9)
	# Gęsta sieć: Kuba lubi ojca, matkę i brata; matka lubi ojca.
	_bond(w, kuba, jan, 50.0)
	_bond(w, kuba, maria, 50.0)
	_bond(w, maria, jan, 50.0)
	f.update_strength()
	check("dense network holds", float(f.strength[kuba.id]) > chain_p)
	check("unbonded member has zero strength", is_zero_approx(float(f.strength[zofia.id])))
	# Brat żony (spoza rodu), choć kocha siostrę, nie wchodzi do rodu.
	var brother := SimPerson.new()
	brother.id = 9999
	brother.name = "Szwagier"
	brother.sex = "m"
	brother.birth_day = maria.birth_day
	f.persons[brother.id] = brother
	_bond(w, brother, maria, 100.0)
	f.update_strength()
	check("spouse does not pull in her family", not f.strength.has(brother.id))


func _test_switch_root() -> void:
	var w = _new_world()
	var f = w.family
	var jan = f.root()
	var maria = f.persons[jan.spouse_id]
	var piotr = _named(f, "Piotr")
	check("attached spouse cannot become root", not w.switch_root(maria.id) and f.root_id == jan.id)
	w.bonds.bonds.clear()
	_bond(w, jan, piotr, 50.0)
	f.update_strength()
	var before: float = f.strength[piotr.id]
	check("switch root to a blood member", w.switch_root(piotr.id) and f.root_id == piotr.id and f.player_lineage().root_id == piotr.id)
	check("strength recomputed from the new root", is_zero_approx(before) and is_equal_approx(float(f.strength[piotr.id]), 1.0) and float(f.strength[jan.id]) > 0.4 and float(f.strength[jan.id]) < 1.0)


func _test_departure_and_ai_life() -> void:
	var w = _new_world(31)
	var f = w.family
	var jan = f.root()
	var piotr = _named(f, "Piotr")
	var zofia = _named(f, "Zofia")
	# Zaniedbany: Piotr nie ma żadnych więzi z bliskimi i nic ich nie odnawia.
	for t in w.bonds.targets_of(piotr.id, "p:"):
		w.bonds.bonds.erase("%d>%s" % [piotr.id, t])
	w.memories["kinds"]["evening_together"]["weight"] = 0.0
	w.memories["kinds"]["meal_together"]["weight"] = 0.0
	w.memories["kinds"]["worked_together"]["weight"] = 0.0
	var leave_days := int(w.balance["belonging"]["leave_days"])
	_run_days_auto(w, float(leave_days) + 1.2)
	var l = f.lineage_of(piotr)
	check("neglected adult leaves the lineage", l.id != f.player_lineage_id and l.root_id == piotr.id and l.members == [piotr.id])
	check("cared-for member stays", zofia.lineage_id == f.player_lineage_id and jan.lineage_id == f.player_lineage_id)
	check("departed is no longer in the family list", not piotr in f.living())
	var ap = w.agent_by_id(piotr.agent_id)
	check("departed sets up own household elsewhere", ap.home_id != "home" and w.household_of(ap) != w.household and piotr.id in w.household_of(ap).members)
	check("departure is in the chronicle", w.chronicle.of_kind("departure").size() == 1 and piotr.id in w.chronicle.of_kind("departure")[0]["who"])
	w.set_job(ap.id, "sawyer")
	check("player can no longer command the departed", ap.job != "sawyer")
	var cash0: float = w.household.cash
	var purse0: float = piotr.purse
	_run_days_auto(w, 3.0)
	check("departed lives on after leaving", piotr.alive() and ap.status == "active")
	check("departed earns into own purse, not family cash", piotr.purse > purse0 or ap.needs["food"] > 0.0)
	var labored := false
	for i in 2000:
		w.step_sim(0.3)
		if ap.activity == "labor":
			labored = true
			break
	check("departed works on own autopilot", labored)


func _test_purse_share_by_strength() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var zofia = _named(f, "Zofia")
	var ap = w.agent_by_id(piotr.agent_id)
	var az = w.agent_by_id(zofia.agent_id)
	f.strength[piotr.id] = 1.0
	f.strength[zofia.id] = 0.25
	var pocket := float(w.balance["purse"]["pocket_money"])
	var c0: float = w.household.cash
	w.earn_for(ap, 10.0)
	check("earnings land in the purse, not the chest far away", is_equal_approx(piotr.purse, 10.0) and is_equal_approx(w.household.cash, c0))
	ap.position = w.home().door()
	w.jobs._return_coins(ap)
	var close_gives: float = w.household.cash - c0
	c0 = w.household.cash
	w.earn_for(az, 10.0)
	az.position = w.home().door()
	w.jobs._return_coins(az)
	var far_gives: float = w.household.cash - c0
	check("close member hands over all but pocket money at home", is_equal_approx(close_gives, 10.0 - pocket) and is_equal_approx(piotr.purse, pocket))
	check("drifting member hands over less and keeps the rest", far_gives < close_gives and is_equal_approx(zofia.purse, 10.0 - far_gives))


func _test_drift_signals() -> void:
	var w = _new_world()
	var f = w.family
	var zofia = _named(f, "Zofia")
	var piotr = _named(f, "Piotr")
	var az = w.agent_by_id(zofia.agent_id)
	var ap = w.agent_by_id(piotr.agent_id)
	var leave := float(w.balance["belonging"]["leave_below"])
	var aloof_days := 0
	var close_aloof := 0
	for d in 20:
		w.clock.set_time(d, 0.5)
		f.strength[zofia.id] = leave + 0.01
		f.strength[piotr.id] = 1.0
		if w.jobs.aloof_today(az):
			aloof_days += 1
		if w.jobs.aloof_today(ap):
			close_aloof += 1
	check("weak member often avoids family evenings (%d/20)" % aloof_days, aloof_days >= 12)
	check("close member never does", close_aloof == 0)
	w.jobs._plan_aloof(az)
	var why := String(az.steps[az.steps.size() - 1]["why"])
	check("aloof reason is descriptive, no numbers", why != "" and not why.contains("0.") and not why.contains("%"))


func _test_preferences_from_memories() -> void:
	var w = _bond_world()
	var piotr = _named(w.family, "Piotr")
	piotr.character = []
	check("no memories, no preferences", w.bonds.preferences(piotr.id).is_empty())
	w.bonds.remember(piotr.id, SimBonds.act("saw"), "did_work")
	w.bonds.remember(piotr.id, SimBonds.act("chop"), "accident")
	var prefs: Array = w.bonds.preferences(piotr.id)
	check("preference follows memories", prefs[0]["act"] == "saw" and prefs[prefs.size() - 1]["act"] == "chop" and float(prefs[prefs.size() - 1]["value"]) < 0.0)
	check("preference says where it came from", String(prefs[prefs.size() - 1]["from"][0]).contains("wypadek"))
	piotr.character = ["ambitny"]
	var craft: float = w.bonds.preference(piotr.id, "craft")
	check("character tilts preferences", craft > 0.0)


func _test_reluctance_and_orders() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var ap = w.agent_by_id(piotr.agent_id)
	var willing: float = w.jobs.willingness(ap, "chop")
	var eff0: float = w.jobs.efficiency(ap, "chop")
	w.bonds.remember(piotr.id, SimBonds.act("chop"), "accident")
	check("disliked work: less willing and slower", w.jobs.willingness(ap, "chop") < willing and w.jobs.efficiency(ap, "chop") < eff0)
	var root_bond: float = w.bonds.value(piotr.id, SimBonds.person(f.root_id))
	w.set_job(ap.id, "woodcutter")
	var marked := false
	for m in w.bonds.memories(piotr.id, SimBonds.person(f.root_id)):
		if m["kind"] == "ordered_against_will":
			marked = true
	check("order against will leaves a memory toward the root", marked and w.bonds.value(piotr.id, SimBonds.person(f.root_id)) < root_bond)
	var s := { "t": "act", "act": "chop", "left": 10.0, "why": "rąbie drzewo" }
	w._check_will(ap, s, "chop")
	check("reluctant work has a descriptive reason", String(s["why"]).contains("niechętnie") or String(s["why"]).contains("rzuci"))


func _test_child_follows_adult() -> void:
	var w = _new_world()
	var f = w.family
	var jan = f.root()
	var kuba = _named(f, "Kuba")
	var aj = w.agent_by_id(jan.agent_id)
	var ak = w.agent_by_id(kuba.agent_id)
	var maria = f.persons[jan.spouse_id]
	w.set_job(aj.id, "sawyer")
	# Własna sympatia: Kuba bardziej lubi matkę, ale gracz każe mu iść z ojcem.
	w.bonds.remember(kuba.id, SimBonds.person(maria.id), "married", [maria.id], 2.0)
	w.set_follow(ak.id, jan.id)
	var s: Dictionary = w.balance["schedule"]
	var mid := (float(s["work_start"]) + float(s["work_end"])) * 0.5
	_run_days_auto(w, mid - w.clock.time_of_day())
	var near: bool = (ak.inside != "" and ak.inside == aj.inside) or ak.position.distance_to(aj.position) < 4.0
	check("child with override goes with father (%s / %s)" % [ak.idle_reason, aj.idle_reason], ak.activity in ["watch", "walk"] and near)
	check("child follows the father, not the more liked mother", ak.idle_reason.contains(jan.name))


func _ai_specs() -> Array:
	return [
		{ "key": "f", "name": "Bartłomiej", "sex": "m", "age_days": 40.0, "root": true, "job": "laborer" },
		{ "key": "m", "name": "Dorota", "sex": "f", "age_days": 36.0, "spouse": "f", "attached": true, "surname": "Sowa", "job": "laborer" },
		{ "key": "s", "name": "Szymon", "sex": "m", "age_days": 18.0, "mother": "m", "father": "f", "job": "laborer" },
	]


func _test_ai_lineage_lives_independently() -> void:
	var w = _new_world()
	var f = w.family
	var l = f.new_lineage("Kos")
	var ids: Array = f.spawn_family(_ai_specs(), l, w.building("n1"))
	check("AI lineage spawned with root and surname", l.root_id == ids[0] and f.persons[ids[2]].surname == "Kos" and f.persons[ids[1]].surname == "Sowa")
	check("AI people are not the player's family", f.living().size() == 6 and f.living_members(l.id).size() == 3)
	check("AI parents and child start bonded", w.bonds.value(ids[2], SimBonds.person(ids[0])) > 0.0)
	var prompts0: int = w.events.prompts.size()
	w.kill(w.agent_by_id(f.persons[ids[0]].agent_id), "zmarł")
	check("AI root death picks successor without asking the player", l.root_id == ids[2] and w.events.prompts.size() == prompts0)
	check("player game goes on", not f.game_over and f.root().name == "Jan")
	_run_days_auto(w, 2.0)
	check("AI lineage lives on", f.persons[ids[2]].alive() and f.persons[ids[2]].lineage_id == l.id)


func _test_households_separate() -> void:
	var w = _new_world()
	var f = w.family
	var l = f.new_lineage("Kos")
	var ids: Array = f.spawn_family(_ai_specs(), l, w.building("n1"))
	var hb = w.new_household("n1", 30.0)
	for id in ids:
		w.join_household(f.persons[id], hb)
	check("each family has its own household and home", w.household_of(w.agent_by_id(f.root().agent_id)) == w.household
		and w.household_of(w.agent_by_id(f.persons[ids[0]].agent_id)) == hb and w.agent_by_id(f.persons[ids[2]].agent_id).home_id == "n1")
	var buyer = w.agent_by_id(f.persons[ids[2]].agent_id)
	var cash_a: float = w.household.cash
	var food_b: int = w.building("n1").amount("food")
	buyer.position = w.building("n1").door()
	w.jobs._fx_take_coins(buyer, 10.0)
	w.jobs._fx_buy_food(buyer, 3)
	buyer.position = w.building("n1").door()
	w.jobs._fx_deposit(buyer, "n1")
	check("purchase paid from own household, stored in own home", hb.cash < 30.0 and is_equal_approx(w.household.cash, cash_a) and w.building("n1").amount("food") == food_b + 3)
	var kids := 0
	for p in f.living():
		if p.household_id == w.household.id:
			kids += 1
	check("player's people are members of the player household", kids == f.living().size())


func _test_rent_eviction_homeless() -> void:
	var w = _new_world()
	var f = w.family
	var home = w.home()
	var l = f.new_lineage("Kos")
	var ids: Array = f.spawn_family(_ai_specs(), l, w.building("n1"))
	var landlord = f.persons[ids[0]]
	home.owner_kind = "person"
	home.owner_id = landlord.id
	var purse0: float = landlord.purse
	var cash0: float = w.household.cash
	w._settle_rent(w.household)
	check("daily rent goes to the owner's purse", is_equal_approx(landlord.purse - purse0, home.rent_per_day) and is_equal_approx(cash0 - w.household.cash, home.rent_per_day))
	# Bankructwo: brak pieniędzy, dług rośnie, po kilku dobach eksmisja.
	w.household.cash = 0.0
	for b in w.buildings.values():
		if b.type in ["home", "decor_house"] and b != home:
			b.type = "decor_town"   # brak wolnych domów
	for i in 30:
		w._settle_rent(w.household)
	check("unpaid rent turns into debt and eviction", w.household.home_id == "" and w.household.debt > 0.0)
	check("eviction is not game over", not f.game_over)
	var a = w.agent_by_id(f.root().agent_id)
	check("evicted family is homeless (no home building)", w.home_of(a) == null)
	w.clock.set_time(w.clock.day_index(), 0.95)
	w.jobs.replan(a)
	var last: Dictionary = a.steps[a.steps.size() - 1]
	check("homeless sleeps outdoors with a reason", String(last.get("act", "")) == "sleep" and String(last["why"]).contains("gołym niebem"))
	w.household.cash = 100.0
	w.buildings["n2"].type = "decor_house"
	w._settle_rent(w.household)
	check("with money the family rents a free house again", w.household.home_id != "" and a.home_id == w.household.home_id)


func _test_recipe_from_data() -> void:
	var w = _new_world()
	check("saw and craft come from recipes", w.jobs.recipe_for_job("sawyer").get("act") == "saw" and w.jobs.recipe_for_job("carpenter").get("act") == "craft")
	# Nowa receptura tylko w danych: „łupanie” kłody na dwie deski w tartaku.
	var r := { "job": "splitter", "building": "sawmill", "act": "split", "skill": "saw", "seconds": 5.0,
		"inputs": { "log": 1 }, "outputs": { "plank": 1 }, "spot": [0.0, 1.0], "doing": "łupie kłodę",
		"accident_where": "przy łupaniu", "wait_input": "czeka na kłody", "full": "pełno" }
	w.jobs.recipes["split"] = r
	var a = w.agent_by_id(_named(w.family, "Piotr").agent_id)
	var mill = w.building("sawmill")
	mill.add("log", 2)
	var planks: int = mill.amount("plank")
	a.job = "splitter"
	w.jobs.replan(a)
	var acts: Array = a.steps.filter(func(s): return s["t"] == "act").map(func(s): return s["act"])
	check("a recipe added only in data is planned", "split" in acts)
	check("and it produces its outputs", w.jobs._fx_produce(a, r) and mill.amount("plank") == planks + 1)


func _test_society_from_data() -> void:
	var w = _new_world()
	var f = w.family
	var specs: Array = w.people["ai_lineages"]
	check("all AI lineages spawned", f.lineages.size() == specs.size() + 1)
	var ok := true
	for spec in specs:
		var l = null
		for x in f.lineages.values():
			if x.name == spec["name"]:
				l = x
		if l == null or f.living_members(l.id).size() != (spec["members"] as Array).size() or l.root_id < 0:
			ok = false
			continue
		for p in f.living_members(l.id):
			var a = w.agent_by_id(p.agent_id)
			if a == null or a.home_id != spec["home"] or w.household_of(a) == w.household:
				ok = false
	check("each AI family has members, root, its own home and household", ok)
	check("player's home is owned by the manor lineage", w.home().owner_kind == "lineage" and f.lineages[w.home().owner_id].name == "Dworscy")
	check("player family list still shows only the player's lineage", f.living().size() == 6)
	check("merchant lineage found by role", w.lineage_by_role("merchant") != null and w.lineage_by_role("merchant").name == "Bednarz")


func _test_ai_households_live() -> void:
	var w = _new_world(77)
	var cash0 := {}
	for h in w.households.values():
		cash0[h.id] = h.cash
	_run_days_auto(w, 8.0)
	var alive := true
	var fed := true
	var worked := false
	var bought := false
	for h in w.households.values():
		if h == w.household:
			continue
		for pid in h.members:
			var p = w.family.persons[pid]
			var a = w.agent_by_id(p.agent_id)
			if not p.alive() and (p.death_cause.contains("głodu") or p.death_cause.contains("zamarzł")):
				alive = false
			elif a.needs["food"] < 5.0:
				fed = false
			if a.job in ["laborer", "forager"]:
				worked = true
		if h.cash < float(cash0.get(h.id, 0.0)) - 0.5:
			bought = true
	check("AI families do not die of hunger or cold in 8 days", alive)
	check("AI families are not starving", fed)
	check("AI adults are assigned work by the AI", worked)
	check("AI households spend their own money", bought)


func _test_bonds_across_lineages() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var jagna = null
	for p in f.all_living():
		if p.name == "Jagna":
			jagna = p
	var ap = w.agent_by_id(piotr.agent_id)
	var aj = w.agent_by_id(jagna.agent_id)
	for a in w.agents:
		a.activity = "idle"
	ap.activity = "saw"
	ap.inside = "sawmill"
	aj.activity = "saw"
	aj.inside = "sawmill"
	for i in 200:
		w.together.sample(1.0)
	w.together.end_day()
	check("neighbours working together build a bond", w.bonds.value(piotr.id, SimBonds.person(jagna.id)) > 0.0 and w.bonds.value(jagna.id, SimBonds.person(piotr.id)) > 0.0)
	f.update_strength()
	var kos = f.lineage_of(jagna)
	check("friendship does not change lineage", piotr.lineage_id == f.player_lineage_id and jagna.lineage_id == kos.id)
	check("strength computed per lineage from its own root", is_equal_approx(float(f.strength[kos.root_id]), 1.0) and float(f.strength[jagna.id]) > 0.0 and is_equal_approx(float(f.strength[f.root_id]), 1.0))


func _test_marriage_with_existing_people() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var max_id: int = f.persons.keys().max()
	f.set_seeking(piotr.id, true)
	var asked := {}
	for i in 1500:
		w.step_sim(5.0)
		if w.events.blocking() and w.events.prompts[0]["kind"] == "marriage":
			asked = w.events.prompts[0]
			break
		while w.events.blocking():
			w.resolve_prompt(int(w.events.prompts[0]["id"]), w.events.prompts[0]["options"][0]["value"])
	check("proposal names an existing person from another lineage", not asked.is_empty() and f.persons.has(int(asked["data"]["cand"]))
		and f.persons[int(asked["data"]["cand"])].lineage_id != f.player_lineage_id)
	if asked.is_empty():
		return
	var bride = f.persons[int(asked["data"]["cand"])]
	w.resolve_prompt(int(asked["id"]), "yes")
	check("wedding joins two existing people, nobody materialises", piotr.spouse_id == bride.id and bride.id <= max_id)
	check("bride joins the groom's lineage and household", bride.lineage_id == f.player_lineage_id and bride.attached
		and bride.household_id == w.household.id and bride.surname == "Wilk")
	# Córka wychodzi za mąż do innego rodu.
	var zofia = _named(f, "Zofia")
	zofia.birth_day -= 4.0
	var grzegorz = null
	for p in f.all_living():
		if p.name == "Grzegorz" and p.surname == "Sowa":
			grzegorz = p
	f.marry(zofia, grzegorz)
	check("daughter moves to her husband's lineage and home", zofia.lineage_id == grzegorz.lineage_id and w.agent_by_id(zofia.agent_id).home_id == "n2" and not zofia in f.living())
	var gran = f.persons[f.root().mother_id]
	check("no fitting candidates, no wedding", f.marriage_candidates(gran).is_empty())


func _test_merchant_is_a_person() -> void:
	var w = _new_world()
	var mk = w.market
	check("merchant is a person from the merchant lineage", mk.merchant() != null and mk.merchant().surname == "Bednarz" and mk.till() != w.household)
	var p0: float = mk.buy_price("plank")
	mk.building.add("plank", 40)
	check("price drops as the merchant's stock grows", mk.buy_price("plank") < p0)
	var till = mk.till()
	var seller = w.household
	var cash0: float = seller.cash
	var till0: float = till.cash
	var r: Dictionary = mk.buy_from(seller, "plank", 2, [])
	check("merchant pays from his own till", int(r["qty"]) == 2 and is_equal_approx(seller.cash - cash0, till0 - till.cash))
	till.cash = 0.0
	r = mk.buy_from(seller, "plank", 2, [])
	check("merchant without money buys nothing", int(r["qty"]) == 0)
	till.cash = 1000.0
	mk.building.add("plank", 200)
	check("merchant with a full store wants no more", mk.wants("plank") == 0 and int(mk.buy_from(seller, "plank", 1, [])["qty"]) == 0)


func _money(w) -> float:
	var s := 0.0
	for h in w.households.values():
		s += h.cash
	for p in w.family.persons.values():
		s += p.purse
	return s


# K1 (S14): kasa gospodarstwa leży w skrzyni w domu; przeprowadzka zabiera skrzynię,
# eksmisja zostawia tobołek; dwa gospodarstwa pod jednym dachem mają osobne skrzynie.
func _test_money_in_chest() -> void:
	var w = _new_world()
	var h = w.household
	var home = w.home()
	var m0: float = _money(w)
	check("household cash lies in the home chest", h.chest == home and is_equal_approx(float(home.chests[h.id]), h.cash))
	h.cash -= 10.0
	check("spending from household empties the chest", is_equal_approx(float(home.chests[h.id]), h.cash))
	var cash: float = h.cash
	w.evict(h)
	check("evicted household carries money in a bundle", h.chest == null and is_equal_approx(h.cash, cash) and not home.chests.has(h.id))
	var free = w.free_house()
	w.move_household(h, free)
	check("moving in puts the chest in the new house", h.chest == free and is_equal_approx(float(free.chests[h.id]), cash))
	var other = w.new_household(free.id, 5.0)
	check("two households under one roof keep separate chests", is_equal_approx(other.cash, 5.0) and is_equal_approx(h.cash, cash))
	check("money is conserved by moving chests", absf(_money(w) - 5.0 - (m0 - 10.0)) < 0.001)


# K2: zakup idzie przez sakwę — kto ma w niej za mało, najpierw zagląda do skrzyni w domu;
# reszta ponad kieszonkowe wraca do skrzyni po powrocie.
func _test_buy_through_purse() -> void:
	var w = _new_world()
	var root = w.family.root()
	var a = w.agent_by_id(root.agent_id)
	var h = w.household
	root.purse = 0.0
	a.position = w.building("market").door()
	check("away from home: no money in purse, no purchase", not w.jobs._fx_take_coins(a, 10.0) and not w.jobs._fx_buy_food(a, 1))
	w.home().take("food", 9999)
	a.job = "none"
	w.jobs.release(a)
	w.jobs._food_trip(a, true)
	var first_walk: Vector2 = a.steps[0]["to"]
	check("food trip starts at the chest at home", first_walk.distance_to(w.home().door()) < 0.01
		and a.steps.any(func(s): return s["t"] == "do" and s["fn"] == "take_coins"))
	var chest0: float = h.cash
	a.position = w.home().door()
	w.jobs._fx_take_coins(a, 12.0)
	check("coins move from chest to purse", is_equal_approx(root.purse, 12.0) and is_equal_approx(h.cash, chest0 - 12.0))
	a.position = w.building("market").door()
	w.jobs._fx_buy_food(a, 2)
	a.position = w.home().door()
	w.jobs._fx_deposit(a, w.home().id)
	var pocket := float(w.balance["purse"]["pocket_money"])
	check("change above pocket money goes back to the chest", is_equal_approx(root.purse, pocket) and h.cash > chest0 - 12.0)


func _test_buyers_pay_from_own_money() -> void:
	var w = _new_world()
	var mk = w.market
	var buyer = w.agent_by_id(w.family.root().agent_id)
	var m0: float = _money(w)
	buyer.position = w.home().door()
	w.jobs._fx_take_coins(buyer, 10.0)
	w.jobs._fx_buy_food(buyer, 3)
	mk.buy_from(w.household, "plank", 2, [])
	check("trade between people only moves money (sum unchanged)", absf(_money(w) - m0) < 0.001)
	w.family.root().purse = 0.0
	buyer.clear_carry()
	check("person with an empty purse buys nothing, even with a full chest", not w.jobs._fx_buy_food(buyer, 1))
	w.family.root().purse = 100.0
	mk.building.take("food", 9999)
	check("merchant without stock sells nothing", not w.jobs._fx_buy_food(buyer, 1))
	w.jobs.replan(buyer)
	buyer.needs["food"] = 1.0
	w.building("home").take("food", 9999)
	w.jobs.replan(buyer)
	var why := String(buyer.steps[buyer.steps.size() - 1].get("why", ""))
	check("hungry person explains the market is empty", why.contains("na targu nie ma jedzenia") or buyer.plan_kind == "eat")


func _test_traveling_traders() -> void:
	var w = _new_world()
	var tr = w.traders
	var origin: Dictionary = (tr._cfg["origins"] as Array)[0]
	var v: Dictionary = tr.arrive(origin)
	var trader = w.family.persons[int(v["person"])]
	check("trader is a named person from a real place", trader.name == String(origin["trader"]["name"]) and v["origin_name"] == origin["name"])
	check("trader wants planks", tr.wants("plank") > 0)
	var cash0: float = w.household.cash
	var r: Dictionary = tr.sell_to_wagon(w.household, "plank", 3, [])
	check("delivered goods are paid from the trader's cash", int(r["qty"]) == 3 and w.household.cash > cash0)
	check("trader can't be married off", not w.family.can_marry(trader))
	# Odjazd: oferta przepada.
	w.clock.set_time(w.clock.day_index(), minf(0.99, w.clock.time_of_day() + float(tr._cfg["stay"]) + 0.01))
	tr.tick()
	var a = w.agent_by_id(trader.agent_id)
	for i in 400:
		if a.status == "away":
			break
		w.step_sim(1.0)
	check("missed offer expires when the wagon leaves", a.status == "away" and tr.wants("plank") == 0)


func _test_estate_pays_wages() -> void:
	var w = _new_world()
	var est = w.estate_owner()
	check("the manor household is the employer", est != null and w.family.persons[est.members[0]].surname == "Dworski")
	var a = w.agent_by_id(_named(w.family, "Piotr").agent_id)
	var s := { "t": "act", "act": "labor", "left": 100.0, "why": "dniówka", "will": 1.0 }
	var est0: float = est.cash
	var hh0: float = w.household.cash + w.family.persons[a.person_id].purse
	var food0: int = w.building("manor").amount("food")
	for i in 60:
		w._labor(a, s, 1.0)
	var paid: float = est0 - est.cash
	check("wage is paid from the employer's cash to the worker", paid > 0.0 and is_equal_approx(w.household.cash + w.family.persons[a.person_id].purse - hh0, paid))
	check("estate work yields food for the manor", w.building("manor").amount("food") > food0)
	est.cash = 0.0
	s["left"] = 100.0
	w._labor(a, s, 1.0)
	check("employer without money stops paying and sends people home", float(s["left"]) <= 0.0)


func _state_sig(w) -> String:
	var parts: Array = ["%.3f" % w.household.cash, str(w.building("sawmill").stock)]
	for a in w.agents:
		parts.append("%d:%.2f,%.2f:%s" % [a.id, a.position.x, a.position.y, a.activity])
	return "|".join(parts)


func _test_world_deterministic() -> void:
	var a = _new_world(777)
	var b = _new_world(777)
	_run_days_auto(a, 6.0)
	_run_days_auto(b, 6.0)
	check("same seed + same inputs -> same state after 6 days", _state_sig(a) == _state_sig(b))


func _test_world_30_days_autonomous() -> void:
	var w = _new_world()
	var ok_reason := true
	var ok_steps := true
	var max_still := 0.0
	var still := {}
	var last := {}
	var end: float = w.clock.now() + 30.0
	while w.clock.now() < end and not w.family.game_over:
		w.step_sim(1.0)
		while w.events.blocking():
			var p: Dictionary = w.events.prompts[0]
			w.resolve_prompt(int(p["id"]), p["options"][0]["value"])
		for a in w.agents:
			if a.status != "active":
				continue
			if String(a.idle_reason) == "":
				ok_reason = false
			# Agent stojący w miejscu poza czynnością = zakleszczenie.
			var moved: bool = not last.has(a.id) or (last[a.id] as Vector2).distance_to(a.position) > 0.01
			last[a.id] = a.position
			if moved or a.activity != "walk":
				still[a.id] = 0.0
			else:
				still[a.id] = float(still.get(a.id, 0.0)) + 1.0
				max_still = maxf(max_still, still[a.id])
	check("30 days: every active agent always has idle_reason", ok_reason)
	check("30 days: nobody stuck walking in place", max_still < 3.0)
	check("30 days: no orphan goods (planks sold or used)", int(w.stats.get("sold_plank", 0)) + int(w.stats.get("sold_chair", 0)) > 0)


func _test_economy_chain_produces_income() -> void:
	var w = _new_world()
	_run_days_auto(w, 5.0)
	check("woodcutter -> sawmill -> market sells planks", int(w.stats.get("sold_plank", 0)) > 0)
	check("household pays daily rent without debt", w.household.debt == 0.0)


func _test_no_income_goes_into_debt() -> void:
	var w = _new_world()
	for a in w.agents:
		a.job = "none"
	_run_days_auto(w, 16.0)
	check("family without income falls into debt", w.household.debt > 0.0 or w.stats.has("jailed"))


func _test_succession_and_game_over() -> void:
	var w = _new_world()
	var root = w.family.root()
	w.kill(w.agent_by_id(root.agent_id), "test")
	check("root death asks for successor", w.events.prompts.size() > 0 and w.events.prompts[-1]["kind"] == "succession")
	var p: Dictionary = w.events.prompts[-1]
	var spouse_offered := false
	for o in p["options"]:
		if int(o["value"]) == root.spouse_id:
			spouse_offered = true
	check("spouse is never a succession candidate", not spouse_offered)
	w.resolve_prompt(int(p["id"]), p["options"][0]["value"])
	check("new root chosen (adult blood first)", w.family.root() != null and w.family.root().name == "Piotr")
	for q in w.family.living():
		if q.blood:
			w.kill(w.agent_by_id(q.agent_id), "test")
	check("extinct bloodline -> game over", w.family.game_over)
	check("attached spouse alive but game still over", w.family.living().size() >= 1)


func _test_marriage_and_birth() -> void:
	var w = _new_world()
	var piotr = null
	for p in w.family.living():
		if p.name == "Piotr":
			piotr = p
	w.family.set_seeking(piotr.id, true)
	_run_days_auto(w, 25.0)
	check("seeking adult eventually marries", not piotr.unions.is_empty())
	for p in w.family.living():
		if w.family.can_marry(p):
			w.family.set_seeking(p.id, true)
	_run_days_auto(w, 15.0)
	# Dziecko pary, która pobrała się w trakcie gry (matka nie jest z rodziny startowej).
	var start_ids: Array = [1, 2, 3, 4, 5, 6]
	var born := false
	for e in w.chronicle.of_kind("birth"):
		if int(e["lineage"]) == w.family.player_lineage_id and not int(e["who"][1]) in start_ids:
			born = true
	check("married couples have children", born)
	var in_lineage := true
	var departed := []
	for e in w.chronicle.of_kind("departure"):
		if int(e["lineage"]) == w.family.player_lineage_id:
			departed.append_array(e["who"])
	var pl: int = w.family.player_lineage_id
	for p in w.family.persons.values():
		# Kto wżenił się w ród gracza albo urodził się jego członkowi, musi w nim być
		# (chyba że odszedł albo sam(a) wyszedł/wyszła za mąż do innego rodu).
		var married_out: bool = p.attached and p.spouse_id >= 0 and w.family.persons[p.spouse_id].lineage_id != pl
		var joined: bool = (p.attached and p.spouse_id >= 0 and w.family.persons[p.spouse_id].lineage_id == pl) \
			or (p.mother_id >= 0 and w.family.persons[p.mother_id].lineage_id == pl and not married_out)
		if joined and p.lineage_id != pl and not p.id in departed:
			in_lineage = false
	check("spouses and newborns join player lineage", in_lineage)


func _test_manual_queue_auto_release() -> void:
	var w = _new_world()
	_run_days(w, 0.1)   # rano, blok pracy
	var a = w.agent_by_id(w.family.root().agent_id)
	var home: Vector2 = w.home().door()
	w.manual_move(a.id, home + Vector2(5, 0))
	w.manual_move(a.id, home + Vector2(5, 5), true)
	check("shift-queue appends orders", a.controlled and a.steps.size() == 2)
	var guard := 0
	while a.controlled and guard < 600:
		w.step_sim(0.1)
		guard += 1
	check("agent returns to autopilot after manual queue", not a.controlled)
	check("after release agent resumes its job plan", a.plan_kind != "manual" and not a.steps.is_empty())
	w.manual_move(a.id, home + Vector2(20, 0))
	w.manual_move(a.id, home + Vector2(-20, 0))
	check("plain order replaces queue", a.steps.size() == 1)


func _test_long_run_no_crash() -> void:
	var w = _new_world(4242)
	# Autopilot gracza: każdy dorosły bez pary szuka małżonka, dorastający dostają pracę.
	var days := 0
	while days < 30 and not w.family.game_over:
		for p in w.family.living():
			if w.family.can_marry(p) and not p.seeking_spouse:
				w.family.set_seeking(p.id, true)
			var a = w.agent_by_id(p.agent_id)
			if a != null and a.job == "none" and a.can_work() and not p.attached:
				a.job = "laborer"
		_run_days_auto(w, 1.0)
		days += 1
	var gen: int = w.stats.get("max_generation", 0)
	print("  long run: days=%d alive=%d persons=%d gen=%d cash=%d debt=%d over=%s" % [
		days, w.family.living().size(), w.family.persons.size(), gen, int(w.household.cash), int(w.household.debt), w.family.game_over])
	check("30 days of family life simulated without crash", days >= 1)
	var ages_ok := true
	for p in w.family.living():
		if w.family.age_of(p) < 0.0 or w.family.age_of(p) > 120.0:
			ages_ok = false
	check("ages within sane range", ages_ok)
