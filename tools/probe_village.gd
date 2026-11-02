## tools/probe_village.gd — sonda wsi (Q2): przewija N dób i co kilka dób drukuje stan
## wszystkich gospodarstw: pieniądze (skrzynia + sakwy), dług, dom, spiżarnię, ludzi.
## Na koniec: czy pieniądze krążą, czy rody AI przeżywają, ile było kradzieży i ślubów.
## Uruchomienie:  godot --headless -s res://tools/probe_village.gd -- [dni] [seed]
extends SceneTree

const EVERY_DAYS := 5   # co ile dób wypisać stan


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 60
	var balance := DataLoader.load_json("res://data/balance.json")
	var seed := int(args[1]) if args.size() > 1 else int(balance["world_seed"])
	var w := SimWorld.new(seed, balance, DataLoader.load_json("res://data/map.json"), DataLoader.load_json("res://data/people.json"), DataLoader.load_json("res://data/memories.json"), DataLoader.load_json("res://data/recipes.json"), DataLoader.load_json("res://data/traders.json"))
	var start_people := w.family.all_living().size()
	var idle_samples := 0
	var samples := 0
	for d in days:
		var end := w.clock.now() + 1.0
		while w.clock.now() < end and not w.family.game_over:
			w.step_sim(2.0)
			while w.events.blocking():
				var p: Dictionary = w.events.prompts[0]
				w.resolve_prompt(int(p["id"]), p["options"][0]["value"])
			if w.jobs.block_at(w.clock.time_of_day()) == "work":
				for a in w.agents:
					var pp := w.person_of(a)
					if a.status != "active" or pp == null or a.is_child or not a.can_work():
						continue
					samples += 1
					if a.inside == a.home_id and a.activity in ["rest", "idle", "wait"]:
						idle_samples += 1
		if (d + 1) % EVERY_DAYS == 0 or d == days - 1:
			_print_state(w, d + 1)
		if w.family.game_over:
			print("KONIEC GRY w dobie %d" % (d + 1))
			break
	print("\nPodsumowanie po %d dobach:" % days)
	print("  ludzi żywych: %d (na starcie %d)" % [w.family.all_living().size(), start_people])
	print("  pieniądze w okolicy: %.0f zł" % _money(w))
	print("  kradzieże: %d, aresztowania: %d" % [int(w.stats.get("thefts", 0)), int(w.stats.get("arrests", 0))])
	print("  śluby: %d, narodziny: %d, śmierci: %d" % [w.chronicle.of_kind("wedding").size(), w.chronicle.of_kind("birth").size(), w.chronicle.of_kind("death").size()])
	print("  dorośli zamknięci w domu w godzinach pracy: %.1f%%" % (100.0 * float(idle_samples) / maxf(1.0, float(samples))))
	quit()


func _money(w: SimWorld) -> float:
	var s := 0.0
	for h in w.households.values():
		s += h.cash
	for p in w.family.persons.values():
		if p.alive():
			s += p.purse
	return s


func _print_state(w: SimWorld, day: int) -> void:
	print("--- doba %d (%s) · pieniądze w okolicy %.0f zł" % [day, w.clock.current_season(), _money(w)])
	for h in w.households.values():
		if h.members.is_empty():
			continue
		var purses := 0.0
		var alive := 0
		var name := ""
		for pid in h.members:
			var p: SimPerson = w.family.persons[pid]
			purses += p.purse
			if p.alive():
				alive += 1
			name = p.surname
		var home: SimBuilding = w.buildings.get(h.home_id)
		print("  %-10s dom=%-8s skrzynia=%5.0f sakwy=%4.0f dług=%4.0f jedzenie=%3d ludzi=%d" % [name, h.home_id if h.home_id != "" else "BRAK",
			h.cash, purses, h.debt, home.amount("food") if home != null else -1, alive])
