# Emerytury i inne świadczenia: budżet dzielony wg ludności miast.
extends EconPolicy


func spend(w: EconWorld, st: EconState, budget: float) -> float:
	var pop := st.population(w)
	var spent := 0.0
	for c: EconCity in st.cities_of(w):
		var p := budget * c.population / maxf(pop, 1.0)
		EconLabor.pay_wages(c, p)
		spent += p
	return spent
