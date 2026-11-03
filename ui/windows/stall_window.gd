# Towar i ceny straganu (S42): co sprzedaje i najtaniej za ile, co skupuje i najdrożej
# za ile. Własny stragan ustawiasz tutaj; cudzy tylko podglądasz.
extends "res://ui/windows/building_window.gd"


func build() -> void:
	set_title("Towar i ceny: " + b.name)
	var st: SimStall = world.trade.stalls.get(b.id)
	if st == null:
		return
	var own := st.owner == world.household.id
	var cfg: Dictionary = world.balance["trade"]
	text("Sprzedaje: nie taniej niż · skupuje: nie drożej niż (do zapasu). Kramarz targuje się w tych granicach." if own
		else "Cudzy stragan: tak handluje jego właściciel.", UiKit.SMALL, UiKit.DIM)
	var g := UiKit.grid(5, 4)
	add(g)
	for t in ["Towar", "Sprzedaje", "", "Skupuje", ""]:
		g.add_child(UiKit.label(t, UiKit.SMALL, UiKit.DIM))
	for good in cfg["ref"]:
		var gd: String = good
		if not own and not st.deals_in(gd) and not gd in st.buys:
			continue
		var lbl := UiKit.label(world.good_label(gd), UiKit.SMALL + 1)
		g.add_child(lbl)
		watch(func(): lbl.text = "%s (%d)" % [world.good_label(gd), st.stock.amount(gd)])
		_toggle(g, st, gd, "goods", own)
		g.add_child(_price(st, gd, "sell_min", "goods", own))
		_toggle(g, st, gd, "buys", own)
		g.add_child(_price(st, gd, "buy_max", "buys", own))


func _on(st: SimStall, gd: String, list: String) -> bool:
	return gd in (st.goods if list == "goods" else st.buys)


# Własny stragan: przycisk ✓/✗; cudzy: sam znak.
func _toggle(g: GridContainer, st: SimStall, gd: String, list: String, own: bool) -> void:
	if not own:
		var l := UiKit.label("", UiKit.SMALL + 1)
		g.add_child(l)
		watch(func():
			l.text = "✓" if _on(st, gd, list) else "—"
			l.add_theme_color_override("font_color", UiKit.GOOD if _on(st, gd, list) else UiKit.DIM))
		return
	var b := UiKit.button("", func(): world.set_stall_trade(st.id, gd, list, not _on(st, gd, list)), UiKit.SMALL)
	b.custom_minimum_size.x = 36
	g.add_child(b)
	watch(func():
		b.text = "✓" if _on(st, gd, list) else "✗"
		b.add_theme_color_override("font_color", UiKit.GOOD if _on(st, gd, list) else UiKit.DIM))


func _price(st: SimStall, gd: String, key: String, list: String, own: bool) -> Control:
	var get_fn := func(): return world.trade.stall_sell_min(st, gd) if key == "sell_min" else world.trade.stall_buy_max(st, gd)
	if not own:
		var l := UiKit.label("", UiKit.SMALL + 1)
		watch(func(): l.text = ("%.1f zł" % float(get_fn.call())) if _on(st, gd, list) else "")
		return l
	var cell := price_cell(get_fn, func(d): world.set_stall_price(st.id, gd, key, float(get_fn.call()) + d))
	watch(func(): cell.modulate.a = 1.0 if _on(st, gd, list) else 0.35)
	return cell
