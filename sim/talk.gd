# SimTalk — rozmowa jako widoczna czynność (S17, N1). Dwie osoby, które akurat mają
# wolne (odpoczywają, czekają, stoją za ladą bez klientów) blisko siebie w miejscu
# publicznym, zatrzymują się i rozmawiają: stoją twarzą w twarz, nad nimi dymek.
# Po rozmowie obie strony mają wspomnienie; jego siła zależy od tego, czy się
# dogadują (charaktery). Spoza domu więź rodzi się tylko tak i przy wspólnej pracy.
# Rozmowa wolnych, młodych ludzi może skończyć się „wpadnięciem w oko” (N3).
class_name SimTalk
extends RefCounted


var w: SimWorld
var _cfg: Dictionary
var _acc := 0.0
var _last: Dictionary = {}     # "a|b" -> doba ostatniej rozmowy tej pary


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


func _free(a: SimAgent) -> bool:
	if a.status != "active" or a.controlled or a.person_id < 0 or a.hidden and a.inside != "" and not _social_place(a.inside):
		return false
	if not a.activity in _cfg["idle_acts"] or not a.interruptible():
		return false
	return a.steps.is_empty() or String(a.steps[0].get("act", "")) != "talk"


func _social_place(bid: String) -> bool:
	var b: SimBuilding = w.buildings.get(bid)
	return b != null and b.type in _cfg["social_buildings"]


func sample(dt: float) -> void:
	_acc += dt
	if _acc < float(_cfg["sample_every"]):
		return
	_acc = 0.0
	var free: Array = w.agents.filter(func(a): return _free(a))
	var paired := {}
	var day := w.clock.day_index()
	for a: SimAgent in free:
		if paired.has(a.id):
			continue
		var best: SimAgent = null
		var best_d := float(_cfg["radius"])
		var love := w.family.beloved(w.person_of(a))
		for b: SimAgent in free:
			if b == a or paired.has(b.id) or a.inside != b.inside:
				continue
			var d := a.position.distance_to(b.position)
			if b.person_id == love and d <= float(_cfg["radius"]) * 2.0:
				best = b
				break
			if d > best_d or int(_last.get(_pair(a, b), -1)) == day:
				continue
			best = b
			best_d = d
		if best != null:
			paired[a.id] = true
			paired[best.id] = true
			start(a, best)


func _pair(a: SimAgent, b: SimAgent) -> String:
	return "%d|%d" % [mini(a.person_id, b.person_id), maxi(a.person_id, b.person_id)]


func start(a: SimAgent, b: SimAgent) -> void:
	_last[_pair(a, b)] = w.clock.day_index()
	for x: Array in [[a, b], [b, a]]:
		var me: SimAgent = x[0]
		var other: SimAgent = x[1]
		var op := w.person_of(other)
		me.steps.push_front({ "t": "do", "fn": "talk_done", "arg": other.person_id })
		me.steps.push_front({ "t": "act", "act": "talk", "left": float(_cfg["seconds"]), "why": "rozmawia z: %s" % op.name,
			"inside": me.inside, "alert": false, "work": false, "partner": other.id })


# Jak dobrze się dogadują: wspólne cechy charakteru zbliżają, „zgrzyty” z danych dzielą.
func compat(p: SimPerson, q: SimPerson) -> float:
	var c := 1.0
	for ch in p.character:
		if ch in q.character:
			c += float(_cfg["same_character"])
	for pair: Array in _cfg["clash"]:
		if (pair[0] in p.character and pair[1] in q.character) or (pair[1] in p.character and pair[0] in q.character):
			c -= float(_cfg["clash_penalty"])
	return c


# Koniec rozmowy (po stronie `a`): wspomnienie o rozmówcy albo kłótnia; może wpaść w oko.
func done(a: SimAgent, other_pid: int) -> void:
	var p := w.person_of(a)
	var q: SimPerson = w.family.persons.get(other_pid)
	if p == null or q == null:
		return
	var c := compat(p, q)
	if c <= 0.0 and w.rng.chance(float(_cfg["quarrel_chance"])):
		w.bonds.remember(p.id, SimBonds.person(q.id), "quarrel", [q.id], 1.0, a.inside)
		w.events.float_text(a.position, "kłótnia!", "cost")
		return
	w.bonds.remember(p.id, SimBonds.person(q.id), "talked", [q.id], maxf(c, float(_cfg["min_scale"])), a.inside)
	w.family.after_talk(p, q, c)
