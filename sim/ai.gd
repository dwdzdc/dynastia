# SimAI — decyzje rodów spoza gracza (G2). Model, potrzeby i plan dnia mają ten sam
# kod co ród gracza (SimJobs); tu jest tylko to, co gracz robi ręcznie: przydział pracy.
# Raz na dobę każde gospodarstwo AI patrzy na spiżarnię i kasę i rozdziela ludzi.
class_name SimAI
extends RefCounted


var w: SimWorld


func _init(world: SimWorld) -> void:
	w = world


func new_day() -> void:
	var cfg: Dictionary = w.balance["ai"]
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty():
			continue
		var workers: Array = []
		for pid in h.members:
			var p: SimPerson = w.family.persons[pid]
			var a := w.agent_by_id(p.agent_id)
			var l := w.family.lineage_of(p)
			if a == null or a.status != "active" or not a.can_work() or w.family.is_ours(p):
				continue
			# Ziemiaństwo i kupcy żyją z majątku i handlu, nie z dniówki.
			if l != null and l.role in cfg["idle_roles"]:
				a.job = "none"
				continue
			workers.append(a)
		# Dorośli bez pary z rodów AI rozglądają się za małżonkiem sami.
		for pid in h.members:
			var q: SimPerson = w.family.persons[pid]
			if not w.family.is_ours(q) and w.family.can_marry(q):
				q.seeking_spouse = true
		var home: SimBuilding = w.buildings.get(h.home_id)
		var hungry := home != null and home.amount("food") < int(cfg["forage_when_food_below"]) \
			and h.cash < float(cfg["forage_when_cash_below"])
		# Dwór bez pieniędzy albo bez roboty w polu nie zatrudnia: wtedy las zamiast dniówki.
		var estate := w.estate_owner()
		var no_wages := estate == null or estate.cash < float(w.balance["jobs"]["laborer_wage_day"]) * float(workers.size()) \
			or w.field_with_work(String(w.balance["estate"]["building"])) == null
		var foragers := 0
		for a: SimAgent in workers:
			var job := String(cfg["default_job"])
			if (no_wages or (hungry and foragers < int(cfg["max_foragers"]))) and w.clock.current_season() != "winter":
				job = "forager"
				foragers += 1
			if a.job != job:
				a.job = job
				w.jobs.replan(a)
