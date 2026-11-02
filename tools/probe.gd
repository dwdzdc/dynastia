## tools/probe.gd — headless sonda balansu: przewija N dni i drukuje dzienne statystyki.
## Uruchomienie:  godot --headless -s res://tools/probe.gd -- [dni] [seed]
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 20
	var balance := DataLoader.load_json("res://data/balance.json")
	var seed := int(args[1]) if args.size() > 1 else int(balance["world_seed"])
	var w := SimWorld.new(seed, balance, DataLoader.load_json("res://data/map.json"), DataLoader.load_json("res://data/people.json"), DataLoader.load_json("res://data/memories.json"), DataLoader.load_json("res://data/recipes.json"), DataLoader.load_json("res://data/traders.json"))
	var strategy := String(args[2]) if args.size() > 2 else "default"
	var plans := {
		"craft": { "Zofia": "woodcutter", "Agnieszka": "carpenter" },
		"wood2": { "Zofia": "woodcutter" },
		"labor": { "Jan": "laborer", "Maria": "laborer", "Piotr": "laborer", "Zofia": "laborer" },
		"none": { "Jan": "none", "Maria": "none", "Piotr": "none" },
		"thief": { "Zofia": "thief" },
		"forage": { "Jan": "forager", "Maria": "forager", "Piotr": "forager", "Zofia": "forager" },
	}
	for a in w.agents:
		var nm := w.person_of(a).name
		if plans.get(strategy, {}).has(nm):
			a.job = plans[strategy][nm]
	var acts := {}
	var reasons := {}
	var last_log := 0
	for d in days:
		var end := w.clock.now() + 1.0
		while w.clock.now() < end and not w.family.game_over:
			w.step_sim(0.5)
			while w.events.blocking():
				var p: Dictionary = w.events.prompts[0]
				print("    [PROMPT] %s: %s" % [p["title"], String(p["text"]).replace("\n", " / ")])
				w.resolve_prompt(int(p["id"]), p["options"][0]["value"])
			for a in w.agents:
				if a.status == "active":
					var k := "%d:%s" % [a.id, a.activity]
					acts[k] = int(acts.get(k, 0)) + 1
					if a.activity in ["wait", "rest", "idle"] or a.alert:
						reasons[("! " if a.alert else "") + a.idle_reason] = int(reasons.get(("! " if a.alert else "") + a.idle_reason, 0)) + 1
		var hh := w.household
		var mill := w.building("sawmill")
		var shop := w.building("workshop")
		print("D%2d %s cash=%4d debt=%3d net=%+4d food=%2d fire=%2d | mill log=%2d plank=%2d | shop plank=%d chair=%d | sold p=%d c=%d alive=%d" % [
			w.clock.day_index(), w.clock.current_season().substr(0, 3), int(hh.cash), int(hh.debt), int(hh.last_day_net),
			w.home().amount("food"), w.home().amount("log"), mill.amount("log"), mill.amount("plank"),
			shop.amount("plank"), shop.amount("chair"), int(w.stats.get("sold_plank", 0)), int(w.stats.get("sold_chair", 0)),
			w.family.living().size()])
		for i in range(last_log, w.events.entries.size()):
			print("    - " + String(w.events.entries[i]["text"]))
		last_log = w.events.entries.size()
		if w.family.game_over:
			break
	print("\nAktywności (próbki co 0.5s sim):")
	for a in w.agents:
		var p := w.person_of(a)
		var line := "  %s (%s): " % [p.name, a.job]
		for k in acts:
			if String(k).begins_with("%d:" % a.id):
				line += "%s=%d " % [String(k).split(":")[1], acts[k]]
		print(line)
	print("\nAlerty (powód: próbki):")
	for r in reasons:
		print("  %s: %d" % [r, reasons[r]])
	quit()
