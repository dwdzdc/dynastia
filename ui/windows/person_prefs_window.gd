# Preferencje osoby: ulubione i znienawidzone zajęcia, z czego się wzięły.
extends "res://ui/windows/person_window.gd"


func build() -> void:
	var p := person
	set_title("Preferencje: " + p.name)
	var prefs: Array = world.bonds.preferences(p.id)
	if prefs.is_empty():
		text("Nie ma jeszcze ulubionych ani znienawidzonych zajęć.", UiKit.SMALL + 2, UiKit.DIM)
		return
	for e in prefs:
		var v: float = e["value"]
		var word := "uwielbia" if v >= hud.WARM else ("lubi" if v >= hud.MILD else ("nie znosi" if v <= -hud.WARM else ("nie lubi" if v <= -hud.MILD else "obojętne mu")))
		var label := String(world.memories["act_labels"].get(e["act"], e["act"]))
		var txt := "%s: %s\n   skąd: %s" % [word, label, "; ".join(e["from"])]
		if hud.debug:
			txt += "  [%.1f]" % v
		text(txt, UiKit.SMALL + 1, hud.feel_color(v))
