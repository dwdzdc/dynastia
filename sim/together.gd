# SimTogether — wykrywa wspólny czas (B1): dwie osoby w tym samym miejscu, w tym samym
# rodzaju zajęcia (praca, posiłek, wieczór). Czas par sumuje się przez dobę, a na jej
# koniec zamienia we wspomnienia w obie strony („pracowali razem w tartaku”).
# Miejsce to budynek (`inside`) albo, na zewnątrz, odległość nie większa niż promień.
# Przy okazji zbiera czas przy czynnościach (B3): własna praca i patrzenie, jak pracuje
# ktoś lubiany, budują więź z czynnością („act:saw”).
class_name SimTogether
extends RefCounted


var w: SimWorld
var seconds: Dictionary = {}    # "a|b|kontekst|miejsce" (a < b, id osób) -> sekundy razem
var act_seconds: Dictionary = {}    # "osoba|czynność" -> sekundy przy czynności
var with_seconds: Dictionary = {}   # "osoba|czynność|kto" -> sekundy przy czyjejś pracy

var _cfg: Dictionary
var _ctx_of: Dictionary = {}    # czynność -> kontekst
var _acc := 0.0                 # czas od ostatniej próbki


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg
	for ctx in cfg["contexts"]:
		for act in cfg["contexts"][ctx]["acts"]:
			_ctx_of[String(act)] = String(ctx)


func _is_work(act: String) -> bool:
	return w.jobs.is_work(act)


# Próbka co `sample_every` sekund (nie co krok symulacji); ludzie grupowani po
# kontekście i budynku, więc pary sprawdzane są tylko w obrębie grupy.
func sample(dt: float) -> void:
	_acc += dt
	if _acc < float(_cfg["sample_every"]):
		return
	dt = _acc
	_acc = 0.0
	var groups := {}   # "kontekst|budynek" -> [agenci]
	var focus := {}    # osoba -> czynność, przy której spędza ten moment
	for a: SimAgent in w.agents:
		if a.status != "active" or a.person_id < 0 or not _ctx_of.has(a.activity):
			continue
		var gk := "%s|%s" % [_ctx_of[a.activity], a.inside]
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append(a)
		if _is_work(a.activity):
			focus[a.person_id] = a.activity
	for gk in groups:
		_sample_group(groups[gk], focus, dt)
	for pid in focus:
		var k := "%d|%s" % [pid, focus[pid]]
		act_seconds[k] = float(act_seconds.get(k, 0.0)) + dt


func _sample_group(here: Array, focus: Dictionary, dt: float) -> void:
	for i in here.size():
		var a: SimAgent = here[i]
		for j in range(i + 1, here.size()):
			var b: SimAgent = here[j]
			if a.inside == "" and a.position.distance_to(b.position) > float(_cfg["radius"]):
				continue
			var ctx: String = _ctx_of[a.activity]
			var lo := mini(a.person_id, b.person_id)
			var hi := maxi(a.person_id, b.person_id)
			var key := "%d|%d|%s|%s" % [lo, hi, ctx, a.inside]
			seconds[key] = float(seconds.get(key, 0.0)) + dt
			if ctx == "work":
				_with(a, b, focus, dt)
				_with(b, a, focus, dt)


# `a` jest przy pracy `b`: zapamiętuje, z kim był przy tej czynności. Kto tylko patrzy,
# skupia się na pracy pierwszego pracującego obok.
func _with(a: SimAgent, b: SimAgent, focus: Dictionary, dt: float) -> void:
	if not _is_work(b.activity):
		return
	if not focus.has(a.person_id):
		focus[a.person_id] = b.activity
	var k := "%d|%s|%d" % [a.person_id, b.activity, b.person_id]
	with_seconds[k] = float(with_seconds.get(k, 0.0)) + dt


# Koniec doby: pary z wystarczającym czasem dostają wspomnienie, skalowane czasem.
func end_day() -> void:
	for key: String in seconds:
		var s: float = seconds[key]
		var parts := key.split("|")
		var ctx: Dictionary = _cfg["contexts"][parts[2]]
		if s < float(ctx.get("min_seconds", _cfg["min_seconds"])):
			continue
		var a := int(parts[0])
		var b := int(parts[1])
		var kind := String(ctx["kind"])
		var scale := minf(1.0, s / float(ctx.get("full_seconds", _cfg["full_seconds"])))
		w.bonds.remember(a, SimBonds.person(b), kind, [b], scale, parts[3])
		w.bonds.remember(b, SimBonds.person(a), kind, [a], scale, parts[3])
	var ac: Dictionary = _cfg["activity"]
	var min_s := float(ac["min_seconds"])
	var full_s := float(ac["full_seconds"])
	for key: String in act_seconds:
		var s: float = act_seconds[key]
		var parts := key.split("|")
		if s >= min_s and _is_work(parts[1]) and w.family.persons.has(int(parts[0])):
			w.bonds.remember(int(parts[0]), SimBonds.act(parts[1]), "did_work", [], minf(1.0, s / full_s))
	for key: String in with_seconds:
		var s: float = with_seconds[key]
		var parts := key.split("|")
		var pid := int(parts[0])
		var other := int(parts[2])
		if s >= min_s and w.bonds.value(pid, SimBonds.person(other)) >= float(ac["liked_threshold"]):
			w.bonds.remember(pid, SimBonds.act(parts[1]), "work_with_liked", [other], minf(1.0, s / full_s))
	seconds.clear()
	act_seconds.clear()
	with_seconds.clear()
