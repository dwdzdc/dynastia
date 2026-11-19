# KurierPage — strona „Kuriera Świata” (EconGazette) jako nakładka z nawigacją
# po numerach. Wspólna dla mapy RTS; zamyka się Esc albo przyciskiem.
class_name KurierPage
extends ColorRect


signal closed

const PAPER_BG := Color(0.95, 0.92, 0.84)
const PAPER_INK := Color(0.12, 0.1, 0.08)
const PAPER_DIM := Color(0.35, 0.3, 0.25)
const PAPER_RULE := Color(0.2, 0.17, 0.13)
const PAPER_W := 980
const FONT := 16
const SMALL := 13

var w: EconWorld
var day := 0


func open(world: EconWorld) -> void:
	w = world
	day = maxi((w.day / EconGazette.MONTH_DAYS) * EconGazette.MONTH_DAYS, EconGazette.MONTH_DAYS)
	color = Color(0, 0, 0, 0.55)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_show()


func _label(text: String, size: int, col := PAPER_INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = PAPER_RULE
	r.custom_minimum_size.y = 2
	return r


func _show() -> void:
	for ch in get_children():
		ch.queue_free()
	var issue := EconGazette.issue(w, day)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER_BG
	st.set_content_margin_all(26)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 12
	page.add_theme_stylebox_override("panel", st)
	page.custom_minimum_size.x = PAPER_W
	center.add_child(page)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	page.add_child(v)
	var mast := _label("KURIER ŚWIATA", 40, PAPER_INK, false)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(mast)
	var meta := _label("nr %d · %s · cena 2 zł" % [int(issue["number"]), str(issue["date"])], SMALL, PAPER_DIM, false)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(meta)
	v.add_child(_rule())
	v.add_child(_label(str(issue["headline"]), 30))
	v.add_child(_label(str(issue["lead"]), FONT, PAPER_DIM))
	v.add_child(_rule())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for col: Dictionary in issue["columns"]:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = PAPER_W / 2 - 50
		box.add_child(_label(str(col["title"]).to_upper(), SMALL, PAPER_RULE, false))
		for line: String in col["lines"]:
			box.add_child(_label("• " + line, SMALL))
		grid.add_child(box)
	v.add_child(_rule())
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	v.add_child(nav)
	var prev := Button.new()
	prev.text = "‹ poprzedni numer"
	prev.disabled = day <= EconGazette.MONTH_DAYS
	prev.pressed.connect(func() -> void:
		day -= EconGazette.MONTH_DAYS
		_show())
	nav.add_child(prev)
	var close := Button.new()
	close.text = "zamknij (Esc)"
	close.pressed.connect(func() -> void: closed.emit())
	nav.add_child(close)
	var next := Button.new()
	next.text = "następny numer ›"
	next.disabled = day + EconGazette.MONTH_DAYS > w.day
	next.pressed.connect(func() -> void:
		day += EconGazette.MONTH_DAYS
		_show())
	nav.add_child(next)
