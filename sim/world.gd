# SimWorld — świat symulacji: zegar, osada (budynki, drzewa), ciała, gospodarstwo,
# ród, zdarzenia. Cała logika i ruch są tu (deterministycznie, ADR-0002); game/ i ui/
# tylko czytają stan i wołają komendy (set_job, manual_move, resolve_prompt...).
class_name SimWorld
extends RefCounted


var balance: Dictionary
var map: Dictionary
var people: Dictionary
var memories: Dictionary

var clock: SimClock
var rng: SimRng
var events: SimEvents
var households: Dictionary = {}  # id -> SimHousehold
var household: SimHousehold      # gospodarstwo rodu gracza (skrót dla UI i czynszu)
var _next_household := 1
var jobs: SimJobs
var family: SimFamily
var bonds: SimBonds
var together: SimTogether
var ai: SimAI
var market: SimMarket
var traders: SimTraders
var chronicle: SimChronicle

var buildings: Dictionary = {}   # id -> SimBuilding
var trees: Array = []            # SimTree
var agents: Array = []           # SimAgent (także zmarli — status "dead")
var chore_claims: Dictionary = {}  # "food:<gosp.>"/"firewood:<gosp.>" -> agent id
var stats: Dictionary = {}

const HOUSE_TYPES := ["home", "decor_house", "decor_town", "manor"]  # budynki, w których można mieszkać
const START_AFTER_WAKE := 0.02           # gra startuje chwilę po pobudce (część doby)
const TREE_PLACE_TRIES := 4000            # limit prób rozmieszczenia drzew
const CHOP_SPOT := Vector2(0.9, 0.4)      # gdzie staje drwal względem pnia
const SAWMILL_DROP := Vector2(-1.5, 0.0)  # gdzie zostawia kłodę względem drzwi tartaku
const MAX_STEPS_PER_TICK := 8             # bezpiecznik pętli kroków w jednym ticku
const AT_TARGET_EPS := 0.05               # odległość uznawana za „już na miejscu”
const MOVE_EPS := 0.001

var _tree_index: Dictionary = {}
var _next_agent := 1
var _last_day := 0
var _regrow_total: float


func _init(seed: int, p_balance: Dictionary, p_map: Dictionary, p_people: Dictionary, p_memories: Dictionary, p_recipes: Dictionary, p_traders: Dictionary) -> void:
	balance = p_balance
	map = p_map
	people = p_people
	memories = p_memories
	clock = SimClock.new(balance)
	clock.set_time(0, float(balance["schedule"]["wake"]) + START_AFTER_WAKE)
	rng = SimRng.new(seed)
	events = SimEvents.new()
	household = new_household("home", float(balance["economy"]["start_cash"]))
	jobs = SimJobs.new(self, p_recipes)
	_regrow_total = float(balance["trees"]["regrow_days"]) * clock.day_seconds

	var storage: Dictionary = balance["storage"]
	for b in map["buildings"]:
		var t := String(b["type"])
		var cap: Dictionary = storage.get(t, storage["home"] if t in HOUSE_TYPES else {})
		var nb := SimBuilding.new(String(b["id"]), String(b["name"]), t,
			Vector2(float(b["x"]), float(b["y"])), cap)
		nb.rent_per_day = float(balance["economy"]["rent_per_day"].get(t, 0.0))
		buildings[b["id"]] = nb
	household.set_chest(home())
	var eco: Dictionary = balance["economy"]
	home().add("food", int(eco["start_food"]))
	home().add("log", int(eco["start_firewood"]))
	_generate_trees()

	family = SimFamily.new(self, people)
	bonds = SimBonds.new(self, memories)
	chronicle = SimChronicle.new()
	together = SimTogether.new(self, memories["together"])
	ai = SimAI.new(self)
	family.setup_start()
	_spawn_society()
	market = SimMarket.new(self, balance["market"])
	traders = SimTraders.new(self, p_traders)
	for p in family.living():
		p.set_meta("stage", family.stage_of(p))
	note("Ród %s zaczyna w wynajętej chacie pod lasem. Czynsz %d zł dziennie — pilnuj kasy." % [
		family.dynasty, int(home().rent_per_day)], "info", home().door())


# Rody AI z danych (G1): każdy z domem, gospodarstwem, kasą i majątkiem.
func _spawn_society() -> void:
	for spec: Dictionary in people.get("ai_lineages", []):
		var l := family.new_lineage(String(spec["name"]), String(spec["surname"]))
		l.role = String(spec.get("role", ""))
		var home_b: SimBuilding = buildings[String(spec["home"])]
		var h := new_household(home_b.id, float(spec["cash"]))
		for id in family.spawn_family(spec["members"], l, home_b):
			join_household(family.persons[id], h)
		for bid in spec.get("owns", []):
			var b: SimBuilding = buildings[String(bid)]
			b.owner_kind = "lineage"
			b.owner_id = l.id
	family.update_strength()


func lineage_by_role(role: String) -> SimLineage:
	for l: SimLineage in family.lineages.values():
		if l.role == role:
			return l
	return null


func _generate_trees() -> void:
	var f: Dictionary = map["forest"]
	var tc: Dictionary = balance["trees"]
	var tr := SimRng.new(SimRng.hash3(int(balance["world_seed"]), 0, "trees"))
	var spacing := float(tc["min_spacing"])
	var tries := 0
	while trees.size() < int(tc["count"]) and tries < TREE_PLACE_TRIES:
		tries += 1
		var p := Vector2(float(f["x"]) + tr.next_float(0.0, float(f["w"])), float(f["y"]) + tr.next_float(0.0, float(f["h"])))
		var ok := true
		for t in trees:
			if t.position.distance_to(p) < spacing:
				ok = false
				break
		if not ok:
			continue
		var t := SimTree.new(trees.size(), p, tr.next_int(int(tc["wood_min"]), int(tc["wood_max"])))
		trees.append(t)
		_tree_index[t.id] = t


# --- Dostęp ---

func home() -> SimBuilding:
	return buildings["home"]


# Dom agenta albo null, gdy jest bezdomny (S7).
func home_of(a: SimAgent) -> SimBuilding:
	return buildings.get(a.home_id)


func new_household(home_id: String, cash: float) -> SimHousehold:
	var h := SimHousehold.new(_next_household, home_id, balance["economy"], cash)
	_next_household += 1
	households[h.id] = h
	h.set_chest(buildings.get(home_id))
	return h


# Osoba zamieszkuje w gospodarstwie: ciało dostaje jego dom.
func join_household(p: SimPerson, h: SimHousehold) -> void:
	var old: SimHousehold = households.get(p.household_id)
	if old != null:
		old.members.erase(p.id)
	if not p.id in h.members:
		h.members.append(p.id)
	p.household_id = h.id
	var a := agent_by_id(p.agent_id)
	if a != null:
		a.home_id = h.home_id


func household_of(a: SimAgent) -> SimHousehold:
	var p := person_of(a)
	if p != null and households.has(p.household_id):
		return households[p.household_id]
	return household


# Wolny dom: budynek mieszkalny, w którym nikt nie mieszka.
func free_house() -> SimBuilding:
	var taken := {}
	for h: SimHousehold in households.values():
		if not h.members.is_empty():
			taken[h.home_id] = true
	for id in buildings:
		var b: SimBuilding = buildings[id]
		if b.type in HOUSE_TYPES and not taken.has(b.id):
			return b
	return null


# Ciało osoby spoza rodu gracza: żyje na autopilocie, gracz nim nie steruje (C4).
func is_independent(a: SimAgent) -> bool:
	var p := person_of(a)
	return p != null and p.lineage_id != family.player_lineage_id


# Zarobek osoby (dniówka, łup) trafia do jej sakwy (S5, S14). Część gospodarstwa
# (`held`) oddaje do skrzyni w domu — tym większą, im silniej należy do rodu (D1, K3).
func earn_for(a: SimAgent, amount: float) -> void:
	var p := person_of(a)
	if p == null:
		household.earn(amount)
		return
	var pc: Dictionary = balance["purse"]
	var s := clampf(float(family.strength.get(p.id, 1.0)), 0.0, 1.0)
	var share := lerpf(float(pc["share_at_zero"]), float(pc["share_at_full"]), s)
	p.purse += amount
	p.held += amount * share


func building(id: String) -> SimBuilding:
	return buildings.get(id)


func tree_by_id(id: int) -> SimTree:
	return _tree_index.get(id)


func regrow_total() -> float:
	return _regrow_total


func agent_by_id(id: int) -> SimAgent:
	for a in agents:
		if a.id == id:
			return a
	return null


func person_of(a: SimAgent) -> SimPerson:
	return family.persons.get(a.person_id)


func active_agents() -> Array:
	return agents.filter(func(a): return a.status != "dead")


func nearest_tree(from: Vector2) -> SimTree:
	var best: SimTree = null
	var bd := INF
	for t in trees:
		if not t.available():
			continue
		var d := from.distance_squared_to(t.position)
		if d < bd:
			bd = d
			best = t
	return best


func good_label(g: String) -> String:
	match g:
		"log":
			return "kłoda"
		"plank":
			return "deski"
		"chair":
			return "krzesła"
		"food":
			return "jedzenie"
	return g


func spawn_agent(p: SimPerson, at: Vector2) -> SimAgent:
	var a := SimAgent.new(_next_agent)
	_next_agent += 1
	a.person_id = p.id
	a.position = at
	var fr: Array = balance["needs"]["food"]["start"]
	a.needs["food"] = rng.next_float(float(fr[0]), float(fr[1]))
	p.agent_id = a.id
	agents.append(a)
	return a


func note(text: String, level: String = "info", focus: Variant = null) -> void:
	events.add(clock.day_index(), clock.time_of_day(), text, level, focus)


func ask_ok(title: String, text: String) -> void:
	events.ask("notice", title, text, [{ "label": "Dalej", "value": "ok" }])


# --- Komendy gracza ---

func set_job(agent_id: int, job: String) -> void:
	var a := agent_by_id(agent_id)
	if a == null or a.status != "active" or is_independent(a):
		return
	_order_against_will(a, job)
	a.job = job
	jobs.replan(a)


# Przydział wbrew woli (D4) zostawia wspomnienie o tym, kto rządzi rodem (root).
func _order_against_will(a: SimAgent, job: String) -> void:
	var p := person_of(a)
	var cfg: Dictionary = balance["will"]
	var act := String(cfg["job_acts"].get(job, ""))
	if p == null or act == "" or job == a.job or p.id == family.root_id or family.root_id < 0:
		return
	if bonds.preference(p.id, act) < float(cfg["against_will_below"]):
		bonds.remember(p.id, SimBonds.person(family.root_id), "ordered_against_will", [family.root_id])


# Rozkazy ręczne: kolejka kroków wykonywana zamiast autopilota. append = dopisz na
# koniec kolejki (Shift+PPM); inaczej zastąp. Po ostatnim kroku agent sam wraca
# do autopilota (patrz _behave).
func _begin_manual(a: SimAgent, append: bool) -> void:
	if append and a.controlled:
		return
	jobs.release(a)
	a.steps.clear()
	a.controlled = true
	a.plan_kind = "manual"


func manual_move(agent_id: int, to: Vector2, append := false) -> void:
	var a := agent_by_id(agent_id)
	if a == null or a.status != "active" or is_independent(a):
		return
	_begin_manual(a, append)
	a.steps.append({ "t": "walk", "to": to, "why": "idzie tam, gdzie kazano" })


# Ręczne ścięcie wskazanego drzewa i odniesienie kłody do tartaku.
func manual_chop(agent_id: int, tree_id: int, append := false) -> void:
	var a := agent_by_id(agent_id)
	var t := tree_by_id(tree_id)
	if a == null or t == null or a.status != "active" or t.wood <= 0 or not a.can_work() or is_independent(a):
		return
	_begin_manual(a, append)
	if t.reserved_by >= 0 and t.reserved_by != a.id:
		var other := agent_by_id(t.reserved_by)
		if other != null:
			jobs.replan(other)
	t.reserved_by = a.id
	a.claims.append("tree:%d" % t.id)
	var chop_secs := jobs._dur(a, "chop", float(balance["jobs"]["chop_seconds"])) * float(balance["jobs"]["manual_chop_mult"])
	a.steps.append({ "t": "walk", "to": t.position + CHOP_SPOT, "why": "idzie ściąć wskazane drzewo" })
	a.steps.append({ "t": "act", "act": "chop", "left": chop_secs, "why": "rąbie wskazane drzewo (ręcznie, szybciej)", "inside": "", "alert": false })
	a.steps.append({ "t": "do", "fn": "chop_done", "arg": t.id })
	a.steps.append({ "t": "walk", "to": building("sawmill").door() + SAWMILL_DROP, "why": "niesie kłodę do tartaku" })
	a.steps.append({ "t": "do", "fn": "deposit", "arg": "sawmill" })


# Anuluj resztę rozkazów i wróć do autopilota od razu.
func release_manual(agent_id: int) -> void:
	var a := agent_by_id(agent_id)
	if a == null:
		return
	a.controlled = false
	jobs.replan(a)


# Komenda gracza: dziecko ma chodzić za tą osobą (D5); -1 = wraca do własnej sympatii.
func set_follow(agent_id: int, person_id: int) -> void:
	var a := agent_by_id(agent_id)
	if a == null or not a.is_child or is_independent(a):
		return
	a.follow_id = person_id
	jobs.replan(a)


# Komenda gracza: przełącz roota (kotwicę rodu) na innego członka rodu (C2).
func switch_root(person_id: int) -> bool:
	return family.set_root(person_id)


func resolve_prompt(prompt_id: int, value: Variant) -> void:
	var p := events.pop_prompt(prompt_id)
	if p.is_empty():
		return
	match String(p["kind"]):
		"marriage":
			family.resolve_marriage(p["data"], String(value) == "yes")
		"succession":
			family.set_root(int(value))
		"arrest":
			var a := agent_by_id(int(p["data"]["agent"]))
			if String(value) == "bail" and a != null and a.status == "jailed":
				household.pay(float(balance["crime"]["bail"]))
				release_from_jail(a)


# --- Symulacja ---

# delta_real: sekundy rzeczywiste klatki. Sim stoi, gdy czeka pytanie do gracza.
func tick(delta_real: float) -> void:
	if events.blocking() or family.game_over:
		return
	var total := delta_real * clock.multiplier()
	step_sim(total)


func step_sim(total: float) -> void:
	var sub := float(balance["time"]["substep"])
	while total > 0.0 and not events.blocking():
		var dt := minf(sub, total)
		total -= dt
		_step(dt)


func _step(dt: float) -> void:
	clock.advance_sim(dt)
	if clock.day_index() != _last_day:
		_last_day = clock.day_index()
		_new_day()
	var days := dt / clock.day_seconds
	for t in trees:
		if t.wood <= 0:
			t.regrow_left -= dt
			if t.regrow_left <= 0.0:
				t.wood = rng.next_int(int(balance["trees"]["wood_min"]), int(balance["trees"]["wood_max"]))
				t.max_wood = t.wood
	for a in agents:
		match a.status:
			"active":
				_body(a, days)
				if a.status == "active":
					_behave(a, dt)
			"jailed":
				a.jail_days -= days
				a.idle_reason = "w areszcie (jeszcze %.1f dnia)" % maxf(a.jail_days, 0.0)
				if a.jail_days <= 0.0:
					release_from_jail(a)
	traders.tick()
	together.sample(dt)


func _body(a: SimAgent, days: float) -> void:
	var n: Dictionary = balance["needs"]
	var h: Dictionary = balance["health"]
	a.needs["food"] = maxf(0.0, a.needs["food"] - float(n["food"]["decay_day"]) * days)
	if a.activity == "sleep":
		a.needs["sleep"] = minf(100.0, a.needs["sleep"] + float(n["sleep"]["recover_day"]) * days)
	else:
		a.needs["sleep"] = maxf(0.0, a.needs["sleep"] - float(n["sleep"]["decay_day"]) * days)
	var dmg := 0.0
	if a.needs["food"] <= 0.0:
		dmg += float(h["starve_damage_day"])
	if a.cold and a.hidden and a.inside_home():
		dmg += float(h["cold_damage_day"])
	if a.sick_days > 0.0:
		dmg += float(h["sick_damage_day"]) * (float(h["sick_fatal_vulnerable_mult"]) if a.sick_mult > float(h["sick_vulnerable_above"]) else 1.0)
		a.sick_days = maxf(0.0, a.sick_days - days)
	if a.injured_days > 0.0:
		a.injured_days = maxf(0.0, a.injured_days - days)
	if dmg > 0.0:
		a.health -= dmg * days
	elif a.needs["food"] > float(h["regen_min_food"]):
		a.health = minf(100.0, a.health + float(h["regen_day"]) * a.regen_mult * days)
	if a.health <= 0.0:
		var cause := "zmarł z głodu"
		if a.sick_days > 0.0:
			cause = "zmarł na chorobę"
		elif a.cold:
			cause = "zamarzł w nieogrzanej chacie"
		elif a.injured_days > 0.0:
			cause = "zmarł z ran"
		var p := person_of(a)
		if p != null and p.sex == "f":
			cause = cause.replace("zmarł", "zmarła").replace("zamarzł", "zamarzła")
		kill(a, cause)


func _behave(a: SimAgent, dt: float) -> void:
	if a.controlled and a.steps.is_empty():
		a.controlled = false   # kolejka rozkazów wykonana — wraca do autopilota
	var want := jobs.desired_kind(a)
	var early_meal := a.plan_kind == "eat" and want in ["work", "chore", "child", "dinner"]
	if want != a.plan_kind and not early_meal and a.interruptible(want == "dinner"):
		jobs.replan(a)
	elif a.steps.is_empty():
		jobs.replan(a)
	var guard := 0
	while not a.steps.is_empty() and guard < MAX_STEPS_PER_TICK:
		guard += 1
		var s: Dictionary = a.steps[0]
		match String(s["t"]):
			"do":
				a.steps.pop_front()
				if not jobs.apply(a, s):
					jobs.release(a)
					a.steps.clear()
					a.steps.append({ "t": "act", "act": "wait", "left": 1.0, "why": "coś poszło nie tak — zmienia plan", "inside": "", "alert": false })
					return
				continue
			"walk":
				var to: Vector2 = s["to"]
				if a.position.distance_to(to) < AT_TARGET_EPS:
					a.steps.pop_front()
					continue
				_walk(a, s, dt)
				return
			"act":
				_act(a, s, dt)
				return


func _walk(a: SimAgent, s: Dictionary, dt: float) -> void:
	a.hidden = false
	a.inside = ""
	a.activity = "walk"
	a.idle_reason = String(s["why"])
	a.alert = false
	var to: Vector2 = s["to"]
	var mv: Dictionary = balance["movement"]
	var spd := float(mv["child_speed"] if a.is_child else mv["speed"])
	spd *= a.speed_mult
	if a.carrying == "log":
		spd *= float(mv["log_carry_mult"])
	if a.health < float(mv["weak_health"]):
		spd *= float(mv["weak_mult"])
	var step := spd * dt
	var d := a.position.distance_to(to)
	if d > MOVE_EPS:
		a.facing = (to - a.position) / d
	if d <= maxf(step, float(balance["movement"]["arrive_radius"]) * 0.5):
		a.position = to
		a.steps.pop_front()
	else:
		a.position = a.position.move_toward(to, step)


func _act(a: SimAgent, s: Dictionary, dt: float) -> void:
	var act := String(s["act"])
	a.activity = act
	a.idle_reason = String(s["why"])
	a.alert = bool(s.get("alert", false))
	var inside := String(s.get("inside", ""))
	a.hidden = inside != ""
	a.inside = inside
	if jobs.is_work(act) and not s.has("will"):
		_check_will(a, s, act)
	if act == "labor":
		_labor(a, s, dt)
	if jobs.is_work(act):
		var target_face: Vector2 = s.get("face", Vector2.ZERO)
		if target_face != Vector2.ZERO:
			a.facing = target_face
	if a.controlled and a.needs["food"] < float(balance["needs"]["food"]["low"]):
		a.alert = true
		a.idle_reason = "GŁODNY — wykonuje rozkazy, zje po ich skończeniu"
	s["left"] = float(s["left"]) - dt
	if float(s["left"]) <= 0.0:
		a.steps.pop_front()
		if s.get("abandon", false):
			# Porzucona robota: dalsze kroki (efekt, odniesienie) przepadają.
			jobs.release(a)
			a.steps.clear()


# Dniówka na folwarku (H7): pracodawca to ród właściciela dworu. Płaci z własnej kasy,
# a praca daje plon (jedzenie) do spiżarni dworu, zależny od pory roku.
func estate_owner() -> SimHousehold:
	var b: SimBuilding = building(String(balance["estate"]["building"]))
	var best: SimHousehold = null
	for h: SimHousehold in households.values():
		if h.home_id == b.id and not h.members.is_empty():
			best = h
	return best


func _labor(a: SimAgent, s: Dictionary, dt: float) -> void:
	var sch: Dictionary = balance["schedule"]
	var work_day := (float(sch["work_end"]) - float(sch["work_start"])) * clock.day_seconds
	var share := dt / work_day * a.age_eff * float(s["will"])
	var employer := estate_owner()
	var wage := float(balance["jobs"]["laborer_wage_day"]) * share
	if employer == null or employer.cash < wage:
		s["left"] = 0.0
		a.idle_reason = "dwór nie ma czym płacić — schodzi z pola"
		return
	employer.pay(wage)
	earn_for(a, wage)
	var est: Dictionary = balance["estate"]
	var acc := float(s.get("yield_acc", 0.0)) + float(est["food_per_labor_day"].get(clock.current_season(), 0.0)) * share
	var n := int(floor(acc))
	s["yield_acc"] = acc - n
	if n > 0:
		building(String(est["building"])).add("food", n)


# Dwór sprzedaje nadwyżkę plonów kupcowi (pieniądze wracają do dworu i dalej do ludzi).
func _estate_sells() -> void:
	var est: Dictionary = balance["estate"]
	var b: SimBuilding = building(String(est["building"]))
	var owner := estate_owner()
	if owner == null:
		return
	var surplus := mini(b.amount("food") - int(est["reserve_food"]), int(est["sell_to_merchant_per_day"]))
	if surplus > 0:
		var r: Dictionary = market.buy_from(owner, "food", surplus, [])
		b.take("food", int(r["qty"]))


# Na początku czynności: niechętny robi wolniej (w efektywności) i czasem rzuca robotę w połowie (D4).
func _check_will(a: SimAgent, s: Dictionary, act: String) -> void:
	var cfg: Dictionary = balance["will"]
	var wl := jobs.willingness(a, act)
	s["will"] = wl
	if wl >= float(cfg["reluctant_below"]):
		return
	s["why"] = "%s — niechętnie, %s" % [String(s["why"]), jobs.reluctance_reason(a, act)]
	if act != "labor" and wl < float(cfg["abandon_below"]) and rng.chance(float(cfg["abandon_chance"])):
		s["left"] = float(s["left"]) * float(cfg["abandon_fraction"])
		s["abandon"] = true
		s["why"] = "rzuci robotę w połowie — %s" % jobs.reluctance_reason(a, act)


# Wypadek zostaje w pamięci ofiary (trwale) i świadków obok (B3) jako więź z czynnością.
func remember_accident(a: SimAgent, act: String, sev: String) -> void:
	var scale := float(memories["accident_scale"][sev])
	var target := SimBonds.act(act)
	if a.person_id >= 0 and sev != "fatal":
		bonds.remember(a.person_id, target, "accident", [], scale, a.inside)
	var radius := float(memories["together"]["radius"])
	for o: SimAgent in agents:
		if o == a or o.status != "active" or o.person_id < 0 or o.inside != a.inside:
			continue
		if a.inside == "" and o.position.distance_to(a.position) > radius:
			continue
		bonds.remember(o.person_id, target, "accident_seen", [a.person_id], scale, a.inside)


func roll_accident(a: SimAgent, act: String) -> void:
	var r: Dictionary = balance["risk"]
	var key := act + "_accident"
	if not r.has(key):
		return
	var p := float(r[key]) * a.accident_mult
	p *= maxf(float(r["skill_reduction_floor"]), 1.0 - float(r["skill_accident_reduction"]) * a.skill(act))
	if clock.light_factor() < float(r["dark_light_below"]):
		p *= float(r["dark_accident_mult"])
	if not rng.chance(p):
		return
	var person := person_of(a)
	var nm := person.name if person else "Ktoś"
	var what := "przy wyrębie"
	for rid in jobs.recipes:
		if String(jobs.recipes[rid]["act"]) == act:
			what = String(jobs.recipes[rid]["accident_where"])
	var roll := rng.next_float()
	var sev := "fatal" if roll < float(r["fatal_share"]) else (
		"severe" if roll < float(r["fatal_share"]) + float(r["severe_share"]) else "minor")
	remember_accident(a, act, sev)
	if sev == "fatal":
		kill(a, "%s w wypadku %s" % ["zginął" if person == null or person.sex == "m" else "zginęła", what])
		return
	var cfg: Dictionary = r[sev]
	a.health -= float(cfg["damage"])
	a.injured_days = float(cfg["days"])
	if sev == "severe":
		var t := "kulawy"
		if person != null and not t in person.traits:
			person.traits.append(t)
			family.apply_modifiers(person)
		note("WYPADEK %s: %s ciężko rann%s — będzie kuleć do końca życia." % [what, nm, "y" if person == null or person.sex == "m" else "a"], "critical", a.position)
		ask_ok("Wypadek", "%s uległ%s ciężkiemu wypadkowi %s.\nLeży %d dni i już zawsze będzie kuleć (wolniej chodzi i rąbie)." % [
			nm, "" if person == null or person.sex == "m" else "a", what, int(cfg["days"])])
	else:
		note("Wypadek %s: %s rann%s, %d dni bez pracy." % [what, nm, "y" if person == null or person.sex == "m" else "a", int(cfg["days"])], "warn", a.position)
	jobs.replan(a)


# Złapany złodziej: areszt, grzywna (w dług), cios w reputację. Rodzina może wpłacić
# kaucję — złapanie otwiera fazę następstw, a nie kończy historii (intro §8).
func arrest(a: SimAgent) -> void:
	var c: Dictionary = balance["crime"]
	var p := person_of(a)
	jobs.release(a)
	a.steps.clear()
	a.clear_carry()
	a.status = "jailed"
	a.hidden = true
	a.jail_days = float(c["jail_days"])
	household.debt += float(c["fine"])
	household.reputation -= float(c["reputation_hit"])
	stats["arrests"] = int(stats.get("arrests", 0)) + 1
	var who := "Złapany" if p.sex == "m" else "Złapana"
	note("%s na kradzieży: %s trafia do aresztu na %d dni. Grzywna %d zł (w dług)." % [who, p.name, int(a.jail_days), int(c["fine"])], "critical", building("jail").door())
	var opts: Array = [{ "label": "Niech siedzi (%d dni)" % int(a.jail_days), "value": "stay" }]
	if household.cash >= float(c["bail"]):
		opts.push_front({ "label": "Wpłać kaucję %d zł — wychodzi od razu" % int(c["bail"]), "value": "bail" })
	events.ask("arrest", "Areszt", "%s %s na kradzieży na targu.\nStraż zamknęła %s w areszcie na %d dni. Grzywna %d zł doliczona do długu.\nLudzie gadają — reputacja rodu spada." % [
		who, p.name, "go" if p.sex == "m" else "ją", int(a.jail_days), int(c["fine"])], opts, { "agent": a.id })


func release_from_jail(a: SimAgent) -> void:
	a.status = "active"
	a.hidden = false
	a.jail_days = 0.0
	a.position = building("jail").door()
	note("%s wychodzi z aresztu." % person_of(a).name, "info", a.position)
	jobs.replan(a)


func kill(a: SimAgent, cause: String) -> void:
	if a == null or a.status == "dead":
		return
	jobs.release(a)
	a.steps.clear()
	a.status = "dead"
	a.hidden = true
	a.activity = "dead"
	a.clear_carry()
	var p := person_of(a)
	if p == null:
		return
	var age := int(family.age_of(p))
	var ours := not is_independent(a)
	note("ŚMIERĆ: %s %s %s w wieku %d lat." % [p.name, p.surname, cause, age], "critical" if ours else "info", a.position)
	var was_root := p.id == family.root_id
	chronicle.add(clock.now(), "death", "%s %s %s w wieku %d lat." % [p.name, p.surname, cause, age], [p.id], p.lineage_id)
	family.on_death(p, cause)
	if ours and not was_root and not family.game_over:
		ask_ok("Śmierć w rodzinie", "%s %s (%s) %s.\nMiał%s %d lat." % [p.name, p.surname, family.relation_to_root(p), cause,
			"" if p.sex == "m" else "a", age])


func _new_day() -> void:
	var day := clock.day_index()
	var season := clock.current_season()
	# Opał: każdy zamieszkany dom zużywa drewno, zwłaszcza zimą.
	var need := float(balance["economy"]["firewood_per_day"].get(season, 0.0))
	for h: SimHousehold in households.values():
		if h.members.is_empty():
			continue
		if not buildings.has(h.home_id):
			# Bez domu: każda noc w chłodnej porze to zimno.
			for pid in h.members:
				var ha := agent_by_id(family.persons[pid].agent_id)
				if ha != null:
					ha.cold = need > 0.0
			continue
		h.burn_acc += need
		var burn := int(floor(h.burn_acc))
		h.burn_acc -= burn
		var cold := false
		if burn > 0:
			cold = buildings[h.home_id].take("log", burn) < burn
		for pid in h.members:
			var pa := agent_by_id(family.persons[pid].agent_id)
			if pa != null:
				pa.cold = cold
		if cold and h == household:
			note("Zimno w chacie — zabrakło opału! Śpiący tracą zdrowie.", "warn", home().door())

	# Czynsz dzienny, eksmisja, nowy dom (S7). Komunikaty tylko dla gospodarstwa gracza.
	for h: SimHousehold in households.values():
		h.new_day()
		_settle_rent(h)
	if household.debt > household.debt_limit:
		_debt_jail()

	# Choroby.
	var h: Dictionary = balance["health"]
	for a in agents:
		if a.status != "active" or a.sick_days > 0.0:
			continue
		var p: float = float(h["sick_base_daily"]) * a.sick_mult
		if season == "winter":
			p *= float(h["sick_winter_mult"])
		if a.cold:
			p *= float(h["sick_cold_mult"])
		if a.needs["food"] < 10.0:
			p *= float(h["sick_hungry_mult"])
		if rng.chance(p):
			var sd: Array = h["sick_days"]
			a.sick_days = rng.next_float(float(sd[0]), float(sd[1]))
			var pr := person_of(a)
			note("%s zachorował%s." % [pr.name, "" if pr.sex == "m" else "a"], "warn", a.position)
	together.end_day()
	_estate_sells()
	market.new_day()
	ai.new_day()
	family.new_day()
	bonds.prune()
	stats["max_generation"] = _max_living_generation()


# Najemca płaci właścicielowi za dobę. Za duży dług przez kilka dób z rzędu → eksmisja.
# Bezdomni z pieniędzmi na kilka dób czynszu wynajmują wolny dom.
func _settle_rent(h: SimHousehold) -> void:
	if h.members.is_empty():
		return
	var eco: Dictionary = balance["economy"]
	var b: SimBuilding = buildings.get(h.home_id)
	if b == null:
		var free := free_house()
		if free != null and h.cash >= free.rent_per_day * float(eco["rehouse_rent_days"]):
			move_household(h, free)
			if h == household:
				note("Rodzina wynajmuje dom: %s (%d zł dziennie)." % [free.name, int(free.rent_per_day)], "good", free.door())
		return
	if b.rent_per_day <= 0.0 or owns(h, b):
		return
	var missing := b.rent_per_day - h.pay_due(b.rent_per_day)
	pay_owner(b, b.rent_per_day - missing)
	if missing > 0.0 and h == household:
		note("Brak na czynsz! Dług %d zł." % int(h.debt), "warn", null)
	if h.debt >= float(eco["evict_debt"]):
		h.evict_days += 1
	else:
		h.evict_days = 0
	if h.evict_days >= int(eco["evict_days"]):
		evict(h)


# Czy gospodarstwo jest właścicielem domu (przez osobę z gospodarstwa albo ród).
func owns(h: SimHousehold, b: SimBuilding) -> bool:
	match b.owner_kind:
		"person":
			return b.owner_id in h.members
		"lineage":
			for pid in h.members:
				if family.persons[pid].lineage_id == b.owner_id:
					return true
	return false


# Czynsz trafia do konkretnej osoby (sakiewka) albo do gospodarstwa roota rodu-właściciela.
func pay_owner(b: SimBuilding, amount: float) -> void:
	if amount <= 0.0:
		return
	match b.owner_kind:
		"person":
			var p: SimPerson = family.persons.get(b.owner_id)
			if p != null:
				p.purse += amount
		"lineage":
			var l: SimLineage = family.lineages.get(b.owner_id)
			var r: SimPerson = family.persons.get(l.root_id) if l != null else null
			if r != null and households.has(r.household_id):
				households[r.household_id].earn(amount)


func move_household(h: SimHousehold, b: SimBuilding) -> void:
	h.home_id = b.id if b != null else ""
	h.set_chest(b)
	h.evict_days = 0
	for pid in h.members:
		var a := agent_by_id(family.persons[pid].agent_id)
		if a != null:
			a.home_id = h.home_id
			jobs.replan(a)


# Eksmisja: gospodarstwo zostaje bez dachu nad głową. To stan gry, nie koniec.
func evict(h: SimHousehold) -> void:
	var b: SimBuilding = buildings.get(h.home_id)
	move_household(h, null)
	if h == household and b != null:
		note("EKSMISJA: właściciel wyrzucił rodzinę z domu (%s). Śpicie pod gołym niebem." % b.name, "critical", b.door())
		chronicle.add(clock.now(), "eviction", "Eksmisja z domu (%s) za długi." % b.name, h.members, family.player_lineage_id)
		ask_ok("Eksmisja", "Dług za dom urósł do %d zł. Właściciel wyrzucił was z: %s.\nŚpicie pod gołym niebem, dopóki nie stać was na nowy dom." % [int(h.debt), b.name])


func _debt_jail() -> void:
	# Straż bierze dorosłego krewnego (nie głowę rodu, jeśli jest ktoś inny).
	var cands: Array = []
	for p in family.living():
		var a := agent_by_id(p.agent_id)
		if a != null and a.status == "active" and family.stage_of(p) in ["adult", "elder"]:
			cands.append(p)
	if cands.is_empty():
		return
	var rid: int = family.root_id
	cands.sort_custom(func(x, y):
		if (x.id == rid) != (y.id == rid):
			return y.id == rid
		return x.id < y.id)
	var p: SimPerson = cands[0]
	var a := agent_by_id(p.agent_id)
	jobs.release(a)
	a.steps.clear()
	a.clear_carry()
	a.status = "jailed"
	a.hidden = true
	a.jail_days = float(balance["economy"]["debt_jail_days"])
	var forgiven := household.debt * float(balance["economy"]["debt_jail_forgive"])
	household.evict_days = 0
	household.debt -= forgiven
	note("Straż zabrała %s do aresztu za długi rodu (%d dni). Połowa długu umorzona." % [p.name, int(a.jail_days)], "critical", building("jail").door())
	ask_ok("Areszt za długi", "Dług przekroczył %d zł. Straż zabrała %s do aresztu na %d dni.\nPołowa długu umorzona, reszta (%d zł) zostaje." % [
		int(household.debt_limit), p.name, int(a.jail_days), int(household.debt)])


func _max_living_generation() -> int:
	var g := 0
	for p in family.living():
		g = maxi(g, int(family.generation_of.get(p.id, 0)))
	return g
