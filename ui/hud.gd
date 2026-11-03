# Hud — składa ekran (S40): pasek górny (meldunki, czas, tempo, monety), pasek po lewej
# (okna ogólne), karta zaznaczenia w prawym dolnym rogu, jedno okno sprawy naraz, okna
# decyzji (auto-pauza) i nakładka nad światem. Treść okien jest w ui/windows/.
extends Control


const AgentView := preload("res://game/agent_view.gd")
const SelectionCard := preload("res://ui/selection_card.gd")
const BuildWindow := preload("res://ui/windows/build_window.gd")
const FamilyWindow := preload("res://ui/windows/family_window.gd")
const ChronicleWindow := preload("res://ui/windows/chronicle_window.gd")
const HelpWindow := preload("res://ui/windows/help_window.gd")
const PeopleWindow := preload("res://ui/windows/people_window.gd")
const StatsWindow := preload("res://ui/windows/stats_window.gd")

const ORDER_COLOR := Color(1.0, 0.85, 0.3, 0.85)
const WARM := 15.0                  # progi słów dla więzi i preferencji (bez liczb w UI)
const MILD := 3.0
const MARGIN := 10.0                # odstęp paneli od krawędzi i od siebie
const TOP_H := 52.0                 # wysokość górnego paska
const LEFT_W := 150.0               # szerokość paska po lewej
const FLAGS_MAX := 8                # ile chorągiewek meldunków naraz
const FLAG_DAYS := 1.0              # meldunek znika po tylu dobach
const FLAG_LEVELS := ["critical", "warn", "good"]
const FLAG_COLORS := { "critical": Color(1.0, 0.35, 0.28), "warn": Color(1.0, 0.75, 0.25), "good": Color(0.5, 0.85, 0.4) }
const LINK_HOME := Color(0.55, 0.85, 1.0, 0.9)    # podświetlenie powiązań pod kursorem (I7)
const LINK_WORK := Color(1.0, 0.8, 0.35, 0.9)
const LINK_R := 3.2                  # promień obwódki budynku (m)
const LINK_PERSON_R := 0.9           # promień obwódki osoby (m)
const JOB_PLACE := { "sawyer": "sawmill", "carpenter": "workshop" }   # własna robota: zawód -> typ budynku

var main: Node
var world: SimWorld
var camera: Camera3D
var debug := false                  # F3: ukryte liczby (więzi, siła) dla dewelopera

var _top_date: Label
var _top_speed: Array = []
var _top_cash: RichTextLabel
var _flags: HBoxContainer
var _flag_sig := ""
var _flag_seen: Dictionary = {}     # klucz meldunku -> true (odkliknięty)
var _left_buttons: Dictionary = {}  # klucz okna -> Button
var _card: TopicWindow
var _card_key := ""
var _window: TopicWindow
var _window_sel := ""               # zaznaczenie, przy którym otwarto okno sprawy
var _menu: PopupMenu
var _menu_fns: Array = []
var _modal: Control
var _modal_id := -1
var _overlay: Control
var _fx: Array = []
var _tick := 0.0


func setup(p_main: Node, w: SimWorld, cam: Camera3D) -> void:
	main = p_main
	world = w
	camera = cam
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.make_theme()

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_build_top()
	_build_left()
	_build_modal()
	toggle_help()


# --- Pasek górny ---

func _build_top() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = TOP_H
	add_child(p)
	var h := UiKit.row(14)
	p.add_child(h)
	_flags = UiKit.row(4)
	_flags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flags.clip_contents = true
	h.add_child(_flags)
	_top_date = UiKit.label("", UiKit.FONT + 2)
	h.add_child(_top_date)
	var names := ["II", "1x", "2x", "4x", "8x"]
	for i in names.size():
		var b := UiKit.button(names[i], func(): main.set_speed(i), UiKit.SMALL + 2)
		b.custom_minimum_size.x = 44
		b.toggle_mode = true
		_top_speed.append(b)
		h.add_child(b)
	# Monety mają stałe pole: zmiana kwoty nie przesuwa reszty paska.
	_top_cash = RichTextLabel.new()
	_top_cash.bbcode_enabled = true
	_top_cash.scroll_active = false
	_top_cash.autowrap_mode = TextServer.AUTOWRAP_OFF
	_top_cash.clip_contents = true
	_top_cash.custom_minimum_size = Vector2(260, 28)
	_top_cash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top_cash.add_theme_font_size_override("normal_font_size", UiKit.FONT + 2)
	_top_cash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_top_cash)


func _update_top() -> void:
	var c := world.clock
	var hm := c.hour_minute()
	_top_date.text = "%s · rok %d · dzień %d/%d · %02d:%02d" % [c.season_label(), c.current_year() + 1,
		c.day_of_season() + 1, c.days_per_season, hm.x, hm.y]
	for i in _top_speed.size():
		_top_speed[i].button_pressed = c.speed == i
	var hh := world.household
	var net := hh.last_day_net
	var t := "[color=#e8d27a]%d zł[/color] [color=%s](%+d)[/color]" % [int(hh.cash), "#9be07a" if net >= 0 else "#ff8a70", int(round(net))]
	if hh.debt > 0.0:
		t += "  [color=#ff6a55]dług %d zł[/color]" % int(ceil(hh.debt))
	_top_cash.text = t
	_update_flags()


# Meldunki (S43): chorągiewki z ostatniej doby; najechanie = treść, klik = pokaż
# miejsce i schowaj chorągiewkę. Wszystko jest też w kronice (zakładka Zdarzenia).
func _update_flags() -> void:
	var now := float(world.clock.day_index()) + world.clock.time_of_day()
	var shown: Array = []
	var entries: Array = world.events.entries
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if now - (float(e["day"]) + float(e["tod"])) > FLAG_DAYS:
			break
		if not String(e["level"]) in FLAG_LEVELS or _flag_seen.has(_flag_key(e)):
			continue
		shown.append(e)
		if shown.size() >= FLAGS_MAX:
			break
	var sig := ",".join(shown.map(func(e): return _flag_key(e)))
	if sig == _flag_sig:
		return
	_flag_sig = sig
	for c in _flags.get_children():
		c.queue_free()
	for e in shown:
		var ed: Dictionary = e
		var b := UiKit.button("⚑", func():
			_flag_seen[_flag_key(ed)] = true
			if ed["focus"] is Vector2:
				main.focus_on(ed["focus"]), UiKit.FONT)
		b.tooltip_text = String(ed["text"])
		b.add_theme_color_override("font_color", FLAG_COLORS[ed["level"]])
		b.add_theme_color_override("font_hover_color", FLAG_COLORS[ed["level"]].lightened(0.3))
		_flags.add_child(b)


static func _flag_key(e: Dictionary) -> String:
	return "%d:%.4f:%s" % [int(e["day"]), float(e["tod"]), e["text"]]


# --- Pasek po lewej ---

func _build_left() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(MARGIN, TOP_H + MARGIN)
	p.custom_minimum_size.x = LEFT_W
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	for it in [["Budowa (B)", "build", toggle_build], ["Ród (G)", "family", toggle_family],
			["Kronika (K)", "chronicle", toggle_chronicle], ["Ludzie (L)", "people", toggle_people],
			["Statystyki", "stats", toggle_stats], ["Pomoc (F1)", "help", toggle_help]]:
		var b := UiKit.button(it[0], it[2], UiKit.SMALL + 1)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
		_left_buttons[it[1]] = b


func toggle_build() -> void:
	toggle_window("build", func(): return BuildWindow.new(), "Budowa")


func toggle_family() -> void:
	toggle_window("family", func(): return FamilyWindow.new(), "Ród")


func toggle_chronicle() -> void:
	toggle_window("chronicle", func(): return ChronicleWindow.new(), "Kronika")


func toggle_people() -> void:
	toggle_window("people", func(): return PeopleWindow.new(), "Ludzie")


func toggle_stats() -> void:
	toggle_window("stats", func(): return StatsWindow.new(), "Statystyki")


func toggle_help() -> void:
	toggle_window("help", func(): return HelpWindow.new(), "Pomoc")


# --- Okno sprawy (jedno naraz) ---

func window_key() -> String:
	return _window.key if _window != null else ""


func toggle_window(key: String, make: Callable, title := "") -> void:
	if window_key() == key:
		close_window()
		return
	close_window()
	var win: TopicWindow = make.call()
	add_child(win)
	win.init_window(self, key, title)
	_window = win
	_window_sel = _sel_key()
	_place(win)
	win.refresh()


# Zamyka okno sprawy; false, gdy żadne nie było otwarte (Esc idzie wtedy dalej).
func close_window() -> bool:
	if _window == null:
		return false
	_window.queue_free()
	_window = null
	return true


func _update_window() -> void:
	for k in _left_buttons:
		_left_buttons[k].set_pressed_no_signal(window_key() == k)
	if _window == null:
		return
	# Okno osoby albo budynku zamyka się, gdy zaznaczenie przejdzie gdzie indziej.
	if _window.anchor == "card" and _sel_key() != _window_sel:
		close_window()
		return
	_place(_window)
	_window.refresh()


# Okna ogólne stoją przy pasku po lewej, okna zaznaczenia obok karty. Prostokąt
# kotwicy ma zerowy rozmiar, więc okno zawsze ma rozmiar treści i rośnie od rogu.
func _place(win: TopicWindow) -> void:
	if win.anchor == "card":
		var right := -MARGIN - ((_card.size.x + MARGIN) if _card != null and _card.visible else 0.0)
		win.anchor_left = 1.0
		win.anchor_right = 1.0
		win.anchor_top = 1.0
		win.anchor_bottom = 1.0
		win.offset_left = right
		win.offset_right = right
		win.offset_top = -MARGIN
		win.offset_bottom = -MARGIN
		win.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		win.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		var x := LEFT_W + 2.0 * UiKit.PANEL_PAD + 2.0 * MARGIN
		win.set_anchors_preset(Control.PRESET_TOP_LEFT)
		win.offset_left = x
		win.offset_right = x
		win.offset_top = TOP_H + MARGIN
		win.offset_bottom = TOP_H + MARGIN


# --- Karta zaznaczenia ---

func _sel_key() -> String:
	if main.selected_id >= 0:
		return "a:%d" % main.selected_id
	if main.selected_building != "":
		return "b:" + main.selected_building
	return ""


func _update_card() -> void:
	var key := _sel_key() + (":debug" if debug else "")
	if key != _card_key:
		_card_key = key
		if _card != null:
			_card.queue_free()
			_card = null
		if _sel_key() != "":
			_card = SelectionCard.new()
			add_child(_card)
			_card.init_window(self, "card", "")
			_card.anchor_left = 1.0
			_card.anchor_right = 1.0
			_card.anchor_top = 1.0
			_card.anchor_bottom = 1.0
			_card.offset_left = -MARGIN
			_card.offset_right = -MARGIN
			_card.offset_top = -MARGIN
			_card.offset_bottom = -MARGIN
			_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if _card != null:
		_card.refresh()


# --- Pomocnicze (dla okien) ---

func feel(v: float) -> String:
	if v >= WARM:
		return "bardzo dobrze"
	if v >= MILD:
		return "dobrze"
	if v <= -WARM:
		return "bardzo źle"
	if v <= -MILD:
		return "źle"
	return "blado"


func feel_color(v: float) -> Color:
	return UiKit.GOOD if v >= MILD else (UiKit.BAD if v <= -MILD else UiKit.DIM)


func count_job(job: String) -> int:
	return world.agents.filter(func(a): return a.status == "active" and a.job == job and a.can_work()).size()


# Kto pracuje w budynku: najęci z umowy albo domownicy właściciela przy własnej robocie.
func workers_at(b: SimBuilding) -> Array:
	var own := not world.is_foreign(b)
	return world.agents.filter(func(a): return a.status == "active" and (a.workplace == b.id
		or (own and a.workplace == "" and world.household_of(a) == world.household and JOB_PLACE.get(a.job, "") == b.type)))


func workplace_of(a: SimAgent) -> SimBuilding:
	if a.workplace != "":
		return world.buildings.get(a.workplace)
	var t: String = JOB_PLACE.get(a.job, "")
	if t == "":
		return null
	for b: SimBuilding in world.buildings.values():
		if b.type == t and not world.is_foreign(b):
			return b
	return null


func household_label(hid: int) -> String:
	var h: SimHousehold = world.households.get(hid)
	if h == null or h.members.is_empty():
		return "właściciel spoza okolicy"
	var p: SimPerson = world.family.persons.get(h.members[0])
	return ("ród " + world.family.lineage_of(p).name) if p != null else "?"


func owner_text(b: SimBuilding) -> String:
	var who := "właściciel spoza okolicy"
	match b.owner_kind:
		"person":
			var p: SimPerson = world.family.persons.get(b.owner_id)
			who = "właściciel: " + (p.full_name() if p != null else "?")
		"lineage":
			var l: SimLineage = world.family.lineages.get(b.owner_id)
			who = "własność rodu " + (l.name if l != null else "?")
	var tenants: Array = []
	for h: SimHousehold in world.households.values():
		if h.home_id == b.id:
			for pid in h.members:
				tenants.append(world.family.persons[pid].name)
	return "%s\nmieszkają: %s" % [who, ", ".join(tenants) if not tenants.is_empty() else "nikt"]


func stock_text(b: SimBuilding) -> String:
	match b.type:
		"home", "decor_house", "shack":
			var hh := world.household_at(b.id)
			if hh == null:
				return "stan %d%%" % int(b.condition * 100.0)
			return "jedzenie %d · opał %d · skrzynia %d zł · stan %d%%" % [b.amount("food"), b.amount("log"), int(b.chests.get(hh.id, 0.0)), int(b.condition * 100.0)]
		"sawmill":
			return "kłody %d/%d · deski %d/%d" % [b.amount("log"), int(b.capacity["log"]), b.amount("plank"), int(b.capacity["plank"])]
		"workshop":
			return "deski %d · krzesła %d" % [b.amount("plank"), b.amount("chair")]
		"market":
			return "otwarte stragany: %d" % world.trade.stalls.values().filter(func(x): return x.is_open()).size()
		"stall":
			var st: SimStall = world.trade.stalls.get(b.id)
			return ("otwarty" if st.is_open() else "zwinięty") if st != null else ""
	return ""


# --- Menu kontekstowe PPM (przydział jak w Cultures): pozycje { label, ok, fn } ---

func show_menu(pos: Vector2, items: Array) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.add_theme_font_size_override("font_size", UiKit.FONT)
		_menu.id_pressed.connect(func(id: int): _menu_fns[id].call())
		add_child(_menu)
	_menu.clear()
	_menu_fns = []
	for i in items.size():
		var it: Dictionary = items[i]
		_menu.add_item(String(it["label"]), i)
		_menu.set_item_disabled(i, not bool(it["ok"]))
		_menu_fns.append(it["fn"])
	_menu.position = Vector2i(pos)
	_menu.reset_size()
	_menu.popup()


# --- Okno decyzji ---

func _build_modal() -> void:
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0, 0, 0, 0.45)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	add_child(_modal)


func _update_modal() -> void:
	var prompts: Array = world.events.prompts
	if prompts.is_empty():
		_modal.visible = false
		_modal_id = -1
		return
	var pr: Dictionary = prompts[0]
	if int(pr["id"]) == _modal_id:
		return
	_modal_id = int(pr["id"])
	for c in _modal.get_children():
		c.queue_free()
	_modal.visible = true
	move_child(_modal, get_child_count() - 1)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.14, 0.11, 0.08, 0.98), Color(0.85, 0.65, 0.3), 10, 24))
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = 620
	p.add_child(v)
	v.add_child(UiKit.label(String(pr["title"]), 30, Color(1.0, 0.82, 0.4)))
	v.add_child(UiKit.wrap(String(pr["text"]), 20))
	v.add_child(UiKit.label("(gra wstrzymana do decyzji)", UiKit.SMALL, UiKit.DIM))
	for o in pr["options"]:
		var val: Variant = o["value"]
		var pid := int(pr["id"])
		var kind := String(pr["kind"])
		var b := UiKit.button(String(o["label"]), func(): main.answer_prompt(pid, kind, val), 20)
		b.custom_minimum_size.y = 44
		v.add_child(b)


# --- Nakładka nad światem ---

func push_fx(items: Array) -> void:
	for f in items:
		var e: Dictionary = f.duplicate()
		e["t"] = 0.0
		_fx.append(e)


func _process(delta: float) -> void:
	if world == null:
		return
	for f in _fx:
		f["t"] = float(f["t"]) + delta
	_fx = _fx.filter(func(f): return float(f["t"]) < 2.2)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.15
		_update_top()
		_update_card()
		_update_window()
	_update_modal()
	_overlay.queue_redraw()


func _screen(p: Vector2, h: float) -> Vector2:
	return camera.unproject_position(Vector3(p.x, h, p.y))


func _text(pos: Vector2, s: String, size: int, col: Color, center := true) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := pos - Vector2(w * 0.5 if center else 0.0, 0)
	_overlay.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.85))
	_overlay.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_overlay() -> void:
	var zoom_ok: bool = main.cam_size < 60.0
	if main.placing != "":
		var cfg: Dictionary = world.buildables.get(main.placing, {})
		var what := String(cfg.get("label", main.placing)).to_lower()
		var msg := ("Kliknij koniec drogi" if main.placing_from != null else "Kliknij początek drogi") if bool(cfg.get("line", false)) \
			else "Kliknij, gdzie stanie: %s" % what
		_text(get_viewport().get_mouse_position() + Vector2(0, -24), msg + " (Esc — anuluj)", 17, Color(1, 0.9, 0.5))
	# Etykiety budynków z zapasami.
	for id in world.buildings:
		var b: SimBuilding = world.buildings[id]
		if b.type.begins_with("decor"):
			continue
		var sp := _screen(b.position, 5.5 if b.type != "manor" else 8.5)
		var sel: bool = main.selected_building == id
		_text(sp, b.name, 19 if zoom_ok else 15, Color(1, 0.92, 0.7) if not sel else Color(1, 0.8, 0.3))
		if zoom_ok:
			var info := stock_text(b)
			if info != "":
				_text(sp + Vector2(0, 20), info, 15, Color(0.88, 0.85, 0.75))
	_draw_links()
	# Ludzie: alarmy, imiona.
	for a in world.agents:
		if a.status != "active" or a.hidden:
			continue
		var p := world.person_of(a)
		var sp := _screen(a.position, 2.6)
		if (a.alert or a.hungry_no_food) and world.family.is_ours(p):
			_overlay.draw_circle(sp + Vector2(0, -10), 12, Color(0.85, 0.15, 0.1))
			_overlay.draw_arc(sp + Vector2(0, -10), 12, 0, TAU, 20, Color(1, 1, 1), 2)
			_text(sp + Vector2(0, -3), "!", 18, Color(1, 1, 1))
		if a.activity == "talk" and zoom_ok:
			# Dymek rozmowy (S17): widać, kto z kim gada.
			var bp := sp + Vector2(14, -22)
			_overlay.draw_circle(bp, 11, Color(1, 1, 1, 0.9))
			_text(bp + Vector2(0, 5), "…", 16, Color(0.2, 0.2, 0.2))
		var ours := world.family.is_ours(p)
		if main.selected_id == a.id or main.hover_id == a.id or (zoom_ok and main.cam_size < 30.0):
			# Obcy z nazwiskiem i w barwie swojego rodu, swoi samym imieniem na biało.
			var label := p.name if ours else p.full_name()
			var col := Color(1, 1, 1) if ours else AgentView.band_color(p.lineage_id, false).lightened(0.45)
			_text(sp + Vector2(0, -26 if (a.alert or a.hungry_no_food) else -6), label, 16 if ours else 14, col)
	# Kolejka rozkazów zaznaczonej osoby: linia przez kolejne cele marszu.
	var sel := world.agent_by_id(main.selected_id)
	if sel != null and sel.controlled and not sel.hidden:
		var prev := _screen(sel.position, 0.1)
		var n := 0
		for st in sel.steps:
			if st["t"] != "walk":
				continue
			n += 1
			var pt := _screen(st["to"], 0.1)
			_overlay.draw_line(prev, pt, ORDER_COLOR, 2.0)
			_overlay.draw_circle(pt, 9, ORDER_COLOR)
			_text(pt + Vector2(0, 5), str(n), 14, Color(0, 0, 0))
			prev = pt
	# Unoszące się teksty (zarobek, koszty).
	for f in _fx:
		var t := float(f["t"])
		var sp := _screen(f["pos"], 3.0) + Vector2(0, -40.0 * t)
		var col := Color(1.0, 0.88, 0.35) if f["kind"] == "money" else (Color(1.0, 0.5, 0.4) if f["kind"] == "cost" else Color(0.85, 0.95, 0.8))
		col.a = clampf(2.2 - t, 0.0, 1.0)
		_text(sp, String(f["text"]), 20, col)
	# Podpowiedź pod kursorem.
	if main.hover_id >= 0:
		var a := world.agent_by_id(main.hover_id)
		if a != null and a.status == "active":
			var p := world.person_of(a)
			var mp := get_viewport().get_mouse_position() + Vector2(18, 28)
			var lines := ["%s (%s)" % [p.name, SimJobs.JOB_LABELS.get(a.job, a.job)], a.idle_reason]
			var font := ThemeDB.fallback_font
			var wmax := 0.0
			for l in lines:
				wmax = maxf(wmax, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
			_overlay.draw_rect(Rect2(mp - Vector2(8, 20), Vector2(wmax + 16, 50)), Color(0.08, 0.06, 0.05, 0.9))
			_text(mp, lines[0], 17, Color(1, 0.85, 0.45), false)
			_text(mp + Vector2(0, 22), lines[1], 17, UiKit.BAD if a.alert else UiKit.TEXT, false)


# Powiązania pod kursorem (I7, jak w Cultures): osoba → jej dom i miejsce pracy;
# budynek → kto w nim mieszka i pracuje.
func _draw_links() -> void:
	if main.hover_id >= 0:
		var a := world.agent_by_id(main.hover_id)
		if a == null:
			return
		var home := world.home_of(a)
		if home != null:
			_ring(home.position, LINK_R, LINK_HOME, "dom")
		var work := workplace_of(a)
		if work != null:
			_ring(work.position, LINK_R, LINK_WORK, "praca")
	elif main.hover_building != "":
		var b := world.building(main.hover_building)
		if b == null:
			return
		var workers := workers_at(b)
		for a: SimAgent in world.agents:
			if a.status != "active" or a.hidden:
				continue
			if a.home_id == b.id:
				_ring(a.position, LINK_PERSON_R, LINK_HOME, "")
			elif a in workers:
				_ring(a.position, LINK_PERSON_R, LINK_WORK, "")


func _ring(pos: Vector2, r: float, col: Color, label: String) -> void:
	var c := _screen(pos, 0.1)
	var rx := c.distance_to(_screen(pos + Vector2(r, 0), 0.1))
	var ry := c.distance_to(_screen(pos + Vector2(0, r), 0.1))
	var pts := PackedVector2Array()
	for i in 33:
		var t := TAU * i / 32.0
		pts.append(_screen(pos + Vector2(cos(t), sin(t)) * r, 0.1))
	_overlay.draw_polyline(pts, col, 3.0)
	if label != "":
		_text(c + Vector2(0, maxf(rx, ry) + 18), label, 16, col)

