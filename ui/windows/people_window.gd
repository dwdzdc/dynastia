# Ludzie (I6): wszyscy mieszkańcy okolicy z bieżącym zajęciem; filtry łączone jak w
# liście postaci Cultures. Klik w wiersz zaznacza osobę i pokazuje ją kamerą.
extends TopicWindow


const ROWS := 60          # tyle wierszy naraz (reszta: zawęź filtrem)
const FILTERS := [
	["ours", "Nasz ród"], ["jobless", "Bez pracy"], ["homeless", "Bez dachu"],
	["hungry", "Głodni"], ["sick", "Chorzy, ranni"], ["single", "Wolni dorośli"],
]

var _on: Dictionary = {}
var _box: VBoxContainer
var _count: Label
var _sig := ""


func build() -> void:
	var g := UiKit.grid(3, 4)
	add(g)
	for f in FILTERS:
		var id: String = f[0]
		var b := UiKit.button(f[1], func():
			_on[id] = not _on.get(id, false)
			_sig = "", UiKit.SMALL)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
		watch(func(): b.set_pressed_no_signal(_on.get(id, false)))
	_count = UiKit.label("", UiKit.SMALL, UiKit.DIM)
	add(_count)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add(_box)
	watch(_fill)


func _match(a: SimAgent, p: SimPerson) -> bool:
	var fam := world.family
	if _on.get("ours", false) and not fam.is_ours(p):
		return false
	if _on.get("jobless", false) and (a.is_child or (a.job != "none" and a.job != "")):
		return false
	if _on.get("homeless", false) and world.home_of(a) != null:
		return false
	if _on.get("hungry", false) and not (a.hungry_no_food or a.needs["food"] < 35.0):
		return false
	if _on.get("sick", false) and not (a.sick_days > 0.0 or a.injured_days > 0.0):
		return false
	if _on.get("single", false) and (a.is_child or p.spouse_id >= 0):
		return false
	return true


func _fill() -> void:
	var rows: Array = []
	for a: SimAgent in world.agents:
		if a.status == "dead":
			continue
		var p := world.person_of(a)
		if p != null and _match(a, p):
			rows.append(a)
	rows.sort_custom(func(x, y): return world.person_of(x).full_name() < world.person_of(y).full_name())
	_count.text = "Pasuje: %d" % rows.size() + ("" if rows.size() <= ROWS else " (widać %d — zawęź filtrem)" % ROWS)
	var sig := ",".join(rows.slice(0, ROWS).map(func(a): return str(a.id)))
	if sig != _sig:
		_sig = sig
		for c in _box.get_children():
			c.queue_free()
		for a in rows.slice(0, ROWS):
			var aid: int = a.id
			var b := UiKit.button("", func(): main.select_agent(aid, true), UiKit.SMALL)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.set_meta("aid", aid)
			_box.add_child(b)
	for b: Button in _box.get_children():
		if b.is_queued_for_deletion():
			continue
		var a := world.agent_by_id(int(b.get_meta("aid")))
		if a == null:
			continue
		var p := world.person_of(a)
		var job := "dziecko" if a.is_child else String(SimJobs.JOB_LABELS.get(a.job, a.job))
		b.text = "%s · %s — %s" % [p.full_name(), job, "W ARESZCIE" if a.status == "jailed" else a.idle_reason]
		b.add_theme_color_override("font_color", UiKit.BAD if a.alert or a.hungry_no_food else (UiKit.TITLE if world.family.is_ours(p) else UiKit.TEXT))
