# EconPopulation — ludzie: co miesiąc przyrost i migracja (do lepszych miast,
# z oszczędnościami), nowi przedsiębiorcy z oszczędności ludności, bankruci
# wracają do szarej masy, a gdy aktor umiera, firmy dziedziczy jego ród.
class_name EconPopulation
extends RefCounted


static func step(w: EconWorld) -> void:
	for a: EconActor in w.actors.values().duplicate():
		if a.alive and w.day >= a.death_day:
			die(w, a)
	var pp: Dictionary = w.data["population"]
	var every := int(pp["update_every"])
	if w.day % every == every - 1:
		_growth(w, pp)
		_migration(w, pp)
		_retire(w)
	var ap: Dictionary = w.data["actors"]
	if w.day % int(ap["new_entrepreneur_every"]) == 10:
		_entrepreneurs(w, ap)


static func _growth(w: EconWorld, pp: Dictionary) -> void:
	for c: EconCity in w.cities:
		var g := float(pp["growth_per_month"]) + float(pp["prosperity_growth"]) * (c.prosperity() - 0.7)
		c.population = maxf(100.0, c.population * (1.0 + g))


static func _attract(c: EconCity) -> float:
	return c.prosperity() + 0.002 * c.wage


static func _migration(w: EconWorld, pp: Dictionary) -> void:
	var share := float(pp["migration_share"])
	var max_km := float(pp["migration_max_km"])
	for r: EconRoute in w.routes:
		if r.length > max_km:
			continue
		var a: EconCity = w.cities[r.a]
		var b: EconCity = w.cities[r.b]
		var diff := _attract(b) - _attract(a)
		if absf(diff) < 0.05:
			continue
		var from := a if diff > 0.0 else b
		var to := b if diff > 0.0 else a
		var n := minf(from.population * share * absf(diff), from.population * 0.05)
		var cash := from.cash * n / maxf(from.population, 1.0)
		from.population -= n
		to.population += n
		from.cash -= cash
		to.cash += cash
		w.stats["migrants"] += n
		if n > from.population * 0.01 and n > 300.0:
			w.news.add("migration", from.id, "Fala wyjazdów: %s → %s, %.0f osób w miesiąc." % [from.name, to.name, n], 1)


static func _entrepreneurs(w: EconWorld, ap: Dictionary) -> void:
	for c: EconCity in w.cities:
		var pot := c.cash * float(ap["new_entrepreneur_share"])
		if pot < float(ap["new_entrepreneur_min_cash"]):
			continue
		# Im bogatsze miasto na głowę, tym większa szansa na nowego przedsiębiorcę.
		var per_capita := c.cash / maxf(c.population, 1.0)
		if not w.rng.chance(clampf(per_capita / 400.0, 0.05, 0.6)):
			continue
		var a := new_actor(w, c.id, -1, "")
		c.cash -= pot
		a.cash = pot
		w.stats["entrepreneurs"] += 1
		w.news.add("entrepreneur", c.id, "%s (%s) zaczyna własny interes z %.0f tys. zł oszczędności." % [a.full_name(), c.name, pot / 1000.0], 0)


static func _retire(w: EconWorld) -> void:
	var limit := float(w.data["actors"]["retire_cash"])
	var idle_days := int(w.data["actors"]["idle_days_to_retire"])
	for a: EconActor in w.actors.values():
		if not a.alive:
			continue
		if not a.businesses.is_empty():
			a.idle_since = -1
			continue
		if a.idle_since == -1:
			a.idle_since = w.day
		# Bez firmy i bez pieniędzy albo długo bez pomysłu: wraca do szarej masy z oszczędnościami.
		if a.cash < limit or w.day - a.idle_since > idle_days:
			w.cities[a.city_id].cash += a.cash
			a.cash = 0.0
			a.alive = false
			w.stats["retired"] += 1


static func new_actor(w: EconWorld, city_id: int, family_id: int, last: String) -> EconActor:
	var ap: Dictionary = w.data["actors"]
	var names: Dictionary = w.data["names"]
	var a := EconActor.new(w.new_id())
	a.first = str(w.rng.choice(names["first"]))
	a.female = EconNames.is_female_first(a.first)
	var base_last := last if last != "" else str(w.rng.choice(names["last"]))
	a.last = EconNames.surname_for(base_last, a.female)
	a.family_id = family_id if family_id != -1 else a.id
	a.city_id = city_id
	var risk: Array = ap["risk"]
	a.risk = w.rng.next_float(float(risk[0]), float(risk[1]))
	var life: Array = ap["life_days"]
	a.born_day = w.day
	a.death_day = w.day + w.rng.next_int(int(life[0]), int(life[1]))
	w.actors[a.id] = a
	return a


# Rodowe nazwisko w formie męskiej (do dziedziczenia przez dzieci obu płci).
static func family_last(a: EconActor) -> String:
	if a.female and a.last.ends_with("ska"):
		return a.last.substr(0, a.last.length() - 1) + "i"
	if a.female and a.last.ends_with("cka"):
		return a.last.substr(0, a.last.length() - 1) + "i"
	return a.last


static func die(w: EconWorld, a: EconActor) -> void:
	a.alive = false
	w.stats["deaths"] += 1
	var ap: Dictionary = w.data["actors"]
	if a.businesses.is_empty() and a.cash < float(ap["min_invest_cash"]):
		w.cities[a.city_id].cash += a.cash
		a.cash = 0.0
		return
	var n := 2 if w.rng.chance(float(ap["split_heirs_chance"])) and a.businesses.size() >= 2 else 1
	var heirs: Array[EconActor] = []
	for i in n:
		var h := new_actor(w, a.city_id, a.family_id, family_last(a))
		h.parent_id = a.id
		h.risk = clampf(a.risk + w.rng.next_float(-0.3, 0.3), 0.1, 1.0)
		heirs.append(h)
	var share := a.cash / n
	for h: EconActor in heirs:
		h.cash += share
	a.cash = 0.0
	var i := 0
	for bid: int in a.businesses:
		var b: EconBusiness = w.business(bid)
		if b == null:
			continue
		var h: EconActor = heirs[i % n]
		b.owner_id = h.id
		h.businesses.append(bid)
		i += 1
	a.businesses.clear()
	var wealth := 0.0
	for h: EconActor in heirs:
		wealth += w.actor_wealth(h)
	if n == 1:
		w.news.add("death", a.city_id, "Zmarł%s %s. Majątek (%.1f mln zł) przejmuje %s." % ["a" if a.female else "", a.full_name(), wealth / 1e6, heirs[0].full_name()], 1 if wealth > 1e6 else 0)
	else:
		w.news.add("death", a.city_id, "Zmarł%s %s. Majątek dzielą %s i %s – ród %s się rozdziela." % ["a" if a.female else "", a.full_name(), heirs[0].full_name(), heirs[1].full_name(), EconNames.family_genitive(family_last(a))], 1)
