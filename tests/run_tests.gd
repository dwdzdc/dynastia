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
	# Etap 2
	_test_world_generation()
	_test_world_autonomous_day()


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


# --- Etap 2 ---

func _map() -> Dictionary:
	return LOADER_SCRIPT.load_json("res://data/map.json")


func _test_world_generation() -> void:
	var balance := _balance()
	var world = WORLD_SCRIPT.new(12345, balance, _map())
	check("population count matches", world.agents.size() == int(balance["population"]["count"]))

	var all_homed := true
	for i in world.agents.size():
		if str(world.agents[i].home_place_id) == "":
			all_homed = false
	check("every agent has a home", all_homed)

	var world2 = WORLD_SCRIPT.new(12345, balance, _map())
	var same := true
	for i in world.agents.size():
		var a = world.agents[i]
		var b = world2.agents[i]
		if int(a.age) != int(b.age) or int(a.skills["lumber"]) != int(b.skills["lumber"]) \
				or str(a.home_place_id) != str(b.home_place_id):
			same = false
	check("same seed -> same world", same)


func _test_world_autonomous_day() -> void:
	var balance := _balance()
	var day_seconds := float(LOADER_SCRIPT.get_nested(balance, "time.day_seconds"))
	var world = WORLD_SCRIPT.new(12345, balance, _map())
	world.clock.speed = 1

	var seen := {}
	for i in world.agents.size():
		seen[int(world.agents[i].id)] = {}

	for step in 30:  # 3 doby w krokach 0.1 doby
		world.tick(day_seconds / 10.0)
		for i in world.agents.size():
			var a = world.agents[i]
			seen[int(a.id)][str(a.activity)] = true

	var ok_needs := true
	var ok_reason := true
	var ok_stuck := true
	for i in world.agents.size():
		var a = world.agents[i]
		if float(a.needs["sleep"]) < 0.0 or float(a.needs["sleep"]) > 100.0:
			ok_needs = false
		if float(a.needs["food"]) < 0.0 or float(a.needs["food"]) > 100.0:
			ok_needs = false
		if str(a.idle_reason) == "":
			ok_reason = false
		if float(a.commute_accum) >= day_seconds:
			ok_stuck = false
	check("needs stay in [0,100]", ok_needs)
	check("idle_reason always set", ok_reason)
	check("no agent stuck commuting (> 1 doba)", ok_stuck)

	var cycled := true
	for i in world.agents.size():
		var d: Dictionary = seen[int(world.agents[i].id)]
		if not (d.has("sleep") and d.has("work") and d.has("eat")):
			cycled = false
	check("every agent cycled sleep+work+eat", cycled)
	check("wood accrues during work", float(world.resources["wood"]) > 0.0)
