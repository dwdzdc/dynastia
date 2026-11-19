# EconNews — kronika świata (gazeta). Moduły dopisują zdarzenia (pożar, bankructwo,
# przejęcie, śmierć krezusa), a step() co dobę sam wykrywa skoki i krachy cen,
# kryzysy i boomy miast. Przy skoku ceny podaje znaną przyczynę (market.shock).
class_name EconNews
extends RefCounted


var w: EconWorld
var entries: Array[Dictionary] = []   # { day, kind, city, text, severity (0 info, 1 ważne, 2 alarm) }
var _cooldown: Dictionary = {}        # klucz -> doba, od której wolno znowu
var _richest_id: int = -1


func _init(w_: EconWorld) -> void:
	w = w_


func add(kind: String, city_id: int, text: String, severity: int = 1) -> void:
	entries.append({"day": w.day, "kind": kind, "city": city_id, "text": text, "severity": severity})
	var keep := int(w.data["news"]["keep"])
	if entries.size() > keep:
		entries.remove_at(0)


func _ready(key: String) -> bool:
	return w.day >= int(_cooldown.get(key, -1))


func _hold(key: String) -> void:
	_cooldown[key] = w.day + int(w.data["news"]["cooldown_days"])


# Przyczyna zamieszania na rynku (pożar, nieurodzaj…), pamiętana przez jakiś czas.
func tag_shock(c: EconCity, good: String, why: String, days: int) -> void:
	var m := c.market(good)
	if m != null:
		m.shock = why
		m.shock_until = w.day + days


func step() -> void:
	var p: Dictionary = w.data["news"]
	for c: EconCity in w.cities:
		for g: String in c.markets.keys():
			var m: EconMarket = c.markets[g]
			if m.use_ema < 1.0 and g != "trucks":
				continue
			var key := "p:%d:%s" % [c.id, g]
			if m.price > m.price_ema * float(p["spike_ratio"]) and _ready(key):
				var why := ""
				if m.shock != "" and w.day < m.shock_until:
					why = " (%s)" % m.shock
				add("spike", c.id, "%s: brakuje towaru (%s), cena +%.0f%%%s." % [c.name, w.good_name(g), (m.price / m.price_ema - 1.0) * 100.0, why], 2)
				_hold(key)
			elif m.price < m.price_ema * float(p["crash_ratio"]) and _ready(key):
				add("crash", c.id, "%s: zalew towaru (%s), cena −%.0f%%." % [c.name, w.good_name(g), (1.0 - m.price / m.price_ema) * 100.0], 0)
				_hold(key)
		var ck := "c:%d" % c.id
		if w.day > 20 and _ready(ck):
			if c.satisfaction < float(p["crisis_satisfaction"]) or c.unemployment() > float(p["crisis_unemployment"]):
				add("crisis", c.id, "%s w kryzysie: bezrobocie %.0f%%, potrzeby zaspokojone w %.0f%%." % [c.name, c.unemployment() * 100.0, c.satisfaction * 100.0], 2)
				_hold(ck)
			elif c.satisfaction > float(p["boom_satisfaction"]) and c.unemployment() < float(p["boom_unemployment"]):
				add("boom", c.id, "%s kwitnie: prawie każdy ma pracę, płaca %.0f zł." % [c.name, c.wage], 0)
				_hold(ck)
	if w.day % 30 == 15:
		_check_richest()


func _check_richest() -> void:
	var best: EconActor = null
	var best_w := -1.0
	for a: EconActor in w.living_actors():
		var aw := w.actor_wealth(a)
		if aw > best_w:
			best_w = aw
			best = a
	if best != null and best.id != _richest_id:
		if _richest_id != -1:
			add("richest", best.city_id, "%s jest teraz najbogatszym człowiekiem świata (%.1f mln zł)." % [best.full_name(), best_w / 1e6], 1)
		_richest_id = best.id
