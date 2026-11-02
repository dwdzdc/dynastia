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
	_test_talk_and_romance()
	_test_stall_trade()
	_test_field_cycle()
	_test_money_in_chest()
	_test_buy_through_purse()
	_test_buyers_pay_from_own_money()
	_test_traveling_traders()
	_test_estate_pays_wages()
	_test_field_work()
	_test_assign_by_place()
	_test_ai_visible_by_day()
	_test_overseer()
	_test_housing_orders()
	_test_construction()
	_test_build_catalog()
	_test_money_invariant()
	_test_needs_tiers()
	_test_wear_and_repair()
	_test_prices_from_stock()
	_test_enterprises()
	_test_ai_runs_enterprise()
	_test_ai_founds_enterprise()
	_test_land_owners()
	_test_towns()
	_test_trip_to_town()
	_test_theft_process()
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
		if w.jobs.is_work(ap.activity):
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
	var st = _stall_ready(w, "stall_bednarz")
	buyer.position = st.counter()
	w.jobs._fx_buy_at(buyer, { "stall": st.id, "good": "food", "qty": 3, "to": "n1" })
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
	check("no automatic rehousing for the player (O1)", w.household.home_id == "")
	var fh = w.free_house()
	check("with money the family rents a free house by order", w.rent_house(fh.id) and a.home_id == w.household.home_id)


func _test_recipe_from_data() -> void:
	var w = _new_world()
	check("saw and craft come from recipes", w.jobs.recipe_for_job("sawyer").get("act") == "saw" and w.jobs.recipe_for_job("carpenter").get("act") == "craft")
	# Nowa receptura tylko w danych: „łupanie” kłody na dwie deski w tartaku.
	var r := { "job": "splitter", "type": "sawmill", "act": "split", "skill": "saw", "seconds": 5.0,
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
	check("and it produces its outputs", w.jobs._fx_produce(a, { "r": r, "b": mill.id }) and mill.amount("plank") == planks + 1)


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
			elif a.status == "active" and a.needs["food"] < 5.0:
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


func _fall_in_love(w, p, q) -> void:
	for i in 12:
		w.bonds.remember(p.id, SimBonds.love(q.id), "courted", [q.id])
		w.bonds.remember(q.id, SimBonds.love(p.id), "courted", [p.id])


# N1–N5: rozmowa daje więź tylko rozmówcom; obcy stojący obok nie zyskują nic;
# zakochanie rośnie z rozmów; mezalians wymaga zgody wyżej stojącego rodu.
func _test_talk_and_romance() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	var other = f.marriage_candidates(piotr)[0]
	var b = w.agent_by_id(other.agent_id)
	check("strangers do not know each other", w.bonds.value(piotr.id, SimBonds.person(other.id)) == 0.0)
	for x in [a, b]:
		x.steps.clear()
		x.controlled = false
		x.activity = "rest"
		x.inside = ""
		x.hidden = false
	a.position = Vector2(60, 40)
	b.position = Vector2(61, 40)
	w.talk.sample(99.0)
	check("two free people next to each other start talking", a.steps.size() > 0 and a.steps[0].get("act") == "talk" and b.steps[0].get("act") == "talk")
	w.talk.done(a, other.id)
	check("talk leaves a memory of the other person", w.bonds.value(piotr.id, SimBonds.person(other.id)) > 0.0)
	w.bonds.remember(piotr.id, SimBonds.love(other.id), "caught_eye", [other.id])
	var l0: float = f.love(piotr, other)
	f.after_talk(piotr, other, 1.0)
	check("in love: each talk deepens it (courting)", f.love(piotr, other) > l0)
	_fall_in_love(w, piotr, other)
	check("in love: free time goes where the beloved is", f.beloved(piotr) == other.id)
	# Mezalians: wyżej stojący ród AI zwykle się nie zgadza.
	var q2 = null
	for p in f.all_living():
		if p.sex != other.sex and p.lineage_id != other.lineage_id and f.can_marry(p) and not f.is_ours(p) and f.could_court(other, p):
			q2 = p
	if q2 != null:
		var rich = f.lineage_of(other)
		w.balance["romance"]["mesalliance_gap"] = 0.0001
		w.balance["romance"]["consent_max"] = 0.0
		w.balance["romance"]["consent_min"] = 0.0
		_fall_in_love(w, other, q2)
		f._families_talk(other, q2)
		check("mesalliance: the higher family refuses", other.spouse_id < 0 and q2.spouse_id < 0)


func _test_marriage_with_existing_people() -> void:
	var w = _new_world()
	var f = w.family
	var piotr = _named(f, "Piotr")
	var max_id: int = f.persons.keys().max()
	# Romans (N3–N5): dwoje zakochanych w sobie nawzajem — rodziny siadają do rozmowy.
	var cand = f.marriage_candidates(piotr)[0]
	_fall_in_love(w, piotr, cand)
	f._check_courtships()
	var asked := {}
	if w.events.blocking() and w.events.prompts[0]["kind"] == "marriage":
		asked = w.events.prompts[0]
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


# Stragan z kramarzem za ladą (pomocnik testów): ktoś z gospodarstwa właściciela stoi
# przy ladzie z pieniędzmi w sakwie.
func _stall_ready(w, id: String):
	var st = w.trade.stalls[id]
	var h = w.households[st.owner]
	var ka = w.agent_by_id(w.family.persons[h.members[0]].agent_id)
	ka.position = st.building.position
	ka.steps.clear()
	w.jobs._fx_open_stall(ka, id)
	w.person_of(ka).purse = 200.0
	return st


# M1–M5 (S16): handel przy ladzie. Bez kramarza nie ma handlu; cena wychodzi między
# granicami obu stron; bez porozumienia brak transakcji; pieniądze z sakwy do sakwy.
func _test_stall_trade() -> void:
	var w = _new_world()
	var st = w.trade.stalls["stall_bednarz"]
	var buyer = w.agent_by_id(w.family.root().agent_id)
	var bp = w.family.root()
	bp.purse = 50.0
	buyer.position = st.counter()
	st.keeper = -1
	st.packed = true
	check("nobody behind the counter: no sale", int(w.trade.sell_to(st, buyer, "food", 2)["qty"]) == 0)
	_stall_ready(w, "stall_bednarz")
	var oh = w.households[st.owner]
	var m0: float = _money(w)
	var r: Dictionary = w.trade.sell_to(st, buyer, "food", 2)
	var unit: float = float(r["paid"]) / 2.0
	check("sale at the counter, price between both limits", int(r["qty"]) == 2
		and unit >= w.trade.sell_min(oh, "food") - 0.001 and unit <= w.trade.buy_max(w.household, "food") + 0.001)
	check("trade only moves money between people", absf(_money(w) - m0) < 0.001)
	buyer.position = w.home().door()
	check("buyer away from the counter buys nothing", int(w.trade.sell_to(st, buyer, "food", 1)["qty"]) == 0)
	buyer.position = st.counter()
	w.trade.set_limit(w.household, "food", "buy_max", 0.1)
	check("no agreement on price, no deal", int(w.trade.sell_to(st, buyer, "food", 1)["qty"]) == 0)
	w.trade.set_limit(w.household, "food", "buy_max", 3.0)
	buyer.skills["trade"] = 0.0
	var p_novice: float = w.trade.quote(st, buyer, "food")
	buyer.skills["trade"] = 8.0
	check("a better haggler pays less", w.trade.quote(st, buyer, "food") < p_novice)
	# Kupiec skupuje deski od sprzedającego, płaci z sakwy kramarza.
	buyer.carrying = "plank"
	buyer.carrying_qty = 3
	w.trade.set_limit(w.household, "plank", "sell_min", 1.0)
	var purse0: float = bp.purse
	var rb: Dictionary = w.trade.buy_from(st, buyer, "plank", 3, [])
	check("merchant stall buys planks and pays in hand", int(rb["qty"]) == 3 and bp.purse > purse0)
	check("the merchant buys cheap and sells dear", w.trade.buy_max(oh, "plank") < w.trade.sell_min(oh, "plank"))
	w.person_of(w.agent_by_id(st.keeper)).purse = 0.0
	check("keeper without money buys nothing", w.trade.best_buyer(buyer, "plank") == null or w.trade.best_buyer(buyer, "plank") != st)


func _money(w) -> float:
	var s := 0.0
	for h in w.households.values():
		s += h.cash
	for p in w.family.persons.values():
		s += p.purse
	return s


# L1: zagon rośnie tylko zasiany i tylko w porach wzrostu; plon tylko z dojrzałego;
# niezebrane marnieje, a zima je zabiera.
func _test_field_cycle() -> void:
	var w = _new_world()
	var cfg: Dictionary = w.balance["fields"]
	var ws: Dictionary = cfg["work_seconds"]
	check("fields from map data belong to the manor", w.fields.size() > 0 and w.fields[0].owner_building == "manor")
	var f := SimField.new({ "id": "t", "owner": "manor", "x": 0, "y": 0, "w": 6, "h": 2 }, cfg)
	check("field is split into strips", f.cells.size() > 1)
	for i in 10:
		f.new_day("spring")
	check("unsown field does not grow", f.count("fallow") == f.cells.size())
	check("no sowing before plowing", f.cell_task(0, "spring") == "plow")
	check("no plowing in winter", f.cell_task(0, "winter") == "" and f.work(0, "winter", 99999.0) == "")
	f.work(0, "spring", float(ws["plow"]))
	f.work(0, "spring", float(ws["sow"]))
	check("one strip plowed and sown by work, the rest untouched", f.cells[0]["stage"] == "sown" and f.count("fallow") == f.cells.size() - 1)
	check("harvest only from a ripe strip", f.cell_task(0, "summer") != "harvest" and f.heap == 0)
	for i in int(cfg["grow_days"]):
		f.new_day("summer")
		if f.cell_task(0, "summer") == "weed":
			f.work(0, "summer", float(ws["weed"]))
	check("sown strip needs weeding mid-growth and then ripens", f.cells[0]["stage"] == "ripe" and f.cells[0]["weeded"])
	f.work(0, "summer", float(ws["harvest"]))
	check("harvest leaves the crop on the field", f.cells[0]["stage"] == "stubble" and f.heap == int(cfg["yield_per_cell"]))
	f.cells[1]["stage"] = "ripe"
	f.new_day("autumn")
	f.new_day("autumn")
	var h0: int = f.heap
	f.work(1, "autumn", float(ws["harvest"]))
	check("neglected ripe strip yields less", f.heap - h0 < int(cfg["yield_per_cell"]))
	f.cells[2]["stage"] = "ripe"
	check("winter takes an unharvested crop", f.new_day("winter") == 1 and f.cells[2]["stage"] == "fallow")
	f.claim(3, 99)
	check("claimed strip is not offered to others", f.free_cell("spring") != 3)


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
	var st = _stall_ready(w, "stall_bednarz")
	var buy: Dictionary = { "stall": "stall_bednarz", "good": "food", "qty": 1 }
	a.position = st.counter()
	check("away from home: no money in purse, no purchase", not w.jobs._fx_take_coins(a, 10.0) and not w.jobs._fx_buy_at(a, buy))
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
	a.position = st.counter()
	buy["qty"] = 2
	w.jobs._fx_buy_at(a, buy)
	a.position = w.home().door()
	w.jobs._fx_deposit(a, w.home().id)
	var pocket := float(w.balance["purse"]["pocket_money"])
	check("change above pocket money goes back to the chest", is_equal_approx(root.purse, pocket) and h.cash > chest0 - 12.0)


func _test_buyers_pay_from_own_money() -> void:
	var w = _new_world()
	var st = _stall_ready(w, "stall_bednarz")
	var buyer = w.agent_by_id(w.family.root().agent_id)
	var buy: Dictionary = { "stall": "stall_bednarz", "good": "food", "qty": 1 }
	buyer.position = st.counter()
	w.family.root().purse = 0.0
	check("person with an empty purse buys nothing, even with a full chest", not w.jobs._fx_buy_at(buyer, buy))
	w.family.root().purse = 100.0
	for x in w.trade.stalls.values():
		x.stock.take("food", 9999)
	check("stall without stock sells nothing", not w.jobs._fx_buy_at(buyer, buy))
	buyer.needs["food"] = 1.0
	w.building("home").take("food", 9999)
	w.jobs.replan(buyer)
	var why := String(buyer.steps[buyer.steps.size() - 1].get("why", ""))
	check("hungry person explains nobody sells food", why.contains("nikt nie sprzedaje jedzenia") or buyer.plan_kind == "eat")


# M7: wóz kupca wędrownego staje na placu jako stragan; skupuje to, po co przyjechał,
# po cenie z oferty; po odjeździe stragan znika, a oferta przepada.
func _test_traveling_traders() -> void:
	var w = _new_world()
	var tr = w.traders
	var origin: Dictionary = (tr._cfg["origins"] as Array)[0]
	var v: Dictionary = tr.arrive(origin)
	var trader = w.family.persons[int(v["person"])]
	var a = w.agent_by_id(trader.agent_id)
	check("trader is a named person from a real place", trader.name == String(origin["trader"]["name"]) and v["origin_name"] == origin["name"])
	var st = tr.stall_of(v)
	check("wagon stands on the square as a stall that buys planks", st != null and "plank" in st.buys and tr.wants("plank") > 0)
	a.position = st.building.position
	a.steps.clear()
	w.jobs._fx_open_stall(a, st.id)
	var seller = w.agent_by_id(_named(w.family, "Piotr").agent_id)
	seller.position = st.counter()
	seller.carrying = "plank"
	seller.carrying_qty = 3
	var purse0: float = w.person_of(seller).purse
	var r: Dictionary = w.trade.buy_from(st, seller, "plank", 3, [])
	check("delivered goods are paid in hand from the trader's purse", int(r["qty"]) == 3 and w.person_of(seller).purse > purse0)
	check("trader can't be married off", not w.family.can_marry(trader))
	w.clock.set_time(w.clock.day_index(), minf(0.99, w.clock.time_of_day() + float(tr._cfg["stay"]) + 0.01))
	tr.tick()
	for i in 400:
		if a.status == "away":
			break
		w.step_sim(1.0)
	check("missed offer expires when the wagon leaves", a.status == "away" and tr.wants("plank") == 0 and not w.trade.stalls.has(st.id))


# L3 (S15): praca u kogoś to umowa z oferty; płaca narasta z pracy, a wręcza ją płatnik
# z gospodarstwa pracodawcy pod miejscem pracy. Niezapłacony pamięta i odchodzi.
func _test_estate_pays_wages() -> void:
	var w = _new_world()
	var est = w.estate_owner()
	check("the manor household is the employer", est != null and w.family.persons[est.members[0]].surname == "Dworski")
	var o: Dictionary = w.contracts.find_offer(est.id, "manor", "laborer")
	check("field owner posts an offer with slots and a wage", not o.is_empty() and int(o["slots"]) > 0 and float(o["wage"]) > 0.0)
	var piotr = _named(w.family, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	w.contracts.hire(o, piotr)
	check("hiring sets job and workplace", a.job == "laborer" and a.workplace == "manor")
	var f = w.fields[0]
	var s := { "t": "act", "act": "labor", "left": 100.0, "why": "dniówka", "will": 1.0, "field": f.id, "cell": 0, "task": "plow" }
	var est0: float = est.cash
	for i in 60:
		w._act(a, s, 1.0)
		s["left"] = 100.0
	var c: Dictionary = w.contracts.of_worker(piotr.id)
	check("wage accrues with work, nobody is paid from thin air", float(c["owed"]) > 0.0 and is_equal_approx(est.cash, est0))
	check("estate work advances work on a concrete strip", f.cells[0]["stage"] != "fallow" or float(f.cells[0]["done"]) > 0.0)
	var payer = w.contracts.payer(est.id)
	check("payer is someone from the employer's household", payer != null and w.person_of(payer).household_id == est.id)
	var pp = w.person_of(payer)
	pp.purse = 100.0
	payer.position = w.contracts.pay_spot("manor")
	a.position = w.building("sawmill").door()
	check("worker away from the pay spot gets nothing", is_zero_approx(w.contracts.hand_out(payer, "manor")))
	a.position = w.contracts.pay_spot("manor")
	var owed: float = c["owed"]
	var purse0: float = piotr.purse
	check("payer hands the wage over in person", is_equal_approx(w.contracts.hand_out(payer, "manor"), owed)
		and is_equal_approx(piotr.purse - purse0, owed) and is_equal_approx(pp.purse, 100.0 - owed))
	c["owed"] = 5.0
	w.contracts.settle_day()
	check("unpaid worker quits and remembers it", w.contracts.of_worker(piotr.id).is_empty()
		and w.bonds.value(piotr.id, SimBonds.person(pp.id)) < 0.0)
	pp.purse = 0.0
	est.cash = 0.0
	w.ai.post_offers()
	check("employer without money offers no work", int(w.contracts.find_offer(est.id, "manor", "laborer")["slots"]) == 0)


# L2: robotnik dworu bierze wolny zagon i idzie wzdłuż niego; dwóch nie bierze tego samego;
# snopy niesie do spichrza dworu, nie do własnego domu; bez roboty w polu czeka z powodem.
func _test_field_work() -> void:
	var w = _new_world()
	var a = w.agent_by_id(_named(w.family, "Piotr").agent_id)
	var b = w.agent_by_id(_named(w.family, "Maria").agent_id)
	w.clock.set_time(0, float(w.balance["schedule"]["work_start"]) + 0.05)
	var est_offer: Dictionary = w.contracts.find_offer_at("manor", "laborer")
	est_offer["slots"] = int(est_offer["slots"]) + 2   # AI zajmuje wakaty od startu
	for x in [a, b]:
		x.job = "laborer"
		w.jobs.release(x)
		x.steps.clear()
		w.jobs._plan_laborer(x)
	var st: Dictionary = a.steps[a.steps.size() - 1]
	var sb: Dictionary = b.steps[b.steps.size() - 1]
	check("spring: laborer plows a strip outside, visible", st.get("act") == "labor" and st.get("task") == "plow" and st.get("inside", "") == "")
	check("two laborers take different strips", st["field"] != sb["field"] or st["cell"] != sb["cell"])
	var f = w.field_by_id(String(st["field"]))
	var c: Dictionary = f.cells[int(st["cell"])]
	a.position = c["start"]
	a.steps = [st]
	st["will"] = 1.0
	st["left"] = 99999.0
	var mid_seen := false
	for i in 3000:
		if a.steps.is_empty():
			break
		w._act(a, st, 1.0)
		if a.position.distance_to(c["start"]) > 0.3 and a.position.distance_to(c["end"]) > 0.3:
			mid_seen = true
	check("laborer walks along the strip while plowing", mid_seen and a.position.distance_to(c["end"]) < 0.01)
	check("work plows that strip and ends the step", c["stage"] == "plowed" and a.steps.is_empty())
	w.jobs.release(a)
	check("finished strip is released", int(c["by"]) < 0)
	f.heap = 12
	for x in f.cells:
		x["stage"] = "stubble"
	var food0: int = w.building("manor").amount("food")
	a.steps.clear()
	w.jobs._plan_laborer(a)
	check("harvest on the field is carried, not left", a.steps.any(func(x): return x["t"] == "do" and x["fn"] == "field_pickup"))
	a.position = f.heap_spot()
	w.jobs._fx_field_pickup(a, f.id)
	var home_food: int = w.home().amount("food")
	a.steps.clear()
	w.jobs._plan_deliver_carried(a)
	check("sheaves go to the owner's granary even after an interrupted plan", a.steps[0]["to"].distance_to(w.building("manor").door()) < 0.01)
	a.position = w.building("manor").door()
	w.jobs._fx_deposit(a, "manor")
	check("manor granary gets the crop, the worker's home does not", w.building("manor").amount("food") > food0 and w.home().amount("food") == home_food)
	for g in w.fields:
		g.heap = 0
		for x in g.cells:
			x["stage"] = "sown"
	a.steps.clear()
	w.jobs._plan_laborer(a)
	check("no field work: laborer says so instead of vanishing", String(a.steps[a.steps.size() - 1]["why"]).contains("nie ma dziś roboty"))


# L4 (S21): przydział przez miejsce — swoje miejsca dają zawody, cudze tylko wakaty;
# gracz sam wystawia oferty, a za niską stawkę nikt nie przyjdzie.
func _test_assign_by_place() -> void:
	var w = _new_world()
	var piotr = _named(w.family, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	var jobs_of := func(opts: Array) -> Array: return opts.map(func(o): return o["job"])
	check("forest offers woodcutter and forager", jobs_of.call(w.job_options(a.id, "forest")).has("woodcutter"))
	check("own sawmill offers sawyer", jobs_of.call(w.job_options(a.id, "sawmill")) == ["sawyer"])
	var vac: Dictionary = w.contracts.find_offer_at("manor", "laborer")
	vac["slots"] = w.contracts.taken(vac) + 1
	var manor_opts: Array = w.job_options(a.id, "field:" + w.fields[0].id)
	check("foreign field shows the vacancy with wage", manor_opts.size() == 1 and manor_opts[0]["job"] == "laborer"
		and manor_opts[0]["place"] == "manor" and String(manor_opts[0]["label"]).contains("zł"))
	check("taking a vacancy makes a contract", w.assign_job(a.id, "laborer", "manor") and w.contracts.of_worker(piotr.id)["place"] == "manor")
	var o: Dictionary = w.contracts.find_offer_at("manor", "laborer")
	o["slots"] = w.contracts.taken(o)
	var zofia = _named(w.family, "Zofia")
	check("no free slot: no contract", not w.assign_job(zofia.agent_id, "laborer", "manor"))
	var stranger: SimPerson = null
	for p in w.family.all_living():
		if not w.family.is_ours(p) and w.family.stage_of(p) == "adult" and w.contracts.of_worker(p.id).is_empty():
			stranger = p
			break
	w.post_player_offer("sawmill", "sawyer", 1, float(w.balance["contracts"]["min_wage"]) - 1.0)
	check("too low wage attracts nobody", w.contracts.best_offer_for(stranger, "sawyer").is_empty())
	w.post_player_offer("sawmill", "sawyer", 1, 30.0)
	var best: Dictionary = w.contracts.best_offer_for(stranger)
	check("good wage in the player's sawmill attracts a stranger", best.get("place", "") == "sawmill")


# L5 (S20): o pracy AI decyduje majątek, nie rola; w godzinach pracy dorośli AI są
# w świecie (praca, wolne wśród ludzi), a nie zamknięci w domu bez powodu.
func _test_ai_visible_by_day() -> void:
	var w = _new_world()
	var est = w.estate_owner()
	_run_days_auto(w, 1.0)
	var adults_est: Array = est.members.filter(func(pid): return w.family.stage_of(w.family.persons[pid]) == "adult")
	check("wealthy household does not hire itself out", adults_est.all(func(pid):
		return w.contracts.of_worker(pid).is_empty()))
	w.clock.set_time(w.clock.day_index(), float(w.balance["schedule"]["work_start"]) + 0.1)
	var inside := 0
	var total := 0
	for i in 40:
		w.step_sim(2.0)
		for a in w.agents:
			var p = w.person_of(a)
			if a.status != "active" or p == null or w.family.is_ours(p) or not a.can_work() or a.status == "away":
				continue
			if w.family.lineage_of(p).role == "trader":
				continue
			total += 1
			if a.inside == a.home_id and a.activity in ["rest", "idle", "wait"]:
				inside += 1
	check("AI adults are out in the world during work hours", total > 0 and float(inside) / float(total) < 0.15)


# L6: najęty bez nadzoru się miga; nadzorca z gospodarstwa pracodawcy obok to zmienia,
# ale ma ograniczoną liczbę ludzi pod okiem.
func _test_overseer() -> void:
	var w = _new_world()
	var est = w.estate_owner()
	var o: Dictionary = w.contracts.find_offer(est.id, "manor", "laborer")
	var piotr = _named(w.family, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	w.contracts.hire(o, piotr)
	var lazy: float = w.jobs.willingness(a, "labor")
	check("unsupervised hired hand works less willingly", lazy < 1.0 and not w.contracts.supervised(a))
	var boss = w.agent_by_id(w.family.persons[est.members[0]].agent_id)
	boss.job = "overseer"
	boss.position = a.position + Vector2(1, 0)
	check("overseer nearby: no shirking", w.jobs.willingness(a, "labor") > lazy and w.contracts.supervised(a))
	boss.position = a.position + Vector2(50, 0)
	check("overseer far away does not help", not w.contracts.supervised(a))


# O1: mieszkanie to rozkazy gracza — wynajem, wyprowadzka na swoje, kupno, wyrzucenie;
# bezdomnej rodziny gracza nikt sam nie wprowadza do domu.
func _test_housing_orders() -> void:
	var w = _new_world()
	var h = w.household
	var free = w.free_house()
	check("there is a free house to rent", free != null and w.is_free_house(free))
	var zofia = _named(w.family, "Zofia")
	zofia.birth_day -= 4.0
	zofia.purse = 50.0
	check("an adult can move out into a rented house", w.rent_house(free.id, zofia.id) and zofia.household_id != h.id
		and zofia.lineage_id == w.family.player_lineage_id and w.agent_by_id(zofia.agent_id).home_id == free.id)
	check("household moved out takes her purse into her own chest", w.households[zofia.household_id].cash >= 50.0 - 0.001)
	var piotr = _named(w.family, "Piotr")
	check("throwing someone out leaves them homeless and resentful", w.throw_out(piotr.id)
		and w.agent_by_id(piotr.agent_id).home_id == ""
		and w.bonds.memories(piotr.id, SimBonds.person(w.family.root_id)).any(func(m): return m["kind"] == "thrown_out"))
	w.leave_home()
	h.cash = 999.0
	w._settle_rent(h)
	check("homeless player family is not rehoused automatically", h.home_id == "")
	var home = w.home()
	check("buying a house makes it the lineage's, no more rent", w.buy_house(home.id) and w.owns(h, home))
	check("player rents a house by order", w.rent_house(home.id) and h.home_id == home.id)


# O2: zlecona budowa powstaje z doniesionych desek i pracy ludzi; bez desek praca staje;
# gotowy dom należy do rodu, który go zlecił.
func _test_construction() -> void:
	var w = _new_world()
	check("too close to another building: no site", w.commission_house(w.home().position + Vector2(1, 1)) == "")
	var sid: String = w.commission_house(Vector2(40, 60))
	check("site is placed and builders are wanted", sid != "" and not w.contracts.find_offer_at(sid, "builder").is_empty())
	var site: Dictionary = w.sites[sid]
	var b = site["b"]
	w.build_work(sid, 99999.0)
	check("without planks no work gets done", is_zero_approx(float(site["work"])))
	var cfg: Dictionary = w.site_cfg(site)
	b.add("plank", int(cfg["materials"]["plank"]) / 2)
	w.build_work(sid, 99999.0)
	check("half the planks allow half the work", absf(float(site["work"]) - w.site_total(site) * 0.5) < 1.0)
	var piotr = _named(w.family, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	w.assign_job(a.id, "builder", "")
	a.steps.clear()
	w.jobs._plan_builder(a)
	w.building("sawmill").add("plank", 10)
	a.steps.clear()
	w.jobs._plan_builder(a)
	check("builder fetches planks when the site runs out", a.steps.any(func(s): return s["t"] == "do" and s["fn"] == "pickup"))
	b.add("plank", int(cfg["materials"]["plank"]))
	w.build_work(sid, 99999.0)
	check("finished house belongs to the lineage that commissioned it", not w.sites.has(sid) and b.type == "home"
		and b.owner_kind == "lineage" and b.owner_id == w.family.player_lineage_id and w.is_free_house(b))


# P1–P2: złodziej upatruje niepilnowany stragan, czeka na moment bez świadków; łapie
# konkretny świadek, który biegnie do straży; kto lubi złodzieja, milczy.
# T0 (S29): budowa z katalogu — stragan staje się działającym straganem rodu, droga
# powstaje między dwoma punktami i potrzebuje tylko pracy.
func _test_build_catalog() -> void:
	var w = _new_world()
	check("catalog has house, stall and road", w.buildables.has("house") and w.buildables.has("stall") and w.buildables.has("road"))
	var sid: String = w.commission("stall", Vector2(40, 62))
	var site: Dictionary = w.sites[sid]
	site["b"].add("plank", int(w.site_cfg(site)["materials"]["plank"]))
	w.build_work(sid, 99999.0)
	check("finished stall trades for the player's household", w.trade.stalls.has(sid) and w.trade.stalls[sid].owner == w.household.id)
	var rid: String = w.commission("road", Vector2(40, 66), Vector2(50, 66))
	var rs: Dictionary = w.sites[rid]
	check("road costs work by its length, no materials", absf(w.site_total(rs) - float(w.buildables["road"]["work_per_unit"]) * 10.0) < 0.01
		and is_equal_approx(w.site_work_allowed(rs), w.site_total(rs)))
	w.build_work(rid, 99999.0)
	check("finished road is on the map and the site is gone", w.roads_built.size() == 1 and not w.buildings.has(rid))


# R1 (S22): zamknięty obieg — suma pieniędzy świata (skrzynie, sakwy, kasy miast)
# nie zmienia się przez dni życia wsi: czynsz, długi, wypłaty, handel, wozy, śluby.
func _test_money_invariant() -> void:
	var w = _new_world(31)
	var m0: float = w.money_total()
	var worst := 0.0
	for d in 6:
		_run_days_auto(w, 1.0)
		worst = maxf(worst, absf(w.money_total() - m0))
	check("money of the world is constant (closed economy)", worst < 0.01)


# R2 (S23): potrzeby w warstwach — bogaty ród chce więcej rzeczy niż biedny.
func _test_needs_tiers() -> void:
	var w = _new_world()
	var rich = w.estate_owner()
	var poor = w.household_at("n2")
	check("rich household lives at a higher tier than a poor one", w.needs.tier_index(rich) > w.needs.tier_index(poor))
	check("rich wants prestige goods (chairs, luxury)", w.needs.wants(rich).has("chair") and w.needs.wants(rich).has("luxury"))
	check("poor household has no prestige wants", not w.needs.wants(poor).has("luxury"))
	poor.cash = 500.0
	check("money lifts a household to wanting more", w.needs.wants(poor).has("luxury"))


# R3: rzeczy się zużywają, domy niszczeją; wieś bez gracza kupuje deski na remont
# i towary z potrzeb, a łatanie chaty widać jako czynność.
func _test_wear_and_repair() -> void:
	var w = _new_world()
	var h = w.household_at("n1")
	var home = w.building("n1")
	home.add("cloth", 4)
	for d in 10:
		w.needs.wear_day(h)
	check("goods wear out and the house decays", home.amount("cloth") < 4 and home.condition < 1.0)
	home.condition = 0.3
	h.cash = 200.0
	var st = _stall_ready(w, "stall_bednarz")
	st.stock.add("plank", 10)
	var adult = null
	for pid in h.members:
		var a = w.agent_by_id(w.family.persons[pid].agent_id)
		if a.can_work():
			adult = a
	adult.steps.clear()
	w.home_of(adult).add("food", 30)
	w.home_of(adult).add("log", 12)
	w.ai.set_prices()
	check("village household without the player goes to buy planks for repairs", w.jobs._repair_trip(adult)
		and adult.steps.any(func(x): return x["t"] == "do" and x["fn"] == "buy_at" and x["arg"]["good"] == "plank"))
	home.add("plank", 14)
	adult.steps.clear()
	w.jobs.release(adult)
	w.jobs._repair_trip(adult)
	adult.position = home.door()
	var c0: float = home.condition
	w.jobs.apply(adult, { "t": "do", "fn": "repair", "arg": "n1" })
	check("patching the house uses planks and restores it", home.condition > c0 and home.amount("plank") < 14)
	var rich = w.estate_owner()
	var ra = w.agent_by_id(w.family.persons[rich.members[1]].agent_id)
	ra.steps.clear()
	w.trade.stalls["stall_bednarz"].stock.add("cloth", 5)
	check("a well-off household shops for what it lacks", w.jobs._wants_trip(ra) or w.needs.wants(rich).is_empty())


# R4 (S26): ceny AI z zapasu i potrzeb — pusta półka u kupca to wyższa cena,
# pusta spiżarnia to gotowość, by zapłacić więcej; pełny spichrz sprzedaje taniej.
func _test_prices_from_stock() -> void:
	var w = _new_world()
	var st = w.trade.stalls["stall_bednarz"]
	var mh = w.households[st.owner]
	st.stock.take("food", 9999)
	w.ai.set_prices()
	var scarce: float = w.trade.sell_min(mh, "food")
	st.stock.add("food", 60)
	w.ai.set_prices()
	check("merchant with an empty shelf asks more than with a full one", scarce > w.trade.sell_min(mh, "food"))
	var h = w.household_at("n1")
	w.building("n1").take("food", 9999)
	w.ai.set_prices()
	var hungry: float = w.trade.buy_max(h, "food")
	w.building("n1").add("food", 30)
	w.ai.set_prices()
	check("empty pantry: household pays more for food", hungry > w.trade.buy_max(h, "food"))
	var est = w.estate_owner()
	var mst = w.trade.stalls["stall_manor"]
	mst.stock.take("food", 9999)
	w.ai.set_prices()
	var lean: float = w.trade.sell_min(est, "food")
	mst.stock.add("food", 190)
	w.ai.set_prices()
	check("full granary sells cheaper", w.trade.sell_min(est, "food") < lean)


# T1 (S24): warsztat to przedsięwzięcie z właścicielem; ten sam kod pracy w dowolnym
# warsztacie danego typu — tracz u obcych pracuje w ich tartaku, nie w twoim.
func _test_enterprises() -> void:
	var w = _new_world()
	check("player's sawmill is an enterprise owned by the player's household",
		w.enterprise_building(w.household.id, "sawmill") == w.building("sawmill") and w.building("sawmill").owner_id == w.family.player_lineage_id)
	var b := SimBuilding.new("mill2", "Tartak Kosów", "sawmill", Vector2(30, 50), w.balance["storage"]["sawmill"])
	w.buildings[b.id] = b
	var kos = w.household_at("n1")
	w.add_enterprise(b, kos.id)
	b.add("log", 3)
	var worker = null
	for pid in kos.members:
		var a = w.agent_by_id(w.family.persons[pid].agent_id)
		if a.can_work():
			worker = a
	worker.job = "sawyer"
	worker.steps.clear()
	w.jobs._plan_producer(worker, w.jobs.recipe_for_job("sawyer"))
	var prod: Array = worker.steps.filter(func(s): return s["t"] == "do" and s["fn"] == "produce")
	check("another household's sawyer works in their own sawmill", not prod.is_empty() and prod[0]["arg"]["b"] == "mill2")
	check("player's sawmill is foreign to them, theirs to the player", w.is_foreign(b) and not w.is_foreign(w.building("sawmill")))


# T2: ród AI prowadzi warsztat — obsadza go swoimi albo najmuje, dokupuje wsad,
# którego sam nie wytwarza, a bez pieniędzy warsztat stoi.
func _test_ai_runs_enterprise() -> void:
	var w = _new_world()
	var kos = w.household_at("n1")
	var shop := SimBuilding.new("shop2", "Stolarnia Kosów", "workshop", Vector2(30, 52), w.balance["storage"]["workshop"])
	w.buildings[shop.id] = shop
	w.add_enterprise(shop, kos.id)
	kos.cash = 40.0
	w.ai.new_day()
	var jobs: Array = kos.members.map(func(pid): return w.agent_by_id(w.family.persons[pid].agent_id).job)
	check("modest owner puts own people to work in the workshop", "carpenter" in jobs)
	var st = _stall_ready(w, "stall_bednarz")
	st.stock.add("plank", 10)
	w.ai.set_prices()
	w.trade.set_limit(w.households[st.owner], "plank", "sell_min", 3.5)
	var carrier = null
	for pid in kos.members:
		var a = w.agent_by_id(w.family.persons[pid].agent_id)
		if a.can_work() and a.job != "carpenter":
			carrier = a
	carrier.steps.clear()
	check("workshop without own sawmill buys planks as input", w.jobs._supply_enterprise(carrier)
		and carrier.steps.any(func(x): return x["t"] == "do" and x["fn"] == "buy_at" and x["arg"]["to"] == "shop2"))
	var rich = w.estate_owner()
	var mill := SimBuilding.new("mill3", "Tartak dworski", "sawmill", Vector2(88, 50), w.balance["storage"]["sawmill"])
	w.buildings[mill.id] = mill
	w.add_enterprise(mill, rich.id)
	w.ai.new_day()
	check("wealthy owner hires people for the sawmill", not w.contracts.find_offer(rich.id, "mill3", "sawyer").is_empty()
		and int(w.contracts.find_offer(rich.id, "mill3", "sawyer")["slots"]) > 0)
	kos.cash = 0.0
	check("no money: the workshop stands idle", not w.ai.operating(kos, shop))


# T3: brak desek na rynku i nikt ich nie robi → zamożny ród AI zleca budowę tartaku
# z katalogu; gotowy tartak jest jego przedsięwzięciem.
func _test_ai_founds_enterprise() -> void:
	var w = _new_world()
	w.household.cash = 0.0   # tartak gracza stoi (brak pieniędzy na wsad i dniówki)
	for st in w.trade.stalls.values():
		st.stock.take("plank", 9999)
	var rich = w.estate_owner()
	rich.cash = 500.0
	w.ai.found_enterprises()
	var sid := ""
	for k in w.sites:
		if int(w.sites[k]["household"]) == rich.id and w.sites[k]["kind"] == "sawmill":
			sid = k
	check("scarce planks: a wealthy AI household commissions a sawmill", sid != "")
	if sid == "":
		return
	var site: Dictionary = w.sites[sid]
	site["b"].add("plank", int(w.site_cfg(site)["materials"]["plank"]))
	w.build_work(sid, 99999.0)
	check("the finished sawmill is their enterprise", w.enterprise_building(rich.id, "sawmill") != null)


# T4 (S27): las i ziemia mają właściciela — wyrąb kosztuje opłatę od pnia, budowa
# wymaga kupienia działki; pieniądze trafiają do właściciela.
func _test_land_owners() -> void:
	var w = _new_world()
	var est = w.estate_owner()
	check("forest and land belong to the manor", w.forest_owner() == est and w.land_owner() == est)
	var a = w.agent_by_id(w.family.root().agent_id)
	var t = w.nearest_tree(a.position)
	var e0: float = est.cash
	var h0: float = w.household.cash + w.household.debt * -1.0
	w.jobs._fx_chop_done(a, t.id)
	check("chopping a log pays the forest owner", est.cash > e0 or w.household.debt > 0.0)
	w.household.cash = 0.0
	check("no money for the plot: no building site", w.commission("house", Vector2(40, 62)) == "")
	w.household.cash = 100.0
	var e1: float = est.cash
	check("buying the plot pays the landowner", w.commission("house", Vector2(40, 62)) != "" and est.cash > e1)


# U1–U2 (S25): miasto okolicy to agregat — czego samo nie robi, tego mu ubywa i to
# drożeje; wóz wiezie jego nadwyżki i skupuje braki, a po powrocie towar i kasa
# wracają do miasta.
func _test_towns() -> void:
	var w = _new_world()
	var town = w.traders.towns["rzeczyca"]
	var p0: float = town.price("plank")
	for d in 6:
		town.new_day()
	check("a town that doesn't make planks runs out and pays more", town.amount("plank") < 20 and town.price("plank") > p0)
	var origin: Dictionary = (w.traders._cfg["origins"] as Array)[0]
	var cash0: float = town.cash
	var v: Dictionary = w.traders.arrive(origin)
	var st = w.traders.stall_of(v)
	check("the wagon carries the town's money and its shortages", town.cash < cash0 and "plank" in st.buys)
	check("the wagon brings the town's surplus", st.goods.any(func(g): return not g in st.buys and st.stock.amount(g) > 0))
	var a = w.agent_by_id(w.family.persons[int(v["person"])].agent_id)
	st.stock.add("plank", 3)
	w.traders._depart(v)
	var planks: int = town.amount("plank")
	w.traders.gone(a, "rzeczyca")
	check("bought goods and the purse go back to the town", town.amount("plank") >= planks + 3 and is_zero_approx(w.person_of(a).purse))


# U3: wyprawa do miasta — towar, którego miastu brakuje, sprzedany po jego cenie,
# za utarg zakupy dla domu; po drodze może być napad; obieg pieniędzy zamknięty.
func _test_trip_to_town() -> void:
	var w = _new_world()
	var m0: float = w.money_total()
	var piotr = _named(w.family, "Piotr")
	var a = w.agent_by_id(piotr.agent_id)
	var mill = w.building("sawmill")
	mill.add("plank", 15)
	var town = w.traders.towns["rzeczyca"]
	for d in 4:
		town.new_day()
	check("trip starts with planks the town lacks", w.send_on_trip(a.id, "rzeczyca") and mill.amount("plank") < 15)
	a.position = Vector2(94, 22)
	var purse0: float = piotr.purse
	w.trips.leave(a, "rzeczyca")
	check("away in town: goods sold at the town's price", a.status == "away" and piotr.purse > purse0 - 0.001)
	w.clock.set_time(w.clock.day_index() + 1, 0.5)
	w.trips.tick()
	check("back on the map after the road", a.status == "active" and not w.trips.on_trip(a))
	check("money of the world is conserved by the trip", absf(w.money_total() - m0) < 0.01)


func _test_theft_process() -> void:
	var w = _new_world()
	w.clock.set_time(1, 0.5)
	var st = w.trade.stalls["stall_bednarz"]
	st.keeper = -1
	st.packed = false
	var thief = w.agent_by_id(_named(w.family, "Zofia").agent_id)
	for a in w.agents:
		if a != thief:
			a.position = Vector2(5, 65)   # nikogo w pobliżu
	thief.position = st.counter()
	var t: Dictionary = w.crime.pick_target(thief)
	check("thief picks the unattended, unpacked stall", t.get("stall", "") == "stall_bednarz")
	var food0: int = st.stock.amount("food") + st.stock.amount("log")
	check("no witnesses: the moment is right", w.crime.moment_ok(thief, t))
	check("goods vanish from the stall into the thief's hands", w.crime.steal(thief, t) and thief.carrying != ""
		and st.stock.amount("food") + st.stock.amount("log") < food0 and thief.status == "active")
	st.packed = true
	check("packed stall is not a target", w.crime.pick_target(thief).get("stall", "") != "stall_bednarz")
	st.packed = false
	var witness = w.agent_by_id(_named(w.family, "Piotr").agent_id)
	witness.position = thief.position + Vector2(1, 0)
	witness.steps.clear()
	witness.activity = "rest"
	check("someone right next to the thief: wait for a better moment", not w.crime.moment_ok(thief, t))
	w.bonds.remember(w.person_of(witness).id, SimBonds.person(w.person_of(thief).id), "covered_theft", [], -50.0)
	w.crime.report(witness, thief)
	check("witness runs to the town hall to report", witness.steps[0]["to"].distance_to(w.building("jail").door()) < 0.01)
	witness.position = w.building("jail").door()
	w.crime.on_report(witness, thief.id)
	check("reported thief is arrested by the watch", thief.status == "jailed")


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
	_fall_in_love(w, piotr, w.family.marriage_candidates(piotr)[0])
	_run_days_auto(w, 3.0)
	check("lovers with the family's consent marry", not piotr.unions.is_empty())
	for p in w.family.living():
		if w.family.can_marry(p) and not w.family.marriage_candidates(p).is_empty():
			_fall_in_love(w, p, w.family.marriage_candidates(p)[0])
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
	var born_ours := {}
	for e in w.chronicle.of_kind("birth"):
		if int(e["lineage"]) == pl:
			born_ours[int(e["who"][0])] = true
	for p in w.family.persons.values():
		# Kto wżenił się w ród gracza albo urodził się jego członkowi, musi w nim być
		# (chyba że odszedł albo sam(a) wyszedł/wyszła za mąż do innego rodu).
		var married_out: bool = p.attached and p.spouse_id >= 0 and w.family.persons[p.spouse_id].lineage_id != pl
		var joined: bool = (p.attached and p.spouse_id >= 0 and w.family.persons[p.spouse_id].lineage_id == pl) \
			or (born_ours.has(p.id) and not married_out)
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
			if w.family.can_marry(p) and w.family.beloved(p) < 0 and not w.family.marriage_candidates(p).is_empty():
				_fall_in_love(w, p, w.family.marriage_candidates(p)[0])
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
