# Zasady zakupów rodu (S42): ile twoi ludzie najwyżej zapłacą u innych i za ile
# najtaniej sprzedadzą komuś innemu. Ceny na własnym straganie ustawia się na straganie.
extends TopicWindow


func build() -> void:
	text("Ile twoi ludzie najwyżej zapłacą u innych i za ile najtaniej sprzedadzą. W tych granicach targują się sami. Ceny na własnym straganie ustawiasz w oknie straganu.", UiKit.SMALL, UiKit.DIM)
	var hh := world.household
	var g := UiKit.grid(4, 4)
	add(g)
	for t in ["Towar", "kupuj do", "", "sprzedaj od"]:
		g.add_child(UiKit.label(t, UiKit.SMALL, UiKit.DIM))
	for good in world.balance["trade"]["ref"]:
		var gd: String = good
		g.add_child(UiKit.label(world.good_label(gd), UiKit.SMALL + 1))
		g.add_child(price_cell(func(): return world.trade.buy_max(hh, gd),
			func(d): world.set_household_limit(gd, "buy_max", world.trade.buy_max(hh, gd) + d)))
		g.add_child(Control.new())
		g.add_child(price_cell(func(): return world.trade.sell_min(hh, gd),
			func(d): world.set_household_limit(gd, "sell_min", world.trade.sell_min(hh, gd) + d)))
