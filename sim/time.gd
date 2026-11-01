# SimClock — zegar symulacji (doba, sezony, rok, światło, prędkości).
# Czysta logika (RefCounted). Widok odczytuje stan, nie dzieli z nim czasu.
#
# Czas płynie w "ułamku doby" (_tod, 0..1) przeliczanym z realnych sekund,
# więc szybkie przewijanie jest niezależne od FPS (patrz ADR-0002, intro §12).
class_name SimClock
extends RefCounted


var day_seconds: float = 30.0
var days_per_season: int = 5
var days_per_year: int = 20
var seasons: Array = ["spring", "summer", "autumn", "winter"]
var daylight: Dictionary = {}
var twilight: float = 0.06
var max_speed: int = 3

var speed: int = 1
var _day: int = 0          # bezwzględny indeks doby
var _tod: float = 0.0       # ułamek doby 0..1
var _paused_speed: int = 1


func _init(cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		return
	var t: Dictionary = cfg.get("time", {})
	day_seconds = float(t.get("day_seconds", day_seconds))
	days_per_season = int(t.get("days_per_season", days_per_season))
	days_per_year = int(t.get("days_per_year", days_per_year))
	max_speed = int(t.get("max_speed", max_speed))
	twilight = float(t.get("twilight", twilight))
	if t.has("seasons"):
		seasons = (t["seasons"] as Array).duplicate()
	if t.has("daylight"):
		daylight = t["daylight"]


func advance(delta: float) -> void:
	if speed <= 0:
		return
	var frac := delta * float(speed) / day_seconds
	if frac <= 0.0:
		return
	_tod += frac
	if _tod >= 1.0:
		var whole := int(floor(_tod))
		_day += whole
		_tod -= float(whole)


func set_speed(s: int) -> void:
	speed = clampi(s, 0, max_speed)


func toggle_pause() -> void:
	if speed == 0:
		speed = _paused_speed
	else:
		_paused_speed = speed
		speed = 0


func set_time(day_index: int, tod: float) -> void:
	_day = day_index
	_tod = clampf(tod, 0.0, 1.0)


# --- Odczyt stanu ---

func day_index() -> int:
	return _day


func time_of_day() -> float:
	return _tod


func current_year() -> int:
	return int(floor(_day / float(days_per_year)))


func current_season() -> String:
	var idx := int(floor(_day / float(days_per_season))) % seasons.size()
	return seasons[idx]


func day_of_season() -> int:
	return _day % days_per_season


func day_of_year() -> int:
	return _day % days_per_year


func hour_minute() -> Vector2i:
	var mins := int(_tod * 24 * 60)
	return Vector2i(mins / 60, mins % 60)


func daylight_bounds() -> Dictionary:
	return daylight.get(current_season(), { "sunrise": 0.25, "sunset": 0.75 })


# 0..1: 0 = noc, 1 = pełny dzień. Płynne przejście przez zmierzch (twilight).
func light_factor() -> float:
	var d := daylight_bounds()
	var sunrise := float(d["sunrise"])
	var sunset := float(d["sunset"])
	if _tod >= sunrise and _tod <= sunset:
		return 1.0
	if _tod < sunrise:
		return clampf((_tod - (sunrise - twilight)) / twilight, 0.0, 1.0)
	return clampf(((sunset + twilight) - _tod) / twilight, 0.0, 1.0)
