# Kronika: losy rodu (E3: narodziny, śluby, śmierci, odejścia) albo bieżące zdarzenia
# z dziennika (S43: wszystko, co nie zmieściło się w chorągiewkach), od najnowszych.
extends TopicWindow


const ROWS := 40
const EVENT_COLORS := { "good": UiKit.GOOD, "warn": UiKit.WARN, "critical": UiKit.BAD }

var _tab := "family"
var _count := -1
var _box: VBoxContainer


func build() -> void:
	_count = -1
	var tabs := UiKit.row(4)
	add(tabs)
	for t in [["family", "Losy rodu"], ["events", "Zdarzenia"]]:
		var id: String = t[0]
		var b := UiKit.button(t[1], func():
			_tab = id
			rebuild(), UiKit.SMALL)
		b.toggle_mode = true
		b.button_pressed = _tab == id
		tabs.add_child(b)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add(_box)
	watch(_fill)


func _fill() -> void:
	var src: Array = world.chronicle.entries if _tab == "family" else world.events.entries
	if src.size() == _count:
		return
	_count = src.size()
	for c in _box.get_children():
		c.queue_free()
	var entries: Array = src.duplicate()
	entries.reverse()
	if entries.is_empty():
		_box.add_child(UiKit.label("Na razie nic się nie wydarzyło.", UiKit.SMALL + 2, UiKit.DIM))
	for e in entries.slice(0, ROWS):
		var day := int(e["day"])
		var col: Color = UiKit.TEXT
		if _tab == "family":
			col = {"death": UiKit.BAD, "departure": UiKit.WARN, "birth": UiKit.GOOD, "wedding": UiKit.GOOD}.get(e["kind"], UiKit.TEXT)
		else:
			col = EVENT_COLORS.get(e["level"], UiKit.TEXT)
		_box.add_child(UiKit.wrap("Rok %d, dzień %d — %s" % [day / world.clock.days_per_year + 1, day % world.clock.days_per_year + 1, e["text"]], UiKit.SMALL + 1, col))
