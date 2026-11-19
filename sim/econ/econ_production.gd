# EconProduction — doba firm: koniec przestojów, budowy i rozbudowy, zatrudnianie,
# pensje, zakup wejść na lokalnym rynku, produkcja (tylko gdy się opłaca) i
# wystawienie towaru. Jak w Port Royale: gdy cena spada poniżej kosztu, firma zwalnia.
class_name EconProduction
extends RefCounted


static func step(w: EconWorld) -> void:
	# Gdy ludzi ubyło (migracja), a zatrudnionych jest więcej niż siły roboczej,
	# firmy tracą pracowników proporcjonalnie.
	var squeeze: Array[float] = []
	for c: EconCity in w.cities:
		squeeze.append(minf(1.0, c.labor_force / c.employed) if c.employed > c.labor_force and c.employed > 0.0 else 1.0)
	for b: EconBusiness in w.businesses.values():
		if b.status in ["burned", "strike"] and w.day >= b.status_until:
			b.status = "active"
			if b.type != "haulage":
				w.news.add("resume", b.city_id, "%s (%s) znowu pracuje." % [b.name, w.cities[b.city_id].name], 0)
		if not b.project.is_empty():
			EconInvest.progress_project(w, b)
		if b.type == "haulage" or b.status == "closed":
			continue
		var c := w.city_of(b)
		if squeeze[c.id] < 1.0:
			var lost := b.workers * (1.0 - squeeze[c.id])
			b.workers -= lost
			c.employed -= lost
		if b.status != "active":
			if b.workers > 0.0 and b.status == "burned":
				c.employed -= b.workers
				b.workers = 0.0
			continue
		if EconHousing.is_housing(w, b.type):
			EconHousing.upkeep(w, b, c)
			continue
		_produce(w, b, c)


# Pensje ludzi gracza (jednostek) pracujących na miejscu idą do kasy gracza.
static func _pay_extra(w: EconWorld, b: EconBusiness, c: EconCity) -> void:
	if b.extra_workers <= 0.0:
		b.extra_paid = true
		return
	var bill := b.extra_workers * c.wage
	var payee := w.actor(b.extra_payee)
	if payee == null or b.cash < bill:
		b.extra_paid = false
		return
	b.cash -= bill
	b.cost_today += bill
	payee.cash += bill
	payee.income_today += bill
	b.extra_paid = true


static func effective_per_worker(w: EconWorld, type: String, c: EconCity) -> float:
	var r: Dictionary = w.recipe(type)
	var eff := float(r["per_worker"])
	var res: String = r.get("resource", "")
	if res != "":
		eff *= float(c.resources.get(res, 0.0))
		if res == "fertile":
			eff *= c.harvest_mult
	return eff


# Koszt jednostki przy bieżących cenach lokalnych (wejścia + robocizna).
static func unit_cost(w: EconWorld, type: String, c: EconCity, eff: float) -> float:
	var r: Dictionary = w.recipe(type)
	var cost := 0.0
	var ins: Dictionary = r["inputs"]
	for g: String in ins.keys():
		cost += float(ins[g]) * c.market(g).price
	if eff > 0.0:
		cost += c.wage / eff
	else:
		cost = INF
	return cost


static func _produce(w: EconWorld, b: EconBusiness, c: EconCity) -> void:
	var r: Dictionary = w.recipe(b.type)
	var bp: Dictionary = w.data["business"]
	var out: String = r["out"]
	var m_out := c.market(out)
	var cap_workers := float(r["workers"]) * b.level
	var eff := effective_per_worker(w, b.type, c)
	var margin := m_out.price - unit_cost(w, b.type, c, eff)
	# Własny niesprzedany towar: jeśli leży dłużej niż kilka dób produkcji, zwalniamy.
	var own := m_out.stock_of(b.id)
	var glut := own > eff * cap_workers * float(w.data["market"]["target_days"])
	var target := b.workers
	var cap_hired := maxf(0.0, cap_workers - b.extra_workers)  # ludzie gracza zajmują etaty
	if margin > float(bp["min_margin"]) * m_out.price and not glut and eff > 0.0:
		target = cap_hired
	else:
		target = b.workers * (1.0 - float(bp["hire_step"]))
		if target < 1.0:
			target = 0.0
	if target > b.workers:
		var hire := minf(minf(target - b.workers, c.free_workers()), maxf(cap_workers * float(bp["hire_step"]), 1.0))
		b.workers += hire
		c.employed += hire
	elif target < b.workers:
		c.employed -= b.workers - target
		b.workers = target
	if b.workers > cap_hired:
		c.employed -= b.workers - cap_hired
		b.workers = cap_hired
	_pay_extra(w, b, c)
	# Pensje.
	var bill := b.workers * c.wage
	if bill > 0.0:
		if b.cash >= bill:
			b.cash -= bill
			EconLabor.pay_wages(c, bill)
			b.cost_today += bill
			b.broke_days = 0
		else:
			var paid := maxf(b.cash, 0.0)
			var keep := paid / bill
			b.cash -= paid
			EconLabor.pay_wages(c, paid)
			b.cost_today += paid
			var leave := b.workers * (1.0 - keep)
			b.workers -= leave
			c.employed -= leave
			b.broke_days += 1
	var staff := b.workers + (b.extra_workers if b.extra_paid else 0.0)
	if staff <= 0.0:
		b.produced_today = 0.0
		return
	# Wejścia: kupujemy brakujące na dziś plus mały zapas.
	var potential := staff * eff
	var units := potential
	var ins: Dictionary = r["inputs"]
	var buffer := float(bp["input_buffer_days"])
	for g: String in ins.keys():
		var per := float(ins[g])
		var have: float = float(b.inputs.get(g, 0.0))
		var need := units * per * (1.0 + buffer) - have
		if need > 0.0 and b.cash > 0.0:
			var res: Array = c.market(g).buy(need, b.cash, w.pay_seller, b.id)
			b.cash -= float(res[1])
			b.cost_today += float(res[1])
			have += float(res[0])
			b.inputs[g] = have
		if per > 0.0:
			units = minf(units, have / per)
	for g: String in ins.keys():
		b.inputs[g] = maxf(0.0, float(b.inputs.get(g, 0.0)) - units * float(ins[g]))
	b.produced_today = units
	m_out.add(b.id, units)
	# Brak wejść: ludzie stoją, więc część zwalniamy (zostaje tylu, ilu ma co robić).
	if units < potential * 0.6:
		var needed := units / eff * 1.3
		var cut := minf(b.workers - needed, b.workers * float(bp["hire_step"]))
		if cut > 0.0:
			b.workers -= cut
			c.employed -= cut
	# Wyczerpywanie złóż kopalnych.
	var res_name: String = r.get("resource", "")
	if res_name in ["oil", "iron", "limestone"] and cap_workers > 0.0:
		var dep := float(w.data["events"]["depletion_per_day"]) * (b.workers / cap_workers)
		c.resources[res_name] = maxf(0.0, float(c.resources[res_name]) - dep)
