# Hud — cały interfejs 2D: pasek górny (czas, pieniądze, czynsz, zapasy), panel rodu,
# panel zaznaczenia (osoba/budynek + polecenia), dziennik, okna decyzji (auto-pauza)
# i nakładka nad światem (etykiety budynków, alarmy, dymki z kwotami, podpowiedź).
extends Control


const AgentView := preload("res://game/agent_view.gd")

const BG := Color(0.11, 0.09, 0.07, 0.9)
const BORDER := Color(0.55, 0.42, 0.25)
const TEXT := Color(0.95, 0.91, 0.82)
const DIM := Color(0.72, 0.67, 0.58)
const GOOD := Color(0.55, 0.88, 0.45)
const WARN := Color(1.0, 0.78, 0.3)
const BAD := Color(1.0, 0.42, 0.35)
const ORDER_COLOR := Color(1.0, 0.85, 0.3, 0.85)
const JOB_ORDER := ["woodcutter", "sawyer", "carpenter", "carrier", "forager", "laborer", "overseer", "thief", "none"]
const JOB_HINTS := {
	"woodcutter": "ścina drzewa, nosi kłody do tartaku",
	"sawyer": "w tartaku tnie kłody na deski",
	"carpenter": "w stolarni robi krzesła z desek (jakość = umiejętność)",
	"carrier": "kupuje jedzenie, nosi opał, wozi deski i krzesła",
	"forager": "zbiera jedzenie w lesie (za darmo, mało; zimą prawie nic)",
	"laborer": "robotnik w polu u kogoś: najlepsza oferta, płaca do ręki po robocie",
	"overseer": "pilnuje najętych przez was ludzi: przy nim się nie migają (kilku na raz)",
	"thief": "kradnie na targu: szybki grosz, ale złapany idzie do aresztu, grzywna i wstyd",
	"none": "pomaga w domu: zakupy i opał, gdy trzeba",
}
const JOB_BUTTONS := {
	"woodcutter": "Drwal", "sawyer": "Tracz", "carpenter": "Stolarz", "carrier": "Tragarz",
	"forager": "Zbieracz", "laborer": "Robotnik", "overseer": "Nadzorca", "thief": "Złodziej", "none": "Bez przydziału",
}
const PERSON_TABS := [["now", "Teraz"], ["memories", "Wspomnienia"], ["prefs", "Preferencje"], ["traits", "Cechy i charakter"]]
const MEMORIES_SHORT := 8          # ile wspomnień widać przed „pokaż więcej”
const MEMORIES_LONG := 30
const WARM := 15.0                  # progi słów dla więzi i preferencji (bez liczb w UI)
const MILD := 3.0
const CHRONICLE_ROWS := 40
const SKILL_LABELS := { "chop": "rąbanie", "saw": "piłowanie", "craft": "stolarka", "forage": "zbieractwo", "steal": "złodziejstwo", "trade": "handel" }

const FAMILY_W := 440.0   # szerokość panelu rodu (karty zawijają tekst)

const PRICE_STEP := 0.1   # krok granicy ceny w panelu chaty (zł)
var main: Node
var world: SimWorld
var camera: Camera3D

var _top_date: Label
var _top_speed: Array = []
var _top_res: RichTextLabel
var _family_title: Label
var _family_panel: PanelContainer
var _build_panel: PanelContainer
var _menu: PopupMenu
var _menu_fns: Array = []
var _family_box: VBoxContainer
var _family_sig := ""
var _family_rows: Dictionary = {}   # agent id -> Button
var _info: PanelContainer
var _info_box: VBoxContainer
var _info_key := ""
var _info_updaters: Array = []
var _log: RichTextLabel
var _log_count := -1
var _modal: Control
var _modal_id := -1
var _help: PanelContainer
var _overlay: Control
var _fx: Array = []
var _person_tab := "now"
var _memories_more := false
var _chronicle: PanelContainer
var _chronicle_box: VBoxContainer
var _chronicle_count := -1
var debug := false                  # F3: ukryte liczby (więzi, siła) dla dewelopera
var _tick := 0.0


func setup(p_main: Node, w: SimWorld, cam: Camera3D) -> void:
	main = p_main
	world = w
	camera = cam
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 19
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_color", "Button", TEXT)
	th.set_stylebox("normal", "Button", _box(Color(0.25, 0.19, 0.13), BORDER.darkened(0.3), 4, 6))
	th.set_stylebox("hover", "Button", _box(Color(0.36, 0.27, 0.17), BORDER, 4, 6))
	th.set_stylebox("pressed", "Button", _box(Color(0.5, 0.36, 0.18), Color(1, 0.85, 0.4), 4, 6))
	th.set_stylebox("disabled", "Button", _box(Color(0.16, 0.14, 0.12), Color(0.25, 0.22, 0.2), 4, 6))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("panel", "PanelContainer", _box(BG, BORDER, 8, 12))
	th.set_stylebox("background", "ProgressBar", _box(Color(0.2, 0.17, 0.14), Color(0, 0, 0, 0), 3, 0))
	theme = th

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_build_top()
	_build_family()
	_build_info()
	_build_log()
	_build_help()
	_build_chronicle()
	_build_modal()


static func _box(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


func _label(text: String, size := 0, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, size := 0) -> Button:
	var b := Button.new()
	b.text = text
	if size > 0:
		b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


# --- Pasek górny ---

func _build_top() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = 58
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	_top_date = _label("", 22)
	_top_date.custom_minimum_size.x = 380
	h.add_child(_top_date)
	var names := ["II", "1x", "2x", "4x", "8x"]
	for i in names.size():
		var b := _button(names[i], func(): main.set_speed(i), 18)
		b.custom_minimum_size = Vector2(48, 0)
		b.toggle_mode = true
		_top_speed.append(b)
		h.add_child(b)
	_top_res = RichTextLabel.new()
	_top_res.bbcode_enabled = true
	_top_res.fit_content = true
	_top_res.scroll_active = false
	_top_res.autowrap_mode = TextServer.AUTOWRAP_OFF
	_top_res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_res.add_theme_font_size_override("normal_font_size", 21)
	_top_res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_top_res)
	h.add_child(_button("Budowa (B)", func(): toggle_build(), 17))
	h.add_child(_button("Ród (G)", func(): toggle_family(), 17))
	h.add_child(_button("Kronika (K)", func(): toggle_chronicle(), 17))
	h.add_child(_button("Pomoc (F1)", func(): _help.visible = not _help.visible, 17))


func _update_top() -> void:
	var c := world.clock
	var hm := c.hour_minute()
	_top_date.text = "%s · rok %d · dzień %d/%d · %02d:%02d" % [c.season_label(), c.current_year() + 1,
		c.day_of_season() + 1, c.days_per_season, hm.x, hm.y]
	for i in _top_speed.size():
		_top_speed[i].button_pressed = c.speed == i
	var hh := world.household
	var home: SimBuilding = world.buildings.get(hh.home_id)
	var rent: float = home.rent_per_day if home != null and not world.owns(hh, home) else 0.0
	var cash_col := "#e8d27a" if hh.cash >= rent else "#ff8a70"
	var t := "[color=%s]Monety: %d zł[/color]" % [cash_col, int(hh.cash)]
	if hh.debt > 0.0:
		t += "   [color=#ff6a55]Dług: %d zł[/color]" % int(ceil(hh.debt))
	if home == null:
		t += "   [color=#ff6a55]BEZ DOMU[/color]"
		_top_res.text = t
		return
	if rent > 0.0:
		t += "   [color=%s]Czynsz %d zł/dzień[/color]" % ["#ff8a70" if hh.cash < rent else "#d8ccb0", int(rent)]
	var food_col := "#ff8a70" if home.amount("food") < 6 else "#d8ccb0"
	t += "   [color=%s]Jedzenie: %d[/color]" % [food_col, home.amount("food")]
	var need := float(world.balance["economy"]["firewood_per_day"].get(c.current_season(), 0.0))
	var fire_col := "#ff8a70" if need > 0.0 and home.amount("log") < need * 2.0 else "#d8ccb0"
	t += "   [color=%s]Opał: %d[/color]" % [fire_col, home.amount("log")]
	var net := hh.last_day_net
	t += "   [color=%s]Wczoraj: %+d zł[/color]" % ["#9be07a" if net >= 0 else "#ff8a70", int(round(net))]
	_top_res.text = t


# --- Panel rodu ---

# Panel rodu jest schowany (jak menu w Cultures): otwiera go przycisk „Ród” albo G.
func _build_family() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(10, 68)
	p.custom_minimum_size = Vector2(FAMILY_W, 0)
	p.visible = false
	add_child(p)
	_family_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_family_title = _label("", 22, Color(1.0, 0.85, 0.45))
	v.add_child(_family_title)
	var go := _button("♛ Pokaż głowę rodu (R)", func(): main.go_to_root(), 17)
	v.add_child(go)
	v.add_child(_label("kliknij osobę, by zaznaczyć · F: kamera za osobą", 15, DIM))
	_family_box = VBoxContainer.new()
	_family_box.add_theme_constant_override("separation", 4)
	v.add_child(_family_box)


# Menu kontekstowe PPM (przydział jak w Cultures): pozycje { label, ok, fn }.
func show_menu(pos: Vector2, items: Array) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.add_theme_font_size_override("font_size", 18)
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


# Menu budowy (S29, T0) jak w Cultures: katalog z danych pogrupowany w kategorie;
# wybór wpisu przełącza na wskazywanie miejsca na mapie.
func toggle_build() -> void:
	if _build_panel == null:
		_build_panel = PanelContainer.new()
		_build_panel.position = Vector2(10, 68)
		add_child(_build_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		_build_panel.add_child(v)
		v.add_child(_label("Budowa", 22, Color(1.0, 0.85, 0.45)))
		var cats := {}
		for kind in world.buildables:
			var cat := String(world.buildables[kind]["category"])
			if not cats.has(cat):
				cats[cat] = []
			cats[cat].append(kind)
		for cat in cats:
			v.add_child(_label(cat, 16, DIM))
			for kind in cats[cat]:
				var cfg: Dictionary = world.buildables[kind]
				var mats: Dictionary = cfg["materials"]
				var cost := ", ".join(mats.keys().map(func(g): return "%d× %s" % [int(mats[g]), world.good_label(g)]))
				var k: String = kind
				var b := _button("%s — %s" % [cfg["label"], cost if cost != "" else "tylko praca"], func():
					main.placing = k
					main.placing_from = null
					_build_panel.visible = false, 17)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				v.add_child(b)
		var tip := _label("Wybierz, potem kliknij miejsce na mapie (droga: początek i koniec). Esc — anuluj.", 14, DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size.x = 360
		v.add_child(tip)
		_build_panel.visible = false
	_build_panel.visible = not _build_panel.visible
	if _build_panel.visible:
		_family_panel.visible = false


func toggle_family() -> void:
	_family_panel.visible = not _family_panel.visible
	if _family_panel.visible and _build_panel != null:
		_build_panel.visible = false


func _update_family() -> void:
	if not _family_panel.visible:
		return
	var fam := world.family
	var r := fam.root()
	_family_title.text = "Ród %s%s" % [fam.dynasty, ("  ·  głowa: " + r.name) if r != null else ""]
	var living := fam.by_kinship()
	var sig := ",".join(living.map(func(p): return str(p.agent_id)))
	if sig != _family_sig:
		_family_sig = sig
		for c in _family_box.get_children():
			c.queue_free()
		_family_rows.clear()
		for p in living:
			var aid: int = p.agent_id
			var b := _button("", func(): main.select_agent(aid, true), 16)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(FAMILY_W - 24, 0)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_family_box.add_child(b)
			_family_rows[aid] = b
	for p in living:
		var a := world.agent_by_id(p.agent_id)
		var b: Button = _family_rows.get(p.agent_id)
		if a == null or b == null:
			continue
		var stage := fam.stage_of(p)
		var job := "dziecko" if stage == "child" else String(SimJobs.JOB_LABELS.get(a.job, a.job))
		var mark := "♛ GŁOWA · " if p.id == fam.root_id else (fam.relation_to_root(p) + " · ")
		var extra := ""
		if p.pregnant_left >= 0.0:
			extra = " · w ciąży"
		if debug:
			extra += " · [%.2f]" % float(fam.strength.get(p.id, -1.0))
		b.text = "%s%s, %d · %s%s\n%s" % [mark, p.name, int(fam.age_of(p)), job, extra, _status_short(a)]
		var col := TEXT
		if a.alert or a.hungry_no_food or a.status == "jailed":
			col = BAD
		elif a.disabled() or a.health < 50.0:
			col = WARN
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", col.lightened(0.2))
		var job_col: Color = AgentView.CHILD_CLOTH if stage == "child" else AgentView.cloth_color(a.person_id)
		var sb := _box(Color(0.2, 0.16, 0.12) if main.selected_id != a.id else Color(0.42, 0.32, 0.16), job_col, 4, 6)
		sb.border_width_left = 8
		b.add_theme_stylebox_override("normal", sb)


func _status_short(a: SimAgent) -> String:
	if a.status == "jailed":
		return "W ARESZCIE"
	var s := a.idle_reason
	if s.length() > 40:
		s = s.substr(0, 39) + "…"
	return s


# --- Panel zaznaczenia ---

func _build_info() -> void:
	_info = PanelContainer.new()
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = -440
	_info.offset_right = -10
	_info.offset_top = 68
	_info.visible = false
	add_child(_info)
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 6)
	_info.add_child(_info_box)


func _update_info() -> void:
	var key := ""
	if main.selected_id >= 0:
		key = "a:%d:%s:%s:%s" % [main.selected_id, _person_tab, _memories_more, debug]
	elif main.selected_building != "":
		key = "b:" + main.selected_building
	if key != _info_key:
		_info_key = key
		for c in _info_box.get_children():
			_info_box.remove_child(c)
			c.queue_free()
		_info_updaters.clear()
		_info.reset_size()
		_info.visible = key != ""
		if key.begins_with("a:"):
			_build_person_info(world.agent_by_id(main.selected_id))
		elif key.begins_with("b:"):
			_build_building_info(world.building(main.selected_building))
		_info.size = Vector2.ZERO
	for u in _info_updaters:
		u.call()


func _dyn(text_fn: Callable, size := 0, color := TEXT) -> Label:
	var l := _label("", size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	_info_box.add_child(l)
	_info_updaters.append(func(): l.text = text_fn.call())
	return l


func _bar(title: String, value_fn: Callable, color: Color) -> void:
	var h := HBoxContainer.new()
	var l := _label(title, 16, DIM)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(280, 16)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := _box(color, Color(0, 0, 0, 0), 3, 0)
	pb.add_theme_stylebox_override("fill", fill)
	h.add_child(pb)
	_info_box.add_child(h)
	_info_updaters.append(func():
		var v: float = value_fn.call()
		pb.value = v
		fill.bg_color = color if v > 35.0 else BAD)


func _build_person_info(a: SimAgent) -> void:
	if a == null:
		return
	var fam := world.family
	var p := world.person_of(a)
	var title := _label("%s%s %s" % ["♛ " if p.id == fam.root_id else "", p.name, p.surname], 26, Color(1.0, 0.85, 0.45))
	_info_box.add_child(title)
	_dyn(func():
		var rel := fam.relation_to_root(p) if fam.is_ours(p) else "ród " + fam.lineage_of(p).name
		return "%s · %d lat · %s" % [rel, int(fam.age_of(p)), fam.stage_label(p)], 17, DIM)
	if debug:
		_dyn(func(): return "[debug] siła %.2f · sakiewka %.1f zł · dni słabości %d" % [
			float(fam.strength.get(p.id, -1.0)), p.purse, p.weak_days], 15, WARN)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_info_box.add_child(tabs)
	for t in PERSON_TABS:
		var id: String = t[0]
		var tb := _button(t[1], func():
			_person_tab = id
			_memories_more = false, 15)
		tb.toggle_mode = true
		tb.button_pressed = _person_tab == id
		tabs.add_child(tb)
	match _person_tab:
		"memories":
			_build_memories(p)
			return
		"prefs":
			_build_prefs(p)
			return
		"traits":
			_build_traits(p)
			return
	var now := _dyn(func(): return "Teraz: " + (a.idle_reason if a.status == "active" else "w areszcie — " + a.idle_reason), 19)
	_info_updaters.append(func(): now.add_theme_color_override("font_color", BAD if a.alert or a.status == "jailed" else GOOD))
	_bar("Zdrowie", func(): return a.health, Color(0.4, 0.75, 0.35))
	_bar("Najedzenie", func(): return a.needs["food"], Color(0.85, 0.7, 0.3))
	_bar("Wyspanie", func(): return a.needs["sleep"], Color(0.4, 0.55, 0.85))
	_dyn(func():
		var parts: Array = []
		for k in ["chop", "saw", "craft", "forage", "steal", "trade"]:
			parts.append("%s %.1f" % [SKILL_LABELS[k], a.skill(k)])
		return "Umiejętności: " + " · ".join(parts), 16, DIM)
	# Sakwa, gospodarstwo i umowa (Q1): pieniądze przy sobie, gdzie mieszka, u kogo pracuje.
	_dyn(func():
		var hh: SimHousehold = world.households.get(p.household_id)
		var home: SimBuilding = world.buildings.get(hh.home_id) if hh != null else null
		var t := "Sakwa: %d zł (z czego %d zł domu) · mieszka: %s" % [int(p.purse), int(p.held), home.name if home != null else "bez dachu"]
		var c: Dictionary = world.contracts.of_worker(p.id)
		if not c.is_empty():
			var eh: SimHousehold = world.households.get(int(c["employer"]))
			var boss := world.contracts.payer(int(c["employer"]))
			t += "\nUmowa: %s w %s, %d zł/dzień%s, należy się %d zł" % [SimJobs.JOB_LABELS.get(c["job"], c["job"]),
				world.buildings[c["place"]].name if world.buildings.has(c["place"]) else "?", int(c["wage"]),
				(" (płaci: %s)" % world.person_of(boss).name) if boss != null else "", int(round(float(c["owed"]))) ]
		return t, 16, DIM)
	_dyn(func():
		var s: Array = []
		if a.sick_days > 0.0:
			s.append("chory jeszcze %.1f dnia" % a.sick_days)
		if a.injured_days > 0.0:
			s.append("ranny jeszcze %.1f dnia" % a.injured_days)
		if p.pregnant_left >= 0.0:
			s.append("w ciąży (poród za %d dni)" % int(ceil(p.pregnant_left)))
		if a.cold:
			s.append("marznie w chacie")
		var sp: SimPerson = fam.persons.get(p.spouse_id)
		if sp != null:
			s.append(("żona: " if sp.sex == "f" else "mąż: ") + sp.name)
		if not p.children.is_empty():
			s.append("dzieci: %d" % p.children.size())
		return " · ".join(s), 16, WARN)

	_info_box.add_child(HSeparator.new())
	if world.is_independent(a):
		var where := world.home_of(a).name if world.home_of(a) != null else "bez domu"
		var txt := "Nie należy do twojego rodu (%s, %s). Żyje po swojemu — nie wydasz mu poleceń." % [fam.lineage_of(p).name, where]
		if p.mother_id >= 0 and fam.is_ours(fam.persons[p.mother_id]) or p.father_id >= 0 and fam.is_ours(fam.persons[p.father_id]):
			txt += " Odszedł z rodu — co się stało, jest w kronice (K)."
		var gone := _label(txt, 17, DIM)
		gone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gone.custom_minimum_size.x = 400
		_info_box.add_child(gone)
		return
	if fam.can_be_root(p) and p.id != fam.root_id:
		_info_box.add_child(_button("♛ Ustaw jako głowę rodu (root)", func(): world.switch_root(p.id), 17))
	if fam.stage_of(p) == "child":
		_info_box.add_child(_label("Dziecko — bawi się przy chacie. Do pracy od %d lat." % int(fam.years_label(fam.stage_start("teen"))), 17, DIM))
		_build_follow(a, p)
	else:
		_info_box.add_child(_label("Przydział pracy:", 18, Color(1.0, 0.85, 0.45)))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_info_box.add_child(grid)
		var hint := _label("", 15, DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 400
		for j in JOB_ORDER:
			var jj: String = j
			var b := _button(JOB_BUTTONS[j], func(): world.set_job(a.id, jj), 16)
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(198, 36)
			b.tooltip_text = JOB_HINTS[j]
			b.mouse_entered.connect(func(): hint.text = JOB_HINTS[jj])
			grid.add_child(b)
			_info_updaters.append(func(): b.button_pressed = a.job == jj)
		_info_box.add_child(hint)
		_info_updaters.append(func():
			if hint.text == "":
				hint.text = JOB_HINTS.get(a.job, ""))

	_dyn(func():
		var b := fam.beloved(p)
		return ("Zakochan%s w: %s" % ["y" if p.sex == "m" else "a", fam.persons[b].name]) if b >= 0 else "", 16, Color(1.0, 0.6, 0.7))
	var rel := _button("", func(): world.release_manual(a.id), 17)
	_info_box.add_child(rel)
	_info_updaters.append(func():
		rel.visible = a.controlled
		rel.text = "Anuluj rozkazy (%d w kolejce)" % a.steps.filter(func(st): return st["t"] != "do").size())
	var fol := _button("", func(): main.follow_cam = not main.follow_cam, 16)
	_info_box.add_child(fol)
	_info_updaters.append(func(): fol.text = "Kamera: przestań śledzić (F)" if main.follow_cam else "Kamera: śledź tę osobę (F)")
	var tip := _label("PPM: idź / zetnij drzewo · Shift+PPM: dopisz do kolejki\nPo wykonaniu rozkazów sam wraca do swojej pracy.", 14, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 400
	_info_box.add_child(tip)


# Dziecko w godzinach pracy chodzi za lubianym dorosłym; gracz może wskazać za kim (D5).
func _build_follow(a: SimAgent, p: SimPerson) -> void:
	_info_box.add_child(_label("W dzień chodzi z:", 17, Color(1.0, 0.85, 0.45)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_info_box.add_child(grid)
	var own := _button("z kim zechce", func(): world.set_follow(a.id, -1), 16)
	own.toggle_mode = true
	own.custom_minimum_size = Vector2(198, 34)
	grid.add_child(own)
	_info_updaters.append(func(): own.button_pressed = a.follow_id < 0)
	for o in world.family.living():
		var oa := world.agent_by_id(o.agent_id)
		if oa == null or oa.is_child:
			continue
		var oid: int = o.id
		var b := _button("z: " + o.name, func(): world.set_follow(a.id, oid), 16)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(198, 34)
		grid.add_child(b)
		_info_updaters.append(func(): b.button_pressed = a.follow_id == oid)


# Słowo zamiast liczby (E1): jak ktoś coś odczuwa.
func _feel(v: float) -> String:
	if v >= WARM:
		return "bardzo dobrze"
	if v >= MILD:
		return "dobrze"
	if v <= -WARM:
		return "bardzo źle"
	if v <= -MILD:
		return "źle"
	return "blado"


func _build_memories(p: SimPerson) -> void:
	var bonds := world.bonds
	var targets: Array = bonds.targets_of(p.id)
	var all: Array = bonds.strongest(p.id, targets, MEMORIES_LONG if _memories_more else MEMORIES_SHORT)
	if all.is_empty():
		_info_box.add_child(_label("Nic szczególnego jeszcze nie przeżył%s." % ("" if p.sex == "m" else "a"), 17, DIM))
		return
	for e in all:
		var m: Dictionary = e["m"]
		var v: float = e["v"]
		var col := GOOD if v >= MILD else (BAD if v <= -MILD else DIM)
		var who := ""
		var t: String = e["t"]
		if t.begins_with("p:"):
			var o: SimPerson = world.family.persons.get(int(t.substr(2)))
			who = (o.name + ": ") if o != null and not int(t.substr(2)) in m["with"] else ""
		var txt := "%s%s — wspomina %s (dzień %d)" % [who, bonds.describe(m, t), _feel(v), int(m["day"]) + 1]
		if debug:
			txt += "  [%.1f]" % v
		var l := _label(txt, 16, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
		_info_box.add_child(l)
	_info_box.add_child(_button("Pokaż mniej" if _memories_more else "Pokaż więcej",
		func(): _memories_more = not _memories_more, 15))


func _build_prefs(p: SimPerson) -> void:
	var prefs: Array = world.bonds.preferences(p.id)
	if prefs.is_empty():
		_info_box.add_child(_label("Nie ma jeszcze ulubionych ani znienawidzonych zajęć.", 17, DIM))
		return
	for e in prefs:
		var v: float = e["value"]
		var word := "uwielbia" if v >= WARM else ("lubi" if v >= MILD else ("nie znosi" if v <= -WARM else ("nie lubi" if v <= -MILD else "obojętne mu")))
		var label := String(world.memories["act_labels"].get(e["act"], e["act"]))
		var txt := "%s: %s\n   skąd: %s" % [word, label, "; ".join(e["from"])]
		if debug:
			txt += "  [%.1f]" % v
		var l := _label(txt, 16, GOOD if v >= MILD else (BAD if v <= -MILD else DIM))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
		_info_box.add_child(l)


func _build_traits(p: SimPerson) -> void:
	var fam := world.family
	_info_box.add_child(_label("Cechy (ciało i talent):", 17, Color(1.0, 0.85, 0.45)))
	_info_box.add_child(_label("brak szczególnych" if p.traits.is_empty() else ", ".join(p.traits.map(func(t): return fam.trait_label(t))), 17))
	_info_box.add_child(_label("Charakter:", 17, Color(1.0, 0.85, 0.45)))
	_info_box.add_child(_label("nic szczególnego" if p.character.is_empty() else ", ".join(p.character.map(func(c): return fam.character_label(c))), 17))


# --- Kronika rodu (E3) ---

func _build_chronicle() -> void:
	_chronicle = PanelContainer.new()
	_chronicle.anchor_left = 0.5
	_chronicle.anchor_right = 0.5
	_chronicle.offset_left = -420
	_chronicle.offset_right = 420
	_chronicle.offset_top = 80
	_chronicle.visible = false
	add_child(_chronicle)
	var v := VBoxContainer.new()
	_chronicle.add_child(v)
	v.add_child(_label("Kronika rodu (K — zamknij)", 22, Color(1.0, 0.85, 0.45)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(800, 460)
	v.add_child(sc)
	_chronicle_box = VBoxContainer.new()
	_chronicle_box.add_theme_constant_override("separation", 4)
	sc.add_child(_chronicle_box)


func toggle_chronicle() -> void:
	_chronicle.visible = not _chronicle.visible
	_chronicle_count = -1


func _update_chronicle() -> void:
	if not _chronicle.visible or world.chronicle.entries.size() == _chronicle_count:
		return
	_chronicle_count = world.chronicle.entries.size()
	for c in _chronicle_box.get_children():
		c.queue_free()
	var entries: Array = world.chronicle.entries.duplicate()
	entries.reverse()
	if entries.is_empty():
		_chronicle_box.add_child(_label("Na razie nic się nie wydarzyło.", 17, DIM))
	for e in entries.slice(0, CHRONICLE_ROWS):
		var day := int(e["day"])
		var col: Color = {"death": BAD, "departure": WARN, "birth": GOOD, "wedding": GOOD}.get(e["kind"], TEXT)
		var l := _label("Rok %d, dzień %d — %s" % [day / world.clock.days_per_year + 1, day % world.clock.days_per_year + 1, e["text"]], 16, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 780
		_chronicle_box.add_child(l)


func _build_building_info(b: SimBuilding) -> void:
	if b == null:
		return
	_info_box.add_child(_label(b.name, 26, Color(1.0, 0.85, 0.45)))
	var hh := world.household
	if b.type in SimWorld.HOUSE_TYPES:
		_dyn(func(): return _owner_text(b), 16, DIM)
		_build_house_actions(b)
	if b.type in ["sawmill", "workshop", "manor"]:
		_build_offers(b)
	match b.type:
		"home", "decor_house":
			_dyn(func(): return "Spiżarnia: %d / %d posiłków\nOpał: %d / %d kłód (zużycie: %s/dzień)" % [
				b.amount("food"), int(b.capacity["food"]), b.amount("log"), int(b.capacity["log"]),
				str(world.balance["economy"]["firewood_per_day"].get(world.clock.current_season(), 0))], 18)
			_dyn(func(): return "Czynsz: %d zł dziennie. Dług ponad %d zł przez %d dni = eksmisja; ponad %d zł = areszt." % [
				int(b.rent_per_day), int(world.balance["economy"]["evict_debt"]), int(world.balance["economy"]["evict_days"]), int(hh.debt_limit)], 16, DIM)
			_info_box.add_child(HSeparator.new())
			var keep := _label("Ile trzymać w zapasie (tragarze i domownicy dokupią / doniosą):", 16, DIM)
			keep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			keep.custom_minimum_size.x = 400
			_info_box.add_child(keep)
			_stepper("Jedzenie", func(): return hh.target_food, func(d): hh.target_food = clampi(hh.target_food + d, 0, int(b.capacity["food"])))
			_stepper("Opał", func(): return hh.target_firewood, func(d): hh.target_firewood = clampi(hh.target_firewood + d, 0, int(b.capacity["log"])))
			if b.id == hh.home_id:
				_build_price_limits(hh)
		"sawmill":
			_dyn(func(): return "Kłody: %d / %d\nDeski: %d / %d" % [b.amount("log"), int(b.capacity["log"]), b.amount("plank"), int(b.capacity["plank"])], 18)
			_dyn(func(): return "Drwale: %d · tracze: %d · drzewa do ścięcia: %d" % [_count_job("woodcutter"), _count_job("sawyer"),
				world.trees.filter(func(t): return t.wood > 0).size()], 16, DIM)
			_info_box.add_child(_label("1 kłoda = 2 deski. Kłody to też opał do chaty.", 15, DIM))
		"workshop":
			_dyn(func():
				var avg := 0.0
				for q in b.chair_qualities:
					avg += float(q)
				var qtxt := SimJobs.quality_label(avg / b.chair_qualities.size()) if not b.chair_qualities.is_empty() else "-"
				return "Deski: %d / %d\nKrzesła: %d / %d (jakość: %s)" % [b.amount("plank"), int(b.capacity["plank"]), b.amount("chair"), int(b.capacity["chair"]), qtxt], 18)
			_dyn(func(): return "Stolarze: %d. 2 deski = 1 krzesło. Lepszy stolarz = droższe krzesła i reputacja." % _count_job("carpenter"), 16, DIM)
		"market":
			_dyn(func():
				var lines: Array = []
				for st: SimStall in world.trade.stalls.values():
					var ka := world.agent_by_id(st.keeper)
					lines.append("%s — %s" % [st.building.name, ("za ladą: " + world.person_of(ka).name) if ka != null and st.is_open() else "zwinięty"])
				return "Stragany:\n  " + "\n  ".join(lines), 17)
			var hint := _label("Kliknij stragan, żeby zobaczyć ceny. Swoje granice cen ustawiasz w panelu chaty.", 15, DIM)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = 400
			_info_box.add_child(hint)
		"stall":
			_build_stall_info(world.trade.stalls.get(b.id))
		"site":
			_dyn(func():
				var site: Dictionary = world.sites.get(b.id, {})
				if site.is_empty():
					return "Budowa skończona."
				var cfg: Dictionary = world.site_cfg(site)
				var mats: Dictionary = cfg["materials"]
				var need := ", ".join(mats.keys().map(func(g): return "%s %d / %d" % [world.good_label(g), b.amount(g), int(mats[g])]))
				return "Budowa: %s %d%%\nMateriały: %s (bez nich praca staje)\nBudują: %s" % [
					String(cfg["label"]).to_lower(), int(100.0 * float(site["work"]) / world.site_total(site)), need if need != "" else "nie trzeba",
					", ".join(world.agents.filter(func(x): return x.activity == "build" and x.position.distance_to(b.position) < 4.0).map(func(x): return world.person_of(x).name))], 17)
			_build_offers(b)
		"manor":
			_dyn(func(): return "Pola dworu: %s" % ", ".join(world.fields.filter(func(f): return f.owner_building == b.id).map(
				func(f): return "%d/%d zagonów zasianych" % [f.count("sown") + f.count("ripe"), f.cells.size()])), 16, DIM)
		"jail":
			_dyn(func():
				var names: Array = []
				for a in world.agents:
					if a.status == "jailed":
						names.append("%s (%.1f dnia)" % [world.person_of(a).name, a.jail_days])
				return "W areszcie: " + (", ".join(names) if not names.is_empty() else "nikt z rodu"), 17)
		_:
			_info_box.add_child(_label("Chata sąsiadów. Stąd przychodzą kandydaci do ożenku.", 17, DIM))


# Wakaty w budynku (L3, L4): kto najmuje, do czego, za ile i ile miejsc wolnych.
# W swoim warsztacie gracz sam ustala, ilu ludzi chce i za ile.
func _build_offers(b: SimBuilding) -> void:
	_dyn(func():
		var lines: Array = []
		for o: Dictionary in world.contracts.offers:
			if o["place"] == b.id and int(o["slots"]) > 0:
				lines.append("%s: %d zł/dzień · zajęte %d/%d" % [SimJobs.JOB_LABELS.get(o["job"], o["job"]), int(o["wage"]),
					world.contracts.taken(o), int(o["slots"])])
		return ("Wakaty:\n  " + "\n  ".join(lines)) if not lines.is_empty() else "Wakaty: brak", 16, DIM)
	if world.is_foreign(b):
		_info_box.add_child(_label("Zaznacz swoją osobę i kliknij PPM na budynek, żeby się najęła.", 15, DIM))
		return
	for r: Dictionary in world.jobs.recipes.values():
		if String(r["building"]) != b.id:
			continue
		var job := String(r["job"])
		var bid := b.id
		var get_o := func() -> Dictionary: return world.contracts.find_offer(world.household.id, bid, job)
		var default_wage := float(world.balance["jobs"]["laborer_wage_day"])
		_info_box.add_child(_label("Najmij obcych: %s" % SimJobs.JOB_LABELS.get(job, job), 16))
		_stepper("Ile osób", func(): return int(get_o.call().get("slots", 0)), func(d):
			var o: Dictionary = get_o.call()
			world.post_player_offer(bid, job, int(o.get("slots", 0)) + signi(d), float(o.get("wage", default_wage))))
		_stepper("Stawka (zł)", func(): return int(get_o.call().get("wage", default_wage)), func(d):
			var o: Dictionary = get_o.call()
			world.post_player_offer(bid, job, int(o.get("slots", 0)), float(o.get("wage", default_wage)) + signi(d)))


# Granice cen (M3): najniższa cena, za jaką twoi ludzie sprzedadzą, i najwyższa, jaką
# zapłacą. W tych granicach targują się sami (umiejętność handlu).
func _build_price_limits(hh: SimHousehold) -> void:
	_info_box.add_child(HSeparator.new())
	_info_box.add_child(_label("Granice cen (sprzedaj nie taniej / kupuj nie drożej):", 16, DIM))
	for g in ["food", "log", "plank", "chair"]:
		var good: String = g
		_price_stepper("%s: min" % world.good_label(good), func(): return world.trade.sell_min(hh, good),
			func(d): world.trade.set_limit(hh, good, "sell_min", world.trade.sell_min(hh, good) + d * PRICE_STEP))
		_price_stepper("%s: max" % world.good_label(good), func(): return world.trade.buy_max(hh, good),
			func(d): world.trade.set_limit(hh, good, "buy_max", world.trade.buy_max(hh, good) + d * PRICE_STEP))


func _price_stepper(title: String, get_fn: Callable, change_fn: Callable) -> void:
	var h := HBoxContainer.new()
	var l := _label(title, 16)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	h.add_child(_button(" − ", func(): change_fn.call(-1), 16))
	var v := _label("", 17)
	v.custom_minimum_size.x = 70
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(v)
	h.add_child(_button(" + ", func(): change_fn.call(1), 16))
	_info_box.add_child(h)
	_info_updaters.append(func(): v.text = "%.1f zł" % float(get_fn.call()))


func _build_stall_info(st: SimStall) -> void:
	if st == null:
		return
	var oh: SimHousehold = world.households.get(st.owner)
	_dyn(func():
		var ka := world.agent_by_id(st.keeper)
		var who := ("za ladą: %s" % world.person_of(ka).full_name()) if ka != null and st.is_open() else ("rozłożony, bez opieki!" if not st.packed else "zwinięty")
		var lines: Array = [who]
		for g in st.goods:
			if st.temporary and g in st.buys:
				continue
			lines.append("%s: %d szt., nie taniej niż %.1f zł" % [world.good_label(g), st.stock.amount(g), world.trade.sell_min(oh, g)])
		for g in st.buys:
			lines.append("skupuje %s: do %.1f zł%s" % [world.good_label(g), world.trade.buy_max(oh, g),
				(" (jeszcze %d)" % int(st.wants[g])) if st.wants.has(g) else ""])
		return "\n".join(lines), 17)
	if st.owner == world.household.id:
		var own := _label("Twój stragan. Zaznacz osobę i PPM na stragan → „kramarz”. Ceny: panel chaty.", 15, DIM)
		own.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		own.custom_minimum_size.x = 400
		_info_box.add_child(own)


# Rozkazy mieszkaniowe (O1): bez automatu — gracz sam wynajmuje, kupuje, wychodzi.
func _build_house_actions(b: SimBuilding) -> void:
	var hh := world.household
	if world.is_free_house(b):
		_info_box.add_child(_button("Wynajmij dla rodziny (%d zł/dzień)" % int(b.rent_per_day), func(): world.rent_house(b.id), 16))
	if world.house_price(b) > 0.0 and not world.owns(hh, b) and (world.is_free_house(b) or b.id == hh.home_id):
		_info_box.add_child(_button("Kup ten dom (%d zł)" % int(world.house_price(b)), func(): world.buy_house(b.id), 16))
	if b.id == hh.home_id:
		_info_box.add_child(_button("Opuść dom (pod gołe niebo)", func(): world.leave_home(), 16))

	var tip := _label("Osobę wyprowadzisz albo wyrzucisz: zaznacz ją i PPM na dom.", 14, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 400
	_info_box.add_child(tip)


func _owner_text(b: SimBuilding) -> String:
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
	return "%s · mieszkają: %s" % [who, ", ".join(tenants) if not tenants.is_empty() else "nikt"]


func _stepper(title: String, get_fn: Callable, change_fn: Callable) -> void:
	var h := HBoxContainer.new()
	var l := _label(title, 17)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	h.add_child(_button(" − ", func(): change_fn.call(-2), 18))
	var v := _label("", 19)
	v.custom_minimum_size.x = 60
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(v)
	h.add_child(_button(" + ", func(): change_fn.call(2), 18))
	_info_box.add_child(h)
	_info_updaters.append(func(): v.text = str(get_fn.call()))


func _count_job(job: String) -> int:
	return world.agents.filter(func(a): return a.status == "active" and a.job == job and a.can_work()).size()


# --- Dziennik ---

func _build_log() -> void:
	var p := PanelContainer.new()
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 10
	p.offset_right = 700
	p.offset_top = -170
	p.offset_bottom = -10
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 16)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_log)


func _update_log() -> void:
	var entries: Array = world.events.entries
	if entries.size() == _log_count:
		return
	_log_count = entries.size()
	var lines: Array = []
	for e in entries.slice(maxi(0, entries.size() - 30)):
		var col := "#d8ccb0"
		match String(e["level"]):
			"good":
				col = "#9be07a"
			"warn":
				col = "#ffc860"
			"critical":
				col = "#ff7a66"
		var d := int(e["day"])
		lines.append("[color=#8a7f6a]d%d[/color] [color=%s]%s[/color]" % [d + 1, col, e["text"]])
	_log.text = "\n".join(lines)


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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.14, 0.11, 0.08, 0.98), Color(0.85, 0.65, 0.3), 10, 24))
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = 620
	p.add_child(v)
	v.add_child(_label(String(pr["title"]), 30, Color(1.0, 0.82, 0.4)))
	var body := _label(String(pr["text"]), 20)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	v.add_child(_label("(gra wstrzymana do decyzji)", 15, DIM))
	for o in pr["options"]:
		var val: Variant = o["value"]
		var pid := int(pr["id"])
		var kind := String(pr["kind"])
		var b := _button(String(o["label"]), func(): main.answer_prompt(pid, kind, val), 20)
		b.custom_minimum_size.y = 44
		v.add_child(b)


# --- Pomoc ---

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.offset_left = -420
	_help.offset_right = 420
	_help.offset_top = 80
	add_child(_help)
	var l := _label("""JAK GRAĆ
Prowadzisz ród Wilków. Przetrwaj: płać czynsz co 5 dni, karm rodzinę, zimą pal w piecu.
Pieniądze robisz na drewnie: drwal ścina → tracz tnie deski → tragarz sprzedaje na targu.
Lepiej: stolarz robi z desek krzesła (więcej zarobku, rośnie reputacja). Pewny grosz: dniówka w dworze.
Bez pieniędzy: zbieracz przyniesie jedzenie z lasu (zimą prawie nic).
Ożeń dorosłych, by mieć dzieci — ród trwa, dopóki żyje ktoś z krwi Wilków (♛ = głowa rodu).

STEROWANIE
LPM — zaznacz osobę / budynek       PPM — rozkaz: idź / zetnij drzewo (Shift = do kolejki)
Przeciągnij LPM / ŚPM, WASD, dwa palce — przesuń kamerę       Kółko / szczypanie — zoom
Q / E — obrót kamery       SPACJA — pauza       1–4 — tempo       TAB — następna osoba       ESC — odznacz
G — panel rodu       K — kronika rodu       F — kamera za zaznaczoną osobą       R — pokaż głowę rodu       F3 — debug

Zawód widać po tym, co ktoś robi i niesie; kliknij osobę, by zobaczyć przydział.
Czerwony „!” = problem (kliknij, by zobaczyć jaki).""", 17)
	_help.add_child(l)


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
		_update_family()
		_update_info()
		_update_chronicle()
		_update_log()
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
			var info := _stock_text(b)
			if info != "":
				_text(sp + Vector2(0, 20), info, 15, Color(0.88, 0.85, 0.75))
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
			_text(mp + Vector2(0, 22), lines[1], 17, BAD if a.alert else TEXT, false)


func _stock_text(b: SimBuilding) -> String:
	match b.type:
		"home":
			return "jedzenie %d · opał %d · skrzynia %d zł" % [b.amount("food"), b.amount("log"), int(b.chests.get(world.household.id, 0.0))]
		"sawmill":
			return "kłody %d/%d · deski %d/%d" % [b.amount("log"), int(b.capacity["log"]), b.amount("plank"), int(b.capacity["plank"])]
		"workshop":
			return "deski %d · krzesła %d" % [b.amount("plank"), b.amount("chair")]
		"market":
			return "otwarte stragany: %d" % world.trade.stalls.values().filter(func(x): return x.is_open()).size()
		"stall":
			var st: SimStall = world.trade.stalls.get(b.id)
			return ("otwarty" if st != null and st.is_open() else "zwinięty") if st != null else ""
	return ""
