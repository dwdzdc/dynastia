# EconConsumption — ludność miast kupuje koszyk według priorytetów (jedzenie,
# paliwo, usługi, meble, AGD); im wyższy dochód na głowę, tym więcej dóbr
# wyższych. Aktorzy wydają część majątku na życie w swoim mieście.
class_name EconConsumption
extends RefCounted


const ACTOR_BASKET := {"services": 0.5, "meat": 0.1, "furniture": 0.2, "appliances": 0.2}
const INCOME_EMA := 0.1


static func step(w: EconWorld) -> void:
	var hp: Dictionary = w.data["households"]
	var needs: Array = w.data["needs"]
	for c: EconCity in w.cities:
		c.income_ema = lerpf(c.income_ema, c.income_today, INCOME_EMA)
		if c.population <= 0.0:
			continue
		var budget := minf(c.cash, c.income_ema * float(hp["spend_of_income"]) + c.cash * float(hp["spend_of_savings"]))
		var lux := (c.income_ema / c.population) / float(hp["reference_income"])
		var met_w := 0.0
		var all_w := 0.0
		for n: Dictionary in needs:
			var g: String = n["good"]
			var factor := clampf(pow(maxf(lux, 0.01), float(n["luxury"])), 0.3, 3.0)
			var desired := float(n["per_capita"]) * c.population * factor
			var got := 0.0
			if budget > 0.0:
				var res: Array = c.market(g).buy(desired, budget, w.pay_seller)
				got = float(res[0])
				budget -= float(res[1])
				c.cash -= float(res[1])
			else:
				c.market(g).buy(desired, 0.0, w.pay_seller)
			var pr := int(n["priority"])
			if pr <= 3:
				var weight := 1.0 / float(pr)
				var base_need := float(n["per_capita"]) * c.population
				all_w += weight
				met_w += weight * clampf(got / maxf(base_need, 1e-6), 0.0, 1.0)
		if all_w > 0.0:
			c.satisfaction = lerpf(c.satisfaction, met_w / all_w, float(hp["satisfaction_ema"]))
	var share := float(w.data["actors"]["spend_of_wealth"])
	var of_income := float(w.data["actors"]["spend_of_income"])
	for a: EconActor in w.actors.values():
		a.income_ema = lerpf(a.income_ema, a.income_today, INCOME_EMA)
		a.income_today = 0.0
		if not a.alive or a.cash <= 0.0:
			continue
		# Bogaci żyją z dochodu (dywidend) i trochę z majątku.
		var spend := minf(a.cash, a.cash * share + a.income_ema * of_income)
		var c: EconCity = w.cities[a.city_id]
		for g: String in ACTOR_BASKET.keys():
			var m := c.market(g)
			var part := spend * float(ACTOR_BASKET[g])
			var res: Array = m.buy(part / maxf(m.price, 0.01), part, w.pay_seller)
			a.cash -= float(res[1])
