# Ludzie budynku: kto tu pracuje, wakaty (L3, L4), a we własnym — ilu najmujesz i za ile.
extends "res://ui/windows/building_window.gd"


func build() -> void:
	set_title("Ludzie: " + b.name)
	dyn(func():
		var names: Array = hud.workers_at(b).map(func(a): return world.person_of(a).name)
		return "Pracują tu: " + (", ".join(names) if not names.is_empty() else "nikt"), UiKit.SMALL + 1)
	dyn(func():
		var lines: Array = []
		for o: Dictionary in world.contracts.offers:
			if o["place"] == b.id and int(o["slots"]) > 0:
				lines.append("%s: %d zł/dzień · zajęte %d/%d" % [SimJobs.JOB_LABELS.get(o["job"], o["job"]), int(o["wage"]),
					world.contracts.taken(o), int(o["slots"])])
		return ("Wakaty:\n  " + "\n  ".join(lines)) if not lines.is_empty() else "Wakaty: brak", UiKit.SMALL + 1, UiKit.DIM)
	if world.is_foreign(b):
		text("Żeby ktoś z rodu się tu najął: zaznacz go i kliknij PPM na budynek.", UiKit.SMALL, UiKit.DIM)
		return
	for r: Dictionary in world.jobs.recipes.values():
		if String(r["type"]) != b.type:
			continue
		var job := String(r["job"])
		var bid := b.id
		var get_o := func() -> Dictionary: return world.contracts.find_offer(world.household.id, bid, job)
		var default_wage := float(world.balance["jobs"]["laborer_wage_day"])
		add(HSeparator.new())
		section("Najmij obcych: %s" % SimJobs.JOB_LABELS.get(job, job))
		stepper("Ile osób", func(): return int(get_o.call().get("slots", 0)), func(d):
			var o: Dictionary = get_o.call()
			world.post_player_offer(bid, job, int(o.get("slots", 0)) + d, float(o.get("wage", default_wage))))
		stepper("Stawka", func(): return int(get_o.call().get("wage", default_wage)), func(d):
			var o: Dictionary = get_o.call()
			world.post_player_offer(bid, job, int(o.get("slots", 0)), float(o.get("wage", default_wage)) + d),
			func(v): return "%d zł" % int(v))
