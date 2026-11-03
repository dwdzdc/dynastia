# Statystyki (I8): jak okolica zmienia się w czasie — ludność, domy, pieniądze, ceny.
# Wykresy z dziennego zapisu SimWorld.history.
extends TopicWindow


const CHART_H := 90.0
const LINE := Color(1.0, 0.82, 0.4)
const LINE2 := Color(0.55, 0.75, 1.0)

var _good := "food"
var _seen := -1


func build() -> void:
	_seen = -1
	_chart("Ludzie w okolicy", func(e): return float(e["people"]), Callable())
	_chart("Domy (żółte) i puste domy (niebieskie)", func(e): return float(e["houses"]), func(e): return float(e["empty_houses"]))
	_chart("Pieniądze w okolicy (zł)", func(e): return float(e["cash"]), Callable())
	var r := UiKit.row(4)
	for g in world.balance["trade"]["ref"]:
		var gd: String = g
		var b := UiKit.button(world.good_label(gd), func():
			_good = gd
			rebuild(), UiKit.SMALL - 1)
		b.toggle_mode = true
		b.button_pressed = gd == _good
		r.add_child(b)
	add(r)
	_chart("Cena na straganach: %s (zł)" % world.good_label(_good), func(e): return float(e["prices"].get(_good, 0.0)), Callable())
	dyn(func():
		var parts: Array = []
		for t: SimTown in world.traders.towns.values():
			parts.append("%s: %d ludzi, %d zł" % [t.name, t.population, int(t.cash)])
		return "Miasta — " + "; ".join(parts), UiKit.SMALL, UiKit.DIM)


# Wykres liniowy: wartość dzienna (i opcjonalnie druga seria) od początku zapisu.
func _chart(title: String, fn: Callable, fn2: Callable) -> void:
	var head := UiKit.label(title, UiKit.SMALL, UiKit.DIM)
	add(head)
	var c := Control.new()
	c.custom_minimum_size.y = CHART_H
	add(c)
	c.draw.connect(func(): _draw_chart(c, head, title, fn, fn2))
	watch(func():
		if world.history.size() != _seen:
			c.queue_redraw())
	watch(func(): _seen = world.history.size())


func _draw_chart(c: Control, head: Label, title: String, fn: Callable, fn2: Callable) -> void:
	var h: Array = world.history
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.25))
	if h.size() < 2:
		c.draw_string(ThemeDB.fallback_font, Vector2(8, sz.y * 0.55), "Za mało dni — wykres pojawi się po dobie.", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.SMALL - 1, UiKit.DIM)
		return
	var hi := 0.0
	for e in h:
		hi = maxf(hi, fn.call(e))
		if fn2.is_valid():
			hi = maxf(hi, fn2.call(e))
	hi = maxf(hi, 1.0)
	for pair in [[fn, LINE], [fn2, LINE2]]:
		var f: Callable = pair[0]
		if not f.is_valid():
			continue
		var pts := PackedVector2Array()
		for i in h.size():
			pts.append(Vector2(sz.x * i / float(h.size() - 1), sz.y - 4.0 - (sz.y - 8.0) * f.call(h[i]) / hi))
		c.draw_polyline(pts, pair[1], 2.0)
	var last: float = fn.call(h[-1])
	head.text = "%s — teraz %s, najwyżej %s (dni: %d)" % [title, _num(last), _num(hi), h.size()]


static func _num(v: float) -> String:
	return str(int(round(v))) if absf(v) >= 10.0 else "%.1f" % v
