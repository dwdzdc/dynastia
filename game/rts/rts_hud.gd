# RtsHud — interfejs gry na mapie. Górny pasek (data, tempo, kasa rodu, Budowa,
# Moje, Kurier), nazwy miast przy mapie, minimapa, meldunki, karta zaznaczenia
# z poleceniami (jak w Cultures: ogólne zadanie + przejęcie ręczne) i okna:
# menu budowy, moje firmy i ciężarówki, Kurier. Tylko czyta stan i woła RtsWorld.
class_name RtsHud
extends Control


const BG := Color(0.08, 0.1, 0.13, 0.92)
const BORDER := Color(0.25, 0.31, 0.4)
const TEXT := Color(0.9, 0.93, 0.98)
const DIM := Color(0.62, 0.68, 0.78)
const ACCENT := Color(0.5, 0.8, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const GOOD := Color(0.5, 0.9, 0.55)
const WARN := Color(1.0, 0.78, 0.35)
const BAD := Color(1.0, 0.45, 0.4)
const FONT := 16
const SMALL := 13
const HEAD := 20
const CARD_W := 420
const MINI_W := 300
const MINI_H := 200
const NOTES := 6
const SPEED_LABELS := ["⏸", "1×", "3×", "10×", "30×"]
const DAYS_PER_YEAR := 360
const LABEL_MIN_POP_FAR := 20000.0   # przy dużym oddaleniu podpisujemy tylko większe miasta
const FAR_CAM := 12000.0
const RESOURCE_PL := {"fertile": "żyzna ziemia", "forest": "las", "oil": "ropa", "iron": "ruda żelaza", "limestone": "wapień"}
const STATUS_PL := {"active": "pracuje", "building": "w budowie", "burned": "po pożarze", "strike": "strajk", "closed": "zamknięta"}
const ROUTE_GOODS := ["grain", "flour", "bread", "vegetables", "meat", "crude", "fuel", "wood", "lumber", "cement", "steel", "iron_ore", "limestone", "plastics", "furniture", "appliances"]

var main: Node
var rts: RtsWorld
var _date: Label
var _cash: Label
var _status: Label
var _speed_btns: Array[Button] = []
var _city_labels: Dictionary = {}
var _card: PanelContainer
var _card_box: VBoxContainer
var _notes: VBoxContainer
var _flash: Label
var _flash_t := 0.0
var _window: Control
var _kurier: KurierPage
var _mini: EconMapCanvas
var _loading: Label
var pick_mode: Dictionary = {}       # oczekiwanie na klik na mapie: { kind, ... }
var _card_t := 0.0
var _route_good := "grain"
var _cargo_good := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _theme()


func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = FONT
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_color", "Button", TEXT)
	var btn := func(bgc: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bgc
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.set_content_margin_all(5)
		return s
	th.set_stylebox("normal", "Button", btn.call(Color(0.15, 0.19, 0.25), BORDER))
	th.set_stylebox("hover", "Button", btn.call(Color(0.2, 0.26, 0.34), ACCENT.darkened(0.3)))
	th.set_stylebox("pressed", "Button", btn.call(Color(0.22, 0.38, 0.55), ACCENT))
	th.set_stylebox("disabled", "Button", btn.call(Color(0.12, 0.14, 0.17), Color(0.2, 0.22, 0.26)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_color = BORDER
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


func _label(text: String, size := FONT, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func show_loading() -> void:
	_loading = _label("Świat się rodzi: miasta, drogi, firmy, ludzie…", HEAD)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_loading)


func setup(m: Node) -> void:
	main = m
	rts = m.rts
	if _loading != null:
		_loading.queue_free()
	_build_top()
	_build_card()
	_build_notes()
	_build_minimap()
	for c: EconCity in rts.econ.cities:
		var l := _label(c.name, FONT, TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_city_labels[c.id] = l
	_flash = _label("", FONT, GOLD)
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_flash.add_theme_constant_override("outline_size", 6)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_flash.position.y = 64
	add_child(_flash)
	on_speed(main.speed_i)
	on_selection()


func _build_top() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	_date = _label("", FONT, TEXT)
	_date.custom_minimum_size.x = 160
	bar.add_child(_date)
	for i in SPEED_LABELS.size():
		var b := _button(SPEED_LABELS[i], func() -> void: main.set_speed(i))
		b.toggle_mode = true
		b.custom_minimum_size.x = 44
		bar.add_child(b)
		_speed_btns.append(b)
	bar.add_child(VSeparator.new())
	_cash = _label("", FONT, GOLD)
	_cash.custom_minimum_size.x = 200
	bar.add_child(_cash)
	bar.add_child(_button("Budowa (B)", func() -> void: open_build(-1)))
	bar.add_child(_button("Moje (M)", open_mine))
	bar.add_child(_button("Ludzie (L)", select_next_unit))
	bar.add_child(_button("Kurier (K)", open_kurier))
	_status = _label("", SMALL, DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_anchor_corner(_card, Vector2(1, 1), Vector2(-10, -10))
	add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 4)
	_card.add_child(_card_box)


# Przypina kontrolkę rogiem do rogu ekranu (corner: 0/1 w x i y), rośnie do środka.
static func _anchor_corner(c: Control, corner: Vector2, margin: Vector2) -> void:
	c.anchor_left = corner.x
	c.anchor_right = corner.x
	c.anchor_top = corner.y
	c.anchor_bottom = corner.y
	c.offset_left = margin.x
	c.offset_right = margin.x
	c.offset_top = margin.y
	c.offset_bottom = margin.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if corner.x > 0.5 else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if corner.y > 0.5 else Control.GROW_DIRECTION_END


func _build_notes() -> void:
	_notes = VBoxContainer.new()
	_notes.position = Vector2(12, 58)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notes)


func _build_minimap() -> void:
	var frame := PanelContainer.new()
	_anchor_corner(frame, Vector2(0, 1), Vector2(10, -10))
	add_child(frame)
	_mini = EconMapCanvas.new()
	_mini.w = rts.econ
	_mini.custom_minimum_size = Vector2(MINI_W, MINI_H)
	_mini.show_labels = false
	_mini.ground_clicked.connect(func(p: Vector2) -> void: main.focus_km(p))
	_mini.city_clicked.connect(func(id: int) -> void:
		if id >= 0:
			main.focus_km(rts.econ.cities[id].pos))
	frame.add_child(_mini)


# --- co klatkę ---------------------------------------------------------------

func update_frame() -> void:
	if rts == null:
		return
	var day := rts.econ.day
	_date.text = "Dzień %d · rok %d" % [day % DAYS_PER_YEAR + 1, day / DAYS_PER_YEAR + 1]
	_cash.text = "Kasa rodu: %s zł" % _thousands(rts.player.cash)
	var far: bool = main.cam_size > FAR_CAM
	for c: EconCity in rts.econ.cities:
		var l: Label = _city_labels[c.id]
		var p: Vector2 = main.screen_of_km(c.pos, 40.0)
		l.visible = not far or c.population > LABEL_MIN_POP_FAR or c.id == rts.player.city_id
		l.position = p + Vector2(-l.size.x * 0.5, -34)
		l.add_theme_color_override("font_color", GOLD if c.id == rts.player.city_id else TEXT)
	_mini.time = rts.time
	_mini.view_rect = _view_rect_km()
	_mini.queue_redraw()
	_flash_t -= get_process_delta_time()
	_flash.visible = _flash_t > 0.0
	_card_t -= get_process_delta_time()
	if _card_t <= 0.0:
		_card_t = 0.35
		_refresh_card()
		_refresh_notes()
		var pop := rts.econ.total_population()
		var unemp := 0.0
		for c: EconCity in rts.econ.cities:
			unemp += c.unemployment() * c.population
		var moving := rts.econ.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving).size()
		_status.text = "świat: %s ludzi · bezrobocie %.0f%% · firm %d · ciężarówek w drodze %d" % [_thousands(pop), unemp / pop * 100.0, rts.econ.businesses.size(), moving]


func _view_rect_km() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var a: Vector2 = main.ground_km(Vector2.ZERO)
	var b: Vector2 = main.ground_km(vs)
	var c: Vector2 = main.ground_km(Vector2(vs.x, 0))
	var d: Vector2 = main.ground_km(Vector2(0, vs.y))
	var r := Rect2(a, Vector2.ZERO).expand(b).expand(c).expand(d)
	return r


func _thousands(v: float) -> String:
	var neg := v < 0.0
	var s := str(int(roundf(absf(v))))
	var out := ""
	for i in s.length():
		out += s[i]
		if (s.length() - i - 1) % 3 == 0 and i < s.length() - 1:
			out += " "
	return ("-" if neg else "") + out


func on_speed(i: int) -> void:
	for j in _speed_btns.size():
		_speed_btns[j].button_pressed = j == i


func typing() -> bool:
	return false


func flash(text: String) -> void:
	_flash.text = text
	_flash_t = 3.0


func on_key(k: int) -> void:
	match k:
		KEY_SPACE:
			main.set_speed(0 if main.speed_i != 0 else 1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			main.set_speed(k - KEY_1)
		KEY_B:
			open_build(-1)
		KEY_M:
			open_mine()
		KEY_K:
			open_kurier()
		KEY_L:
			select_next_unit()
		KEY_ESCAPE:
			if _kurier != null:
				_close_kurier()
			elif _window != null:
				close_window()
			elif not pick_mode.is_empty():
				cancel_pick()
			else:
				main.selected = {}
				on_selection()


func select_next_unit() -> void:
	var ids: Array = rts.units.keys()
	if ids.is_empty():
		return
	var cur := int(main.selected.get("id", -1)) if str(main.selected.get("kind", "")) == "unit" else -1
	var idx := (ids.find(cur) + 1) % ids.size()
	main.selected = {"kind": "unit", "id": ids[idx]}
	var u: RtsUnit = rts.units[ids[idx]]
	var at := u.pos
	if u.inside >= 0:
		at = rts.business_pos(rts.econ.business(u.inside))
	main.focus_km(at, minf(main.cam_size, 1600.0))
	on_selection()


# --- tryb wskazywania na mapie ------------------------------------------------

func start_pick(mode: Dictionary, hint: String) -> void:
	pick_mode = mode
	flash(hint + "  (PPM albo Esc: anuluj)")
	_flash_t = 1e9


func cancel_pick() -> bool:
	if pick_mode.is_empty():
		return false
	pick_mode = {}
	_flash_t = 0.0
	return true


func handle_pick_click(screen: Vector2) -> bool:
	if pick_mode.is_empty():
		return false
	var mode := pick_mode
	pick_mode = {}
	_flash_t = 0.0
	var target: Dictionary = main.pick(screen)
	var city: int = int(target["id"]) if str(target.get("kind", "")) == "city" else int(main.nearest_city(main.ground_km(screen)))
	match str(mode["kind"]):
		"work":
			if str(target.get("kind", "")) != "business":
				flash("Kliknij budynek firmy.")
			else:
				var why := rts.order_work(int(mode["unit"]), int(target["id"]))
				flash(why if why != "" else "Idzie do pracy.")
		"build":
			var why := rts.build(str(mode["type"]), city)
			flash(why if why != "" else "Budowa ruszyła: %s." % rts.econ.cities[city].name)
		"truck_go":
			var why := rts.truck_go(int(mode["truck"]), city, str(mode.get("good", "")))
			flash(why if why != "" else "Jedzie do: %s." % rts.econ.cities[city].name)
		"route":
			var tr: EconTruck = rts.econ.trucks.get(int(mode["truck"]))
			if tr != null:
				rts.truck_route(tr.id, tr.city_id if not tr.moving else tr.to_city, city, str(mode["good"]))
				flash("Trasa stała: %s → %s." % [rts.econ.good_name(str(mode["good"])), rts.econ.cities[city].name])
	on_selection()
	return true


func is_mine_truck(id: int) -> bool:
	var tr: EconTruck = rts.econ.trucks.get(id)
	var comp := rts.haulage()
	return tr != null and comp != null and tr.company_id == comp.id


# --- karta zaznaczenia ----------------------------------------------------------

func on_selection() -> void:
	_card_t = 0.0


func _clear(box: Control) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


func _row(key: String, value: String, color := TEXT) -> void:
	var h := HBoxContainer.new()
	var k := _label(key, SMALL, DIM)
	k.custom_minimum_size.x = 140
	h.add_child(k)
	var v := _label(value, FONT, color)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = CARD_W - 170
	h.add_child(v)
	_card_box.add_child(h)


func _actions(buttons: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for b: Button in buttons:
		flow.add_child(b)
	_card_box.add_child(flow)


func _refresh_card() -> void:
	_clear(_card_box)
	var sel: Dictionary = main.selected
	match str(sel.get("kind", "")):
		"unit":
			_unit_card(rts.units.get(int(sel["id"])))
		"truck":
			_truck_card(rts.econ.trucks.get(int(sel["id"])))
		"business":
			_business_card(rts.econ.business(int(sel["id"])))
		"city":
			_city_card(rts.econ.cities[int(sel["id"])])
		_:
			_home_card()


func _home_card() -> void:
	_card_box.add_child(_label("Ród %s" % EconNames.family_genitive(EconPopulation.family_last(rts.player)), HEAD, GOLD))
	_row("dom", rts.home_city().name)
	_row("ludzie", ", ".join(rts.units.values().map(func(u: RtsUnit) -> String: return u.first)))
	_row("firmy", str(rts.player_businesses().size()))
	_row("ciężarówki", str(rts.player_trucks().size()))
	var hint := _label("LPM: zaznacz człowieka, ciężarówkę, firmę albo miasto. PPM: rozkaz dla zaznaczonego (idź, pracuj tu, jedź do miasta). WASD: kamera, kółko: zoom, spacja: pauza.", SMALL, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = CARD_W - 30
	_card_box.add_child(hint)


func _unit_card(u: RtsUnit) -> void:
	if u == null:
		return
	_card_box.add_child(_label(u.full_name(), HEAD, GOLD))
	_row("co robi", u.reason)
	_row("zarobił%s" % ("a" if u.female else ""), "%s zł" % _thousands(u.earned))
	_actions([
		_button("Do pracy… (wskaż firmę)", func() -> void: start_pick({"kind": "work", "unit": u.id}, "Kliknij firmę, w której %s ma pracować." % u.first)),
		_button("Stój", func() -> void:
			rts.order_idle(u.id)
			on_selection()),
		_button("Pokaż", func() -> void: main.focus_km(u.pos if u.inside < 0 else rts.business_pos(rts.econ.business(u.inside)), minf(main.cam_size, 1500.0))),
	])
	var hint := _label("PPM na mapie: idź tam. PPM na firmie: pracuj tam.", SMALL, DIM)
	_card_box.add_child(hint)


func _truck_card(tr: EconTruck) -> void:
	if tr == null:
		return
	var comp: EconBusiness = rts.econ.business(tr.company_id)
	var mine := is_mine_truck(tr.id)
	_card_box.add_child(_label("Ciężarówka" + (" (twoja)" if mine else ""), HEAD, GOLD if mine else TEXT))
	if comp != null:
		_row("firma", comp.name)
		var owner := rts.econ.actor(comp.owner_id)
		if owner != null:
			_row("właściciel", owner.full_name())
	_row("stan", rts.truck_status(tr))
	_row("bak", "%.0f / %.0f l" % [tr.tank, float(rts.econ.data["transport"]["tank_km"]) * float(rts.econ.data["transport"]["fuel_per_km"])])
	_row("kursów", "%d · zysk łącznie %s zł" % [tr.trips, _thousands(tr.profit_total)])
	if not mine:
		return
	_row("zadanie", {"auto": "handluje sama (szuka kursów jak inni przewoźnicy)", "manual": "czeka na rozkazy", "route": "trasa stała"}.get(tr.mode, tr.mode))
	var good_pick := OptionButton.new()
	for g: String in ROUTE_GOODS:
		good_pick.add_item(rts.econ.good_name(g))
	good_pick.select(maxi(0, ROUTE_GOODS.find(_route_good)))
	good_pick.item_selected.connect(func(i: int) -> void: _route_good = ROUTE_GOODS[i])
	_actions([
		_button("Handluj sama", func() -> void:
			rts.truck_auto(tr.id)
			on_selection()),
		_button("Jedź do… (wskaż miasto)", func() -> void: start_pick({"kind": "truck_go", "truck": tr.id}, "Kliknij miasto, do którego ma jechać.")),
	])
	var h := HBoxContainer.new()
	h.add_child(_label("towar:", SMALL, DIM))
	h.add_child(good_pick)
	_card_box.add_child(h)
	_actions([
		_button("Wieź stąd towar do…", func() -> void: start_pick({"kind": "truck_go", "truck": tr.id, "good": _route_good}, "Kliknij miasto: kupi tu %s i zawiezie." % rts.econ.good_name(_route_good))),
		_button("Trasa stała do…", func() -> void: start_pick({"kind": "route", "truck": tr.id, "good": _route_good}, "Kliknij miasto docelowe trasy stałej (%s)." % rts.econ.good_name(_route_good))),
	])


func _business_card(b: EconBusiness) -> void:
	if b == null:
		return
	var c := rts.econ.city_of(b)
	var mine := rts.player.businesses.has(b.id)
	var r: Dictionary = rts.econ.recipe(b.type)
	_card_box.add_child(_label(b.name, HEAD, GOLD if mine else TEXT))
	_row("gdzie", c.name)
	var owner := rts.econ.actor(b.owner_id)
	if owner != null:
		_row("właściciel", owner.full_name() + (" (ty)" if mine else ""))
	_row("stan", STATUS_PL.get(b.status, b.status) + ("" if b.project.is_empty() or b.status == "building" else " · rozbudowa"))
	if b.type == "haulage":
		_row("ciężarówki", str(b.trucks.size()))
	else:
		_row("poziom", "%d · ludzie %d / %d" % [b.level, int(b.workers + b.extra_workers), int(float(r["workers"]) * b.level)])
		var out: String = r["out"]
		var m := c.market(out)
		_row("produkuje", "%s: %.0f j. dziennie" % [rts.econ.good_name(out), b.produced_today])
		_row("cena tutaj", "%.2f zł (×%.2f bazowej)" % [m.price, m.price / m.base])
		var ins: Dictionary = r["inputs"]
		if not ins.is_empty():
			_row("potrzebuje", ", ".join(ins.keys().map(func(g: String) -> String: return rts.econ.good_name(g))))
		if b.status == "building" and not b.project.is_empty():
			var mats: Dictionary = b.project["materials"]
			var missing: Array = mats.keys().filter(func(g: String) -> bool: return float(mats[g]) > 0.01)
			_row("budowa", "czeka na: %s" % ", ".join(missing.map(func(g: String) -> String: return rts.econ.good_name(g))) if not missing.is_empty() else "zostało %d dni" % int(b.project["days"]))
	if mine:
		_row("kasa firmy", "%s zł · zysk %s zł/dzień" % [_thousands(b.cash), _thousands(b.profit_ema)], GOOD if b.profit_ema >= 0.0 else BAD)
		_actions([
			_button("Dopłać 10 tys.", func() -> void:
				rts.move_cash(b.id, 10000.0)
				on_selection()),
			_button("Wypłać 10 tys.", func() -> void:
				rts.move_cash(b.id, -10000.0)
				on_selection()),
		])
	if b.type != "haulage" and b.status == "active":
		var btns: Array = []
		for u: RtsUnit in rts.units.values():
			btns.append(_button("Wyślij: %s" % u.first, func() -> void:
				var why := rts.order_work(u.id, b.id)
				flash(why if why != "" else "%s idzie do pracy." % u.first)
				on_selection()))
		_actions(btns)


func _city_card(c: EconCity) -> void:
	_card_box.add_child(_label(c.name, HEAD, GOLD if c.id == rts.player.city_id else TEXT))
	_row("ludność", _thousands(c.population))
	_row("bezrobocie", "%.0f%% · płaca %.0f zł" % [c.unemployment() * 100.0, c.wage], BAD if c.unemployment() > 0.15 else TEXT)
	_row("potrzeby", "zaspokojone w %.0f%%" % (c.satisfaction * 100.0), BAD if c.satisfaction < 0.5 else TEXT)
	var res: Array = c.resources.keys().filter(func(k: String) -> bool: return float(c.resources[k]) > 0.05)
	_row("złoża", ", ".join(res.map(func(k: String) -> String: return RESOURCE_PL.get(k, k))) if not res.is_empty() else "brak")
	var cheap: Array = []
	var dear: Array = []
	for g: String in ROUTE_GOODS:
		var m := c.market(g)
		var avg := 0.0
		for o: EconCity in rts.econ.cities:
			avg += o.market(g).price
		avg /= rts.econ.cities.size()
		var rel := m.price / avg
		if rel < 0.8 and m.stock() > 100.0:
			cheap.append([rel, rts.econ.good_name(g)])
		elif rel > 1.25:
			dear.append([rel, rts.econ.good_name(g)])
	cheap.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	dear.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	_row("tanio tu", ", ".join(cheap.slice(0, 4).map(func(x: Array) -> String: return "%s (−%.0f%%)" % [x[1], (1.0 - x[0]) * 100.0])) if not cheap.is_empty() else "—", GOOD)
	_row("drogo tu", ", ".join(dear.slice(0, 4).map(func(x: Array) -> String: return "%s (+%.0f%%)" % [x[1], (x[0] - 1.0) * 100.0])) if not dear.is_empty() else "—", WARN)
	var n := rts.econ.businesses.values().filter(func(b: EconBusiness) -> bool: return b.city_id == c.id and b.status != "closed").size()
	_row("firm", str(n))
	_actions([_button("Buduj tutaj…", func() -> void: open_build(c.id))])


# --- meldunki ------------------------------------------------------------------

func _refresh_notes() -> void:
	_clear(_notes)
	var lines: Array = []
	for n: String in rts.notes.slice(maxi(0, rts.notes.size() - 3)):
		lines.append([n, GOLD])
	var entries := rts.econ.news.entries
	var count := 0
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if int(e["severity"]) < 2 or rts.econ.day - int(e["day"]) > 6:
			continue
		lines.append(["d%d  %s" % [int(e["day"]), str(e["text"])], BAD])
		count += 1
		if count >= NOTES - 3:
			break
	for ln: Array in lines:
		var l := _label(str(ln[0]), SMALL, ln[1])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
		_notes.add_child(l)


# --- okna ----------------------------------------------------------------------

func close_window() -> void:
	if _window != null:
		_window.queue_free()
		_window = null


func _open_window(title: String) -> VBoxContainer:
	close_window()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	_window = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var t := _label(title, HEAD, ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_button("✕", close_window))
	v.add_child(head)
	panel.resized.connect(func() -> void: panel.position = (size - panel.size) * 0.5)
	return v


func open_build(city_id: int) -> void:
	var v := _open_window("Budowa" + ("" if city_id < 0 else ": " + rts.econ.cities[city_id].name))
	var where := city_id if city_id >= 0 else rts.player.city_id
	var hint := _label("Wybierz, co budować. %s" % ("Potem kliknij miasto na mapie." if city_id < 0 else ""), SMALL, DIM)
	v.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	for type: String in rts.econ.recipes.keys():
		if type == "haulage":
			continue
		var r: Dictionary = rts.econ.recipe(type)
		var cost := EconInvest.build_cost(rts.econ, type, rts.econ.cities[where]) * 1.25
		var why := rts.build_problem(type, where)
		var b := _button(str(r["name"]), func() -> void:
			close_window()
			if city_id >= 0:
				var res := rts.build(type, city_id)
				flash(res if res != "" else "Budowa ruszyła.")
			else:
				start_pick({"kind": "build", "type": type}, "Kliknij miasto, w którym postawić: %s." % str(r["name"])))
		b.disabled = city_id >= 0 and why != ""
		b.tooltip_text = why
		grid.add_child(b)
		grid.add_child(_label("%s zł" % _thousands(cost), SMALL, DIM))
		var res_name: String = r.get("resource", "")
		grid.add_child(_label(("wymaga: " + RESOURCE_PL.get(res_name, res_name)) if res_name != "" else "", SMALL, WARN if why.begins_with("w okolicy") else DIM))
	v.add_child(HSeparator.new())
	v.add_child(_button("Kup ciężarówkę (firma przewozowa rodu)", func() -> void:
		var why := rts.buy_truck()
		flash(why if why != "" else "Kupiono ciężarówkę: handluje sama, zmień jej zadanie na karcie.")
		close_window()))


func open_mine() -> void:
	var v := _open_window("Moje firmy i ciężarówki")
	var list := rts.player_businesses()
	if list.is_empty() and rts.player_trucks().is_empty():
		v.add_child(_label("Ród nie ma jeszcze firm. Budowa (B) albo wyślij ludzi do pracy u innych.", FONT, DIM))
	for b: EconBusiness in list:
		var h := HBoxContainer.new()
		var l := _label("%s (%s) · %s · kasa %s zł · zysk %s zł/d" % [b.name, rts.econ.city_of(b).name, STATUS_PL.get(b.status, b.status), _thousands(b.cash), _thousands(b.profit_ema)], SMALL, TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_button("Pokaż", func() -> void:
			main.selected = {"kind": "business", "id": b.id}
			main.focus_km(rts.business_pos(b), minf(main.cam_size, 2000.0))
			close_window()
			on_selection()))
		v.add_child(h)
	for tr: EconTruck in rts.player_trucks():
		var h := HBoxContainer.new()
		var l := _label("Ciężarówka: %s" % rts.truck_status(tr), SMALL, TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_button("Pokaż", func() -> void:
			main.selected = {"kind": "truck", "id": tr.id}
			main.focus_km(rts.econ.truck_pos(tr, rts.time), minf(main.cam_size, 3000.0))
			close_window()
			on_selection()))
		v.add_child(h)


func open_kurier() -> void:
	_close_kurier()
	_kurier = KurierPage.new()
	add_child(_kurier)
	_kurier.open(rts.econ)
	_kurier.closed.connect(_close_kurier)
	main.set_speed(0)


func _close_kurier() -> void:
	if _kurier != null:
		_kurier.queue_free()
		_kurier = null
