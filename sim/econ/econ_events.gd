# EconEvents — wstrząsy dotyczą tylko pojedynczych rzeczy (pożar zakładu, strajk,
# plony regionu, zamknięta droga, zbójcy, złoże). Kryzysy i boomy biorą się z tego,
# jak skutki rozchodzą się łańcuchami dostaw — nic nie jest oskryptowane.
class_name EconEvents
extends RefCounted


static func step(w: EconWorld) -> void:
	var ep: Dictionary = w.data["events"]
	_businesses(w, ep)
	if w.day % int(ep["harvest_every"]) == 0:
		_harvest(w, ep)
	_roads(w, ep)
	_discoveries(w, ep)


static func _days(w: EconWorld, range_: Array) -> int:
	return w.rng.next_int(int(range_[0]), int(range_[1]))


static func _businesses(w: EconWorld, ep: Dictionary) -> void:
	for b: EconBusiness in w.businesses.values():
		if b.status != "active" or b.type == "haulage":
			continue
		var c := w.city_of(b)
		var out: String = w.recipe(b.type)["out"]
		if w.rng.chance(float(ep["fire_chance"])):
			var days := _days(w, ep["fire_days"])
			b.status = "burned"
			b.status_until = w.day + days
			var lost := 0.0 if out == "" else c.market(out).take_from(b.id, c.market(out).stock_of(b.id) * float(ep["fire_stock_loss"]))
			w.stats["fires"] += 1
			var big := float(w.recipe(b.type)["build"]["money"]) >= 20000.0
			w.news.add("fire", c.id, "Pożar: %s (%s) stoi przez %d dni, spłonęło %.0f j. towaru." % [b.name, c.name, days, lost], 2 if big else 0)
			if out != "":
				w.news.tag_shock(c, out, "po pożarze: %s" % b.name, days + 20)
		elif w.rng.chance(float(ep["strike_chance"]) * _strike_mood(w, b, c)):
			var days := _days(w, ep["strike_days"])
			var big := float(w.recipe(b.type)["build"]["money"]) >= 20000.0
			b.status = "strike"
			b.status_until = w.day + days
			w.stats["strikes"] += 1
			w.news.add("strike", c.id, "Strajk: %s (%s), załoga chce podwyżki, przestój %d dni." % [b.name, c.name, days], 1 if big else 0)
			w.news.tag_shock(c, out, "strajk: %s" % b.name, days + 10)


# Strajk grozi częściej tam, gdzie płaca spadła, a firma dobrze zarabia.
static func _strike_mood(w: EconWorld, b: EconBusiness, c: EconCity) -> float:
	var base := float(w.data["labor"]["base_wage"])
	var mood := 1.0
	if c.wage < base * 0.8:
		mood += 1.5
	if b.profit_ema > b.cost_ema * 0.3:
		mood += 1.0
	return mood


static func _harvest(w: EconWorld, ep: Dictionary) -> void:
	var table: Array = ep["harvest_mult"]
	for c: EconCity in w.cities:
		if not c.resources.has("fertile"):
			continue
		var roll := w.rng.next_float()
		var acc := 0.0
		var mult := 1.0
		for row: Array in table:
			acc += float(row[1])
			if roll <= acc:
				mult = float(row[0])
				break
		c.harvest_mult = mult
		if mult <= 0.5:
			w.news.add("harvest", c.id, "Susza: %s, plony to ledwie %.0f%% zwykłych." % [c.name, mult * 100.0], 2)
			for g: String in ["grain", "vegetables"]:
				w.news.tag_shock(c, g, "susza: %s" % c.name, int(ep["harvest_every"]))
		elif mult <= 0.8:
			w.news.add("harvest", c.id, "Słabe plony: %s." % c.name, 0)
		elif mult >= 1.5:
			w.news.add("harvest", c.id, "Rekordowe plony: %s." % c.name, 0)


static func _roads(w: EconWorld, ep: Dictionary) -> void:
	var decay := float(ep["bandits_decay"])
	for r: EconRoute in w.routes:
		r.danger *= decay
		if r.danger < 0.01:
			r.danger = 0.0
		var a: EconCity = w.cities[r.a]
		var b: EconCity = w.cities[r.b]
		if not r.is_closed(w.day) and w.rng.chance(float(ep["road_closure_chance"])):
			var days := _days(w, ep["road_closure_days"])
			r.closed_until = w.day + days
			r.closed_reason = str(w.rng.choice(["powódź", "osuwisko", "zawalony most", "remont"]))
			w.stats["closures"] += 1
			w.news.add("road", r.a, "Droga %s – %s zamknięta (%s) na %d dni." % [a.name, b.name, r.closed_reason, days], 1)
		if r.danger < 0.05 and w.rng.chance(float(ep["bandits_chance"]) * _poverty(a, b)):
			var lv: Array = ep["bandits_level"]
			r.danger = w.rng.next_float(float(lv[0]), float(lv[1]))
			w.news.add("bandits", r.a, "Na drodze %s – %s grasują zbójcy." % [a.name, b.name], 1)


# Zbójcy biorą się z biedy: częściej przy miastach z bezrobociem.
static func _poverty(a: EconCity, b: EconCity) -> float:
	return 0.5 + 4.0 * maxf(a.unemployment(), b.unemployment())


static func _discoveries(w: EconWorld, ep: Dictionary) -> void:
	if not w.rng.chance(float(ep["discovery_chance"]) * w.cities.size()):
		return
	var c: EconCity = w.rng.choice(w.cities)
	var res: String = w.rng.choice(["oil", "iron", "limestone"])
	var rich: Array = w.data["world"]["resources"][res]["richness"]
	var v := w.rng.next_float(float(rich[0]), float(rich[1])) * 1.2
	c.resources[res] = float(c.resources.get(res, 0.0)) + v
	w.stats["discoveries"] += 1
	var label := {"oil": "ropę", "iron": "rudę żelaza", "limestone": "złoże wapienia"}
	w.news.add("discovery", c.id, "%s: odkryto %s! Inwestorzy już liczą." % [c.name, label[res]], 2)
