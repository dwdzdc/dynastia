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
	set_prices()
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty():
			continue
		var workers: Array = []
		for pid in h.members:
			var p: SimPerson = w.family.persons[pid]
			var a := w.agent_by_id(p.agent_id)
			if a == null or a.status != "active" or not a.can_work() or w.family.is_ours(p):
				continue
			workers.append(a)
		# Bez klas (S20): kogo stać, ten nie najmuje się do cudzej roboty — żyje z majątku,
		# płaci, nadzoruje, bywa. Decyduje skrzynia, nie rola w danych.
		if not workers.is_empty() and h.cash / float(workers.size()) >= float(cfg["wealthy_cash_per_adult"]):
			# Role z majątku: kramarz za ladą własnego straganu (M2), zaopatrzeniowiec, gdy
			# stragan skupuje i dokupuje (kupiec, M5), nadzorca, gdy mają najętych (L6).
			var roles: Array = []
			var own: Array = w.trade.stalls_of(h.id).filter(func(x): return not x.temporary)
			if not own.is_empty():
				roles.append("stallkeeper")
				if not own[0].buys.is_empty():
					roles.append("carrier")
			if not w.contracts.of_employer(h.id).is_empty():
				roles.append("overseer")
			for i in workers.size():
				var wa: SimAgent = workers[i]
				w.contracts.quit(w.person_of(wa), "")
				var job: String = roles[i] if i < roles.size() else "none"
				_assign(wa, job)
				wa.workplace = own[0].id if job == "stallkeeper" else ""
			continue
		var home: SimBuilding = w.buildings.get(h.home_id)
		var hungry := home != null and home.amount("food") < int(cfg["forage_when_food_below"]) \
			and h.cash < float(cfg["forage_when_cash_below"])
		var winter := w.clock.current_season() == "winter"
		# Pusta spiżarnia, a pieniądze są: ktoś idzie w dzień na zakupy (tragarz domu).
		var shop_run := home != null and home.amount("food") < h.target_food / 2 and not hungry
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
			if shop_run:
				w.contracts.quit(p, "")
				_assign(a, "carrier")
				shop_run = false
				continue
			if not w.contracts.of_worker(p.id).is_empty():
				continue
			var o := w.contracts.best_offer_for(p)
			if not o.is_empty():
				w.contracts.hire(o, p)
				w.jobs.replan(a)
			else:
				_assign(a, "none" if winter else "forager")


# Granice cen rodów AI (M3): zwykły dom sprzedaje taniej, niż kupuje, a w głodzie
# zapłaci więcej za jedzenie; ród ze straganem, który skupuje (kupiec), kupuje tanio
# i sprzedaje drogo — z tej różnicy żyje.
func set_prices() -> void:
	var tc: Dictionary = w.balance["trade"]
	var cfg: Dictionary = w.balance["ai"]
	for h: SimHousehold in w.households.values():
		if h == w.household or h.members.is_empty() or h.home_id == "":
			continue
		var merchant := w.trade.stalls_of(h.id).any(func(x): return not x.temporary and not x.buys.is_empty())
		var home: SimBuilding = w.buildings.get(h.home_id)
		var hungry := home != null and home.amount("food") < int(cfg["forage_when_food_below"])
		for g in tc["ref"]:
			var r := w.trade.ref(g)
			if merchant:
				w.trade.set_limit(h, g, "sell_min", r * float(tc["stall_sell_min"]))
				w.trade.set_limit(h, g, "buy_max", r * float(tc["stall_buy_max"]))
			else:
				w.trade.set_limit(h, g, "sell_min", r * float(tc["ai_sell_min"]))
				w.trade.set_limit(h, g, "buy_max", r * float(tc["ai_buy_max_hungry" if hungry and g == "food" else "ai_buy_max"]))


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
