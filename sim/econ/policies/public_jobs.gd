# Budżetówka (nauczyciele, lekarze, policja): pensje wg ludności miast, najwyżej
# ustalona część siły roboczej i tylko z wolnych ludzi. To też miejsca pracy.
extends EconPolicy


func spend(w: EconWorld, st: EconState, budget: float) -> float:
	var pop := st.population(w)
	var spent := 0.0
	for c: EconCity in st.cities_of(w):
		var pay := budget * c.population / maxf(pop, 1.0)
		var max_workers := c.labor_force * float(params["max_share"])
		var workers := minf(pay / maxf(c.wage, 0.01), max_workers)
		workers = minf(workers, c.free_workers() + c.public_workers)
		pay = workers * c.wage
		c.employed += workers - c.public_workers
		c.public_workers = workers
		EconLabor.pay_wages(c, pay)
		spent += pay
	return spent
