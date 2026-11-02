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
var talk: SimTalk
var crime: SimCrime
var trips: SimTrips
var standing: SimStanding
var migration: SimMigration
var ai: SimAI
var trade: SimTrade
var traders: SimTraders
var contracts: SimContracts
var chronicle: SimChronicle

var buildings: Dictionary = {}   # id -> SimBuilding
var trees: Array = []            # SimTree
var fields: Array = []           # SimField (L1)
var sites: Dictionary = {}       # plac budowy (O2): id -> { b, kind, lineage, household, work, total, from, to }
var buildables: Dictionary       # katalog budowy (S29): data/buildables.json
var needs: SimNeeds              # potrzeby gospodarstw (S23): data/needs.json
var roads_built: Array = []      # drogi zbudowane w grze: [od, do] (Vector2)
var enterprises: Dictionary = {} # przedsięwzięcia (S24, T1): id budynku -> { b, type, owner (gosp.) }
var _next_site := 1
var agents: Array = []           # SimAgent (także zmarli — status "dead")
var chore_claims: Dictionary = {}  # "food:<gosp.>"/"firewood:<gosp.>" -> agent id
var stats: Dictionary = {}

const SITE_CLEARANCE := 6.0   # plac budowy nie może stać bliżej innego budynku
const FOREST_JOBS := ["woodcutter", "forager"]   # co można robić w lesie (PPM na las)
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
	buildables = DataLoader.load_json("res://data/buildables.json")
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
	for fs: Dictionary in map.get("fields", []):
		fields.append(SimField.new(fs, balance["fields"]))

	family = SimFamily.new(self, people)
	bonds = SimBonds.new(self, memories)
	chronicle = SimChronicle.new()
	together = SimTogether.new(self, memories["together"])
	talk = SimTalk.new(self, memories["talk"])
	crime = SimCrime.new(self, balance["crime"])
	ai = SimAI.new(self)
	family.setup_start()
	_spawn_society()
	trade = SimTrade.new(self, balance["trade"])
	needs = SimNeeds.new(self, DataLoader.load_json("res://data/needs.json"))
	_spawn_stalls()
	_spawn_enterprises()
	traders = SimTraders.new(self, p_traders)
	contracts = SimContracts.new(self, balance["contracts"])
	trips = SimTrips.new(self, p_traders["trips"])
	standing = SimStanding.new(self, DataLoader.load_json("res://data/standing.json"))
	migration = SimMigration.new(self, balance["migration"])
	ai.new_day()   # rody AI od razu rozdzielają role (kramarz, nadzorca, praca)
	for p in family.living():
		p.set_meta("stage", family.stage_of(p))
	note("Ród %s zaczyna w wynajętej chacie pod lasem. Czynsz %d zł dziennie — pilnuj kasy." % [
		family.dynasty, int(home().rent_per_day)], "info", home().door())


# Stragany z danych (M1): lada na placu albo przy budynku właściciela.
func _spawn_stalls() -> void:
	for sd: Dictionary in map.get("stalls", []):
		var b := SimBuilding.new(String(sd["id"]), String(sd["name"]), "stall",
			Vector2(float(sd["x"]), float(sd["y"])), balance["storage"]["stall"])
		buildings[b.id] = b
		var h := household_at(String(sd["owner_home"]))
		if h == null:
			continue
		var stock: SimBuilding = buildings.get(String(sd.get("stock_from", "")), b)
		var st := trade.add_stall(b, stock, h.id, sd["goods"])
		st.buys = sd.get("buys", []).duplicate()
		for g in sd.get("start_stock", {}):
			stock.add(g, int(sd["start_stock"][g]))


# Przedsięwzięcia z danych (T1): warsztat z właścicielem. Ten sam byt dla gracza i AI.
func _spawn_enterprises() -> void:
	for ed: Dictionary in map.get("enterprises", []):
		var h := household_at(String(ed["owner_home"]))
		var b: SimBuilding = buildings.get(String(ed["building"]))
		if h != null and b != null:
			add_enterprise(b, h.id)


func add_enterprise(b: SimBuilding, owner_hid: int) -> void:
	enterprises[b.id] = { "b": b, "type": b.type, "owner": owner_hid }
	var h: SimHousehold = households.get(owner_hid)
	if h != null and not h.members.is_empty():
		b.owner_kind = "lineage"
		b.owner_id = family.persons[h.members[0]].lineage_id


# Warsztat danego typu należący do gospodarstwa (pierwszy), albo null.
func enterprise_building(hid: int, type: String) -> SimBuilding:
	for e: Dictionary in enterprises.values():
		if int(e["owner"]) == hid and e["type"] == type:
			return e["b"]
	return null


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
	h.repay = pay_to
	return h


# --- Obieg pieniędzy (S22, R1): każda złotówka trafia do kogoś ---

# Odbiorcy płatności, które nie idą z ręki do ręki: „b:<budynek>” (właściciel budynku),
# „authority” (pan na włościach: grzywny, kaucje), „tavern” (karczmarz: posiłki na
# mieście, wesela), „merchant” (kupiec: drobiazgi na prezent).
func pay_to(to: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if to.begins_with("b:") and buildings.has(to.substr(2)):
		pay_owner(buildings[to.substr(2)], amount)
		return
	if to.begins_with("home:"):
		var oh := household_at(to.substr(5))
		if oh != null:
			oh.earn(amount)
			return
	var h: SimHousehold = null
	match to:
		"tavern":
			if buildings.has("tavern") and buildings["tavern"].owner_kind != "none":
				pay_owner(buildings["tavern"], amount)
				return
		"merchant":
			for st: SimStall in trade.stalls.values():
				if not st.temporary and not st.buys.is_empty():
					h = households.get(st.owner)
					break
	if h == null:
		h = authority()
	if h != null:
		h.earn(amount)


# Urząd (V2): grzywny, kaucje i pieniądze bez właściciela trafiają do sołtysa — ród,
# który stoi najwyżej; na starcie (i bez nikogo) pan na włościach z danych.
func authority() -> SimHousehold:
	var l: SimLineage = standing.office_holder() if standing != null else null
	if l != null and l.root_id >= 0 and family.persons.has(l.root_id):
		var h: SimHousehold = households.get(family.persons[l.root_id].household_id)
		if h != null:
			return h
	return household_at(String(balance["economy"]["authority_home"]))


# Las i ziemia mają właściciela (S27, T4): gospodarstwo z domu wskazanego w mapie.
func forest_owner() -> SimHousehold:
	return household_at(String(map["forest"].get("owner_home", "")))


func land_owner() -> SimHousehold:
	return household_at(String(map.get("land_owner_home", "")))


# Opłata od pnia: kto rąbie w cudzym lesie, płaci właścicielowi (z kasy rodu,
# a brak idzie w dług wobec niego).
func pay_stumpage(a: SimAgent, logs: int) -> void:
	var owner := forest_owner()
	var h := household_of(a)
	if owner == null or owner == h or logs <= 0:
		return
	h.pay_or_debt(float(balance["economy"]["stumpage_per_log"]) * logs, "home:" + owner.home_id)


# Wszystkie pieniądze świata: skrzynie, sakwy (także osób w drodze) i kasy miast okolicy.
func money_total() -> float:
	var s := 0.0
	for h: SimHousehold in households.values():
		s += h.cash
	for p: SimPerson in family.persons.values():
		s += p.purse
	return s + traders.town_cash_total()


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
	return needs.label(g) if needs != null else g


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
	var p := person_of(a)
	if p != null and job != a.job:
		contracts.quit(p, "")
	a.job = job
	jobs.replan(a)


# Przydział jak w Cultures (S21, L4): zaznaczona osoba + PPM na miejsce. Zwraca opcje
# { label, job, place, ok }: na swoich miejscach zawody, które się tam robi; na cudzych
# tylko wakaty z ofert (z płacą), a bez wakatu — opcja wyszarzona z powodem.
# `target`: id budynku, "forest" albo "field:<id>".
func job_options(agent_id: int, target: String) -> Array:
	var a := agent_by_id(agent_id)
	if a == null or is_independent(a) or a.is_child:
		return []
	var out: Array = []
	if target == "forest":
		for j in FOREST_JOBS:
			out.append({ "label": "Przydziel: %s" % SimJobs.JOB_LABELS[j], "job": j, "place": "", "ok": true })
		return out
	var bid := target
	if target.begins_with("field:"):
		var f := field_by_id(target.substr(6))
		if f == null:
			return []
		bid = f.owner_building
	var b: SimBuilding = buildings.get(bid)
	if b == null:
		return []
	if is_free_house(b):
		return _house_options(a, b)
	if b.id == household.home_id:
		return _house_options(a, b) + _work_options(a, b)
	return _work_options(a, b)


func _work_options(a: SimAgent, b: SimBuilding) -> Array:
	var out: Array = []
	var bid := b.id
	if is_foreign(b):
		for o: Dictionary in contracts.offers:
			if o["place"] != bid or int(o["slots"]) <= 0:
				continue
			var free := contracts.free_slots(o)
			out.append({ "label": "Najmij się: %s — %d zł/dzień (wolne %d/%d)" % [SimJobs.JOB_LABELS.get(o["job"], o["job"]),
				int(o["wage"]), maxi(free, 0), int(o["slots"])], "job": o["job"], "place": bid, "ok": free > 0 })
		if out.is_empty():
			out.append({ "label": "%s: brak wakatów" % b.name, "job": "", "place": bid, "ok": false })
		return out
	for r: Dictionary in jobs.recipes.values():
		if String(r["type"]) == b.type and enterprises.has(bid) and int(enterprises[bid]["owner"]) == household.id:
			out.append({ "label": "Przydziel: %s" % SimJobs.JOB_LABELS.get(r["job"], r["job"]), "job": String(r["job"]), "place": "", "ok": true })
	if trade.stalls.has(bid):
		out.append({ "label": "Przydziel: %s" % SimJobs.JOB_LABELS["stallkeeper"], "job": "stallkeeper", "place": "", "ok": true })
	if sites.has(bid):
		out.append({ "label": "Przydziel: %s" % SimJobs.JOB_LABELS["builder"], "job": "builder", "place": "", "ok": true })
	if b.type in ["market", "stall"] or b.id == a.home_id:
		out.append({ "label": "Przydziel: %s" % SimJobs.JOB_LABELS["carrier"], "job": "carrier", "place": "", "ok": true })
	if b.id == a.home_id:
		out.append({ "label": "Bez przydziału (domowe obowiązki)", "job": "none", "place": "", "ok": true })
	return out


# Mieszkanie z PPM (O1): wolny dom — wynajem dla rodziny albo wyprowadzka tej osoby,
# kupno; własny dom — wyrzucenie zaznaczonej osoby.
func _house_options(a: SimAgent, b: SimBuilding) -> Array:
	var p := person_of(a)
	var out: Array = []
	if is_free_house(b):
		out.append({ "label": "Wynajmij dla rodziny: %s (%d zł/dzień)" % [b.name, int(b.rent_per_day)], "action": "rent", "place": b.id, "ok": true })
		if p.household_id == household.id and family.stage_of(p) in ["adult", "elder"]:
			out.append({ "label": "%s wyprowadza się tutaj (na swoje)" % p.name, "action": "move_out", "place": b.id, "ok": true })
	if house_price(b) > 0.0 and not owns(household, b) and (is_free_house(b) or b.id == household.home_id):
		out.append({ "label": "Kup dom: %s (%d zł)" % [b.name, int(house_price(b))], "action": "buy", "place": b.id, "ok": household.cash >= house_price(b) })
	if b.id == household.home_id and p.household_id == household.id and p.id != family.root_id and family.stage_of(p) != "child":
		out.append({ "label": "Wyrzuć z domu: %s" % p.name, "action": "throw_out", "place": b.id, "ok": true })
	return out


func house_action(action: String, agent_id: int, bid: String) -> bool:
	var p := person_of(agent_by_id(agent_id))
	match action:
		"rent":
			return rent_house(bid)
		"move_out":
			return p != null and rent_house(bid, p.id)
		"buy":
			return buy_house(bid)
		"throw_out":
			return p != null and throw_out(p.id)
	return false


# Cudze miejsce: budynek należy do innego rodu albo osoby spoza rodu gracza.
func is_foreign(b: SimBuilding) -> bool:
	if sites.has(b.id):
		return int(sites[b.id]["household"]) != household.id
	if trade.stalls.has(b.id):
		return trade.stalls[b.id].owner != household.id
	match b.owner_kind:
		"lineage":
			return b.owner_id != family.player_lineage_id and not owns(household, b)
		"person":
			var p: SimPerson = family.persons.get(b.owner_id)
			return p == null or not family.is_ours(p)
	return false


# Wybór z menu PPM: swoje miejsce — zwykły przydział; cudze — umowa z wakatu.
func assign_job(agent_id: int, job: String, place: String) -> bool:
	var a := agent_by_id(agent_id)
	if a == null or is_independent(a) or job == "":
		return false
	if place == "":
		set_job(agent_id, job)
		return true
	var o := contracts.find_offer_at(place, job)
	if o.is_empty() or contracts.free_slots(o) <= 0:
		return false
	set_job(agent_id, job)
	contracts.hire(o, person_of(a))
	jobs.replan(a)
	note("%s najmuje się: %s (%d zł/dzień)." % [person_of(a).name, SimJobs.JOB_LABELS.get(job, job), int(o["wage"])], "info", a.position)
	return true


# --- Mieszkanie: bezpośrednie rozkazy gracza (O1) ---

func is_free_house(b: SimBuilding) -> bool:
	if b == null or not b.type in HOUSE_TYPES:
		return false
	for h: SimHousehold in households.values():
		if h.home_id == b.id and not h.members.is_empty():
			return false
	return true


func house_price(b: SimBuilding) -> float:
	return float(balance["housing"]["price"].get(b.type, 0.0))


# Wynajem wolnego domu: dla całej rodziny gracza albo dla jednej osoby, która się
# wyprowadza i zakłada osobne gospodarstwo w obrębie rodu (I4).
func rent_house(bid: String, person_id: int = -1) -> bool:
	var b: SimBuilding = buildings.get(bid)
	if not is_free_house(b):
		return false
	var days := float(balance["housing"]["rent_upfront_days"])
	if person_id < 0:
		if household.cash < b.rent_per_day * days:
			note("Za mało pieniędzy na wynajem: %s (%d zł z góry)." % [b.name, int(b.rent_per_day * days)], "warn", null)
			return false
		var old := household.home_id
		move_household(household, b)
		note("Rodzina przeprowadza się: %s (%d zł dziennie)." % [b.name, int(b.rent_per_day)], "good", b.door())
		chronicle.add(clock.now(), "move", "Przeprowadzka do: %s (z: %s)." % [b.name, old if old != "" else "pod gołym niebem"], household.members, family.player_lineage_id)
		return true
	return move_out(person_id, b)


func move_out(person_id: int, b: SimBuilding) -> bool:
	var p: SimPerson = family.persons.get(person_id)
	if p == null or not family.is_ours(p) or family.stage_of(p) in ["child", "teen"] or not is_free_house(b):
		return false
	var days := float(balance["housing"]["rent_upfront_days"])
	if p.purse + household.cash < b.rent_per_day * days and not owns(household, b):
		note("%s nie stać na wynajem: %s." % [p.name, b.name], "warn", null)
		return false
	var h := new_household(b.id, 0.0)
	join_household(p, h)
	# Na start bierze swoją sakwę (i nic ze wspólnej skrzyni).
	h.cash = p.purse
	p.purse = 0.0
	p.held = 0.0
	var a := agent_by_id(p.agent_id)
	if a != null:
		jobs.replan(a)
	note("%s wyprowadza się na swoje: %s." % [p.name, b.name], "info", b.door())
	chronicle.add(clock.now(), "move", "%s wyprowadza się na swoje (%s), zostaje w rodzie." % [p.name, b.name], [p.id], p.lineage_id)
	return true


func buy_house(bid: String) -> bool:
	var b: SimBuilding = buildings.get(bid)
	var price := house_price(b) if b != null else 0.0
	if b == null or price <= 0.0 or owns(household, b) or household.cash < price:
		note("Nie da się kupić: %s (cena %d zł)." % [b.name if b != null else "?", int(price)], "warn", null)
		return false
	household.pay(price)
	pay_owner(b, price)
	b.owner_kind = "lineage"
	b.owner_id = family.player_lineage_id
	note("Ród %s kupuje: %s. Koniec czynszu za ten dom." % [family.dynasty, b.name], "good", b.door())
	chronicle.add(clock.now(), "purchase", "Kupno domu: %s za %d zł." % [b.name, int(price)], household.members, family.player_lineage_id)
	return true


# Wyrzucenie z domu: osoba zostaje bez dachu (osobne gospodarstwo, ten sam ród) i to pamięta.
func throw_out(person_id: int) -> bool:
	var p: SimPerson = family.persons.get(person_id)
	if p == null or p.household_id != household.id or p.id == family.root_id or family.stage_of(p) == "child":
		return false
	var h := new_household("", 0.0)
	join_household(p, h)
	if family.root_id >= 0:
		bonds.remember(p.id, SimBonds.person(family.root_id), "thrown_out", [family.root_id])
	var a := agent_by_id(p.agent_id)
	if a != null:
		jobs.replan(a)
	note("%s zostaje wyrzucon%s z domu." % [p.name, "y" if p.sex == "m" else "a"], "warn", a.position if a != null else null)
	chronicle.add(clock.now(), "thrown_out", "%s wyrzucon%s z domu." % [p.name, "y" if p.sex == "m" else "a"], [p.id], p.lineage_id)
	return true


# Rodzina sama wychodzi z domu (np. żeby nie płacić czynszu): pod gołe niebo.
func leave_home() -> void:
	var b: SimBuilding = buildings.get(household.home_id)
	move_household(household, null)
	note("Rodzina opuszcza dom%s. Śpicie pod gołym niebem." % ((": " + b.name) if b != null else ""), "warn", null)


# --- Budowa (O2) ---

# Zlecenie budowy z katalogu (S29, T0): powstaje plac budowy, na który trzeba donieść
# materiały i na którym ktoś musi pracować; ród wystawia też ofertę dla budowlańców.
# Budowa liniowa (droga) bierze dwa punkty: początek i koniec.
func commission(kind: String, at: Vector2, to: Variant = null, owner: SimHousehold = null) -> String:
	if owner == null:
		owner = household
	var cfg: Dictionary = buildables.get(kind, {})
	if cfg.is_empty():
		return ""
	var line := bool(cfg.get("line", false))
	var pos := at if not line else (at + (to as Vector2)) * 0.5
	var clearance := float(cfg["clearance"])
	for b: SimBuilding in buildings.values():
		if clearance > 0.0 and b.position.distance_to(pos) < clearance:
			note("Za blisko innego budynku — wybierz inne miejsce.", "warn", null)
			return ""
	# Działka pod budowę (T4): płaci się właścicielowi ziemi, chyba że to własna ziemia.
	var plot := float(balance["economy"]["plot_price"].get(kind, 0.0))
	var lo := land_owner()
	if plot > 0.0 and lo != null and lo != owner:
		if owner.cash < plot:
			if owner == household:
				note("Za mało pieniędzy na działkę pod budowę (%d zł dla właściciela ziemi)." % int(plot), "warn", null)
			return ""
		owner.pay(plot)
		lo.earn(plot)
	var id := "site_%d" % _next_site
	_next_site += 1
	var mats: Dictionary = cfg["materials"]
	var b := SimBuilding.new(id, "Plac budowy: %s" % String(cfg["label"]).to_lower(), "site", pos, mats)
	buildings[id] = b
	var total := float(cfg["work"]) if not line else float(cfg["work_per_unit"]) * at.distance_to(to as Vector2)
	var lin: int = family.persons[owner.members[0]].lineage_id if not owner.members.is_empty() else family.player_lineage_id
	sites[id] = { "b": b, "kind": kind, "lineage": lin, "household": owner.id, "work": 0.0,
		"total": total, "from": at, "to": to if line else at }
	contracts.post(owner.id, id, "builder", int(balance["construction"]["builders"]), float(balance["jobs"]["laborer_wage_day"]))
	if owner != household:
		return id
	var need := ", ".join(mats.keys().map(func(g): return "%d× %s" % [int(mats[g]), good_label(g)]))
	note("Plac budowy wytyczony (%s). %s — przydziel budowlańca (PPM na plac) albo poczekaj na najętych." % [
		String(cfg["label"]).to_lower(), ("Potrzeba: " + need) if need != "" else "Potrzeba tylko pracy"], "info", b.door())
	return id


func commission_house(at: Vector2) -> String:
	return commission("house", at)


func site_cfg(site: Dictionary) -> Dictionary:
	return buildables[String(site["kind"])]


func site_total(site: Dictionary) -> float:
	return float(site["total"])


# Ile pracy wolno już wykonać: tyle, na ile starcza doniesionych materiałów.
func site_work_allowed(site: Dictionary) -> float:
	var mats: Dictionary = site_cfg(site)["materials"]
	var b: SimBuilding = site["b"]
	var frac := 1.0
	for g in mats:
		frac = minf(frac, float(b.amount(g)) / float(mats[g]))
	return site_total(site) * frac


func build_work(site_id: String, secs: float) -> void:
	var site: Dictionary = sites.get(site_id, {})
	if site.is_empty():
		return
	site["work"] = minf(float(site["work"]) + secs, site_work_allowed(site))
	if float(site["work"]) >= site_total(site) - 0.001:
		_finish_site(site_id)


func _finish_site(site_id: String) -> void:
	var site: Dictionary = sites[site_id]
	var cfg := site_cfg(site)
	var b: SimBuilding = site["b"]
	sites.erase(site_id)
	contracts.post(int(site["household"]), site_id, "builder", 0, 0.0)
	for c: Dictionary in contracts.list.duplicate():
		if c["place"] == site_id:
			contracts.quit(family.persons[int(c["worker"])], "")
	for a: SimAgent in agents:
		if a.workplace == site_id or (a.job == "builder" and household_of(a).id == int(site["household"]) and sites.is_empty()):
			a.workplace = ""
			a.job = "none"
			jobs.replan(a)
	var l: SimLineage = family.lineages.get(int(site["lineage"]))
	var lname := l.name if l != null else "?"
	match String(cfg["result"]):
		"road":
			buildings.erase(site_id)
			roads_built.append([site["from"], site["to"]])
			note("Droga gotowa.", "good", b.position)
			return
		"stall":
			b.type = "stall"
			b.name = "%s rodu %s" % [String(cfg["name"]), lname]
			b.capacity = (balance["storage"]["stall"] as Dictionary).duplicate()
			b.stock = {}
			for g in b.capacity:
				b.stock[g] = 0
			trade.add_stall(b, b, int(site["household"]), cfg.get("goods", []))
			note("Stragan gotowy. Postaw za ladą kramarza (PPM na stragan).", "good", b.door())
			return
	b.type = String(cfg["result"])
	b.name = "%s (%s)" % [String(cfg["name"]), lname] if bool(cfg.get("enterprise", false)) else String(cfg["name"])
	b.stock = {}
	b.capacity = (balance["storage"].get(b.type, balance["storage"]["home"]) as Dictionary).duplicate()
	for g in b.capacity:
		b.stock[g] = 0
	b.owner_kind = "lineage"
	b.owner_id = int(site["lineage"])
	b.rent_per_day = float(balance["economy"]["rent_per_day"].get(b.type, 0.0))
	if bool(cfg.get("enterprise", false)):
		add_enterprise(b, int(site["household"]))
	note("Budowa skończona: %s należy do rodu %s." % [b.name, lname], "good" if int(site["household"]) == household.id else "info", b.door())
	chronicle.add(clock.now(), "built", "Zbudowany: %s." % b.name, [], int(site["lineage"]))


# Wyprawa do miasta (U3): z towarem z własnego warsztatu (albo domu).
func send_on_trip(agent_id: int, town_id: String) -> bool:
	var a := agent_by_id(agent_id)
	if a == null or is_independent(a):
		return false
	var h := household_of(a)
	var town: SimTown = traders.towns.get(town_id)
	if town == null:
		return false
	var from: SimBuilding = home_of(a)
	for type in ["workshop", "sawmill"]:
		var b := enterprise_building(h.id, type)
		if b != null and not trips.cargo_plan(town, b).is_empty():
			from = b
			break
	if not trips.start(a, town_id, from):
		return false
	note("%s wyrusza na wyprawę do: %s." % [person_of(a).name, town.name], "info", a.position)
	return true


# Gracz jako pracodawca (L4): oferta pracy w swoim warsztacie (ile osób, za ile).
func post_player_offer(bid: String, job: String, slots: int, wage: float) -> void:
	contracts.post(household.id, bid, job, maxi(slots, 0), maxf(wage, 0.0))


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
	var mill := enterprise_building(household_of(a).id, "sawmill")
	var drop: SimBuilding = mill if mill != null else home_of(a)
	if drop != null:
		a.steps.append({ "t": "walk", "to": drop.door() + SAWMILL_DROP, "why": "niesie kłodę: %s" % drop.name })
		a.steps.append({ "t": "do", "fn": "deposit", "arg": drop.id })


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
				pay_to("authority", float(balance["crime"]["bail"]))
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
	trips.tick()
	together.sample(dt)
	talk.sample(dt)


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
	a.labor_task = String(s.get("task", ""))
	if act == "sell":
		_quiet_stall(a)
	if act == "talk":
		var other := agent_by_id(int(s.get("partner", -1)))
		if other != null and other.position.distance_to(a.position) > MOVE_EPS:
			a.facing = (other.position - a.position).normalized()
	if jobs.is_work(act):
		contracts.accrue(a, s, dt)
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


# Pole właściciela (budynku), na którym jest dziś robota albo snopy do zniesienia.
func field_with_work(owner_building: String) -> SimField:
	var season := clock.current_season()
	for f: SimField in fields:
		if f.owner_building == owner_building and f.has_work(season):
			return f
	return null


func field_by_id(id: String) -> SimField:
	for f: SimField in fields:
		if f.id == id:
			return f
	return null


# Gospodarstwo, które mieszka w budynku (np. właściciel dworu i jego pól).
func household_at(bid: String) -> SimHousehold:
	var best: SimHousehold = null
	for h: SimHousehold in households.values():
		if h.home_id == bid and not h.members.is_empty():
			best = h
	return best


func estate_owner() -> SimHousehold:
	var b: SimBuilding = building(String(balance["estate"]["building"]))
	var best: SimHousehold = null
	for h: SimHousehold in households.values():
		if h.home_id == b.id and not h.members.is_empty():
			best = h
	return best


# Brak zbytu widać (M6): kramarz, przy którym długo nikt nic nie kupił, mówi to wprost.
func _quiet_stall(a: SimAgent) -> void:
	var st: SimStall = trade.stall_of_keeper(a)
	if st == null or st.keeper != a.id:
		return
	if st.last_deal == 0.0:
		st.last_deal = clock.now()
	if clock.now() - st.last_deal > float(balance["trade"]["quiet_days"]):
		a.idle_reason = "stoi za ladą — nikt nie kupuje (ceny? towar?)"


func _labor(a: SimAgent, s: Dictionary, dt: float) -> void:
	# Płaca narasta w umowie (SimContracts.accrue), wręcza ją płatnik po robocie (L3).
	# Praca posuwa robotę na konkretnym polu (L2); po skończonym zadaniu nowy plan.
	# Robotnik idzie wzdłuż zagonu razem z postępem.
	var f := field_by_id(String(s.get("field", "")))
	var i := int(s.get("cell", -1))
	var season := clock.current_season()
	if f == null or i < 0 or f.cell_task(i, season) == "":
		s["left"] = 0.0
		return
	var done := f.work(i, season, dt * a.age_eff * float(s["will"]) * a.trait_mult("labor"))
	var c: Dictionary = f.cells[i]
	var from: Vector2 = c["start"]
	var to: Vector2 = c["end"]
	a.facing = (to - from).normalized()
	if done != "":
		a.position = to
		s["left"] = 0.0
		if done == "harvest" and f.count("ripe") == 0:
			note("Żniwa skończone na polu (%s): %d snopów do zniesienia." % [building(f.owner_building).name, f.heap], "info", f.heap_spot())
	else:
		a.position = from.lerp(to, f.progress(i, season))


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
	var h := household_of(a)
	h.owe("authority", float(c["fine"]))
	h.reputation -= float(c["reputation_hit"])
	stats["arrests"] = int(stats.get("arrests", 0)) + 1
	var who := "Złapany" if p.sex == "m" else "Złapana"
	if not family.is_ours(p):
		note("%s %s na kradzieży — siedzi w areszcie." % [who, p.full_name()], "info", building("jail").door())
		return
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
	# Sakwa zmarłego zostaje w domu (spadek do skrzyni gospodarstwa).
	var dh: SimHousehold = households.get(p.household_id)
	if dh != null and p.purse > 0.0:
		dh.cash += p.purse
		p.purse = 0.0
		p.held = 0.0
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
		# Zniszczony dom trzyma mniej ciepła: więcej opału (R3).
		var home_b: SimBuilding = buildings[h.home_id]
		h.burn_acc += need * (1.0 + float(needs.house_cfg()["cold_extra_burn"]) * (1.0 - home_b.condition))
		needs.wear_day(h)
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
	for f: SimField in fields:
		if f.new_day(season) > 0:
			note("Niezebrane zboże zgniło na polu (%s)." % building(f.owner_building).name, "warn", f.center())
	contracts.settle_day()
	together.end_day()
	traders.new_day()
	standing.new_day()
	migration.new_day()
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
		# Bez automatu dla gracza (O1): gracz sam wynajmuje, kupuje albo buduje.
		var free := free_house() if h != household else null
		if free != null and h.cash >= free.rent_per_day * float(eco["rehouse_rent_days"]):
			move_household(h, free)
			if h == household:
				note("Rodzina wynajmuje dom: %s (%d zł dziennie)." % [free.name, int(free.rent_per_day)], "good", free.door())
		return
	if b.rent_per_day <= 0.0 or owns(h, b):
		return
	var missing := b.rent_per_day - h.pay_due(b.rent_per_day, "b:" + b.id)
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
			if p != null and p.alive():
				p.purse += amount
				return
		"lineage":
			var l: SimLineage = family.lineages.get(b.owner_id)
			var r: SimPerson = family.persons.get(l.root_id) if l != null else null
			if r != null and households.has(r.household_id):
				households[r.household_id].earn(amount)
				return
	# Właściciel nieznany albo nie żyje: pieniądze bierze urząd (S22, V2).
	var auth := authority()
	if auth != null:
		auth.earn(amount)


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
	household.evict_days = 0
	household.forgive(float(balance["economy"]["debt_jail_forgive"]))
	note("Straż zabrała %s do aresztu za długi rodu (%d dni). Połowa długu umorzona." % [p.name, int(a.jail_days)], "critical", building("jail").door())
	ask_ok("Areszt za długi", "Dług przekroczył %d zł. Straż zabrała %s do aresztu na %d dni.\nPołowa długu umorzona, reszta (%d zł) zostaje." % [
		int(household.debt_limit), p.name, int(a.jail_days), int(household.debt)])


func _max_living_generation() -> int:
	var g := 0
	for p in family.living():
		g = maxi(g, int(family.generation_of.get(p.id, 0)))
	return g
