# SimAgent — anonimowy agent (Etap 2): id, wiek, umiejętności, potrzeby,
# harmonogram i powód bezczynności. BEZ traitów, rodzin i więzi (te wchodzą
# w etapach 5–7). Czysta logika (RefCounted), testowalna headless.
class_name SimAgent
extends RefCounted


var id: int
var name: String
var age: int
var skills: Dictionary = {}
var needs: Dictionary = { "sleep": 100.0, "food": 100.0 }

var home_place_id: String
var work_place_id: String
var food_place_id: String

var position: Vector2 = Vector2.ZERO
var activity: String = "free"      # sleep | work | eat | free | commute
var pending_activity: String = ""
var target_place_id: String = ""
var location_place_id: String = ""
var controlled: bool = false
var idle_reason: String = ""
var commute_accum: float = 0.0      # sekund w bieżącym dojeździe (detekcja zakleszczeń)


# wartości stałych pieczone w konstrukcji (rate = na dobę / sekund_na_dobę)
var _sleep_decay: float
var _sleep_rec: float
var _food_decay: float
var _food_rec: float
var _sleep_low: float
var _food_low: float
var _wake: float
var _sleep_at: float
var _work_start: float
var _work_end: float
var _places: Dictionary


func _init(
	p_id: int, p_name: String, p_age: int, p_skills: Dictionary,
	p_home: String, p_work: String, p_food: String,
	places: Dictionary, balance: Dictionary,
) -> void:
	id = p_id
	name = p_name
	age = p_age
	skills = p_skills
	home_place_id = p_home
	work_place_id = p_work
	food_place_id = p_food
	_places = places

	var day_seconds := float(balance["time"]["day_seconds"])
	var n: Dictionary = balance["needs"]
	_sleep_decay = float(n["sleep"]["decay_day"]) / day_seconds
	_sleep_rec = float(n["sleep"]["recover_day"]) / day_seconds
	_food_decay = float(n["food"]["decay_day"]) / day_seconds
	_food_rec = float(n["food"]["recover_day"]) / day_seconds
	_sleep_low = float(n["sleep"]["low"])
	_food_low = float(n["food"]["low"])
	var s: Dictionary = balance["schedule"]
	_wake = float(s["wake"])
	_sleep_at = float(s["sleep"])
	_work_start = float(s["work_start"])
	_work_end = float(s["work_end"])


# delta_sim w sekundach symulacyjnych (nie realnych!).
func tick(tod: float, delta_sim: float) -> void:
	if controlled:
		idle_reason = "przejęty — sterowanie ręczne"
		return

	needs["sleep"] = clampf(needs["sleep"] - _sleep_decay * delta_sim, 0.0, 100.0)
	needs["food"] = clampf(needs["food"] - _food_decay * delta_sim, 0.0, 100.0)

	match activity:
		"sleep":
			needs["sleep"] = clampf(needs["sleep"] + _sleep_rec * delta_sim, 0.0, 100.0)
			idle_reason = "śpi"
			_maybe_switch(tod)
		"work":
			idle_reason = "pracuje (wycinka drewna)"
			_maybe_switch(tod)
		"eat":
			needs["food"] = clampf(needs["food"] + _food_rec * delta_sim, 0.0, 100.0)
			idle_reason = "je"
			_maybe_switch(tod)
		"free":
			idle_reason = "wypoczywa w domu"
			_maybe_switch(tod)
		"commute":
			idle_reason = "idzie do " + _place_name(target_place_id)


func _desired(tod: float) -> String:
	if needs["food"] < _food_low:
		return "eat"
	if needs["sleep"] < _sleep_low or tod < _wake or tod >= _sleep_at:
		return "sleep"
	if tod >= _work_start and tod < _work_end:
		return "work"
	return "free"


func _maybe_switch(tod: float) -> void:
	var d := _desired(tod)
	if d != activity:
		_start_commute(d)


func _start_commute(target: String) -> void:
	activity = "commute"
	pending_activity = target
	target_place_id = _place_for(target)


func _place_for(a: String) -> String:
	match a:
		"work":
			return work_place_id
		"eat":
			return food_place_id
		_:
			return home_place_id


func _place_name(place_id: String) -> String:
	if _places.has(place_id):
		return String(_places[place_id]["name"])
	return place_id


# Wywoływane przez świat po dotarciu na miejsce.
func on_arrival() -> void:
	location_place_id = target_place_id
	activity = pending_activity
	target_place_id = ""
	commute_accum = 0.0
	idle_reason = _reason_for(activity)


func _reason_for(a: String) -> String:
	match a:
		"sleep":
			return "śpi"
		"work":
			return "pracuje (wycinka drewna)"
		"eat":
			return "je"
		"free":
			return "wypoczywa w domu"
		_:
			return "wykonuje zadanie"
