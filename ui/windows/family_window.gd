# Okno rodu (G): pozycja i opinia rodu, członkowie jako karty (kolor paska = barwa
# ubrania osoby). Klik w kartę zaznacza osobę i pokazuje ją kamerą.
extends TopicWindow


const AgentView := preload("res://game/agent_view.gd")
const RulesWindow := preload("res://ui/windows/rules_window.gd")
const CARD_STRIPE := 8    # grubość paska koloru na karcie osoby
const CARD_PAD := 10      # wcięcie tekstu karty od pasków/krawędzi
const STATUS_MAX := 40    # tyle znaków statusu mieści się w karcie

var _box: VBoxContainer
var _sig := ""
var _rows: Dictionary = {}   # agent id -> Button


func build() -> void:
	var fam := world.family
	dyn(func():
		var r := fam.root()
		return "%s%s" % [world.standing.rank_label(fam.player_lineage()), ("  ·  głowa: " + r.name) if r != null else ""], UiKit.SMALL + 2)
	dyn(func(): return "Mówią o was: " + ", ".join(world.standing.describe(fam.player_lineage())), UiKit.SMALL, UiKit.DIM)
	add(UiKit.button("♛ Pokaż głowę rodu (R)", func(): main.go_to_root(), UiKit.SMALL + 2))
	_sig = ""
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add(_box)
	watch(_fill)
	add(HSeparator.new())
	add(UiKit.button("Zasady zakupów rodu…", func(): hud.toggle_window("rules", func(): return RulesWindow.new(), "Zasady zakupów rodu"), UiKit.SMALL + 1))


func _fill() -> void:
	var fam := world.family
	set_title("Ród " + fam.dynasty)
	var living := fam.by_kinship()
	var sig := ",".join(living.map(func(p): return str(p.agent_id)))
	if sig != _sig:
		_sig = sig
		for c in _box.get_children():
			c.queue_free()
		_rows.clear()
		for p in living:
			var aid: int = p.agent_id
			var b := UiKit.button("", func(): main.select_agent(aid, true), UiKit.SMALL + 1)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_box.add_child(b)
			_rows[aid] = b
	for p in living:
		var a := world.agent_by_id(p.agent_id)
		var b: Button = _rows.get(p.agent_id)
		if a == null or b == null:
			continue
		var stage := fam.stage_of(p)
		var job := "dziecko" if stage == "child" else String(SimJobs.JOB_LABELS.get(a.job, a.job))
		var mark := "♛ GŁOWA · " if p.id == fam.root_id else (fam.relation_to_root(p) + " · ")
		var extra := " · w ciąży" if p.pregnant_left >= 0.0 else ""
		if hud.debug:
			extra += " · [%.2f]" % float(fam.strength.get(p.id, -1.0))
		var status := "W ARESZCIE" if a.status == "jailed" else a.idle_reason
		if status.length() > STATUS_MAX:
			status = status.substr(0, STATUS_MAX - 1) + "…"
		b.text = "%s%s, %d · %s%s\n%s" % [mark, p.name, int(fam.age_of(p)), job, extra, status]
		var col := UiKit.TEXT
		if a.alert or a.hungry_no_food or a.status == "jailed":
			col = UiKit.BAD
		elif a.disabled() or a.health < 50.0:
			col = UiKit.WARN
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_hover_color", col.lightened(0.2))
		var stripe: Color = AgentView.CHILD_CLOTH if stage == "child" else AgentView.cloth_color(a.person_id)
		var sb := UiKit.box(UiKit.CARD_SEL if main.selected_id == a.id else UiKit.CARD_BG, stripe, 4, 6)
		sb.border_width_left = CARD_STRIPE
		sb.content_margin_left = CARD_STRIPE + CARD_PAD
		sb.content_margin_right = CARD_PAD
		b.add_theme_stylebox_override("normal", sb)
