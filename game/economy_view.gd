# EconomyView — podgląd świata, który żyje sam (iteracja 5, E9). Mapa sieci miast
# z jadącymi ciężarówkami, panel wybranego miasta (ceny, firmy, wykresy),
# najbogatsze rody i kronika świata. Gracza tu jeszcze nie ma: patrzymy.
# Tylko czyta EconWorld i woła step_day(). Spacja: pauza, 1–4: tempo.
extends Control


const BG := Color(0.07, 0.09, 0.12)
const PANEL := Color(0.1, 0.13, 0.17, 0.97)
const PANEL_BORDER := Color(0.22, 0.28, 0.36)
const TEXT := Color(0.88, 0.92, 0.98)
const DIM := Color(0.58, 0.64, 0.74)
const ACCENT := Color(0.45, 0.78, 1.0)
const GOOD := Color(0.45, 0.88, 0.5)
const WARN := Color(1.0, 0.78, 0.35)
const BAD := Color(1.0, 0.45, 0.4)
const FONT := 16
const SMALL := 13
const HEAD := 20
const SIDE_W := 430
const NEWS_H := 190
const NEWS_LINES := 8
const SPEEDS := [0.0, 1.0, 4.0, 12.0]
const SPEED_LABELS := ["⏸", "1×", "4×", "12×"]
const REFRESH_S := 0.4
const DAYS_PER_YEAR := 360
const PRICE_GOODS := ["fuel", "bread", "grain", "crude", "steel", "lumber", "meat", "appliances"]

var w: EconWorld
var canvas: EconMapCanvas
var speed_i := 1
var accum := 0.0
var _refresh := 0.0
var _side: VBoxContainer
var _news: VBoxContainer
var _status: Label
var _day_label: Label
var _speed_buttons: Array[Button] = []
var _mode: OptionButton
var _loading: Label
var _paper_btn: Button
var _paper: Control            # nakładka z gazetą (null = zamknięta)
var _paper_day := 0            # doba końca pokazywanego numeru
var _last_issue_day := 0


func _ready() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_loading = _label("Świat się rodzi: miasta, drogi, firmy, ludzie…", HEAD, TEXT)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_loading)
	await get_tree().process_frame
	await get_tree().process_frame
	var data := DataLoader.load_json("res://data/economy.json")
	var seed_env := OS.get_environment("ECON_SEED")
	var seed := int(seed_env) if seed_env != "" else int(data["world"]["seed"])
	w = EconWorld.new(seed, data)
	_loading.queue_free()
	_build()
	_refresh_all()


func _make_theme() -> Theme:
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
	th.set_stylebox("normal", "Button", btn.call(Color(0.15, 0.19, 0.25), PANEL_BORDER))
	th.set_stylebox("hover", "Button", btn.call(Color(0.2, 0.26, 0.34), ACCENT.darkened(0.3)))
	th.set_stylebox("pressed", "Button", btn.call(Color(0.22, 0.38, 0.55), ACCENT))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = PANEL_BORDER
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


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	# Górny pasek.
	var top := PanelContainer.new()
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	top.add_child(bar)
	bar.add_child(_label("ŚWIAT", HEAD, ACCENT))
	_day_label = _label("", FONT, TEXT)
	_day_label.custom_minimum_size.x = 170
	bar.add_child(_day_label)
	for i in SPEEDS.size():
		var b := Button.new()
		b.text = SPEED_LABELS[i]
		b.toggle_mode = true
		b.custom_minimum_size.x = 46
		b.pressed.connect(_set_speed.bind(i))
		bar.add_child(b)
		_speed_buttons.append(b)
	bar.add_child(_label("   Kolor miast:", SMALL, DIM))
	_mode = OptionButton.new()
	_mode.add_item("dobrobyt")
	_mode.add_item("bezrobocie")
	for g: String in PRICE_GOODS:
		_mode.add_item("cena: %s" % w.good_name(g))
	_mode.item_selected.connect(_on_mode)
	bar.add_child(_mode)
	_paper_btn = Button.new()
	_paper_btn.text = "Kurier"
	_paper_btn.pressed.connect(_open_paper)
	bar.add_child(_paper_btn)
	_status = _label("", SMALL, DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	# Środek: mapa i panel boczny.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	root.add_child(mid)
	canvas = EconMapCanvas.new()
	canvas.w = w
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.city_clicked.connect(_on_city)
	mid.add_child(canvas)
	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size.x = SIDE_W
	mid.add_child(side_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 6)
	scroll.add_child(_side)
	# Dół: kronika świata.
	var news_panel := PanelContainer.new()
	news_panel.custom_minimum_size.y = NEWS_H
	root.add_child(news_panel)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 1)
	news_panel.add_child(nv)
	nv.add_child(_label("KRONIKA ŚWIATA", SMALL, ACCENT))
	_news = VBoxContainer.new()
	_news.add_theme_constant_override("separation", 0)
	nv.add_child(_news)
	_set_speed(speed_i)


func _set_speed(i: int) -> void:
	speed_i = i
	for j in _speed_buttons.size():
		_speed_buttons[j].button_pressed = j == i


func _on_mode(idx: int) -> void:
	if idx == 0:
		canvas.mode = "prosperity"
	elif idx == 1:
		canvas.mode = "unemployment"
	else:
		canvas.mode = "price"
		canvas.price_good = PRICE_GOODS[idx - 2]
	_refresh_all()


func _on_city(id: int) -> void:
	canvas.selected = id
	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE:
			_set_speed(0 if speed_i != 0 else 1)
		elif k >= KEY_1 and k <= KEY_4:
			_set_speed(k - KEY_1)
		elif k == KEY_ESCAPE:
			if _paper != null:
				_close_paper()
			else:
				_on_city(-1)
		elif k == KEY_K:
			_open_paper()


func _process(delta: float) -> void:
	if w == null or canvas == null:
		return
	accum += delta * float(SPEEDS[speed_i])
	if accum >= 1.0:
		w.step_day()
		accum = minf(accum - 1.0, 0.99)
	canvas.time = float(w.day - 1) + accum
	canvas.queue_redraw()
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_refresh_all()


# --- panele ------------------------------------------------------------------

func _refresh_all() -> void:
	if w == null or _side == null:
		return
	var year := w.day / DAYS_PER_YEAR + 1
	_day_label.text = "Dzień %d · rok %d" % [w.day % DAYS_PER_YEAR + 1, year]
	var unemp := 0.0
	for c: EconCity in w.cities:
		unemp += c.unemployment() * c.population
	var pop := w.total_population()
	var firms := w.businesses.values().filter(func(b: EconBusiness) -> bool: return b.status != "closed").size()
	var moving := w.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving).size()
	var issue_day := (w.day / EconGazette.MONTH_DAYS) * EconGazette.MONTH_DAYS
	if issue_day > _last_issue_day and issue_day > 0:
		_paper_btn.text = "Kurier: nowy numer!"
		_paper_btn.add_theme_color_override("font_color", WARN)
	_status.text = "ludność %s · bezrobocie %.1f%% · firm %d · ciężarówek %d (w drodze %d) · pieniądze w obiegu %.0f mln zł" % [
		_thousands(pop), unemp / pop * 100.0, firms, w.trucks.size(), moving, w.money_total() / 1e6]
	_clear(_side)
	if canvas.selected >= 0:
		_city_panel(w.cities[canvas.selected])
	else:
		_world_panel()
	_news_panel()


func _clear(box: Control) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


func _thousands(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		if (n - i - 1) % 3 == 0 and i < n - 1:
			out += " "
	return out


func _section(text: String) -> void:
	var l := _label(text, SMALL, ACCENT)
	_side.add_child(l)


func _row(key: String, value: String, color := TEXT) -> void:
	var h := HBoxContainer.new()
	var k := _label(key, SMALL, DIM)
	k.custom_minimum_size.x = 150
	h.add_child(k)
	h.add_child(_label(value, FONT, color))
	_side.add_child(h)


func _spark(values: Array, base := NAN, col := ACCENT) -> void:
	var s := EconSparkline.new()
	s.custom_minimum_size = Vector2(SIDE_W - 40, 48)
	s.set_data(values, base, col)
	_side.add_child(s)


func _world_panel() -> void:
	_side.add_child(_label("Świat bez gracza", HEAD, TEXT))
	var hint := _label("Kliknij miasto na mapie. Kółko: przybliżenie, prawy przycisk: przesuwanie, spacja: pauza.", SMALL, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = SIDE_W - 40
	_side.add_child(hint)
	_section("NAJBOGATSZE RODY")
	var fams := {}
	for a: EconActor in w.living_actors():
		var f: Dictionary = fams.get(a.family_id, {"wealth": 0.0, "people": [], "firms": 0, "last": a.last})
		f["wealth"] = float(f["wealth"]) + w.actor_wealth(a)
		(f["people"] as Array).append(a)
		f["firms"] = int(f["firms"]) + a.businesses.size()
		fams[a.family_id] = f
	var list: Array = fams.values()
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["wealth"]) > float(y["wealth"]))
	for f: Dictionary in list.slice(0, 10):
		var people: Array = f["people"]
		var head: EconActor = people[0]
		var names := ", ".join(people.map(func(p: EconActor) -> String: return p.first))
		var line := "Ród %s · %.1f mln zł · firm %d" % [EconNames.family_genitive(EconPopulation.family_last(head)), float(f["wealth"]) / 1e6, int(f["firms"])]
		_side.add_child(_label(line, FONT, TEXT))
		var sub := _label("   %s (%s)" % [names, w.cities[head.city_id].name], SMALL, DIM)
		_side.add_child(sub)
	_section("CENY W ŚWIECIE (średnia / bazowa)")
	for g: String in PRICE_GOODS:
		var s := 0.0
		for c: EconCity in w.cities:
			s += c.market(g).price / c.market(g).base
		s /= w.cities.size()
		_row(w.good_name(g), "×%.2f" % s, _price_color(s))
	_section("PAŃSTWO")
	_row("skarb", "%.1f mln zł" % (w.state_cash / 1e6))
	_row("budżetówka", _thousands(w.cities.reduce(func(acc: float, c: EconCity) -> float: return acc + c.public_workers, 0.0)) + " osób")


func _price_color(mult: float) -> Color:
	if mult > 2.0:
		return BAD
	if mult > 1.3:
		return WARN
	if mult < 0.6:
		return ACCENT
	return GOOD


func _city_panel(c: EconCity) -> void:
	_side.add_child(_label(c.name, HEAD, TEXT))
	_row("ludność", _thousands(c.population))
	_row("bezrobocie", "%.1f%%" % (c.unemployment() * 100.0), BAD if c.unemployment() > 0.15 else TEXT)
	_row("płaca dzienna", "%.1f zł" % c.wage)
	_row("potrzeby zaspokojone", "%.0f%%" % (c.satisfaction * 100.0), BAD if c.satisfaction < 0.6 else GOOD if c.satisfaction > 0.85 else WARN)
	_row("oszczędności / os.", "%.0f zł" % (c.cash / maxf(c.population, 1.0)))
	var res: Array = []
	for r: String in c.resources.keys():
		if float(c.resources[r]) > 0.05:
			res.append(r)
	_row("złoża", ", ".join(res.map(func(r: String) -> String: return RESOURCE_PL.get(r, r))) if not res.is_empty() else "brak")
	if c.history.has("satisfaction"):
		_section("ZADOWOLENIE W CZASIE")
		_spark(c.history["satisfaction"], NAN, GOOD)
	if canvas.mode == "price":
		var m := c.market(canvas.price_good)
		_section("CENA: %s (przerywana = bazowa)" % w.good_name(canvas.price_good).to_upper())
		_spark(m.history, m.base, WARN)
	_section("RYNEK  (cena · ×bazowa · zapas w dniach)")
	for g: String in w.goods.keys():
		var m := c.market(g)
		if m.demand_ema < 0.5 and m.stock() < 1.0:
			continue
		var mult := m.price / m.base
		var trend := ""
		if m.history.size() >= 2:
			var prev: float = m.history[m.history.size() - 2]
			trend = " ▲" if m.price > prev * 1.03 else " ▼" if m.price < prev * 0.97 else ""
		var days := m.stock() / maxf(m.demand_ema, 1e-3)
		var line := "%s · ×%.2f · %s" % [_money(m.price), mult, "∞" if days > 99.0 else "%.0f" % days]
		_row(w.good_name(g) + trend, line, _price_color(mult))
	_section("FIRMY")
	var firms: Array = w.businesses.values().filter(func(b: EconBusiness) -> bool: return b.city_id == c.id and b.status != "closed")
	firms.sort_custom(func(x: EconBusiness, y: EconBusiness) -> bool: return x.level > y.level)
	for b: EconBusiness in firms.slice(0, 14):
		var owner := w.actor(b.owner_id)
		var st: String = STATUS_PL.get(b.status, b.status)
		var extra := " · %d ciężarówek" % b.trucks.size() if b.type == "haulage" else " · poz. %d · %d os." % [b.level, int(b.workers)]
		_side.add_child(_label("%s%s%s" % [b.name, extra, "" if st == "" else " · " + st], SMALL, TEXT if b.status == "active" else WARN))
		if owner != null:
			_side.add_child(_label("      właściciel: %s" % owner.full_name(), SMALL, DIM))
	if firms.size() > 14:
		_side.add_child(_label("…i %d innych" % (firms.size() - 14), SMALL, DIM))


const RESOURCE_PL := {"fertile": "żyzna ziemia", "forest": "las", "oil": "ropa", "iron": "ruda żelaza", "limestone": "wapień"}
const STATUS_PL := {"active": "", "building": "w budowie", "burned": "po pożarze", "strike": "strajk"}


func _money(v: float) -> String:
	if v >= 1000.0:
		return "%.0f zł" % v
	return "%.2f zł" % v


func _news_panel() -> void:
	_clear(_news)
	var shown := 0
	for i in range(w.news.entries.size() - 1, -1, -1):
		var e: Dictionary = w.news.entries[i]
		if int(e["severity"]) < 1:
			continue
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "d%d   %s" % [int(e["day"]), str(e["text"])]
		b.add_theme_font_size_override("font_size", SMALL)
		b.add_theme_color_override("font_color", BAD if int(e["severity"]) >= 2 else TEXT)
		b.clip_text = true
		b.pressed.connect(_on_city.bind(int(e["city"])))
		_news.add_child(b)
		shown += 1
		if shown >= NEWS_LINES:
			break


# --- gazeta ------------------------------------------------------------------

const PAPER_BG := Color(0.95, 0.92, 0.84)
const PAPER_INK := Color(0.12, 0.1, 0.08)
const PAPER_DIM := Color(0.35, 0.3, 0.25)
const PAPER_RULE := Color(0.2, 0.17, 0.13)
const PAPER_W := 980


func _open_paper() -> void:
	if w == null:
		return
	var last := (w.day / EconGazette.MONTH_DAYS) * EconGazette.MONTH_DAYS
	_paper_day = maxi(last, EconGazette.MONTH_DAYS)
	_last_issue_day = last
	_paper_btn.text = "Kurier"
	_paper_btn.remove_theme_color_override("font_color")
	_set_speed(0)
	_show_paper()


func _close_paper() -> void:
	if _paper != null:
		_paper.queue_free()
		_paper = null


func _paper_label(text: String, size: int, color := PAPER_INK, wrap := true) -> Label:
	var l := _label(text, size, color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _show_paper() -> void:
	_close_paper()
	var issue := EconGazette.issue(w, _paper_day)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_paper = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var page := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PAPER_BG
	st.set_corner_radius_all(2)
	st.set_content_margin_all(26)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 12
	page.add_theme_stylebox_override("panel", st)
	page.custom_minimum_size.x = PAPER_W
	center.add_child(page)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	page.add_child(v)
	var mast := _paper_label("KURIER ŚWIATA", 40, PAPER_INK, false)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(mast)
	var meta := _paper_label("nr %d · %s · cena 2 zł" % [int(issue["number"]), str(issue["date"])], SMALL, PAPER_DIM, false)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(meta)
	v.add_child(_rule())
	v.add_child(_paper_label(str(issue["headline"]), 30))
	v.add_child(_paper_label(str(issue["lead"]), FONT, PAPER_DIM))
	v.add_child(_rule())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	for col: Dictionary in issue["columns"]:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = PAPER_W / 2 - 50
		box.add_child(_paper_label(str(col["title"]).to_upper(), SMALL, PAPER_RULE, false))
		for line: String in col["lines"]:
			box.add_child(_paper_label("• " + line, SMALL))
		grid.add_child(box)
	v.add_child(_rule())
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	v.add_child(nav)
	var prev := Button.new()
	prev.text = "‹ poprzedni numer"
	prev.disabled = _paper_day <= EconGazette.MONTH_DAYS
	prev.pressed.connect(func() -> void:
		_paper_day -= EconGazette.MONTH_DAYS
		_show_paper())
	nav.add_child(prev)
	var close := Button.new()
	close.text = "zamknij (Esc)"
	close.pressed.connect(_close_paper)
	nav.add_child(close)
	var next := Button.new()
	next.text = "następny numer ›"
	next.disabled = _paper_day + EconGazette.MONTH_DAYS > w.day
	next.pressed.connect(func() -> void:
		_paper_day += EconGazette.MONTH_DAYS
		_show_paper())
	nav.add_child(next)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = PAPER_RULE
	r.custom_minimum_size.y = 2
	return r
