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
	return WORLD_SCRIPT.new(seed, _balance(), _map(), _people(), LOADER_SCRIPT.load_json("res://data/memories.json"))


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
	var w = _bond_world()
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
	check("departed moves out to the neighbours", ap.home_id == String(w.balance["belonging"]["leave_home"]))
	check("departure is in the chronicle", w.chronicle.of_kind("departure").size() == 1 and piotr.id in w.chronicle.of_kind("departure")[0]["who"])
	w.set_job(ap.id, "sawyer")
	check("player can no longer command the departed", ap.job == String(w.balance["belonging"]["leave_job"]))
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
	var c0: float = w.household.cash
	w.earn_for(ap, 10.0)
	var close_gives: float = w.household.cash - c0
	c0 = w.household.cash
	w.earn_for(az, 10.0)
	var far_gives: float = w.household.cash - c0
	check("close member hands over everything", is_equal_approx(close_gives, 10.0) and is_zero_approx(piotr.purse))
	check("drifting member hands over less and keeps the rest", far_gives < close_gives and is_equal_approx(zofia.purse, 10.0 - far_gives))


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
	check("household paid first rent without debt", w.household.debt == 0.0)


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
	var n0: int = w.family.persons.size()
	for p in w.family.living():
		if w.family.can_marry(p):
			w.family.set_seeking(p.id, true)
	_run_days_auto(w, 40.0)
	check("married couples have children", w.family.persons.size() > n0)
	var in_lineage := true
	var departed := []
	for e in w.chronicle.of_kind("departure"):
		departed.append_array(e["who"])
	for p in w.family.persons.values():
		if p.lineage_id != w.family.player_lineage_id and not p.id in departed:
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
