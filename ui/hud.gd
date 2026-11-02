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
const JOB_ORDER := ["woodcutter", "sawyer", "carpenter", "carrier", "forager", "laborer", "thief", "none"]
const JOB_HINTS := {
	"woodcutter": "ścina drzewa, nosi kłody do tartaku",
	"sawyer": "w tartaku tnie kłody na deski",
	"carpenter": "w stolarni robi krzesła z desek (jakość = umiejętność)",
	"carrier": "kupuje jedzenie, nosi opał, wozi deski i krzesła",
	"forager": "zbiera jedzenie w lesie (za darmo, mało; zimą prawie nic)",
	"laborer": "dniówka w dworze: pewny grosz, bez rozwoju",
	"thief": "kradnie na targu: szybki grosz, ale złapany idzie do aresztu, grzywna i wstyd",
	"none": "pomaga w domu: zakupy i opał, gdy trzeba",
}
const JOB_BUTTONS := {
	"woodcutter": "Drwal", "sawyer": "Tracz", "carpenter": "Stolarz", "carrier": "Nosiciel",
	"forager": "Zbieracz", "laborer": "Dniówka", "thief": "Złodziej", "none": "Bez przydziału",
}
const SKILL_LABELS := { "chop": "rąbanie", "saw": "piłowanie", "craft": "stolarka", "forage": "zbieractwo", "steal": "złodziejstwo" }

var main: Node
var world: SimWorld
var camera: Camera3D

var _top_date: Label
var _top_speed: Array = []
var _top_res: RichTextLabel
var _family_title: Label
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
	h.add_child(_button("Pomoc (F1)", func(): _help.visible = not _help.visible, 17))


func _update_top() -> void:
	var c := world.clock
	var hm := c.hour_minute()
	_top_date.text = "%s · rok %d · dzień %d/%d · %02d:%02d" % [c.season_label(), c.current_year() + 1,
		c.day_of_season() + 1, c.days_per_season, hm.x, hm.y]
	for i in _top_speed.size():
		_top_speed[i].button_pressed = c.speed == i
	var hh := world.household
	var home := world.home()
	var days := hh.days_to_rent(c.day_index())
	var cash_col := "#e8d27a" if hh.cash >= hh.rent else "#ff8a70"
	var t := "[color=%s]Monety: %d zł[/color]" % [cash_col, int(hh.cash)]
	if hh.debt > 0.0:
		t += "   [color=#ff6a55]Dług: %d zł[/color]" % int(ceil(hh.debt))
	var rent_col := "#ff8a70" if days <= 1 and hh.cash < hh.rent else ("#ffd070" if days <= 1 else "#d8ccb0")
	t += "   [color=%s]Czynsz %d zł za %d %s[/color]" % [rent_col, int(hh.rent), days, "dzień" if days == 1 else "dni"]
	var food_col := "#ff8a70" if home.amount("food") < 6 else "#d8ccb0"
	t += "   [color=%s]Jedzenie: %d[/color]" % [food_col, home.amount("food")]
	var need := float(world.balance["economy"]["firewood_per_day"].get(c.current_season(), 0.0))
	var fire_col := "#ff8a70" if need > 0.0 and home.amount("log") < need * 2.0 else "#d8ccb0"
	t += "   [color=%s]Opał: %d[/color]" % [fire_col, home.amount("log")]
	var net := hh.last_day_net
	t += "   [color=%s]Wczoraj: %+d zł[/color]" % ["#9be07a" if net >= 0 else "#ff8a70", int(round(net))]
	_top_res.text = t


# --- Panel rodu ---

func _build_family() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(10, 68)
	p.custom_minimum_size = Vector2(380, 0)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_family_title = _label("", 22, Color(1.0, 0.85, 0.45))
	v.add_child(_family_title)
	v.add_child(_label("kliknij osobę, by zaznaczyć i pokazać", 15, DIM))
	_family_box = VBoxContainer.new()
	_family_box.add_theme_constant_override("separation", 4)
	v.add_child(_family_box)


func _update_family() -> void:
	var fam := world.family
	var r := fam.root()
	_family_title.text = "Ród %s%s" % [fam.dynasty, ("  ·  głowa: " + r.name) if r != null else ""]
	var living := fam.living()
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
			b.custom_minimum_size = Vector2(356, 50)
			b.clip_text = true
			_family_box.add_child(b)
			_family_rows[aid] = b
	for p in living:
		var a := world.agent_by_id(p.agent_id)
		var b: Button = _family_rows.get(p.agent_id)
		if a == null or b == null:
			continue
		var stage := fam.stage_of(p)
		var job := "dziecko" if stage == "child" else String(SimJobs.JOB_LABELS.get(a.job, a.job))
		var mark := "♛ " if p.id == fam.root_id else ""
		var extra := ""
		if p.pregnant_left >= 0.0:
			extra = " · w ciąży"
		b.text = "%s%s, %d · %s%s\n   %s" % [mark, p.name, int(fam.age_of(p)), job, extra, _status_short(a)]
		var col := TEXT
		if a.alert or a.hungry_no_food or a.status == "jailed":
			col = BAD
		elif a.disabled() or a.health < 50.0:
			col = WARN
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", col.lightened(0.2))
		var job_col: Color = AgentView.JOB_COLORS["child"] if stage == "child" else AgentView.JOB_COLORS.get(a.job, Color.WHITE)
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
		key = "a:%d" % main.selected_id
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
	var title := _label("%s %s" % [p.name, p.surname], 26, Color(1.0, 0.85, 0.45))
	_info_box.add_child(title)
	_dyn(func():
		var rel := fam.relation_to_root(p)
		return "%s · %d lat · %s" % [rel, int(fam.age_of(p)), fam.stage_label(p)], 17, DIM)
	_dyn(func():
		if p.traits.is_empty():
			return "Cechy: brak szczególnych"
		return "Cechy: " + ", ".join(p.traits.map(func(t): return fam.trait_label(t))), 17)
	var now := _dyn(func(): return "Teraz: " + (a.idle_reason if a.status == "active" else "w areszcie — " + a.idle_reason), 19)
	_info_updaters.append(func(): now.add_theme_color_override("font_color", BAD if a.alert or a.status == "jailed" else GOOD))
	_bar("Zdrowie", func(): return a.health, Color(0.4, 0.75, 0.35))
	_bar("Najedzenie", func(): return a.needs["food"], Color(0.85, 0.7, 0.3))
	_bar("Wyspanie", func(): return a.needs["sleep"], Color(0.4, 0.55, 0.85))
	_dyn(func():
		var parts: Array = []
		for k in ["chop", "saw", "craft", "forage", "steal"]:
			parts.append("%s %.1f" % [SKILL_LABELS[k], a.skill(k)])
		return "Umiejętności: " + " · ".join(parts), 16, DIM)
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
	if fam.stage_of(p) == "child":
		_info_box.add_child(_label("Dziecko — bawi się przy chacie. Do pracy od %d lat." % int(world.balance["aging"]["stages"]["teen"]["min"]), 17, DIM))
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

	var marry := _button("", func():
		fam.set_seeking(p.id, not p.seeking_spouse), 17)
	_info_box.add_child(marry)
	_info_updaters.append(func():
		marry.visible = fam.can_marry(p)
		marry.text = ("Przestań szukać " if p.seeking_spouse else "Szukaj ") + ("żony" if p.sex == "m" else "męża")
		marry.button_pressed = p.seeking_spouse)
	var rel := _button("Puść wolno (wróć do autopilota)", func(): world.release_manual(a.id), 17)
	_info_box.add_child(rel)
	_info_updaters.append(func(): rel.visible = a.controlled)
	_info_box.add_child(_label("PPM na ziemi: idź tam (przejęcie) · PPM na drzewie: zetnij je", 14, DIM))


func _build_building_info(b: SimBuilding) -> void:
	if b == null:
		return
	_info_box.add_child(_label(b.name, 26, Color(1.0, 0.85, 0.45)))
	var hh := world.household
	match b.type:
		"home":
			_dyn(func(): return "Spiżarnia: %d / %d posiłków\nOpał: %d / %d kłód (zużycie: %s/dzień)" % [
				b.amount("food"), int(b.capacity["food"]), b.amount("log"), int(b.capacity["log"]),
				str(world.balance["economy"]["firewood_per_day"].get(world.clock.current_season(), 0))], 18)
			_dyn(func(): return "Czynsz: %d zł co %d dni (następny za %d). Brak = dług, dług > %d zł = areszt." % [
				int(hh.rent), hh.rent_period, hh.days_to_rent(world.clock.day_index()), int(hh.debt_limit)], 16, DIM)
			_info_box.add_child(HSeparator.new())
			_info_box.add_child(_label("Ile trzymać w zapasie (nosiciele i domownicy dokupią / doniosą):", 16, DIM))
			_stepper("Jedzenie", func(): return hh.target_food, func(d): hh.target_food = clampi(hh.target_food + d, 0, int(b.capacity["food"])))
			_stepper("Opał", func(): return hh.target_firewood, func(d): hh.target_firewood = clampi(hh.target_firewood + d, 0, int(b.capacity["log"])))
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
			_dyn(func(): return "Ceny dziś:\n  deski: %.1f zł/szt\n  krzesło: %d–%d zł (wg jakości)\n  jedzenie: %.1f zł/posiłek\n  opał (kupno): %.1f zł/kłoda" % [
				hh.plank_price(), int(hh.chair_price(0.2)), int(hh.chair_price(0.8)), hh.food_price(), hh.firewood_price()], 18)
			_dyn(func(): return "Reputacja stolarska rodu: %.1f\nIm więcej sprzedasz jednego dnia, tym niższa cena (mały rynek)." % hh.reputation, 16, DIM)
			var sell := _button("", func(): hh.sell_planks = not hh.sell_planks, 17)
			_info_box.add_child(sell)
			_info_updaters.append(func(): sell.text = "Sprzedawaj deski: " + ("TAK" if hh.sell_planks else "NIE (tylko do stolarni)"))
		"manor":
			_dyn(func(): return "Dniówka: %d zł za dzień pracy na osobę.\nPewny grosz, ale bez rozwoju i bez reputacji.\nPracuje tu: %d" % [
				int(world.balance["jobs"]["laborer_wage_day"]), _count_job("laborer")], 17)
		"jail":
			_dyn(func():
				var names: Array = []
				for a in world.agents:
					if a.status == "jailed":
						names.append("%s (%.1f dnia)" % [world.person_of(a).name, a.jail_days])
				return "W areszcie: " + (", ".join(names) if not names.is_empty() else "nikt z rodu"), 17)
		_:
			_info_box.add_child(_label("Chata sąsiadów. Stąd przychodzą kandydaci do ożenku.", 17, DIM))


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
Pieniądze robisz na drewnie: drwal ścina → tracz tnie deski → nosiciel sprzedaje na targu.
Lepiej: stolarz robi z desek krzesła (więcej zarobku, rośnie reputacja). Pewny grosz: dniówka w dworze.
Bez pieniędzy: zbieracz przyniesie jedzenie z lasu (zimą prawie nic).
Ożeń dorosłych, by mieć dzieci — ród trwa, dopóki żyje ktoś z krwi Wilków (♛ = głowa rodu).

STEROWANIE
LPM — zaznacz osobę / budynek       PPM — każ zaznaczonej osobie iść (lub ściąć drzewo)
Przeciągnij LPM / ŚPM, WASD, dwa palce — przesuń kamerę       Kółko / szczypanie — zoom
Q / E — obrót kamery       SPACJA — pauza       1–4 — tempo       TAB — następna osoba       ESC — odznacz

KOLORY UBRAŃ: zielony drwal · pomarańczowy tracz · niebieski stolarz · żółty nosiciel
fioletowy zbieracz · szary dniówka · czarny złodziej · beżowy bez przydziału. Czerwony „!” = problem (kliknij, by zobaczyć jaki).""", 17)
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
		if a.alert or a.hungry_no_food:
			_overlay.draw_circle(sp + Vector2(0, -10), 12, Color(0.85, 0.15, 0.1))
			_overlay.draw_arc(sp + Vector2(0, -10), 12, 0, TAU, 20, Color(1, 1, 1), 2)
			_text(sp + Vector2(0, -3), "!", 18, Color(1, 1, 1))
		if main.selected_id == a.id or main.hover_id == a.id or (zoom_ok and main.cam_size < 30.0):
			_text(sp + Vector2(0, -26 if (a.alert or a.hungry_no_food) else -6), p.name, 16, Color(1, 1, 1))
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
			return "jedzenie %d · opał %d" % [b.amount("food"), b.amount("log")]
		"sawmill":
			return "kłody %d/%d · deski %d/%d" % [b.amount("log"), int(b.capacity["log"]), b.amount("plank"), int(b.capacity["plank"])]
		"workshop":
			return "deski %d · krzesła %d" % [b.amount("plank"), b.amount("chair")]
		"market":
			return "deski %.1f zł · jedzenie %.1f zł" % [world.household.plank_price(), world.household.food_price()]
	return ""
