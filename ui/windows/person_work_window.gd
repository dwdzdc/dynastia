# Praca osoby: przydział zawodu, umiejętności, umowa, wyprawy do miast; dziecko —
# za kim chodzi w dzień (D5). Obcy ród: tylko opis, bez poleceń.
extends "res://ui/windows/person_window.gd"


const JOB_ORDER := ["woodcutter", "sawyer", "carpenter", "carrier", "forager", "laborer", "overseer", "thief", "none"]
const JOB_BUTTONS := {
	"woodcutter": "Drwal", "sawyer": "Tracz", "carpenter": "Stolarz", "carrier": "Tragarz",
	"forager": "Zbieracz", "laborer": "Robotnik", "overseer": "Nadzorca", "thief": "Złodziej", "none": "Bez przydziału",
}
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
const SKILL_LABELS := { "chop": "rąbanie", "saw": "piłowanie", "craft": "stolarka", "forage": "zbieractwo", "steal": "złodziejstwo", "trade": "handel" }
const JOB_BTN_H := 36


func build() -> void:
	var a := agent
	var p := person
	var fam := world.family
	set_title("Praca: " + p.name)
	dyn(func():
		var parts: Array = []
		for k in SKILL_LABELS:
			parts.append("%s %.1f" % [SKILL_LABELS[k], a.skill(k)])
		return "Umiejętności: " + " · ".join(parts), UiKit.SMALL, UiKit.DIM)
	dyn(func():
		var c: Dictionary = world.contracts.of_worker(p.id)
		if c.is_empty():
			return ""
		var boss := world.contracts.payer(int(c["employer"]))
		return "Umowa: %s w %s, %d zł/dzień%s, należy się %d zł" % [SimJobs.JOB_LABELS.get(c["job"], c["job"]),
			world.buildings[c["place"]].name if world.buildings.has(c["place"]) else "?", int(c["wage"]),
			(" (płaci: %s)" % world.person_of(boss).name) if boss != null else "", int(round(float(c["owed"])))], UiKit.SMALL, UiKit.DIM)
	if world.is_independent(a):
		text("Nie należy do twojego rodu (%s). Żyje po swojemu — nie wydasz mu poleceń." % fam.lineage_of(p).name, UiKit.SMALL + 2, UiKit.DIM)
		return
	if fam.stage_of(p) == "child":
		text("Dziecko — bawi się przy chacie. Do pracy od %d lat." % int(fam.years_label(fam.stage_start("teen"))), UiKit.SMALL + 2, UiKit.DIM)
		_build_follow()
		return
	section("Zawód")
	var g := UiKit.grid(2)
	add(g)
	var hint := UiKit.wrap("", UiKit.SMALL, UiKit.DIM)
	for j in JOB_ORDER:
		var jj: String = j
		var b := UiKit.button(JOB_BUTTONS[j], func(): world.set_job(a.id, jj), UiKit.SMALL + 1)
		b.toggle_mode = true
		b.custom_minimum_size.y = JOB_BTN_H
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = JOB_HINTS[j]
		b.mouse_entered.connect(func(): hint.text = JOB_HINTS[jj])
		g.add_child(b)
		watch(func(): b.button_pressed = a.job == jj)
	add(hint)
	watch(func():
		if hint.text == "":
			hint.text = JOB_HINTS.get(a.job, ""))
	text("Miejsce pracy u kogoś: zaznacz osobę i kliknij PPM na budynek albo pole.", UiKit.SMALL - 1, UiKit.DIM)
	if fam.is_ours(p) and fam.stage_of(p) in ["adult", "elder"]:
		# Wyprawa do miasta (U3): towar, którego miastu brakuje, i zakupy dla domu.
		section("Wyprawa do miasta")
		var trip := UiKit.row(4)
		for tid in world.traders.towns:
			var town: SimTown = world.traders.towns[tid]
			var t_id: String = tid
			trip.add_child(UiKit.button(town.name, func(): world.send_on_trip(a.id, t_id), UiKit.SMALL))
		add(trip)


# Dziecko w godzinach pracy chodzi za lubianym dorosłym; gracz może wskazać za kim (D5).
func _build_follow() -> void:
	var a := agent
	section("W dzień chodzi z:")
	var g := UiKit.grid(2)
	add(g)
	var own := UiKit.button("z kim zechce", func(): world.set_follow(a.id, -1), UiKit.SMALL + 1)
	own.toggle_mode = true
	own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(own)
	watch(func(): own.button_pressed = a.follow_id < 0)
	for o in world.family.living():
		var oa := world.agent_by_id(o.agent_id)
		if oa == null or oa.is_child:
			continue
		var oid: int = o.id
		var b := UiKit.button("z: " + o.name, func(): world.set_follow(a.id, oid), UiKit.SMALL + 1)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
		watch(func(): b.button_pressed = a.follow_id == oid)
