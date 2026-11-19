# Podatek majątkowy: codziennie część gotówki aktorów ponad próg wolny od podatku.
extends EconPolicy


func collect(w: EconWorld, st: EconState) -> void:
	var rate := float(params["rate"])
	var free := float(params["free"])
	for a: EconActor in w.actors.values():
		if a.alive and a.cash > free and st.has_city(a.city_id):
			var t := (a.cash - free) * rate
			a.cash -= t
			st.collect(t)
