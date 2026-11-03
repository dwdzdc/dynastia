# Ogłoszenia o pracę: wakaty w okolicy (L3), kto najmuje, do czego, za ile i ile miejsc
# wolnych. „Wyślij…” najmuje kogoś z rodu; klik w nazwę pokazuje miejsce.
extends TopicWindow


var _box: VBoxContainer
var _sig := ""


func build() -> void:
	text("Na górze wolne miejsca, najlepiej płatne. Własne ogłoszenia (ilu ludzi najmujesz i za ile) ustawiasz w oknie „Ludzie” swojego warsztatu.", UiKit.SMALL, UiKit.DIM)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add(_box)
	_sig = ""
	watch(_fill)


func _fill() -> void:
	var offers: Array = world.contracts.offers.filter(func(o): return int(o["slots"]) > 0 and world.buildings.has(o["place"]))
	# Najpierw te z wolnymi miejscami, w nich najlepiej płatne.
	offers.sort_custom(func(x, y):
		var fx := world.contracts.free_slots(x) > 0
		var fy := world.contracts.free_slots(y) > 0
		return fx and not fy if fx != fy else float(x["wage"]) > float(y["wage"]))
	var sig := ",".join(offers.map(func(o): return "%d:%d:%d:%d" % [int(o["id"]), int(o["wage"]), world.contracts.free_slots(o), int(o["slots"])]))
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	if offers.is_empty():
		_box.add_child(UiKit.label("Nikt teraz nie szuka ludzi.", UiKit.SMALL + 1, UiKit.DIM))
		return
	for o: Dictionary in offers:
		var b: SimBuilding = world.buildings[o["place"]]
		var free := maxi(0, world.contracts.free_slots(o))
		var own := int(o["employer"]) == world.household.id
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		_box.add_child(card)
		var go := UiKit.button("%s — %s" % [SimJobs.JOB_LABELS.get(o["job"], o["job"]), b.name], func():
			main.selected_id = -1
			main.selected_building = b.id
			main.focus_on(b.position), UiKit.SMALL + 1)
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		go.tooltip_text = "Pokaż miejsce"
		card.add_child(go)
		var r := UiKit.row(6)
		card.add_child(r)
		var info := UiKit.label("%d zł/dzień · wolne %d/%d · %s" % [int(o["wage"]), free, int(o["slots"]), hud.household_label(int(o["employer"]))],
			UiKit.SMALL, UiKit.GOOD if free > 0 else UiKit.DIM)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(info)
		if own:
			r.add_child(UiKit.label("twoje", UiKit.SMALL, UiKit.TITLE))
			continue
		var send := Button.new()
		send.text = "Wyślij…"
		send.focus_mode = Control.FOCUS_NONE
		send.add_theme_font_size_override("font_size", UiKit.SMALL)
		send.disabled = free <= 0
		send.pressed.connect(func(): _send_menu(send, o))
		r.add_child(send)


# Kogo z rodu wysłać do tej roboty: menu z dorosłymi i ich obecnym zajęciem.
func _send_menu(btn: Button, o: Dictionary) -> void:
	var items: Array = []
	for p: SimPerson in world.family.living():
		var a := world.agent_by_id(p.agent_id)
		if a == null or a.is_child or a.status != "active" or world.is_independent(a):
			continue
		var aid := a.id
		var job := String(o["job"])
		var place := String(o["place"])
		var now := String(SimJobs.JOB_LABELS.get(a.job, a.job))
		items.append({ "label": "%s (teraz: %s)" % [p.name, now], "ok": a.workplace != place,
			"fn": func(): world.assign_job(aid, job, place) })
	if items.is_empty():
		items.append({ "label": "Nie ma kogo wysłać", "ok": false, "fn": func(): pass })
	hud.show_menu(btn.get_screen_position() + Vector2(0, btn.size.y), items)
