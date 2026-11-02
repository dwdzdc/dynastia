# SimField — pole uprawne (L1, L2): działka na mapie z właścicielem (budynek gospodarstwa,
# np. dwór), podzielona na zagony. Każdy zagon ma własny cykl: ugór → zaorany → zasiany
# → dojrzały → ściernisko. Robotnik bierze wolny zagon (rezerwacja), idzie wzdłuż niego,
# orząc, siejąc albo kosząc, i bierze następny. Zboże rośnie samo z dobami, ale tylko
# w porach wzrostu; dojrzałe, a nieskoszone, marnieje, zimą przepada.
# Skoszony plon leży na polu (`heap`), dopóki ktoś go nie zniesie.
class_name SimField
extends RefCounted


var id: String
var rect: Rect2
var owner_building: String
var cells: Array = []          # zagony: { start, end, stage, growth, crop, done, by }
var heap: int = 0              # skoszony plon leżący na polu

var _cfg: Dictionary
var _heap_frac := 0.0          # ułamek snopa z poprzednich zagonów (zmarniały plon nie ginie w zaokrągleniu)

const RIPE_EPS := 0.0001   # suma ułamków dób nie trafia równo w 1.0
const HEAP_INSET := 1.0    # snopy: odległość od narożnika pola
const EDGE := 0.4          # zagon zaczyna się kawałek od miedzy
const TASK_LABELS := { "plow": "orka", "sow": "siew", "harvest": "żniwa" }


func _init(spec: Dictionary, cfg: Dictionary) -> void:
	id = String(spec["id"])
	rect = Rect2(float(spec["x"]), float(spec["y"]), float(spec["w"]), float(spec["h"]))
	owner_building = String(spec["owner"])
	_cfg = cfg
	# Zagony: rzędy wzdłuż X, każdy rząd pocięty na odcinki; kolejność „wężykiem”,
	# żeby wolne zagony szły rząd po rzędzie jak przy prawdziwej orce.
	var cs: Array = cfg["cell"]
	var cols := maxi(1, int(rect.size.x / float(cs[0])))
	var rows := maxi(1, int(rect.size.y / float(cs[1])))
	var cw := rect.size.x / float(cols)
	var rh := rect.size.y / float(rows)
	for r in rows:
		var y := rect.position.y + rh * (r + 0.5)
		for k in cols:
			var fwd := r % 2 == 0
			var c := k if fwd else cols - 1 - k
			var x0 := rect.position.x + cw * c + EDGE
			var x1 := rect.position.x + cw * (c + 1) - EDGE
			cells.append({
				"start": Vector2(x0 if fwd else x1, y), "end": Vector2(x1 if fwd else x0, y),
				"stage": "fallow", "growth": 0.0, "crop": 1.0, "done": 0.0, "by": -1,
			})


func center() -> Vector2:
	return rect.get_center()


# Gdzie składa się snopy (róg pola od strony drogi).
func heap_spot() -> Vector2:
	return rect.end - Vector2(HEAP_INSET, HEAP_INSET)


# Co jest do zrobienia na zagonie w tej porze roku ("" = nic).
func cell_task(i: int, season: String) -> String:
	match String(cells[i]["stage"]):
		"fallow":
			return "plow" if season in _cfg["plow_seasons"] else ""
		"plowed":
			return "sow" if season in _cfg["sow_seasons"] else ""
		"ripe":
			return "harvest"
	return ""


# Pierwszy zagon z robotą, którego nikt nie zajął (-1 = brak).
func free_cell(season: String) -> int:
	for i in cells.size():
		if int(cells[i]["by"]) < 0 and cell_task(i, season) != "":
			return i
	return -1


func has_work(season: String) -> bool:
	return heap > 0 or free_cell(season) >= 0


func claim(i: int, agent_id: int) -> void:
	cells[i]["by"] = agent_id


func release(i: int, agent_id: int) -> void:
	if i >= 0 and i < cells.size() and int(cells[i]["by"]) == agent_id:
		cells[i]["by"] = -1


# Postęp roboty na zagonie 0..1 (robotnik idzie wzdłuż zagonu razem z postępem).
func progress(i: int, season: String) -> float:
	var t := cell_task(i, season)
	if t == "":
		return 0.0
	return clampf(float(cells[i]["done"]) / float(_cfg["work_seconds"][t]), 0.0, 1.0)


# Praca na zagonie. Zwraca nazwę zadania, gdy właśnie się skończyło.
func work(i: int, season: String, secs: float) -> String:
	var t := cell_task(i, season)
	if t == "":
		return ""
	var c: Dictionary = cells[i]
	c["done"] = float(c["done"]) + secs
	if float(c["done"]) < float(_cfg["work_seconds"][t]):
		return ""
	c["done"] = 0.0
	match t:
		"plow":
			c["stage"] = "plowed"
		"sow":
			c["stage"] = "sown"
			c["growth"] = 0.0
			c["crop"] = 1.0
		"harvest":
			var got := float(_cfg["yield_per_cell"]) * float(c["crop"]) + _heap_frac
			heap += int(floor(got))
			_heap_frac = got - floor(got)
			c["stage"] = "stubble"
			c["growth"] = 0.0
	return t


# Ile zagonów jest w danym stanie (do komunikatów i testów).
func count(stage: String) -> int:
	var n := 0
	for c: Dictionary in cells:
		if c["stage"] == stage:
			n += 1
	return n


# Koniec doby: wzrost w porach wzrostu, marnienie dojrzałego, zima zabiera resztę.
# Zwraca liczbę zagonów, których plon właśnie przepadł.
func new_day(season: String) -> int:
	var rotted := 0
	var winter := season == String(_cfg["rot_season"])
	for c: Dictionary in cells:
		match String(c["stage"]):
			"sown":
				if winter:
					_reset(c)   # zima zastaje zasiew: wymarza
				elif season in _cfg["grow_seasons"]:
					c["growth"] = minf(1.0, float(c["growth"]) + 1.0 / float(_cfg["grow_days"]))
					if float(c["growth"]) >= 1.0 - RIPE_EPS:
						c["growth"] = 1.0
						c["stage"] = "ripe"
			"ripe":
				if winter:
					_reset(c)
					rotted += 1
				else:
					c["crop"] = maxf(0.0, float(c["crop"]) - float(_cfg["ripe_loss_per_day"]))
			"plowed":
				if winter:
					_reset(c)
			"stubble":
				if season in _cfg["plow_seasons"]:
					c["stage"] = "fallow"
	return rotted


func _reset(c: Dictionary) -> void:
	c["stage"] = "fallow"
	c["growth"] = 0.0
	c["done"] = 0.0
