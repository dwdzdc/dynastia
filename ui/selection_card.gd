# Karta zaznaczenia (S41) w prawym dolnym rogu: krótki stan osoby albo budynku,
# przyciski „pokaż” i przyciski okien spraw. Ustawienia są w oknach, nie tutaj.
extends TopicWindow


const PersonWork := preload("res://ui/windows/person_work_window.gd")
const PersonMemories := preload("res://ui/windows/person_memories_window.gd")
const PersonPrefs := preload("res://ui/windows/person_prefs_window.gd")
const PersonTraits := preload("res://ui/windows/person_traits_window.gd")
const BuildingStock := preload("res://ui/windows/building_stock_window.gd")
const BuildingPeople := preload("res://ui/windows/building_people_window.gd")
const HouseSupplies := preload("res://ui/windows/house_supplies_window.gd")
const StallGoods := preload("res://ui/windows/stall_window.gd")

const CARD_W := 400.0
const WORK_TYPES := ["sawmill", "workshop", "manor", "site"]


func build() -> void:
	width = CARD_W
	body.custom_minimum_size.x = CARD_W
	if main.selected_id >= 0:
		_build_person(world.agent_by_id(main.selected_id))
	elif main.selected_building != "":
		_build_building(world.building(main.selected_building))


func close_pressed() -> void:
	main.selected_id = -1
	main.selected_building = ""


# Rząd przycisków otwierających okna spraw: [etykieta, klucz, fabryka okna].
func _topics(items: Array) -> void:
	var r := UiKit.row(4)
	for it in items:
		var k: String = it[1]
		var make: Callable = it[2]
		var btn := UiKit.button(it[0], func(): hud.toggle_window(k, make), UiKit.SMALL)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(btn)
		watch(func(): btn.button_pressed = hud.window_key() == k)
	add(r)


# --- Osoba ---

func _build_person(a: SimAgent) -> void:
	if a == null:
		return
	var fam := world.family
	var p := world.person_of(a)
	set_title("%s%s %s" % ["♛ " if p.id == fam.root_id else "", p.name, p.surname])
	dyn(func():
		var rel := fam.relation_to_root(p) if fam.is_ours(p) else "ród " + fam.lineage_of(p).name
		var job := "dziecko" if fam.stage_of(p) == "child" else String(SimJobs.JOB_LABELS.get(a.job, a.job))
		return "%s · %d lat · %s" % [rel, int(fam.age_of(p)), job], UiKit.SMALL + 1, UiKit.DIM)
	if hud.debug:
		dyn(func(): return "[debug] siła %.2f · sakiewka %.1f zł · dni słabości %d" % [
			float(fam.strength.get(p.id, -1.0)), p.purse, p.weak_days], UiKit.SMALL, UiKit.WARN)
	var now := dyn(func(): return "Teraz: " + (a.idle_reason if a.status == "active" else "w areszcie — " + a.idle_reason), UiKit.FONT)
	watch(func(): now.add_theme_color_override("font_color", UiKit.BAD if a.alert or a.status == "jailed" else UiKit.GOOD))
	bar("Zdrowie", func(): return a.health, Color(0.4, 0.75, 0.35))
	bar("Najedzenie", func(): return a.needs["food"], Color(0.85, 0.7, 0.3))
	bar("Wyspanie", func(): return a.needs["sleep"], Color(0.4, 0.55, 0.85))
	dyn(func():
		var s: Array = []
		if a.sick_days > 0.0:
			s.append("chory jeszcze %.1f dnia" % a.sick_days)
		if a.injured_days > 0.0:
			s.append("ranny jeszcze %.1f dnia" % a.injured_days)
		if p.pregnant_left >= 0.0:
			s.append("w ciąży (poród za %d dni)" % int(ceil(p.pregnant_left)))
		if a.cold:
			s.append("marznie")
		var b := fam.beloved(p)
		if b >= 0:
			s.append("zakochan%s w: %s" % ["y" if p.sex == "m" else "a", fam.persons[b].name])
		return " · ".join(s), UiKit.SMALL, UiKit.WARN)
	dyn(func():
		var home := world.home_of(a)
		return "Mieszka: %s · sakwa %d zł" % [home.name if home != null else "bez dachu", int(p.purse)], UiKit.SMALL, UiKit.DIM)
	var ka := "a:%d:" % a.id
	_topics([
		["Praca", ka + "work", func(): return PersonWork.new().for_agent(a, p)],
		["Wspomnienia", ka + "mem", func(): return PersonMemories.new().for_agent(a, p)],
		["Preferencje", ka + "prefs", func(): return PersonPrefs.new().for_agent(a, p)],
		["Cechy", ka + "traits", func(): return PersonTraits.new().for_agent(a, p)],
	])
	var jumps := UiKit.row(4)
	add(jumps)
	var home_b := UiKit.button("Dom", func():
		var h := world.home_of(a)
		if h != null:
			_show_building(h.id), UiKit.SMALL)
	var work_b := UiKit.button("Miejsce pracy", func():
		var w: SimBuilding = hud.workplace_of(a)
		if w != null:
			_show_building(w.id), UiKit.SMALL)
	var spouse_b := UiKit.button("Małżonek", func():
		var sp: SimPerson = fam.persons.get(p.spouse_id)
		if sp != null and sp.agent_id >= 0:
			main.select_agent(sp.agent_id, true), UiKit.SMALL)
	var fol := UiKit.button("", func(): main.follow_cam = not main.follow_cam, UiKit.SMALL)
	for btn in [home_b, work_b, spouse_b, fol]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		jumps.add_child(btn)
	watch(func():
		home_b.disabled = world.home_of(a) == null
		work_b.disabled = hud.workplace_of(a) == null
		var sp: SimPerson = fam.persons.get(p.spouse_id)
		spouse_b.disabled = sp == null or world.agent_by_id(sp.agent_id) == null
		fol.text = "Nie śledź (F)" if main.follow_cam else "Śledź (F)")
	if world.is_independent(a):
		return
	var rel := UiKit.button("", func(): world.release_manual(a.id), UiKit.SMALL + 1)
	add(rel)
	watch(func():
		rel.visible = a.controlled
		rel.text = "Anuluj rozkazy (%d w kolejce)" % a.steps.filter(func(st): return st["t"] != "do").size())
	if fam.can_be_root(p) and p.id != fam.root_id:
		add(UiKit.button("♛ Ustaw jako głowę rodu", func(): world.switch_root(p.id), UiKit.SMALL + 1))


func _show_building(id: String) -> void:
	main.selected_id = -1
	main.selected_building = id
	main.focus_on(world.building(id).position)


# --- Budynek ---

func _build_building(b: SimBuilding) -> void:
	if b == null:
		return
	set_title(b.name)
	var kb := "b:%s:" % b.id
	if b.type in SimWorld.HOUSE_TYPES:
		dyn(func(): return hud.owner_text(b), UiKit.SMALL + 1, UiKit.DIM)
		dyn(func():
			var hh := world.household_at(b.id)
			if hh == null:
				return ""
			var miss: Dictionary = world.needs.wants(hh)
			var txt := ", ".join(miss.keys().map(func(g): return "%s %d" % [world.good_label(g), int(miss[g])]))
			return "Żyją na poziomie: %s%s" % [world.needs.tier_label(hh), ("; brakuje: " + txt) if txt != "" else ""], UiKit.SMALL, UiKit.DIM)
	var stock := dyn(func(): return hud.stock_text(b), UiKit.SMALL + 1)
	stock.visible = hud.stock_text(b) != ""
	match b.type:
		"market":
			dyn(func():
				var lines: Array = []
				for st: SimStall in world.trade.stalls.values():
					var ka := world.agent_by_id(st.keeper)
					lines.append("%s — %s" % [st.building.name, ("za ladą: " + world.person_of(ka).name) if ka != null and st.is_open() else "zwinięty"])
				return "Stragany:\n  " + "\n  ".join(lines), UiKit.SMALL + 1)
			text("Kliknij stragan, żeby zobaczyć jego towar i ceny.", UiKit.SMALL, UiKit.DIM)
		"stall":
			var st: SimStall = world.trade.stalls.get(b.id)
			if st != null:
				dyn(func():
					var ka := world.agent_by_id(st.keeper)
					var who := ("za ladą: %s" % world.person_of(ka).full_name()) if ka != null and st.is_open() else ("rozłożony, bez opieki!" if not st.packed else "zwinięty")
					return "%s\n%s" % [hud.household_label(st.owner), who], UiKit.SMALL + 1)
				_topics([["Towar i ceny", kb + "goods", func(): return StallGoods.new().for_building(b)]])
		"site":
			dyn(func():
				var site: Dictionary = world.sites.get(b.id, {})
				if site.is_empty():
					return "Budowa skończona."
				var cfg: Dictionary = world.site_cfg(site)
				var mats: Dictionary = cfg["materials"]
				var need := ", ".join(mats.keys().map(func(g): return "%s %d / %d" % [world.good_label(g), b.amount(g), int(mats[g])]))
				return "Budowa: %s %d%%\nMateriały: %s (bez nich praca staje)\nBudują: %s" % [
					String(cfg["label"]).to_lower(), int(100.0 * float(site["work"]) / world.site_total(site)), need if need != "" else "nie trzeba",
					", ".join(world.agents.filter(func(x): return x.activity == "build" and x.position.distance_to(b.position) < 4.0).map(func(x): return world.person_of(x).name))], UiKit.SMALL + 1)
		"jail":
			dyn(func():
				var names: Array = []
				for a in world.agents:
					if a.status == "jailed":
						names.append("%s (%.1f dnia)" % [world.person_of(a).name, a.jail_days])
				return "W areszcie: " + (", ".join(names) if not names.is_empty() else "nikt"), UiKit.SMALL + 1)
	var topics: Array = []
	if b.type in WORK_TYPES:
		topics.append(["Magazyn", kb + "stock", func(): return BuildingStock.new().for_building(b)])
		topics.append(["Ludzie", kb + "people", func(): return BuildingPeople.new().for_building(b)])
	if b.type in ["home", "decor_house", "shack"] and world.household_at(b.id) != null:
		topics.append(["Zapasy", kb + "supplies", func(): return HouseSupplies.new().for_building(b)])
	if not topics.is_empty():
		_topics(topics)
	if b.type in SimWorld.HOUSE_TYPES:
		_house_actions(b)


# Rozkazy mieszkaniowe (O1): bez automatu — gracz sam wynajmuje, kupuje, wychodzi.
func _house_actions(b: SimBuilding) -> void:
	var hh := world.household
	var r := UiKit.row(4)
	if world.is_free_house(b):
		r.add_child(UiKit.button("Wynajmij (%d zł/dzień)" % int(b.rent_per_day), func(): world.rent_house(b.id), UiKit.SMALL))
	if world.house_price(b) > 0.0 and not world.owns(hh, b) and (world.is_free_house(b) or b.id == hh.home_id):
		r.add_child(UiKit.button("Kup (%d zł)" % int(world.house_price(b)), func(): world.buy_house(b.id), UiKit.SMALL))
	if b.id == hh.home_id:
		r.add_child(UiKit.button("Opuść dom", func(): world.leave_home(), UiKit.SMALL))
	if r.get_child_count() > 0:
		add(r)
	if b.id == hh.home_id and not world.owns(hh, b):
		dyn(func(): return "Czynsz: %d zł dziennie. Dług ponad %d zł przez %d dni = eksmisja; ponad %d zł = areszt." % [
			int(b.rent_per_day), int(world.balance["economy"]["evict_debt"]), int(world.balance["economy"]["evict_days"]), int(hh.debt_limit)], UiKit.SMALL - 1, UiKit.DIM)
