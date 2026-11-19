# EconGazette — miesięczna gazeta świata („Kurier”). Składa numer z kroniki
# (EconNews) i stanu świata: nagłówek miesiąca, ceny, ludzie i firmy, drogi,
# ranking rodów. Czysta funkcja stanu — nic nie zmienia w świecie.
class_name EconGazette
extends RefCounted


const MONTH_DAYS := 30
const MONTHS := ["styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec", "lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"]
# Waga rodzaju wpisu przy wyborze nagłówka (im wyżej, tym bardziej na pierwszą stronę).
const HEADLINE_WEIGHT := {"crisis": 6.0, "discovery": 5.5, "spike": 4.0, "fire": 3.5, "richest": 3.5,
	"death": 3.0, "migration": 3.0, "harvest": 3.0, "takeover": 2.5, "bandits": 2.0, "strike": 2.0,
	"closed": 1.5, "road": 1.5, "robbery": 1.0, "boom": 2.5, "founded": 1.0}
const PRICE_GOODS := ["bread", "vegetables", "meat", "fuel", "steel", "lumber", "appliances"]
const COLUMN_LINES := 5


# Numer gazety za miesiąc kończący się przed dobą `to_day` (wyłącznie).
static func issue(w: EconWorld, to_day: int) -> Dictionary:
	var from_day := maxi(0, to_day - MONTH_DAYS)
	var month: Array = w.news.entries.filter(func(e: Dictionary) -> bool: return int(e["day"]) >= from_day and int(e["day"]) < to_day)
	var number := maxi(1, to_day / MONTH_DAYS)
	var year := (to_day - 1) / (MONTH_DAYS * MONTHS.size()) + 1
	var month_name: String = MONTHS[((to_day - 1) / MONTH_DAYS) % MONTHS.size()]
	var out := {
		"number": number,
		"date": "%s, rok %d" % [month_name, year],
		"headline": "Spokojny miesiąc",
		"lead": "Świat pracuje, ciężarówki jeżdżą, nic wielkiego się nie stało.",
		"columns": [],
	}
	var top := _headline(w, month)
	if not top.is_empty():
		out["headline"] = _short(str(top["text"]))
		out["lead"] = _lead(w, top, month)
	out["columns"] = [
		{"title": "Ceny miesiąca", "lines": _prices(w)},
		{"title": "Ludzie i firmy", "lines": _people(month)},
		{"title": "Drogi i bezpieczeństwo", "lines": _roads(month)},
		{"title": "Najbogatsze rody", "lines": _families(w)},
	]
	return out


static func _headline(w: EconWorld, month: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for e: Dictionary in month:
		var score := float(HEADLINE_WEIGHT.get(str(e["kind"]), 0.5)) * (1.0 + int(e["severity"]))
		var cid := int(e["city"])
		if cid >= 0:
			score *= 1.0 + sqrt(w.cities[cid].population) / 300.0  # większe miasto, większa sprawa
		if score > best_score:
			best_score = score
			best = e
	return best


static func _short(text: String) -> String:
	return text.trim_suffix(".")


static func _lead(w: EconWorld, top: Dictionary, month: Array) -> String:
	var cid := int(top["city"])
	var parts: Array[String] = []
	if cid >= 0:
		var c: EconCity = w.cities[cid]
		parts.append("%s: %s mieszkańców, bezrobocie %.0f%%, płaca %.0f zł dziennie." % [c.name, _int(c.population), c.unemployment() * 100.0, c.wage])
		var related := month.filter(func(e: Dictionary) -> bool: return int(e["city"]) == cid and e != top)
		if not related.is_empty():
			parts.append("W tym miesiącu było tam jeszcze %d innych wydarzeń." % related.size())
	var crises := month.filter(func(e: Dictionary) -> bool: return e["kind"] == "crisis").size()
	if crises > 1:
		parts.append("Kryzysów w świecie: %d." % crises)
	return " ".join(parts)


static func _int(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	for i in s.length():
		out += s[i]
		if (s.length() - i - 1) % 3 == 0 and i < s.length() - 1:
			out += " "
	return out


# Zmiana średniej ceny w świecie w ciągu miesiąca (z historii rynków).
static func _prices(w: EconWorld) -> Array:
	var every := int(w.data["market"]["history_every"])
	var back := MONTH_DAYS / every
	var rows: Array = []
	for g: String in PRICE_GOODS:
		var now := 0.0
		var then := 0.0
		var n := 0
		for c: EconCity in w.cities:
			var h: Array = c.market(g).history
			if h.size() > back:
				now += float(h[h.size() - 1])
				then += float(h[h.size() - 1 - back])
				n += 1
		if n == 0 or then <= 0.0:
			continue
		var ch := (now / then - 1.0) * 100.0
		rows.append([absf(ch), "%s %s%.0f%%" % [w.good_name(g), "+" if ch >= 0.0 else "−", absf(ch)]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	return rows.slice(0, COLUMN_LINES).map(func(r: Array) -> String: return str(r[1]))


static func _people(month: Array) -> Array:
	var kinds := ["death", "takeover", "richest", "entrepreneur", "closed", "opened"]
	var lines: Array = []
	for k: String in kinds:
		for e: Dictionary in month:
			if e["kind"] == k and (int(e["severity"]) >= 1 or k in ["death", "richest"]):
				lines.append(_short(str(e["text"])))
	var newcomers := month.filter(func(e: Dictionary) -> bool: return e["kind"] == "entrepreneur").size()
	var opened := month.filter(func(e: Dictionary) -> bool: return e["kind"] == "opened").size()
	var closed := month.filter(func(e: Dictionary) -> bool: return e["kind"] == "closed").size()
	lines.append("Nowych firm: %d, upadło: %d, nowych przedsiębiorców: %d." % [opened, closed, newcomers])
	return lines.slice(maxi(0, lines.size() - COLUMN_LINES))


static func _roads(month: Array) -> Array:
	var lines: Array = []
	for e: Dictionary in month:
		if e["kind"] in ["road", "bandits"]:
			lines.append(_short(str(e["text"])))
	var robberies := month.filter(func(e: Dictionary) -> bool: return e["kind"] == "robbery").size()
	if robberies > 0:
		lines.append("Rabunków na drogach: %d." % robberies)
	if lines.is_empty():
		lines.append("Na drogach spokojnie.")
	return lines.slice(maxi(0, lines.size() - COLUMN_LINES))


static func _families(w: EconWorld) -> Array:
	var fams := {}
	var heads := {}
	for a: EconActor in w.living_actors():
		fams[a.family_id] = float(fams.get(a.family_id, 0.0)) + w.actor_wealth(a)
		if not heads.has(a.family_id):
			heads[a.family_id] = a
	var ids: Array = fams.keys()
	ids.sort_custom(func(x: int, y: int) -> bool: return float(fams[x]) > float(fams[y]))
	var lines: Array = []
	for i in mini(COLUMN_LINES, ids.size()):
		var a: EconActor = heads[ids[i]]
		lines.append("%d. Ród %s: %.1f mln zł" % [i + 1, EconNames.family_genitive(EconPopulation.family_last(a)), float(fams[ids[i]]) / 1e6])
	return lines
