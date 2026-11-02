# SimFamily — rejestr wszystkich ludzi i rodów świata (F1): osoby, wiek i etapy życia,
# cechy, małżeństwa, porody, śmierć, rooty i sukcesja. Ród gracza to jeden z rodów;
# tylko on dostaje okna decyzji i tylko jego wygaśnięcie kończy grę (intro §5).
# Warstwa tożsamości: ciała (SimAgent) ustawia tylko przez modyfikatory.
class_name SimFamily
extends RefCounted


var w: SimWorld
var persons: Dictionary = {}    # id -> SimPerson
var lineages: Dictionary = {}   # id -> SimLineage
var player_lineage_id: int = -1
var dynasty: String
var game_over: bool = false
var generation_of: Dictionary = {}  # person id -> pokolenie (0 = założyciele)
var strength: Dictionary = {}   # id osoby -> siła przynależności do własnego rodu (raz na dobę)

var _people: Dictionary
var _fam: Dictionary
var _aging: Dictionary
var _stages: Array              # etapy życia z danych, w kolejności
var _stage_start := {}          # id etapu -> przeżyte doby na jego początku
var _next_id := 1
var _next_lineage := 1

# Root rodu gracza; mieszka w SimLineage, tu tylko skrót.
var root_id: int:
	get:
		var l := player_lineage()
		return l.root_id if l != null else -1
	set(v):
		player_lineage().root_id = v

const SPAWN_SPREAD_X := 2.0             # rozrzut miejsca startu przy drzwiach chaty
const SPAWN_DEPTH := Vector2(0.5, 2.5)  # odległość przed drzwiami (min, max)
const SUCCESSION_OPTIONS := 5           # ilu kandydatów pokazuje okno sukcesji


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
	player_lineage_id = new_lineage(dynasty).id


func setup_start() -> void:
	for id in spawn_family(_people["start_family"], player_lineage(), w.home()):
		w.join_household(persons[id], w.household)


# Ród ze specyfikacji w danych (osoby, pokrewieństwo, małżeństwa) w danym domu.
# Wspólne dla rodu gracza i rodów AI. Zwraca id osób w kolejności specyfikacji.
func spawn_family(specs: Array, l: SimLineage, home: SimBuilding) -> Array:
	var by_key := {}
	var ids: Array = []
	var now: float = w.clock.now()
	for spec in specs:
		var p := SimPerson.new()
		p.id = _new_id()
		p.name = String(spec["name"])
		p.sex = String(spec["sex"])
		p.surname = String(spec.get("surname", l.surname)) if spec.get("attached", false) else l.surname
		p.birth_day = now - float(spec["age_days"]) - w.rng.next_float(0.0, float(_fam["start_age_jitter_days"]))
		p.traits = (spec.get("traits", []) as Array).duplicate()
		p.character = (spec.get("character", []) as Array).duplicate()
		p.attached = bool(spec.get("attached", false))
		p.blood = not p.attached
		by_key[String(spec["key"])] = p
		persons[p.id] = p
		ids.append(p.id)
		l.add(p)
		var a: SimAgent = w.spawn_agent(p, home.door() + Vector2(w.rng.next_float(-SPAWN_SPREAD_X, SPAWN_SPREAD_X), w.rng.next_float(SPAWN_DEPTH.x, SPAWN_DEPTH.y)))
		a.home_id = home.id
		a.job = String(spec.get("job", "none"))
		for s in spec.get("skills", {}):
			a.skills[s] = float(spec["skills"][s])
		if bool(spec.get("root", false)):
			l.root_id = p.id
	for spec in specs:
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
	for id in ids:
		generation_of[id] = 0 if persons[id].mother_id < 0 else 1
	_seed_start_bonds(ids)
	update_strength()
	for id in ids:
		apply_modifiers(persons[id])
	return ids


# Przeszłość rodziny startowej jako wspomnienia (wychowanie, rodzeństwo, małżeństwo),
# rodzaje z memories.json → start.
func _seed_start_bonds(ids: Array) -> void:
	var cfg: Dictionary = w.memories["start"]
	for id in ids:
		var p: SimPerson = persons[id]
		for pid in [p.mother_id, p.father_id]:
			if pid >= 0:
				_remember_all(pid, p.id, cfg["parent_to_child"])
				_remember_all(p.id, pid, cfg["child_to_parent"])
		if p.spouse_id >= 0:
			_remember_all(p.id, p.spouse_id, cfg["spouses"])
		for oid in ids:
			var o: SimPerson = persons[oid]
			if o.id != p.id and siblings(p, o):
				_remember_all(p.id, o.id, cfg["siblings"])


func _remember_all(from: int, to: int, kinds: Array) -> void:
	for k in kinds:
		w.bonds.remember(from, SimBonds.person(to), String(k), [to])


func siblings(a: SimPerson, b: SimPerson) -> bool:
	return (a.mother_id >= 0 and a.mother_id == b.mother_id) or (a.father_id >= 0 and a.father_id == b.father_id)


func _new_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


# Siła liczona per ród od jego roota (S12); wynik scalony w jeden słownik osób.
func update_strength() -> void:
	strength = {}
	for l: SimLineage in lineages.values():
		if l.root_id < 0:
			continue
		var s := SimBelonging.compute(self, w.bonds, l, w.balance["belonging"])
		for id in s:
			strength[id] = s[id]


func new_lineage(lname: String, surname: String = "") -> SimLineage:
	var l := SimLineage.new(_next_lineage, lname, surname)
	_next_lineage += 1
	lineages[l.id] = l
	return l


func player_lineage() -> SimLineage:
	return lineages.get(player_lineage_id)


func is_ours(p: SimPerson) -> bool:
	return p != null and p.lineage_id == player_lineage_id


func lineage_of(p: SimPerson) -> SimLineage:
	return lineages.get(p.lineage_id)


func living_members(lineage_id: int) -> Array:
	var out: Array = []
	var l: SimLineage = lineages.get(lineage_id)
	if l == null:
		return out
	for id in l.members:
		if persons[id].alive():
			out.append(persons[id])
	return out


func root() -> SimPerson:
	return persons.get(root_id)


# Żywi członkowie rodu gracza (to, co gracz nazywa „rodziną”), po id.
func living() -> Array:
	var out: Array = []
	for id in _sorted_ids():
		if persons[id].alive() and persons[id].lineage_id == player_lineage_id:
			out.append(persons[id])
	return out


# Wszyscy żywi, także ci, którzy odeszli z rodu.
func all_living() -> Array:
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


func character_label(c: String) -> String:
	return String(_people["character"].get(c, {}).get("label", c))


# Kolejność na liście rodu: root, małżonek, dzieci, rodzice, rodzeństwo, wnuki,
# wżenieni, reszta; w obrębie grupy od najstarszych.
const KIN_ORDER := ["głowa rodu", "żona", "mąż", "córka", "syn", "matka", "ojciec", "siostra", "brat",
	"wnuczka", "wnuk", "synowa", "zięć", "wżeniona", "wżeniony"]


func by_kinship() -> Array:
	var out := living()
	var rank := func(p: SimPerson) -> int:
		var i := KIN_ORDER.find(relation_to_root(p))
		return i if i >= 0 else KIN_ORDER.size()
	out.sort_custom(func(x, y):
		var rx: int = rank.call(x)
		var ry: int = rank.call(y)
		if rx != ry:
			return rx < ry
		return x.birth_day < y.birth_day)
	return out


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
	a.sick_mult = float(_aging["sick_mult"].get(st, 1.0))
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
	for p in all_living():
		var before := String(p.get_meta("stage", ""))
		var now_stage := stage_of(p)
		p.set_meta("stage", now_stage)
		apply_modifiers(p)
		if before != "" and before != now_stage and p.lineage_id == player_lineage_id:
			_on_stage_change(p, now_stage)
		_roll_old_age(p)
	for p in all_living():
		_tick_pregnancy(p)
	for p in all_living():
		_roll_conception(p)
	_check_courtships()
	update_strength()
	_check_departures()


# Odejście (C3): kto ma siłę przynależności poniżej progu przez kilka dób z rzędu,
# zakłada własny ród jednoosobowy i wyprowadza się. Root nie odchodzi, dzieci też nie.
func _check_departures() -> void:
	var cfg: Dictionary = w.balance["belonging"]
	for p in all_living():
		var pl := lineage_of(p)
		if pl == null or p.id == pl.root_id:
			p.weak_days = 0
			continue
		var a: SimAgent = w.agent_by_id(p.agent_id)
		if a == null or a.status != "active" or not stage_of(p) in cfg["leave_stages"]:
			p.weak_days = 0
			continue
		if float(strength.get(p.id, 1.0)) < float(cfg["leave_below"]):
			p.weak_days += 1
		else:
			p.weak_days = 0
		if p.weak_days >= int(cfg["leave_days"]):
			depart(p)


func depart(p: SimPerson) -> void:
	var cfg: Dictionary = w.balance["belonging"]
	var old := lineage_of(p)
	var kin: Array = []
	for o in living_members(old.id):
		if o.id != p.id:
			kin.append(SimBonds.person(o.id))
	var why: Array = []
	for e in w.bonds.strongest(p.id, kin, int(w.memories["departure_memories"]) * 4):
		var txt := w.bonds.describe(e["m"], e["t"])
		if not txt in why and why.size() < int(w.memories["departure_memories"]):
			why.append(txt)
	old.remove(p)
	var l := new_lineage("%s (%s)" % [p.surname, p.name])
	l.add(p)
	l.root_id = p.id
	p.weak_days = 0
	var a: SimAgent = w.agent_by_id(p.agent_id)
	# Własne gospodarstwo: wolny dom, a gdy go nie ma, kąt u sąsiadów.
	var house: SimBuilding = w.free_house()
	var hh := w.new_household(house.id if house != null else String(cfg["leave_home"]), 0.0)
	w.join_household(p, hh)
	a.job = String(cfg["leave_job"])
	w.jobs.replan(a)
	var pamieta := "niewiele wspólnego z bliskimi" if why.is_empty() else "; ".join(why)
	var text := "%s odchodzi z rodu %s i wyprowadza się (%s). Pamięta: %s." % [
		p.name, old.name, w.home_of(a).name if w.home_of(a) != null else "bez domu", pamieta]
	w.chronicle.add(w.clock.now(), "departure", text, [p.id], old.id)
	if old.id == player_lineage_id:
		w.note("%s wyprowadza się z chaty." % p.name, "warn", a.position)


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
	if s == null or not s.alive() or s.lineage_id != p.lineage_id or p.children.size() >= int(_fam["max_children"]):
		return
	# Ciasnota: w przepełnionym rodzie nie przybywa dzieci.
	if living_members(p.lineage_id).size() >= int(_fam["max_household"]):
		return
	var a: SimAgent = w.agent_by_id(p.agent_id)
	if a == null or a.status != "active":
		return
	var c := float(_fam["conceive_per_day"])
	if a.hungry_no_food or a.health < float(_fam["conceive_weak_health"]):
		c *= float(_fam["conceive_weak_mult"])
	if w.rng.chance(c):
		p.pregnant_left = float(_fam["pregnancy_days"])
		if is_ours(p):
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
	if ma != null and ma.health < float(_fam["birth_risk_low_health"]):
		risk *= float(_fam["birth_risk_low_health_mult"])
	var child := SimPerson.new()
	child.id = _new_id()
	child.sex = "m" if w.rng.chance(float(_fam["boy_chance"])) else "f"
	child.name = _pick_name(child.sex)
	var cl := _lineage_for_child(mother, father)
	child.surname = cl.surname
	child.birth_day = w.clock.now()
	child.mother_id = mother.id
	child.father_id = father.id if father != null else -1
	# Krew rodu, do którego dziecko wchodzi: ma ją, jeśli któryś rodzic jest krwią tego rodu.
	child.blood = (mother.blood and mother.lineage_id == cl.id) or (father != null and father.blood and father.lineage_id == cl.id)
	child.traits = _inherit("traits", mother.traits, father.traits if father else [])
	child.character = _inherit("character", mother.character, father.character if father else [])
	persons[child.id] = child
	cl.add(child)
	mother.children.append(child.id)
	if father != null:
		father.children.append(child.id)
	generation_of[child.id] = int(generation_of.get(mother.id, 0)) + 1
	if father != null:
		generation_of[child.id] = maxi(int(generation_of[child.id]), int(generation_of.get(father.id, 0)) + 1)

	var child_dies := w.rng.chance(float(_fam["birth_child_death"]) * risk)
	var mother_dies := w.rng.chance(float(_fam["birth_mother_death"]) * risk)
	var where: Vector2 = ma.position if ma != null else w.home_of(w.agent_by_id(mother.agent_id)).door()
	var ours := is_ours(child)
	if child_dies:
		child.death_day = w.clock.now()
		child.death_cause = "zmarł%s przy porodzie" % ("" if child.sex == "m" else "a")
		if ours:
			w.events.add(w.clock.day_index(), w.clock.time_of_day(),
				"%s urodził%s się martw%s. %s w żałobie." % [child.name, "" if child.sex == "m" else "a",
				"y" if child.sex == "m" else "a", mother.name], "critical", where)
			w.ask_ok("Poród", "Dziecko %s i %s nie przeżyło porodu." % [mother.name, father.name if father else "?"])
	else:
		var a: SimAgent = w.spawn_agent(child, where)
		var mh: SimHousehold = w.households.get(mother.household_id)
		if mh != null:
			w.join_household(child, mh)
		a.needs["food"] = float(_fam["newborn_food"])
		apply_modifiers(child)
		child.set_meta("stage", "child")
		for par in [mother, father]:
			if par != null and par.alive():
				_remember_all(par.id, child.id, w.memories["on_birth"]["parent_to_child"])
		var trait_txt := ""
		if not child.traits.is_empty():
			trait_txt = " (%s)" % ", ".join(child.traits.map(func(t): return trait_label(t)))
		if ours:
			w.note("Narodziny! %s %s urodził%s się%s." % [child.name, child.surname, "" if child.sex == "m" else "a", trait_txt], "good", where)
		w.chronicle.add(w.clock.now(), "birth", "Narodziny: %s, dziecko %s%s." % [child.name, mother.name,
			(" i " + father.name) if father != null else ""], [child.id, mother.id], child.lineage_id)
	if mother_dies and ma != null:
		w.kill(ma, "zmarła w połogu")


# Dziedziczenie listy (cechy albo charakter) według people.json → inheritance[kind].
# Sprzeczne pary [zostaje, odpada] rozstrzyga kolejność w danych.
# Dziecko wchodzi do rodu krwi; gdy oboje rodzice są krwią różnych rodów,
# do rodu gracza, jeśli któreś z nich w nim jest, w przeciwnym razie do rodu matki.
func _lineage_for_child(mother: SimPerson, father: SimPerson) -> SimLineage:
	var opts: Array = [mother] if father == null else [mother, father]
	for par: SimPerson in opts:
		if par.lineage_id == player_lineage_id:
			return player_lineage()
	return lineage_of(mother) if lineage_of(mother) != null else player_lineage()


func _inherit(kind: String, from_mother: Array, from_father: Array) -> Array:
	var cfg: Dictionary = _people["inheritance"][kind]
	var pool: Array = cfg["pool"]
	var out: Array = []
	for t in from_mother + from_father:
		if t in pool and not t in out and w.rng.chance(float(cfg["inherit_chance"])):
			out.append(t)
	if w.rng.chance(float(cfg["random_chance"])):
		var t: String = w.rng.choice(pool)
		if not t in out:
			out.append(t)
	for pair: Array in cfg["conflicts"]:
		if pair[0] in out and pair[1] in out:
			out.erase(pair[1])
	return out


func _pick_name(sex: String) -> String:
	return String(w.rng.choice(_people["names"][sex]))


# --- Małżeństwa ---

func can_marry(p: SimPerson) -> bool:
	var l := lineage_of(p)
	if l != null and l.role == "trader":
		return false   # kupiec wędrowny tylko przejeżdża
	return p.alive() and p.spouse_id < 0 and days_lived(p) >= life_day(_fam["marry_from"]) and not p.attached


# --- Romans jako proces (S18, N3–N5) ---

func _romance() -> Dictionary:
	return w.balance["romance"]


# Czy tych dwoje w ogóle może się w sobie zakochać „na serio” (do ślubu).
func could_court(p: SimPerson, q: SimPerson) -> bool:
	return p.sex != q.sex and p.lineage_id != q.lineage_id and can_marry(p) and can_marry(q) \
		and absf(days_lived(p) - days_lived(q)) <= float(_marriage()["max_age_gap_days"])


func love(p: SimPerson, q: SimPerson) -> float:
	return w.bonds.value(p.id, SimBonds.love(q.id))


# W kim osoba jest zakochana (najmocniej, powyżej progu szukania okazji); -1 = w nikim.
func beloved(p: SimPerson) -> int:
	if p == null:
		return -1
	var best := -1
	var best_v := float(_romance()["seek_love"])
	for t: String in w.bonds.targets_of(p.id, "love:"):
		var v := w.bonds.value(p.id, t)
		if v >= best_v:
			best_v = v
			best = int(t.substr(5))
	return best


# Po rozmowie (N3, N4): wolnemu może ktoś wpaść w oko; kto już jest zakochany, ten
# z każdą rozmową bardziej (zaloty), a z sakwy kupuje drobny prezent.
func after_talk(p: SimPerson, q: SimPerson, compat: float) -> void:
	if not could_court(p, q):
		return
	var r := _romance()
	if love(p, q) <= 0.0:
		var liking := maxf(0.0, w.bonds.value(p.id, SimBonds.person(q.id)))
		if w.rng.chance(float(r["eye_chance"]) + float(r["eye_per_liking"]) * liking):
			w.bonds.remember(p.id, SimBonds.love(q.id), "caught_eye", [q.id])
			if is_ours(p):
				w.note("%s zerka na %s (ród %s)." % [p.name, q.name, lineage_of(q).name], "info", null)
		return
	w.bonds.remember(p.id, SimBonds.love(q.id), "courted", [q.id], maxf(compat, 0.1))
	if love(p, q) >= float(r["gift_love"]) and p.purse >= float(r["gift_cost"]):
		p.purse -= float(r["gift_cost"])
		p.held = minf(p.held, p.purse)
		w.bonds.remember(q.id, SimBonds.love(p.id), "gift", [p.id])
		var a: SimAgent = w.agent_by_id(p.agent_id)
		if a != null:
			w.events.float_text(a.position, "prezent dla: %s" % q.name, "info")


# Raz na dobę: pary zakochane w sobie nawzajem dochodzą do rozmowy rodzin (N5).
func _check_courtships() -> void:
	var r := _romance()
	for p in all_living():
		if p.has_meta("engaged") or not can_marry(p):
			continue
		var qid := beloved(p)
		var q: SimPerson = persons.get(qid)
		if q == null or q.has_meta("engaged") or beloved(q) != p.id or p.id > q.id:
			continue
		if love(p, q) < float(r["propose_love"]) or love(q, p) < float(r["propose_love"]) or not could_court(p, q):
			continue
		_families_talk(p, q)


# Pozycja rodu (S19): pieniądze w skrzyniach, budynki i to, co myślą o nim inni.
func standing(l: SimLineage) -> float:
	var r := _romance()
	var cash := 0.0
	var mem := living_members(l.id)
	var hh := {}
	for p: SimPerson in mem:
		hh[p.household_id] = true
	for hid in hh:
		var h: SimHousehold = w.households.get(hid)
		if h != null:
			cash += maxf(h.cash, 0.0) - h.debt
	var owned := 0
	for b: SimBuilding in w.buildings.values():
		if b.owner_kind == "lineage" and b.owner_id == l.id:
			owned += 1
	var opinion := 0.0
	var n := 0
	for o in all_living():
		if o.lineage_id == l.id:
			continue
		for m: SimPerson in mem:
			opinion += w.bonds.value(o.id, SimBonds.person(m.id))
			n += 1
	return cash + float(r["standing_building"]) * owned + float(r["standing_opinion"]) * (opinion / maxf(1.0, float(n)))


# Rodziny się dogadują: przy dużej różnicy pozycji (mezalians) wyżej stojący ród musi
# się zgodzić — trudno, ale możliwe. Gdy w grę wchodzi ród gracza, decyduje gracz.
func _families_talk(p: SimPerson, q: SimPerson) -> void:
	var r := _romance()
	var lp := lineage_of(p)
	var lq := lineage_of(q)
	var sp := standing(lp)
	var sq := standing(lq)
	var gap := absf(sp - sq)
	var higher: SimLineage = lp if sp >= sq else lq
	var lower_person: SimPerson = q if higher == lp else p
	if gap > float(r["mesalliance_gap"]) and higher.id != player_lineage_id:
		var avg := (love(p, q) + love(q, p)) * 0.5
		var chance := clampf(avg / float(r["consent_love_scale"]) - (gap - float(r["mesalliance_gap"])) / float(r["mesalliance_gap"]),
			float(r["consent_min"]), float(r["consent_max"]))
		if not w.rng.chance(chance):
			var head: SimPerson = persons.get(higher.root_id)
			for x in [p, q]:
				if head != null and x != head:
					w.bonds.remember(x.id, SimBonds.person(head.id), "match_refused", [head.id])
			if is_ours(p) or is_ours(q):
				w.note("Ród %s nie zgadza się na ślub %s i %s — za niska pozycja %s." % [higher.name, p.name, q.name, lower_person.name], "warn", null)
			return
	if not is_ours(p) and not is_ours(q):
		marry(p, q)
		return
	_ask_player(p if is_ours(p) else q, q if is_ours(p) else p, gap > float(r["mesalliance_gap"]))


func _ask_player(ours: SimPerson, other: SimPerson, mesalliance: bool) -> void:
	var mover := _mover(ours, other)
	var after := ("%s wejdzie do rodu %s i zamieszka z wami." % [other.name, dynasty]) if mover == other \
		else ("%s przejdzie do rodu %s i zamieszka u nich." % [ours.name, lineage_of(other).name])
	var traits_txt := "brak szczególnych" if other.traits.is_empty() else ", ".join(other.traits.map(func(t): return trait_label(t)))
	var char_txt := "nic szczególnego" if other.character.is_empty() else ", ".join(other.character.map(func(x): return character_label(x)))
	ours.set_meta("engaged", true)
	other.set_meta("engaged", true)
	w.events.ask("marriage", "Rodziny rozmawiają o ślubie",
		"%s i %s %s (lat %d, ród %s) chodzą ze sobą i chcą się pobrać.%s\n%s\nCechy: %s. Charakter: %s.\nWesele kosztuje %d zł (płaci rodzina, do której wchodzi panna młoda lub pan młody; brak pójdzie w dług)." % [
			ours.name, other.name, other.surname, int(age_of(other)), lineage_of(other).name,
			" To mezalians — ludzie będą gadać." if mesalliance else "", after, traits_txt, char_txt, int(_marriage()["wedding_cost"])],
		[{ "label": "Zgoda na ślub", "value": "yes" }, { "label": "Odmowa", "value": "no" }],
		{ "person": ours.id, "cand": other.id })


func _marriage() -> Dictionary:
	return w.balance["marriage"]


# Kandydaci (S11): wolni dorośli przeciwnej płci z innych rodów okolicy, w rozsądnym
# wieku, od najbardziej lubianych (więź w obie strony). Nikt nie bierze się z powietrza.
func marriage_candidates(p: SimPerson) -> Array:
	var gap := float(_marriage()["max_age_gap_days"])
	var out: Array = []
	for c in all_living():
		if c.id == p.id or c.sex == p.sex or c.lineage_id == p.lineage_id or not can_marry(c) or c.has_meta("engaged"):
			continue
		if absf(days_lived(c) - days_lived(p)) > gap:
			continue
		out.append(c)
	var score := func(c: SimPerson) -> float:
		return w.bonds.value(p.id, SimBonds.person(c.id)) + w.bonds.value(c.id, SimBonds.person(p.id))
	out.sort_custom(func(x, y):
		var sx: float = score.call(x)
		var sy: float = score.call(y)
		if not is_equal_approx(sx, sy):
			return sx > sy
		return x.id < y.id)
	return out


# Kto się przenosi (reguła z danych): root nigdy; poza tym według zwyczaju („bride_moves”).
func _mover(a: SimPerson, b: SimPerson) -> SimPerson:
	for x in [a, b]:
		var l := lineage_of(x)
		if l != null and l.root_id == x.id:
			return b if x == a else a
	var bride: SimPerson = a if a.sex == "f" else b
	if String(_marriage()["residence"]) == "bride_moves":
		return bride
	return b if bride == a else a


func resolve_marriage(data: Dictionary, accepted: bool) -> void:
	var p: SimPerson = persons.get(int(data["person"]))
	var c: SimPerson = persons.get(int(data["cand"]))
	for x in [p, c]:
		if x != null and x.has_meta("engaged"):
			x.remove_meta("engaged")
	if p == null or c == null or not p.alive() or not c.alive() or not can_marry(p) or not can_marry(c):
		return
	if not accepted:
		# Odmowa rodu gracza: oboje to pamiętają (głowie rodu), a uczucie słabnie.
		var head: SimPerson = root()
		for x in [p, c]:
			if head != null and x != head:
				w.bonds.remember(x.id, SimBonds.person(head.id), "match_refused", [head.id])
		w.note("Rodzina nie zgadza się na ślub %s i %s." % [p.name, c.name], "info", null)
		return
	marry(p, c)


# Ślub dwóch istniejących osób: jedna wchodzi do rodu i gospodarstwa drugiej.
func marry(a: SimPerson, b: SimPerson) -> void:
	var mover := _mover(a, b)
	var stayer: SimPerson = b if mover == a else a
	var old := lineage_of(mover)
	var new_l := lineage_of(stayer)
	var sh: SimHousehold = w.households.get(stayer.household_id)
	if sh != null:
		sh.pay_or_debt(float(_marriage()["wedding_cost"]))
	old.remove(mover)
	new_l.add(mover)
	mover.attached = true
	mover.blood = false
	mover.surname = new_l.surname
	a.spouse_id = b.id
	b.spouse_id = a.id
	a.unions.append({ "spouse": b.id, "start": w.clock.now(), "end": -1.0 })
	b.unions.append({ "spouse": a.id, "start": w.clock.now(), "end": -1.0 })
	if sh != null:
		w.join_household(mover, sh)
		var ma: SimAgent = w.agent_by_id(mover.agent_id)
		if ma != null:
			w.jobs.replan(ma)
	_remember_all(a.id, b.id, w.memories["on_wedding"]["spouses"])
	_remember_all(b.id, a.id, w.memories["on_wedding"]["spouses"])
	generation_of[mover.id] = int(generation_of.get(stayer.id, 0))
	var text := "Ślub: %s i %s (z rodu %s)." % [stayer.name, mover.name, old.name]
	w.chronicle.add(w.clock.now(), "wedding", text, [stayer.id, mover.id], new_l.id)
	if old.id != new_l.id:
		w.chronicle.add(w.clock.now(), "wedding", "%s wychodzi za mąż / żeni się do rodu %s (%s)." % [mover.name, new_l.name, stayer.name], [mover.id, stayer.id], old.id)
	if new_l.id == player_lineage_id:
		w.note("Ślub! %s i %s. Nowa osoba w rodzinie." % [stayer.name, mover.name], "good", null)
	elif old.id == player_lineage_id:
		w.note("Ślub! %s odchodzi do rodu %s (%s)." % [mover.name, new_l.name, stayer.name], "warn", null)
		if not _blood_alive():
			_end_game()
	update_strength()


# --- Śmierć i sukcesja ---

func on_death(p: SimPerson, cause: String) -> void:
	p.death_day = w.clock.now()
	p.death_cause = cause
	p.pregnant_left = -1.0
	var s: SimPerson = persons.get(p.spouse_id)
	if s != null and s.alive():
		# Wdowieństwo: małżeństwo pozostaje faktem, ale żyjący może szukać nowego.
		s.spouse_id = -1
		for u in s.unions + p.unions:
			if float(u["end"]) < 0.0:
				u["end"] = w.clock.now()
	var l := lineage_of(p)
	if l != null and l.id == player_lineage_id:
		if p.id == root_id:
			_succession(p)
		elif not _blood_alive():
			_end_game()
	elif l != null and p.id == l.root_id:
		_succession_ai(p, l)


# Ród AI wybiera następcę sam: pierwszy kandydat według tych samych reguł.
# Bez krwi ród gaśnie (pozostali żyją dalej, ale ród nie ma kotwicy).
func _succession_ai(dead: SimPerson, l: SimLineage) -> void:
	var cands := succession_candidates(dead.id, l.id)
	l.root_id = cands[0].id if not cands.is_empty() else -1


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
func succession_candidates(dead_id: int = -1, lineage_id: int = -1) -> Array:
	var out: Array = []
	for p in living_members(player_lineage_id if lineage_id < 0 else lineage_id):
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
	for c in cands.slice(0, SUCCESSION_OPTIONS):
		opts.append({ "label": "%s, lat %d (%s)" % [c.name, int(age_of(c)), stage_label(c)], "value": c.id })
	w.events.ask("succession", "Śmierć głowy rodu",
		"%s %s nie żyje (%s).\nKto poprowadzi ród %s?" % [dead.name, dead.surname, dead.death_cause, dynasty],
		opts, {})


# Root to kotwica grafu rodu: żywy członek rodu gracza, nigdy wżeniony małżonek.
func can_be_root(p: SimPerson) -> bool:
	return p != null and p.alive() and p.lineage_id == player_lineage_id and not p.attached


func set_root(pid: int) -> bool:
	var p: SimPerson = persons.get(pid)
	if not can_be_root(p):
		return false
	root_id = pid
	update_strength()
	w.note("%s jest nową głową rodu %s." % [p.name, dynasty], "good", null)
	return true


func _end_game() -> void:
	if game_over:
		return
	game_over = true
	w.events.ask("game_over", "Koniec rodu",
		"Wygasła krew rodu %s. Nie żyje nikt z linii założycieli.\nRód przetrwał %d dni." % [dynasty, w.clock.day_index()],
		[{ "label": "Zacznij od nowa", "value": "restart" }], {})
