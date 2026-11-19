# Zasiłki dla bezrobotnych: budżet dzielony wg liczby bezrobotnych w miastach.
extends EconPolicy


func spend(w: EconWorld, st: EconState, budget: float) -> float:
	var unemployed := 0.0
	for c: EconCity in st.cities_of(w):
		unemployed += c.free_workers()
	if unemployed <= 0.0:
		return 0.0
	var spent := 0.0
	for c: EconCity in st.cities_of(w):
		var ben := budget * c.free_workers() / unemployed
		EconLabor.pay_wages(c, ben)
		spent += ben
	return spent
