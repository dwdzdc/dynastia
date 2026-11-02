# SimTogether — wykrywa wspólny czas (B1): dwie osoby w tym samym miejscu, w tym samym
# rodzaju zajęcia (praca, posiłek, wieczór). Czas par sumuje się przez dobę, a na jej
# koniec zamienia we wspomnienia w obie strony („pracowali razem w tartaku”).
# Miejsce to budynek (`inside`) albo, na zewnątrz, odległość nie większa niż promień.
class_name SimTogether
extends RefCounted


var w: SimWorld
var seconds: Dictionary = {}    # "a|b|kontekst|miejsce" (a < b, id osób) -> sekundy razem

var _cfg: Dictionary
var _ctx_of: Dictionary = {}    # czynność -> kontekst


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg
	for ctx in cfg["contexts"]:
		for act in cfg["contexts"][ctx]["acts"]:
			_ctx_of[String(act)] = String(ctx)


func sample(dt: float) -> void:
	var here: Array = []
	for a: SimAgent in w.agents:
		if a.status == "active" and a.person_id >= 0 and _ctx_of.has(a.activity):
			here.append(a)
	var radius := float(_cfg["radius"])
	for i in here.size():
		var a: SimAgent = here[i]
		for j in range(i + 1, here.size()):
			var b: SimAgent = here[j]
			var ctx: String = _ctx_of[a.activity]
			if _ctx_of[b.activity] != ctx or a.inside != b.inside:
				continue
			if a.inside == "" and a.position.distance_to(b.position) > radius:
				continue
			var lo := mini(a.person_id, b.person_id)
			var hi := maxi(a.person_id, b.person_id)
			var key := "%d|%d|%s|%s" % [lo, hi, ctx, a.inside]
			seconds[key] = float(seconds.get(key, 0.0)) + dt


# Koniec doby: pary z wystarczającym czasem dostają wspomnienie, skalowane czasem.
func end_day() -> void:
	var min_s := float(_cfg["min_seconds"])
	var full_s := float(_cfg["full_seconds"])
	for key: String in seconds:
		var s: float = seconds[key]
		if s < min_s:
			continue
		var parts := key.split("|")
		var a := int(parts[0])
		var b := int(parts[1])
		var kind := String(_cfg["contexts"][parts[2]]["kind"])
		var scale := minf(1.0, s / full_s)
		w.bonds.remember(a, SimBonds.person(b), kind, [b], scale, parts[3])
		w.bonds.remember(b, SimBonds.person(a), kind, [a], scale, parts[3])
	seconds.clear()
