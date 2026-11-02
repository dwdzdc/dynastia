# SimField — pole uprawne (L1): działka na mapie z właścicielem (budynek gospodarstwa,
# np. dwór) i rocznym cyklem: ugór → zaorane → zasiane → dojrzałe → ściernisko.
# Orka, siew i żniwa to praca ludzi na działce (`work`); wzrost idzie sam z dobami,
# ale tylko w porach wzrostu. Dojrzałe, a nieskoszone, marnieje; zimą przepada.
# Zebrany plon leży na polu (`heap`), dopóki ktoś go nie zniesie.
class_name SimField
extends RefCounted


var id: String
var rect: Rect2
var owner_building: String
var stage: String = "fallow"   # fallow | plowed | sown | ripe | stubble
var growth: float = 0.0        # 0..1 od siewu do dojrzałości
var crop: float = 1.0          # ile z pełnego plonu zostało (marnienie dojrzałego)
var work_done: float = 0.0     # sekundy pracy przy bieżącym zadaniu
var heap: int = 0              # zebrany plon leżący na polu

var _cfg: Dictionary

const RIPE_EPS := 0.0001   # suma ułamków dób nie trafia równo w 1.0
const HEAP_INSET := 1.0    # snopy: odległość od narożnika pola
const SPOT_MARGIN := 0.8   # robotnicy nie stają na samej miedzy
const TASK_LABELS := { "plow": "orka", "sow": "siew", "harvest": "żniwa" }


func _init(spec: Dictionary, cfg: Dictionary) -> void:
	id = String(spec["id"])
	rect = Rect2(float(spec["x"]), float(spec["y"]), float(spec["w"]), float(spec["h"]))
	owner_building = String(spec["owner"])
	_cfg = cfg


func center() -> Vector2:
	return rect.get_center()


# Gdzie składa się snopy (róg pola od strony drogi).
func heap_spot() -> Vector2:
	return rect.end - Vector2(HEAP_INSET, HEAP_INSET)


# Miejsce pracy danej osoby na polu: rozrzucone po działce, stałe dla osoby.
func work_spot(person_seed: int) -> Vector2:
	var span := rect.size - Vector2(SPOT_MARGIN, SPOT_MARGIN) * 2.0
	var u := fmod(float(person_seed) * 0.618034, 1.0)
	var v := fmod(float(person_seed) * 0.381966 + 0.37, 1.0)
	return rect.position + Vector2(SPOT_MARGIN, SPOT_MARGIN) + Vector2(span.x * u, span.y * v)


func has_work(season: String) -> bool:
	return heap > 0 or task(season) != ""


# Co jest teraz do zrobienia na polu w tej porze roku ("" = nic).
func task(season: String) -> String:
	match stage:
		"fallow":
			return "plow" if season in _cfg["plow_seasons"] else ""
		"plowed":
			return "sow" if season in _cfg["sow_seasons"] else ""
		"ripe":
			return "harvest"
	return ""


# Praca przy bieżącym zadaniu. Zwraca nazwę zadania, gdy właśnie się skończyło.
func work(season: String, secs: float) -> String:
	var t := task(season)
	if t == "":
		return ""
	work_done += secs
	if work_done < float(_cfg["work_seconds"][t]):
		return ""
	work_done = 0.0
	match t:
		"plow":
			stage = "plowed"
		"sow":
			stage = "sown"
			growth = 0.0
			crop = 1.0
		"harvest":
			heap += int(round(float(_cfg["yield"]) * crop))
			stage = "stubble"
			growth = 0.0
	return t


# Koniec doby: wzrost w porach wzrostu, marnienie dojrzałego, zima zabiera resztę.
# Zwraca "rotted", gdy niezebrany plon właśnie przepadł.
func new_day(season: String) -> String:
	match stage:
		"sown":
			if season in _cfg["grow_seasons"]:
				growth = minf(1.0, growth + 1.0 / float(_cfg["grow_days"]))
				if growth >= 1.0 - RIPE_EPS:
					growth = 1.0
					stage = "ripe"
		"ripe":
			if season == String(_cfg["rot_season"]):
				stage = "fallow"
				growth = 0.0
				work_done = 0.0
				return "rotted"
			crop = maxf(0.0, crop - float(_cfg["ripe_loss_per_day"]))
		"stubble":
			if season in _cfg["plow_seasons"]:
				stage = "fallow"
	if season == String(_cfg["rot_season"]) and stage in ["plowed", "sown"]:
		# Zima zastaje niedokończoną robotę: zasiew wymarza, orka do powtórki.
		stage = "fallow"
		growth = 0.0
		work_done = 0.0
	return ""
