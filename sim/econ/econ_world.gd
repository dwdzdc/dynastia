# EconWorld — wielka gospodarka, która żyje bez gracza (docs/design/world-economy.md).
# Czysta, deterministyczna logika (ADR-0002): RNG tylko z seeda, iteracja w
# porządku wstawiania. Pieniądze w zamkniętym obiegu: money_total() jest stałe.
# Doba: wstrząsy → praca → firmy → ciężarówki → konsumpcja → ceny → aktorzy →
# ludność → kronika.
class_name EconWorld
extends RefCounted


var data: Dictionary
var rng: SimRng
var world_seed: int
var day: int = 0

var cities: Array[EconCity] = []
var routes: Array[EconRoute] = []
var dist: Array[PackedFloat32Array] = []   # odległości drogowe [a][b] (km)
var actors: Dictionary = {}                # id -> EconActor (także zmarli, alive=false)
var businesses: Dictionary = {}            # id -> EconBusiness
var trucks: Dictionary = {}                # id -> EconTruck
var news: EconNews

var goods: Dictionary                      # data["goods"]
var recipes: Dictionary                    # data["recipes"]
var producer_of: Dictionary = {}           # towar -> id przepisu
var tradable: Array[String] = []           # towary, które da się wozić ciężarówką

var _next_id := 1
var stats: Dictionary = {}                 # liczniki do sondy i kroniki
var truck_profit_ema: float = 0.0          # średni zysk z kursu (decyzje o kupnie ciężarówek)
var last_money: float = 0.0
var state_cash: float = 0.0                # skarb państwa (EconState)
var state_income_today: float = 0.0
var state_income_ema: float = 0.0
var supply_cache: Dictionary = {}          # EconInvest: moc produkcyjna (liczona raz na dobę)
var supply_cache_day: int = -1


func _init(seed_: int, data_: Dictionary, warmup: bool = true) -> void:
	world_seed = seed_
	data = data_
	rng = SimRng.new(seed_)
	goods = data["goods"]
	recipes = data["recipes"]
	for rid: String in recipes.keys():
		var out: String = recipes[rid]["out"]
		if out != "":
			producer_of[out] = rid
	for g: String in goods.keys():
		var spec: Dictionary = goods[g]
		if not bool(spec.get("local_only", false)) and float(spec["weight"]) > 0.0:
			tradable.append(g)
	news = EconNews.new(self)
	stats = {"founded": 0, "closed": 0, "sold": 0, "fires": 0, "strikes": 0, "robberies": 0,
		"trips": 0, "deaths": 0, "entrepreneurs": 0, "retired": 0, "trucks_bought": 0, "trucks_scrapped": 0,
		"closures": 0, "discoveries": 0, "migrants": 0.0}
	EconMap.generate(self)
	for c: EconCity in cities:
		for g: String in goods.keys():
			c.markets[g] = EconMarket.new(g, float(goods[g]["base"]), float(goods[g].get("spoil", 0.0)))
	EconSetup.populate(self)
	last_money = money_total()
	if warmup:
		for i in int(data["world"]["warmup_days"]):
			step_day()
		news.entries.clear()
		for k: String in stats.keys():
			stats[k] = 0.0 if k == "migrants" else 0


func new_id() -> int:
	_next_id += 1
	return _next_id


# --- pieniądze -------------------------------------------------------------

func money_total() -> float:
	var s := 0.0
	for c: EconCity in cities:
		s += c.cash
	for a: EconActor in actors.values():
		s += a.cash
	for b: EconBusiness in businesses.values():
		s += b.cash
	return s + state_cash


# Zapłata sprzedawcy za towar z rynku (callback dla EconMarket.buy).
func pay_seller(seller_id: int, amount: float) -> void:
	var b: EconBusiness = businesses.get(seller_id)
	if b != null:
		b.cash += amount
		b.revenue_today += amount
		return
	# Sprzedawca zniknął (firma zlikwidowana): pieniądze idą do miasta.
	cities[0].cash += amount


# --- zapytania ---------------------------------------------------------------

func city_of(b: EconBusiness) -> EconCity:
	return cities[b.city_id]


func actor(id: int) -> EconActor:
	return actors.get(id) as EconActor


func business(id: int) -> EconBusiness:
	return businesses.get(id) as EconBusiness


func recipe(type: String) -> Dictionary:
	return recipes[type]


func good_name(g: String) -> String:
	return str(goods[g]["name"])


func living_actors() -> Array:
	return actors.values().filter(func(a: EconActor) -> bool: return a.alive)


func actor_wealth(a: EconActor) -> float:
	var s := a.cash
	for bid: int in a.businesses:
		var b: EconBusiness = businesses.get(bid)
		if b != null:
			s += b.cash + EconInvest.book_value(self, b)
	return s


func total_population() -> float:
	var s := 0.0
	for c: EconCity in cities:
		s += c.population
	return s


# --- doba --------------------------------------------------------------------

func step_day() -> void:
	EconEvents.step(self)
	EconLabor.step(self)
	EconState.step(self)
	EconProduction.step(self)
	EconLogistics.step(self)
	EconConsumption.step(self)
	var mp: Dictionary = data["market"]
	var record := day % int(mp["history_every"]) == 0
	for c: EconCity in cities:
		for m: EconMarket in c.markets.values():
			m.end_day(mp, record)
		if record:
			_record_city(c, int(mp["history_len"]))
	EconInvest.step(self)
	EconPopulation.step(self)
	news.step()
	day += 1


func _record_city(c: EconCity, keep: int) -> void:
	for k: String in ["population", "unemployment", "satisfaction", "wage"]:
		if not c.history.has(k):
			c.history[k] = []
		var arr: Array = c.history[k]
		var v := 0.0
		match k:
			"population": v = c.population
			"unemployment": v = c.unemployment()
			"satisfaction": v = c.satisfaction
			"wage": v = c.wage
		arr.append(v)
		if arr.size() > keep:
			arr.remove_at(0)


# Pozycja ciężarówki na mapie (do podglądu): `t` = czas świata z ułamkiem doby.
func truck_pos(tr: EconTruck, t: float) -> Vector2:
	if not tr.moving or tr.path.is_empty():
		return cities[tr.city_id].pos
	var total := tr.arrive_time - tr.depart_time
	var f := clampf((t - tr.depart_time) / maxf(total, 1e-6), 0.0, 1.0)
	var km_total := 0.0
	for rid: int in tr.path:
		km_total += routes[rid].length
	var target := f * km_total
	var cur := tr.city_id
	for rid: int in tr.path:
		var r: EconRoute = routes[rid]
		var nxt := r.other(cur)
		if target <= r.length:
			return cities[cur].pos.lerp(cities[nxt].pos, target / maxf(r.length, 1e-6))
		target -= r.length
		cur = nxt
	return cities[tr.to_city].pos
