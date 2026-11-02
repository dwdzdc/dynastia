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
	post_offers()
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
		var winter := w.clock.current_season() == "winter"
		# Praca u kogoś (L3): kto ma umowę, robi swoje; reszta bierze najlepszą ofertę,
		# a jak żadna się nie opłaca — las (poza zimą) albo wolne.
		var foragers := 0
		for a: SimAgent in workers:
			var p := w.person_of(a)
			if hungry and foragers < int(cfg["max_foragers"]) and not winter:
				w.contracts.quit(p, "")
				_assign(a, "forager")
				foragers += 1
				continue
			if not w.contracts.of_worker(p.id).is_empty():
				continue
			var o := w.contracts.best_offer_for(p)
			if not o.is_empty():
				w.contracts.hire(o, p)
				w.jobs.replan(a)
			else:
				_assign(a, "none" if winter else "forager")


func _assign(a: SimAgent, job: String) -> void:
	if a.job != job:
		a.job = job
		w.jobs.replan(a)


# Właściciele pól wystawiają oferty pracy w polu (L3): tyle rąk, ile z danych i na ile
# ich stać na dziś; bez roboty w polu — brak oferty.
func post_offers() -> void:
	var est: Dictionary = w.balance["estate"]
	var wage := float(w.balance["jobs"]["laborer_wage_day"])
	var owners := {}
	for f: SimField in w.fields:
		owners[f.owner_building] = true
	for bid in owners:
		var h := w.household_at(bid)
		if h == null or h == w.household:
			continue
		var slots := 0
		if w.field_with_work(bid) != null:
			slots = mini(int(est["laborers"]), int(floor(h.cash / wage)))
		w.contracts.post(h.id, bid, "laborer", slots, wage)
