## tools/probe_economy.gd — sonda gospodarki świata (E8): przewija N dób bez gracza
## i co `every` dób drukuje stan; na koniec kryteria „żyje” z docs/design/world-economy.md,
## najbogatszych i wybór z kroniki.
## Uruchomienie:  godot --headless -s res://tools/probe_economy.gd -- [dni] [seed] [co_ile] [prof]
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 360
	var data := DataLoader.load_json("res://data/economy.json")
	var seed := int(args[1]) if args.size() > 1 else int(data["world"]["seed"])
	var every := int(args[2]) if args.size() > 2 else 30
	var prof := args.size() > 3 and args[3] == "prof"
	var t0 := Time.get_ticks_msec()
	var w := EconWorld.new(seed, data)
	print("start: %d miast, %d dróg, %d firm, %d aktorów, %d ciężarówek, ludność %.0f, pieniądze %.0f (%.1f s)" % [w.cities.size(), w.routes.size(), w.businesses.size(), w.living_actors().size(), w.trucks.size(), w.total_population(), w.money_total(), (Time.get_ticks_msec() - t0) / 1000.0])
	var money0 := w.money_total()
	var pop0 := w.total_population()
	var timing := {}
	var price_hist := {}  # towar -> [min, max] średniej ceny / bazowej
	for d in days:
		if prof:
			_step_profiled(w, timing)
		else:
			w.step_day()
		for g: String in w.goods.keys():
			var idx := _price_index(w, g)
			if not price_hist.has(g):
				price_hist[g] = [idx, idx]
			price_hist[g][0] = minf(price_hist[g][0], idx)
			price_hist[g][1] = maxf(price_hist[g][1], idx)
		if w.day % every == 0:
			_print_state(w)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("\n=== po %d dobach (%.1f s, %.0f ms/dobę) ===" % [days, secs, secs * 1000.0 / maxf(days, 1)])
	if prof:
		for k: String in timing.keys():
			print("  %-14s %6.1f ms/dobę" % [k, float(timing[k]) / days])
	print("statystyki: %s" % str(w.stats))
	print("ceny (średnia/bazowa, min..max w przebiegu, teraz):")
	for g: String in w.goods.keys():
		print("  %-11s %.2f..%.2f  teraz %.2f" % [g, price_hist[g][0], price_hist[g][1], _price_index(w, g)])
	_print_cities(w)
	_print_richest(w)
	var crit := {
		"pieniądze stałe": absf(w.money_total() - money0) < money0 * 1e-6,
		"ludność 70–150%": w.total_population() > pop0 * 0.7 and w.total_population() < pop0 * 1.5,
		"firmy powstają": int(w.stats["founded"]) > 5,
		"firmy padają": int(w.stats["closed"]) > 0,
		"ciężarówki jeżdżą": w.trucks.size() > 10 and int(w.stats["trips"]) > days,
		"są kryzysy": w.news.entries.any(func(e: Dictionary) -> bool: return e["kind"] in ["spike", "crisis"]),
	}
	print("\nkryteria „żyje”:")
	for k: String in crit.keys():
		print("  [%s] %s" % ["x" if crit[k] else " ", k])
	print("\nkronika (ostatnie 40 ważnych):")
	var imp: Array = w.news.entries.filter(func(e: Dictionary) -> bool: return int(e["severity"]) >= 1)
	for e: Dictionary in imp.slice(maxi(0, imp.size() - 40)):
		print("  d%4d  %s" % [int(e["day"]), str(e["text"])])
	quit(0)


func _price_index(w: EconWorld, g: String) -> float:
	var s := 0.0
	for c: EconCity in w.cities:
		s += c.market(g).price / c.market(g).base
	return s / w.cities.size()


func _step_profiled(w: EconWorld, timing: Dictionary) -> void:
	for p: Array in w.phases():
		var t := Time.get_ticks_usec()
		(p[1] as Callable).call()
		timing[p[0]] = float(timing.get(p[0], 0.0)) + (Time.get_ticks_usec() - t) / 1000.0
	w.day += 1


func _print_state(w: EconWorld) -> void:
	var active := 0
	var building := 0
	for b: EconBusiness in w.businesses.values():
		if b.status == "building":
			building += 1
		elif b.status != "closed":
			active += 1
	var unemp := 0.0
	var sat := 0.0
	for c: EconCity in w.cities:
		unemp += c.unemployment() * c.population
		sat += c.satisfaction * c.population
	var pop := w.total_population()
	var moving := w.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving).size()
	var hh := 0.0
	for c: EconCity in w.cities:
		hh += c.cash
	var ac := 0.0
	for a: EconActor in w.actors.values():
		ac += a.cash
	var money := w.money_total()
	var st := w.state_cash()
	print("      pieniądze: ludność %.0f%%  aktorzy %.0f%%  firmy %.0f%%  państwo %.0f%%" % [hh / money * 100.0, ac / money * 100.0, (money - hh - ac - st) / money * 100.0, st / money * 100.0])
	print("d%4d  ludność %7.0f  bezrob %4.1f%%  potrzeby %4.1f%%  firmy %4d (+%d bud.)  aktorzy %3d  ciężarówki %3d (w drodze %3d)  kurs %.0f  chleb %.2f paliwo %.2f stal %.2f" % [
		w.day, pop, unemp / pop * 100.0, sat / pop * 100.0, active, building, w.living_actors().size(),
		w.trucks.size(), moving, w.truck_profit_ema, _price_index(w, "bread"), _price_index(w, "fuel"), _price_index(w, "steel")])


func _print_cities(w: EconWorld) -> void:
	print("\nmiasta:")
	for c: EconCity in w.cities:
		var n := w.businesses.values().filter(func(b: EconBusiness) -> bool: return b.city_id == c.id and b.status != "closed").size()
		print("  %-15s ludność %6.0f  bezrob %4.1f%%  potrzeby %4.0f%%  płaca %5.1f  kasa/os. %6.0f  firm %3d  złoża %s" % [c.name, c.population, c.unemployment() * 100.0, c.satisfaction * 100.0, c.wage, c.cash / maxf(c.population, 1.0), n, str(c.resources.keys())])


func _print_richest(w: EconWorld) -> void:
	var list: Array = w.living_actors()
	list.sort_custom(func(a: EconActor, b: EconActor) -> bool: return w.actor_wealth(a) > w.actor_wealth(b))
	print("\nnajbogatsi:")
	for a: EconActor in list.slice(0, 8):
		var kinds := {}
		for bid: int in a.businesses:
			var b: EconBusiness = w.business(bid)
			if b != null:
				kinds[w.recipe(b.type)["name"]] = int(kinds.get(w.recipe(b.type)["name"], 0)) + 1
		print("  %-24s %8.0f tys. zł  firm %2d  %s" % [a.full_name(), w.actor_wealth(a) / 1000.0, a.businesses.size(), str(kinds)])
