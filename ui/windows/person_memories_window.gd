# Wspomnienia osoby (więzi): najsilniejsze, słowami zamiast liczb (E1).
extends "res://ui/windows/person_window.gd"


const SHORT := 8          # ile wspomnień widać przed „pokaż więcej”
const LONG := 30

var _more := false


func build() -> void:
	var p := person
	set_title("Wspomnienia: " + p.name)
	var bonds := world.bonds
	var all: Array = bonds.strongest(p.id, bonds.targets_of(p.id), LONG if _more else SHORT)
	if all.is_empty():
		text("Nic szczególnego jeszcze nie przeżył%s." % ("" if p.sex == "m" else "a"), UiKit.SMALL + 2, UiKit.DIM)
		return
	for e in all:
		var m: Dictionary = e["m"]
		var v: float = e["v"]
		var who := ""
		var t: String = e["t"]
		if t.begins_with("p:"):
			var o: SimPerson = world.family.persons.get(int(t.substr(2)))
			who = (o.name + ": ") if o != null and not int(t.substr(2)) in m["with"] else ""
		var txt := "%s%s — wspomina %s (dzień %d)" % [who, bonds.describe(m, t), hud.feel(v), int(m["day"]) + 1]
		if hud.debug:
			txt += "  [%.1f]" % v
		text(txt, UiKit.SMALL + 1, hud.feel_color(v))
	add(UiKit.button("Pokaż mniej" if _more else "Pokaż więcej", func():
		_more = not _more
		rebuild(), UiKit.SMALL))
