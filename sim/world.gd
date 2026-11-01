# SimWorld — świat symulacji (Etap 2): zegar, miejsca, anonimowi agenci.
# Własność pozycji/ruchu leży tutaj (deterministycznie, prosty dojazd liniowy),
# dzięki czemu cały dzień osady da się przewinąć headless. game/ tylko renderuje.
#
# Patrz ADR-0002 (determinizm) — generowanie i ruch są w pełni deterministyczne
# z seeda; nie ma randifa() ani iteracji po nieuporządkowanych mapach (sortujemy id).
class_name SimWorld
extends RefCounted


const SimClock := preload("res://sim/time.gd")
const SimAgent := preload("res://sim/agent.gd")
const SimRng := preload("res://sim/rng.gd")

var clock: SimClock
var agents: Array = []
var places: Dictionary = {}   # id -> { name, type, position: Vector2 }
var move_speed: float
var arrive_radius: float


func _init(seed: int, balance: Dictionary, map: Dictionary) -> void:
	clock = SimClock.new(balance)

	for p in map["places"]:
		places[p["id"]] = {
			"name": p["name"],
			"type": p["type"],
			"position": Vector2(float(p["x"]), float(p["y"])),
		}

	move_speed = float(balance["movement"]["speed"])
	arrive_radius = float(balance["movement"]["arrive_radius"])

	var houses := _ids_of_type("house")
	var works := _ids_of_type("work")
	var foods := _ids_of_type("food")
	var count := int(balance["population"]["count"])
	var rng := SimRng.new(seed)

	for i in count:
		var home := _pick_or(houses, i)
		var work := _pick_random_or(works, rng, home)
		var food := _pick_random_or(foods, rng, home)
		var age := rng.next_int(16, 59)
		var skills := { "lumber": rng.next_int(1, 6) }
		var agent := SimAgent.new(i, "Osadnik %d" % i, age, skills, home, work, food, places, balance)
		agent.position = place_position(home)
		agent.location_place_id = home
		agents.append(agent)


func _ids_of_type(t: String) -> Array:
	var out: Array = []
	for id in places:
		if String(places[id]["type"]) == t:
			out.append(id)
	out.sort()
	return out


func _pick_or(items: Array, idx: int) -> String:
	if items.is_empty():
		return ""
	return String(items[idx % items.size()])


func _pick_random_or(items: Array, rng: SimRng, fallback: String) -> String:
	if items.is_empty():
		return fallback
	return String(items[rng.choice_i(items)])


func place_position(id: String) -> Vector2:
	if places.has(id):
		return places[id]["position"]
	return Vector2.ZERO


func place_name(id: String) -> String:
	if places.has(id):
		return String(places[id]["name"])
	return id


# delta_real: sekundy rzeczywiste (widok). Przeliczamy na sekundy symulacyjne.
func tick(delta_real: float) -> void:
	clock.advance(delta_real)
	var delta_sim := delta_real * float(clock.speed)
	if delta_sim <= 0.0:
		return
	var tod := clock.time_of_day()
	for a in agents:
		a.tick(tod, delta_sim)
		if a.activity == "commute":
			a.commute_accum += delta_sim
			var tpos := place_position(a.target_place_id)
			var step := move_speed * delta_sim
			var dist: float = a.position.distance_to(tpos)
			if dist <= maxf(step, arrive_radius):
				a.position = tpos
				a.on_arrival()
			else:
				a.position = a.position.move_toward(tpos, step)
		else:
			a.commute_accum = 0.0


func find_agent(id: int) -> SimAgent:
	for a in agents:
		if a.id == id:
			return a
	return null
