# Magazyn budynku: co leży w środku względem pojemności i jak działa produkcja.
extends "res://ui/windows/building_window.gd"


func build() -> void:
	set_title("Magazyn: " + b.name)
	dyn(func():
		var lines: Array = []
		for g in b.capacity:
			lines.append("%s: %d / %d" % [world.good_label(g), b.amount(g), int(b.capacity[g])])
		return "\n".join(lines) if not lines.is_empty() else "Pusto.", UiKit.FONT)
	match b.type:
		"sawmill":
			dyn(func(): return "Drwale: %d · tracze: %d · drzewa do ścięcia: %d" % [hud.count_job("woodcutter"), hud.count_job("sawyer"),
				world.trees.filter(func(t): return t.wood > 0).size()], UiKit.SMALL + 1, UiKit.DIM)
			text("1 kłoda = 2 deski. Kłody to też opał do chaty.", UiKit.SMALL, UiKit.DIM)
		"workshop":
			dyn(func():
				if b.chair_qualities.is_empty():
					return ""
				var avg := 0.0
				for q in b.chair_qualities:
					avg += float(q)
				return "Jakość krzeseł: " + SimJobs.quality_label(avg / b.chair_qualities.size()), UiKit.SMALL + 1)
			text("2 deski = 1 krzesło. Lepszy stolarz = droższe krzesła i reputacja.", UiKit.SMALL, UiKit.DIM)
		"manor":
			dyn(func(): return "Pola dworu: %s" % ", ".join(world.fields.filter(func(f): return f.owner_building == b.id).map(
				func(f): return "%d/%d zagonów zasianych" % [f.count("sown") + f.count("ripe"), f.cells.size()])), UiKit.SMALL + 1, UiKit.DIM)
