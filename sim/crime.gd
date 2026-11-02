# SimCrime — kradzież jako proces (faza P). Złodziej upatruje cel (rozłożony stragan
# bez opieki albo sakwę kogoś w tłumie na targu), obserwuje i czeka na moment, kiedy
# nikt blisko nie patrzy; w tłumie łatwiej się ukryć. Łapie konkretny świadek, który
# widział — i to on biegnie do straży. Kto zna złodzieja i go lubi, może przemilczeć.
# Złodziej wygląda jak każdy inny.
class_name SimCrime
extends RefCounted


var w: SimWorld
var _cfg: Dictionary


func _init(world: SimWorld, cfg: Dictionary) -> void:
	w = world
	_cfg = cfg


# Cel: najpierw niepilnowany, rozłożony stragan z towarem; potem sakwa w tłumie na targu.
func pick_target(thief: SimAgent) -> Dictionary:
	var th := w.household_of(thief)
	var best: SimStall = null
	var best_d := INF
	for st: SimStall in w.trade.stalls.values():
		if st.packed or st.owner == th.id or _keeper_near(st):
			continue
		if not st.goods.any(func(g): return st.stock.amount(g) > 0):
			continue
		var d := thief.position.distance_to(st.counter())
		if d < best_d:
			best_d = d
			best = st
	if best != null:
		return { "kind": "stall", "stall": best.id }
	var square := w.building("market").door()
	var marks: Array = []
	for a: SimAgent in w.agents:
		var p := w.person_of(a)
		if a == thief or p == null or not a.is_active() or a.hidden or p.household_id == th.id:
			continue
		if p.purse >= float(_cfg["min_purse"]) and a.position.distance_to(square) <= float(_cfg["square_radius"]):
			marks.append(a)
	if marks.is_empty():
		return {}
	var m: SimAgent = marks[w.rng.next_int(0, marks.size() - 1)]
	return { "kind": "purse", "agent": m.id }


func _keeper_near(st: SimStall) -> bool:
	var ka := w.agent_by_id(st.keeper)
	return ka != null and ka.position.distance_to(st.building.position) <= float(_cfg["close_radius"]) * 2.0


func target_pos(t: Dictionary) -> Vector2:
	if t.get("kind", "") == "stall":
		var st: SimStall = w.trade.stalls.get(String(t["stall"]))
		return st.counter() if st != null else Vector2.INF
	var a := w.agent_by_id(int(t.get("agent", -1)))
	return a.position if a != null and a.is_active() and not a.hidden else Vector2.INF


# Kto widzi złodzieja: przytomni ludzie w zasięgu wzroku, poza nim samym.
func observers(thief: SimAgent) -> Array:
	var out: Array = []
	for a: SimAgent in w.agents:
		if a != thief and a.is_active() and not a.hidden and a.activity != "sleep" and a.person_id >= 0 \
				and a.position.distance_to(thief.position) <= float(_cfg["sight_radius"]):
			out.append(a)
	return out


# Moment: nikt nie stoi tuż obok (poza ofiarą sakwy, którą się okrada), albo tłum
# jest tak gęsty, że jeden więcej nie zwraca uwagi.
func moment_ok(thief: SimAgent, t: Dictionary) -> bool:
	var obs := observers(thief)
	if obs.size() >= int(_cfg["crowd_size"]):
		return true
	var victim := int(t.get("agent", -1))
	for o: SimAgent in obs:
		if o.id != victim and o.position.distance_to(thief.position) <= float(_cfg["close_radius"]):
			return false
	return true


# Sama kradzież. Zwraca true, gdy coś zginęło. Potem świadkowie decydują, co widzieli.
func steal(thief: SimAgent, t: Dictionary) -> bool:
	if thief.position.distance_to(target_pos(t)) > float(_cfg["reach"]):
		return false
	var tp := w.person_of(thief)
	var victim: SimAgent = null
	if t["kind"] == "stall":
		var st: SimStall = w.trade.stalls.get(String(t["stall"]))
		if st == null or st.packed or _keeper_near(st):
			return false
		var goods: Array = st.goods.filter(func(g): return st.stock.amount(g) > 0)
		if goods.is_empty():
			return false
		var g: String = goods[w.rng.next_int(0, goods.size() - 1)]
		var r: Array = _cfg["stall_take"]
		var n := st.stock.take(g, w.rng.next_int(int(r[0]), int(r[1])))
		thief.clear_carry()
		thief.carrying = g
		thief.carrying_qty = n
		if g == "chair":
			for i in n:
				thief.carrying_qualities.append(st.stock.chair_qualities.pop_front() if not st.stock.chair_qualities.is_empty() else 0.0)
		w.events.float_text(thief.position, "ginie towar ze straganu", "info")
	else:
		victim = w.agent_by_id(int(t["agent"]))
		var vp := w.person_of(victim)
		var r2: Array = _cfg["purse_take"]
		var amt := vp.purse * w.rng.next_float(float(r2[0]), float(r2[1]))
		vp.purse -= amt
		vp.held = minf(vp.held, vp.purse)
		w.earn_for(thief, amt)
		w.events.float_text(victim.position, "ktoś ma lżejszą sakwę", "info")
	thief.skills["steal"] = minf(float(w.balance["skills"]["max"]), thief.skill("steal") + float(_cfg["skill_per_theft"]))
	w.stats["thefts"] = int(w.stats.get("thefts", 0)) + 1
	_witnesses(thief, tp, victim)
	return true


# Każdy, kto patrzył, mógł zauważyć — w tłumie i po ciemku trudniej; zręczny złodziej
# rzadziej wpada. Zauważył i lubi złodzieja — milczy; nie lubi albo nie zna — donosi.
func _witnesses(thief: SimAgent, tp: SimPerson, victim: SimAgent) -> void:
	var obs := observers(thief)
	var crowd := float(obs.size())
	var light := w.clock.light_factor()
	for o: SimAgent in obs:
		var p := float(_cfg["notice_base"]) * light * maxf(0.2, 1.0 - float(_cfg["notice_skill_reduction"]) * thief.skill("steal"))
		p /= 1.0 + float(_cfg["crowd_cover"]) * maxf(0.0, crowd - 1.0)
		if o == victim:
			p *= float(_cfg["victim_mult"])
		if not w.rng.chance(p):
			continue
		var op := w.person_of(o)
		if w.bonds.value(op.id, SimBonds.person(tp.id)) >= float(_cfg["silent_bond"]):
			w.bonds.remember(op.id, SimBonds.person(tp.id), "covered_theft", [tp.id])
			continue
		if o == victim:
			w.bonds.remember(op.id, SimBonds.person(tp.id), "robbed", [tp.id])
		report(o, thief)
		return


# Świadek biegnie do ratusza i mówi, kogo widział.
func report(witness: SimAgent, thief: SimAgent) -> void:
	w.jobs.release(witness)
	witness.steps.clear()
	witness.controlled = true   # bieg do straży nie przerywa się innym planem
	var jail: SimBuilding = w.building("jail")
	var tp := w.person_of(thief)
	witness.steps.append({ "t": "walk", "to": jail.door(), "why": "biegnie do straży: widział(a), jak %s kradnie" % tp.name })
	witness.steps.append({ "t": "do", "fn": "report_theft", "arg": thief.id })
	witness.plan_kind = "manual"
	w.events.float_text(witness.position, "Złodziej!", "cost")


# Donos w ratuszu: straż zamyka wskazanego, jeśli jest jeszcze na wolności.
func on_report(witness: SimAgent, thief_id: int) -> void:
	var thief := w.agent_by_id(thief_id)
	if thief == null or thief.status != "active":
		return
	var wp := w.person_of(witness)
	var tp := w.person_of(thief)
	w.note("%s doniósł/doniosła straży: %s kradnie na targu." % [wp.name, tp.name], "warn", w.building("jail").door())
	w.arrest(thief)
