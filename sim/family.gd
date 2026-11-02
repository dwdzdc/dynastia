# SimFamily — ród gracza: osoby, wiek i etapy życia, traity, małżeństwa, porody,
# śmierć, głowa rodu (root), sukcesja i koniec gry przy wygaśnięciu krwi (intro §5).
# Warstwa tożsamości: ciała (SimAgent) ustawia tylko przez modyfikatory.
class_name SimFamily
extends RefCounted


var w: SimWorld
var persons: Dictionary = {}    # id -> SimPerson
var root_id: int = -1
var dynasty: String
var game_over: bool = false
var generation_of: Dictionary = {}  # person id -> pokolenie (0 = założyciele)

var _people: Dictionary
var _fam: Dictionary
var _aging: Dictionary
var _stages: Array              # etapy życia z danych, w kolejności
var _stage_start := {}          # id etapu -> przeżyte doby na jego początku
var _next_id := 1


func _init(world: SimWorld, people: Dictionary) -> void:
	w = world
	_people = people
	_fam = world.balance["family"]
	_aging = world.balance["aging"]
	_stages = _aging["stages"]
	var start := 0.0
	for st: Dictionary in _stages:
		_stage_start[String(st["id"])] = start
		start += float(st["days"])
	dynasty = String(people["dynasty"])


func setup_start() -> void:
	var by_key := {}
	var now: float = w.clock.now()
	for spec in _people["start_family"]:
		var p := SimPerson.new()
		p.id = _new_id()
		p.name = String(spec["name"])
		p.sex = String(spec["sex"])
		p.surname = String(spec.get("surname", dynasty)) if spec.get("attached", false) else dynasty
		p.birth_day = now - float(spec["age_days"]) - w.rng.next_float(0.0, float(_fam["start_age_jitter_days"]))
		p.traits = (spec.get("traits", []) as Array).duplicate()
		p.attached = bool(spec.get("attached", false))
		p.blood = not p.attached
		by_key[String(spec["key"])] = p
		persons[p.id] = p
		var a: SimAgent = w.spawn_agent(p, w.home().door() + Vector2(w.rng.next_float(-2, 2), w.rng.next_float(0.5, 2.5)))
		a.job = String(spec.get("job", "none"))
		for s in spec.get("skills", {}):
			a.skills[s] = float(spec["skills"][s])
		if bool(spec.get("root", false)):
			root_id = p.id
	for spec in _people["start_family"]:
		var p: SimPerson = by_key[String(spec["key"])]
		if spec.has("mother"):
			p.mother_id = by_key[String(spec["mother"])].id
			by_key[String(spec["mother"])].children.append(p.id)
		if spec.has("father"):
			p.father_id = by_key[String(spec["father"])].id
			by_key[String(spec["father"])].children.append(p.id)
		if spec.has("spouse"):
			var s: SimPerson = by_key[String(spec["spouse"])]
			p.spouse_id = s.id
			s.spouse_id = p.id
			p.unions.append({ "spouse": s.id, "start": now, "end": -1.0 })
	for id in persons:
		generation_of[id] = 0 if persons[id].mother_id < 0 else 1
	for id in persons:
		apply_modifiers(persons[id])


func _new_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func root() -> SimPerson:
	return persons.get(root_id)


func living() -> Array:
	var out: Array = []
	for id in _sorted_ids():
		if persons[id].alive():
			out.append(persons[id])
	return out


func _sorted_ids() -> Array:
	var ids := persons.keys()
	ids.sort()
	return ids


func days_lived(p: SimPerson) -> float:
	return p.days_lived(w.clock.now())


# Wiek w latach to tylko etykieta: interpolacja lat wewnątrz etapu, ostatni etap
# ciągnie się dalej w tym samym tempie.
func age_of(p: SimPerson) -> float:
	return years_label(days_lived(p))


func years_label(days: float) -> float:
	for i in _stages.size():
		var st: Dictionary = _stages[i]
		var start: float = _stage_start[String(st["id"])]
		var span: float = float(st["days"])
		if days < start + span or i == _stages.size() - 1:
			var y: Array = st["years"]
			return float(y[0]) + (days - start) / span * (float(y[1]) - float(y[0]))
	return 0.0


func stage_of(p: SimPerson) -> String:
	return stage_at(days_lived(p))


func stage_at(days: float) -> String:
	var out := String(_stages[0]["id"])
	for st: Dictionary in _stages:
		if days >= float(_stage_start[String(st["id"])]):
			out = String(st["id"])
	return out


# Próg z danych {stage, day} → przeżyte doby.
func life_day(at: Dictionary) -> float:
	return float(_stage_start[String(at["stage"])]) + float(at["day"])


func stage_start(stage: String) -> float:
	return float(_stage_start[stage])


func stage_label(p: SimPerson) -> String:
	match stage_of(p):
		"child":
			return "dziecko"
		"teen":
			return "podrostek"
		"adult":
			return "dorosły" if p.sex == "m" else "dorosła"
	return "starzec" if p.sex == "m" else "staruszka"


func trait_label(t: String) -> String:
	return String(_people["traits"].get(t, {}).get("label", t))


func relation_to_root(p: SimPerson) -> String:
	var r := root()
	if r == null:
		return ""
	if p.id == r.id:
		return "głowa rodu"
	if p.id == r.spouse_id:
		return "żona" if p.sex == "f" else "mąż"
	if p.mother_id == r.id or p.father_id == r.id:
		return "córka" if p.sex == "f" else "syn"
	if r.mother_id == p.id:
		return "matka"
	if r.father_id == p.id:
		return "ojciec"
	if (p.mother_id >= 0 and p.mother_id == r.mother_id) or (p.father_id >= 0 and p.father_id == r.father_id):
		return "siostra" if p.sex == "f" else "brat"
	for cid in r.children:
		var c: SimPerson = persons[cid]
		if p.mother_id == c.id or p.father_id == c.id:
			return "wnuczka" if p.sex == "f" else "wnuk"
		if p.id == c.spouse_id:
			return "synowa" if p.sex == "f" else "zięć"
	if p.attached:
		return "wżeniona" if p.sex == "f" else "wżeniony"
	return "krewna" if p.sex == "f" else "krewny"


# Modyfikatory ciała z wieku i traitów.
func apply_modifiers(p: SimPerson) -> void:
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a == null:
		return
	var st := stage_of(p)
	a.is_child = st == "child"
	a.age_eff = float(_aging["work_eff"][st])
	a.work_mult = {}
	a.speed_mult = 1.0
	a.accident_mult = 1.0
	a.quality_bonus = 0.0
	a.sick_mult = 1.4 if st in ["child", "elder"] else 1.0
	a.regen_mult = 1.0
	for t in p.traits:
		var td: Dictionary = _people["traits"].get(t, {})
		for k in td.get("work", {}):
			a.work_mult[k] = float(a.work_mult.get(k, 1.0)) * float(td["work"][k])
		a.speed_mult *= float(td.get("speed", 1.0))
		a.accident_mult *= float(td.get("accident", 1.0))
		a.quality_bonus += float(td.get("quality", 0.0))
		a.sick_mult *= float(td.get("sick", 1.0))
		a.regen_mult *= float(td.get("health_regen", 1.0))


# --- Doba ---

func new_day() -> void:
	if game_over:
		return
	for p in living():
		var before := String(p.get_meta("stage", ""))
		var now_stage := stage_of(p)
		p.set_meta("stage", now_stage)
		apply_modifiers(p)
		if before != "" and before != now_stage:
			_on_stage_change(p, now_stage)
		_roll_old_age(p)
	for p in living():
		_tick_pregnancy(p)
	for p in living():
		_roll_conception(p)
	for p in living():
		_roll_courtship(p)


func _on_stage_change(p: SimPerson, st: String) -> void:
	var a: SimAgent = w.agent_by_id(p.agent_id)
	match st:
		"teen":
			w.note("%s dorasta — może już pracować (słabiej niż dorośli)." % p.name, "good", a.position if a else null)
		"adult":
			w.note("%s jest już dorosł%s." % [p.name, "y" if p.sex == "m" else "a"], "good", a.position if a else null)
		"elder":
			w.note("%s się starzeje — słabnie w pracy." % p.name, "warn", a.position if a else null)


func _roll_old_age(p: SimPerson) -> void:
	var elder_days := days_lived(p) - stage_start("elder")
	if elder_days < 0.0:
		return
	var chance := float(_aging["old_age_death_per_day"]) * pow(float(_aging["old_age_growth_per_day"]), elder_days)
	if w.rng.chance(chance):
		var a: SimAgent = w.agent_by_id(p.agent_id)
		w.kill(a, "zmarł%s ze starości" % ("" if p.sex == "m" else "a"))


func _fertile(p: SimPerson) -> bool:
	var d := days_lived(p)
	return p.sex == "f" and d >= life_day(_fam["fertile_from"]) and d <= life_day(_fam["fertile_to"])


func _roll_conception(p: SimPerson) -> void:
	if not _fertile(p) or p.pregnant_left >= 0.0 or p.spouse_id < 0:
		return
	var s: SimPerson = persons.get(p.spouse_id)
	if s == null or not s.alive() or p.children.size() >= int(_fam["max_children"]):
		return
	# Ciasnota: w przepełnionej chacie nie przybywa dzieci.
	if living().size() >= int(_fam["max_household"]):
		return
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a == null or a.status != "active":
		return
	var c := float(_fam["conceive_per_day"])
	if a.hungry_no_food or a.health < 40.0:
		c *= 0.3
	if w.rng.chance(c):
		p.pregnant_left = float(_fam["pregnancy_days"])
		w.note("%s spodziewa się dziecka." % p.name, "good", a.position)


func _tick_pregnancy(p: SimPerson) -> void:
	if p.pregnant_left < 0.0:
		return
	p.pregnant_left -= 1.0
	if p.pregnant_left > 0.0:
		return
	p.pregnant_left = -1.0
	_give_birth(p)


func _give_birth(mother: SimPerson) -> void:
	var father: SimPerson = persons.get(mother.spouse_id)
	var ma: SimAgent = w.agent_by_id(mother.agent_id)
	var risk := 1.0
	if days_lived(mother) >= life_day(_fam["birth_risk_from"]):
		risk *= float(_fam["birth_risk_age_mult"])
	if ma != null and ma.health < 50.0:
		risk *= float(_fam["birth_risk_low_health_mult"])
	var child := SimPerson.new()
	child.id = _new_id()
	child.sex = "m" if w.rng.chance(0.5) else "f"
	child.name = _pick_name(child.sex)
	child.surname = dynasty
	child.birth_day = w.clock.now()
	child.mother_id = mother.id
	child.father_id = father.id if father != null else -1
	child.blood = mother.blood or (father != null and father.blood)
	child.traits = _inherit_traits(mother, father)
	persons[child.id] = child
	mother.children.append(child.id)
	if father != null:
		father.children.append(child.id)
	generation_of[child.id] = int(generation_of.get(mother.id, 0)) + 1
	if father != null:
		generation_of[child.id] = maxi(int(generation_of[child.id]), int(generation_of.get(father.id, 0)) + 1)

	var child_dies := w.rng.chance(float(_fam["birth_child_death"]) * risk)
	var mother_dies := w.rng.chance(float(_fam["birth_mother_death"]) * risk)
	var where: Vector2 = ma.position if ma != null else w.home().door()
	if child_dies:
		child.death_day = w.clock.now()
		child.death_cause = "zmarł%s przy porodzie" % ("" if child.sex == "m" else "a")
		w.events.add(w.clock.day_index(), w.clock.time_of_day(),
			"%s urodził%s się martw%s. %s w żałobie." % [child.name, "" if child.sex == "m" else "a",
			"y" if child.sex == "m" else "a", mother.name], "critical", where)
		w.ask_ok("Poród", "Dziecko %s i %s nie przeżyło porodu." % [mother.name, father.name if father else "?"])
	else:
		var a: SimAgent = w.spawn_agent(child, where)
		a.needs["food"] = 80.0
		apply_modifiers(child)
		child.set_meta("stage", "child")
		var trait_txt := ""
		if not child.traits.is_empty():
			trait_txt = " (%s)" % ", ".join(child.traits.map(func(t): return trait_label(t)))
		w.note("Narodziny! %s %s urodził%s się%s." % [child.name, dynasty, "" if child.sex == "m" else "a", trait_txt], "good", where)
	if mother_dies and ma != null:
		w.kill(ma, "zmarła w połogu")


func _inherit_traits(m: SimPerson, f: SimPerson) -> Array:
	var out: Array = []
	var pool: Array = _people["inheritable_traits"]
	for parent in [m, f]:
		if parent == null:
			continue
		for t in parent.traits:
			if t in pool and not t in out and w.rng.chance(float(_people["trait_inherit_chance"])):
				out.append(t)
	if w.rng.chance(float(_people["trait_random_chance"])):
		var t: String = w.rng.choice(pool)
		if not t in out:
			out.append(t)
	# sprzeczne cechy
	if "pracowity" in out and "leniwy" in out:
		out.erase("leniwy")
	if "chorowity" in out and "krzepki" in out:
		out.erase("chorowity")
	return out


func _pick_name(sex: String) -> String:
	return String(w.rng.choice(_people["names"][sex]))


# --- Małżeństwa ---

func can_marry(p: SimPerson) -> bool:
	return p.alive() and p.spouse_id < 0 and days_lived(p) >= life_day(_fam["marry_from"]) and not p.attached


func set_seeking(pid: int, on: bool) -> void:
	var p: SimPerson = persons.get(pid)
	if p == null or not can_marry(p):
		return
	p.seeking_spouse = on
	if on:
		w.note("%s rozgląda się za %s." % [p.name, "żoną" if p.sex == "m" else "mężem"], "info", null)


func _roll_courtship(p: SimPerson) -> void:
	if not p.seeking_spouse or not can_marry(p):
		return
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a == null or a.status != "active":
		return
	if not w.rng.chance(float(_fam["marry_chance_per_day"])):
		return
	var cand := _materialize_candidate(p)
	var traits_txt := "brak szczególnych cech"
	if not (cand["traits"] as Array).is_empty():
		traits_txt = ", ".join((cand["traits"] as Array).map(func(t): return trait_label(t)))
	var who := "Panna" if cand["sex"] == "f" else "Kawaler"
	w.events.ask("marriage", "Propozycja ślubu",
		"%s %s %s (lat %d) z chaty sąsiadów chce poślubić %s.\nCechy: %s.\nWesele kosztuje %d zł (brakująca kwota pójdzie w dług)." % [
			who, cand["name"], cand["surname"], int(years_label(float(cand["age_days"]))), p.name, traits_txt, int(cand["cost"])],
		[{ "label": "Zgoda na ślub", "value": "yes" }, { "label": "Odmowa", "value": "no" }],
		{ "person": p.id, "cand": cand })


# Materializacja kandydata na żądanie: deterministyczna z hash(seed, id, cel) (intro §10).
func _materialize_candidate(p: SimPerson) -> Dictionary:
	var rng := SimRng.new(SimRng.hash3(int(w.balance["world_seed"]), p.id * 1000 + int(w.clock.day_index()), "spouse"))
	var sex := "f" if p.sex == "m" else "m"
	var spread := float(_fam["spouse_age_spread_days"])
	var age_days := clampf(days_lived(p) + rng.next_float(-spread, spread * 0.5),
		life_day(_fam["marry_from"]), life_day(_fam["spouse_oldest"]))
	var traits: Array = []
	if rng.chance(0.6):
		traits.append(rng.choice(_people["inheritable_traits"]))
	return {
		"name": String(rng.choice(_people["names"][sex])),
		"surname": String(rng.choice(_people["surnames"])),
		"sex": sex,
		"age_days": age_days,
		"traits": traits,
		"cost": 15,
		"skills": { "craft": rng.next_float(0.0, 3.0), "chop": rng.next_float(0.0, 2.5), "saw": rng.next_float(0.0, 2.0) },
	}


func resolve_marriage(data: Dictionary, accepted: bool) -> void:
	var p: SimPerson = persons.get(int(data["person"]))
	if p == null or not p.alive():
		return
	if not accepted:
		w.note("%s odrzuca zaloty. Szuka dalej." % p.name, "info", null)
		return
	var cand: Dictionary = data["cand"]
	w.household.pay_or_debt(float(cand["cost"]))
	var s := SimPerson.new()
	s.id = _new_id()
	s.name = String(cand["name"])
	s.surname = String(cand["surname"]) if cand["sex"] == "m" else dynasty
	s.sex = String(cand["sex"])
	s.birth_day = w.clock.now() - float(cand["age_days"])
	s.traits = (cand["traits"] as Array).duplicate()
	s.attached = true
	s.spouse_id = p.id
	p.spouse_id = s.id
	p.seeking_spouse = false
	p.unions.append({ "spouse": s.id, "start": w.clock.now(), "end": -1.0 })
	s.unions.append({ "spouse": p.id, "start": w.clock.now(), "end": -1.0 })
	persons[s.id] = s
	generation_of[s.id] = int(generation_of.get(p.id, 0))
	var from: SimBuilding = w.building("n1")
	var a: SimAgent = w.spawn_agent(s, from.door())
	for k in cand["skills"]:
		a.skills[k] = float(cand["skills"][k])
	apply_modifiers(s)
	s.set_meta("stage", stage_of(s))
	w.note("Ślub! %s i %s %s są małżeństwem. Nowa osoba w chacie." % [p.name, s.name, String(cand["surname"])], "good", a.position)


# --- Śmierć i sukcesja ---

func on_death(p: SimPerson, cause: String) -> void:
	p.death_day = w.clock.now()
	p.death_cause = cause
	p.seeking_spouse = false
	p.pregnant_left = -1.0
	var s: SimPerson = persons.get(p.spouse_id)
	if s != null and s.alive():
		# Wdowieństwo: małżeństwo pozostaje faktem, ale żyjący może szukać nowego.
		s.spouse_id = -1
		for u in s.unions + p.unions:
			if float(u["end"]) < 0.0:
				u["end"] = w.clock.now()
	if p.id == root_id:
		_succession(p)
	elif not _blood_alive():
		_end_game()


func _blood_alive() -> bool:
	for p in living():
		if p.blood:
			return true
	return false


func is_descendant(p: SimPerson, ancestor_id: int) -> bool:
	for pid in [p.mother_id, p.father_id]:
		if pid < 0:
			continue
		if pid == ancestor_id or is_descendant(persons[pid], ancestor_id):
			return true
	return false


# Kandydaci: krew rodu. Kolejność: potomkowie zmarłego przed resztą krwi,
# dorośli przed dziećmi, starsi przed młodszymi. Małżonkowie nigdy (intro §5.3).
func succession_candidates(dead_id: int = -1) -> Array:
	var out: Array = []
	for p in living():
		if p.blood:
			out.append(p)
	var rank := func(x: SimPerson) -> int:
		var r := 0
		if dead_id >= 0 and not is_descendant(x, dead_id):
			r += 2
		if not stage_of(x) in ["adult", "elder"]:
			r += 1
		return r
	out.sort_custom(func(x, y):
		var rx: int = rank.call(x)
		var ry: int = rank.call(y)
		if rx != ry:
			return rx < ry
		return age_of(x) > age_of(y))
	return out


func _succession(dead: SimPerson) -> void:
	var cands := succession_candidates(dead.id)
	if cands.is_empty():
		_end_game()
		return
	root_id = -1
	var opts: Array = []
	for c in cands.slice(0, 5):
		opts.append({ "label": "%s, lat %d (%s)" % [c.name, int(age_of(c)), stage_label(c)], "value": c.id })
	w.events.ask("succession", "Śmierć głowy rodu",
		"%s %s nie żyje (%s).\nKto poprowadzi ród %s?" % [dead.name, dead.surname, dead.death_cause, dynasty],
		opts, {})


func set_root(pid: int) -> void:
	var p: SimPerson = persons.get(pid)
	if p == null or not p.alive():
		return
	root_id = pid
	w.note("%s jest nową głową rodu %s." % [p.name, dynasty], "good", null)


func _end_game() -> void:
	if game_over:
		return
	game_over = true
	w.events.ask("game_over", "Koniec rodu",
		"Wygasła krew rodu %s. Nie żyje nikt z linii założycieli.\nRód przetrwał %d dni." % [dynasty, w.clock.day_index()],
		[{ "label": "Zacznij od nowa", "value": "restart" }], {})
