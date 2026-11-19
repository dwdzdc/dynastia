# EconLabor — rynek pracy miast: siła robocza, zatrudnieni (firmy + kierowcy),
# płaca rośnie przy niskim bezrobociu i spada przy wysokim.
class_name EconLabor
extends RefCounted


static func step(w: EconWorld) -> void:
	var p: Dictionary = w.data["labor"]
	var base := float(p["base_wage"])
	for c: EconCity in w.cities:
		c.labor_force = c.population * float(p["participation"])
		c.employed = c.public_workers
		c.income_today = 0.0
	for b: EconBusiness in w.businesses.values():
		if b.type == "haulage":
			if b.is_open():
				w.cities[b.city_id].employed += b.trucks.size()
		else:
			w.cities[b.city_id].employed += b.workers
	for c: EconCity in w.cities:
		# Płaca dąży do poziomu wynikającego z bezrobocia (stały punkt, nie całka).
		var u := c.unemployment()
		var goal := base * (1.0 + float(p["wage_slope"]) * (float(p["natural_unemployment"]) - u))
		# Drogi czynsz: ludzie chcą więcej zarabiać (duże miasta są droższe dla firm).
		goal *= 1.0 + float(w.data["housing"]["rent_wage_push"]) * (c.rent_mult - 1.0)
		goal = clampf(goal, base * float(p["min_wage_mult"]), base * float(p["max_wage_mult"]))
		c.wage = lerpf(c.wage, goal, float(p["wage_speed"]))


# Przelew pensji do kasy gospodarstw miasta.
static func pay_wages(c: EconCity, amount: float) -> void:
	c.cash += amount
	c.income_today += amount
