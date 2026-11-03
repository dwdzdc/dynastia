# Okno budowy (S29, T0): katalog z danych pogrupowany w kategorie; wybór wpisu
# przełącza na wskazywanie miejsca na mapie.
extends TopicWindow


func build() -> void:
	var cats := {}
	for kind in world.buildables:
		var cat := String(world.buildables[kind]["category"])
		if not cats.has(cat):
			cats[cat] = []
		cats[cat].append(kind)
	for cat in cats:
		add(UiKit.label(cat, UiKit.SMALL, UiKit.DIM))
		for kind in cats[cat]:
			var cfg: Dictionary = world.buildables[kind]
			var mats: Dictionary = cfg["materials"]
			var cost := ", ".join(mats.keys().map(func(g): return "%d× %s" % [int(mats[g]), world.good_label(g)]))
			var k: String = kind
			var b := UiKit.button("%s — %s" % [cfg["label"], cost if cost != "" else "tylko praca"], func():
				main.placing = k
				main.placing_from = null
				hud.close_window(), UiKit.SMALL + 2)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			add(b)
	text("Wybierz, potem kliknij miejsce na mapie (droga: początek i koniec). Esc — anuluj.", UiKit.SMALL - 1, UiKit.DIM)
