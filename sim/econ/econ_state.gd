# EconState — skarb państwa: zamyka obieg pieniędzy we współczesnym świecie.
# Pobiera podatek od dywidend (EconInvest._to_owner) i od majątku aktorów, a wydaje
# na pensje budżetówki (nauczyciele, lekarze, policja — to też miejsca pracy) i
# zasiłki dla bezrobotnych, a resztę na emerytury. Nic nie bierze się z powietrza: państwo wydaje tylko
# to, co zebrało (kasa w EconWorld.state_cash).
class_name EconState
extends RefCounted


static func step(w: EconWorld) -> void:
	var sp: Dictionary = w.data["state"]
	# Podatek od majątku (gotówki) aktorów.
	var wealth_tax := float(sp["wealth_tax"])
	for a: EconActor in w.actors.values():
		if a.alive and a.cash > 0.0:
			var t := a.cash * wealth_tax
			a.cash -= t
			collect(w, t)
	w.state_income_ema = lerpf(w.state_income_ema, w.state_income_today, 0.05)
	w.state_income_today = 0.0
	var budget := minf(w.state_cash, w.state_income_ema + w.state_cash * float(sp["spend_of_savings"]))
	if budget <= 0.0:
		for c: EconCity in w.cities:
			c.public_workers = 0.0
		return
	var pop := w.total_population()
	var unemployed := 0.0
	for c: EconCity in w.cities:
		unemployed += c.free_workers()
	var public := budget * float(sp["public_share"])
	var benefits := budget - public
	var spent := 0.0
	var unused := 0.0  # niewydane na pensje (brak ludzi / limit) idzie na emerytury
	for c: EconCity in w.cities:
		# Budżetówka: pensje wg ludności, najwyżej ustalona część siły roboczej.
		var pay := public * c.population / maxf(pop, 1.0)
		var max_workers := c.labor_force * float(sp["max_public_workers"])
		var workers := minf(pay / maxf(c.wage, 0.01), max_workers)
		# Nie zatrudnimy więcej, niż jest wolnych ludzi (plus dotychczasowi).
		workers = minf(workers, c.free_workers() + c.public_workers)
		unused += pay - workers * c.wage
		pay = workers * c.wage
		c.employed += workers - c.public_workers
		c.public_workers = workers
		var ben := 0.0
		if unemployed > 0.0:
			ben = benefits * c.free_workers() / unemployed
		EconLabor.pay_wages(c, pay + ben)
		spent += pay + ben
	# Emerytury i inne świadczenia: reszta budżetu wg ludności.
	for c: EconCity in w.cities:
		var pension := unused * c.population / maxf(pop, 1.0)
		EconLabor.pay_wages(c, pension)
		spent += pension
	w.state_cash -= spent


static func collect(w: EconWorld, amount: float) -> void:
	w.state_cash += amount
	w.state_income_today += amount
