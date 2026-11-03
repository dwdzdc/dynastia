# TopicWindow — rama okna jednej sprawy (S40): tytuł, ✕, przewijana treść odświeżana
# co tick. Hud trzyma naraz jedno takie okno. Podklasy w ui/windows/ nadpisują build().
class_name TopicWindow
extends PanelContainer


const WIDTH := 440.0          # szerokość treści okna
const MAX_H_FRAC := 0.72      # najwyżej taka część wysokości ekranu, dalej przewijanie
const PRICE_STEP := 0.1       # krok ceny w polach [−] cena [+] (zł)

var hud: Control
var world: SimWorld
var main: Node
var key := ""                 # tożsamość okna: ten sam klucz drugi raz = zamknij
var anchor := "left"          # left: przy pasku po lewej; card: obok karty zaznaczenia
var width := WIDTH
var body: VBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _updaters: Array = []


func init_window(p_hud: Control, p_key: String, title: String) -> void:
	hud = p_hud
	world = hud.world
	main = hud.main
	key = p_key
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := UiKit.row()
	v.add_child(head)
	_title = UiKit.label(title, UiKit.HEAD, UiKit.TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := UiKit.button(" ✕ ", close_pressed, UiKit.SMALL)
	x.tooltip_text = "Zamknij (Esc)"
	head.add_child(x)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.custom_minimum_size.x = width
	_scroll.add_child(body)
	body.minimum_size_changed.connect(_fit)
	build()


func close_pressed() -> void:
	hud.close_window()


func set_title(t: String) -> void:
	_title.text = t


# Treść okna; podklasy dokładają kontrolki do body i odświeżacze przez dyn()/watch().
func build() -> void:
	pass


func rebuild() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_updaters.clear()
	build()


func refresh() -> void:
	for u in _updaters:
		u.call()
	_fit()


# Okno rośnie z treścią do MAX_H_FRAC ekranu, dalej przewija.
func _fit() -> void:
	if not is_inside_tree():
		return
	var max_h := get_viewport_rect().size.y * MAX_H_FRAC
	_scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, max_h)


func add(c: Control) -> Control:
	body.add_child(c)
	return c


func watch(fn: Callable) -> void:
	_updaters.append(fn)


func text(t: String, size := 0, color := UiKit.TEXT) -> Label:
	return add(UiKit.wrap(t, size, color)) as Label


func section(t: String) -> void:
	add(UiKit.label(t, UiKit.FONT, UiKit.TITLE))


# Etykieta, której treść liczy się co tick.
func dyn(text_fn: Callable, size := 0, color := UiKit.TEXT) -> Label:
	var l := text("", size, color)
	watch(func():
		l.text = text_fn.call()
		l.visible = l.text != "")
	return l


func bar(title: String, value_fn: Callable, color: Color, parent: Control = null) -> void:
	var h := UiKit.row()
	var l := UiKit.label(title, UiKit.SMALL, UiKit.DIM)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.show_percentage = false
	pb.custom_minimum_size.y = 14
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := UiKit.box(color, Color(0, 0, 0, 0), 3, 0)
	pb.add_theme_stylebox_override("fill", fill)
	h.add_child(pb)
	(parent if parent != null else body).add_child(h)
	watch(func():
		var v: float = value_fn.call()
		pb.value = v
		fill.bg_color = color if v > 35.0 else UiKit.BAD)


# Wiersz „tytuł  [−] wartość [+]”; fmt_fn zamienia wartość na tekst.
func stepper(title: String, get_fn: Callable, change_fn: Callable, fmt_fn: Callable = Callable(), parent: Control = null) -> void:
	var h := UiKit.row()
	var l := UiKit.label(title, UiKit.SMALL + 1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UiKit.button(" − ", func(): change_fn.call(-1), UiKit.SMALL + 1))
	var v := UiKit.label("", UiKit.SMALL + 2)
	v.custom_minimum_size.x = 72
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(v)
	h.add_child(UiKit.button(" + ", func(): change_fn.call(1), UiKit.SMALL + 1))
	(parent if parent != null else body).add_child(h)
	watch(func():
		var val: Variant = get_fn.call()
		v.text = fmt_fn.call(val) if fmt_fn.is_valid() else str(val))


# Pole „[−] 3.4 zł [+]” do tabel cen; change_fn dostaje zmianę w złotych.
func price_cell(get_fn: Callable, change_fn: Callable) -> Control:
	var h := UiKit.row(2)
	h.add_child(UiKit.button("−", func(): change_fn.call(-PRICE_STEP), UiKit.SMALL))
	var v := UiKit.label("", UiKit.SMALL + 1)
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(v)
	h.add_child(UiKit.button("+", func(): change_fn.call(PRICE_STEP), UiKit.SMALL))
	watch(func(): v.text = "%.1f zł" % float(get_fn.call()))
	return h
