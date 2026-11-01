# Minimalny runner testów sim/ (własny, bez GUT) — patrz ADR-0002.
# Uruchomienie: godot --headless --script res://tests/run_tests.gd
extends SceneTree


const RNG_SCRIPT := preload("res://sim/rng.gd")
const LOADER_SCRIPT := preload("res://sim/data_loader.gd")

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
	_test_rng_deterministic()
	_test_rng_range_and_distribution()
	_test_hash3_stable()
	_test_hash3_sensitive_to_inputs()
	_test_data_loader()


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
