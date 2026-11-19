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
var states: Array[EconState] = []          # państwa (polityki z data/economy.json → "states")
var capitals: Array[int] = []              # stolica każdego państwa (id miasta)
var supply_cache: Dictionary = {}          # EconInvest: moc produkcyjna (liczona raz na dobę)
var supply_cache_day: int = -1
var fleet_use_cache: float = 1.0
var fleet_use_day: int = -1
var _firms_by_city: Array = []             # firmy wg miasta (odświeżane raz na dobę)
var _firms_day: int = -1


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
	var sid := 0
	for spec: Dictionary in data["states"]:
		states.append(EconState.from_data(sid, spec))
		sid += 1
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


# Nowa firma w świecie: dostaje miejsce na mapie i dojazd do drogi.
func add_business(b: EconBusiness) -> void:
	businesses[b.id] = b
	EconLayout.place(self, b)


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
	for st: EconState in states:
		s += st.cash
	return s


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

func state_of_city(city_id: int) -> EconState:
	return states[cities[city_id].state_id]


# Cło przy wwozie z miasta `from_id` do miasta `to_id` (stawka od wartości; 0 w kraju).
func tariff_rate(from_id: int, to_id: int) -> float:
	var a := cities[from_id].state_id
	var b := cities[to_id].state_id
	return 0.0 if a == b else states[b].import_rate()


# Skarb wszystkich państw (do sondy i podglądu).
func state_cash() -> float:
	var s := 0.0
	for st: EconState in states:
		s += st.cash
	return s


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


# Otwarte firmy w mieście (lista liczona raz na dobę).
func firms_in(city_id: int) -> Array:
	if _firms_day != day or _firms_by_city.size() != cities.size():
		_firms_day = day
		_firms_by_city.clear()
		for c: EconCity in cities:
			_firms_by_city.append([])
		for b: EconBusiness in businesses.values():
			if b.is_open():
				(_firms_by_city[b.city_id] as Array).append(b)
	return _firms_by_city[city_id]


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
	for ph: Array in phases():
		(ph[1] as Callable).call()
	day += 1


# Fazy doby w kolejności (sonda mierzy ich czas tą samą listą).
func phases() -> Array:
	return [
		["events", func() -> void: EconEvents.step(self)],
		["labor", func() -> void: EconLabor.step(self)],
		["state", func() -> void:
			for st: EconState in states:
				st.step(self)],
		["production", func() -> void: EconProduction.step(self)],
		["logistics", func() -> void: EconLogistics.step(self)],
		["consumption", func() -> void: EconConsumption.step(self)],
		["markets", _end_markets],
		["invest", func() -> void: EconInvest.step(self)],
		["population", func() -> void: EconPopulation.step(self)],
		["news", func() -> void: news.step()],
	]


func _end_markets() -> void:
	var mp: Dictionary = data["market"]
	var record := day % int(mp["history_every"]) == 0
	for c: EconCity in cities:
		for m: EconMarket in c.markets.values():
			m.end_day(mp, record)
		if record:
			_record_city(c, int(mp["history_len"]))


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


# Pozycja ciężarówki na mapie: `t` = czas świata z ułamkiem doby. Jedzie od budynku
# do budynku po łamanej kursu (EconTruck.pts) ze stałą prędkością.
func truck_pos(tr: EconTruck, t: float) -> Vector2:
	if not tr.moving or tr.pts.size() < 2:
		return tr.spot.get("pos", cities[tr.city_id].pos)
	var total := tr.arrive_time - tr.depart_time
	var f := clampf((t - tr.depart_time) / maxf(total, 1e-6), 0.0, 1.0)
	return EconLayout.point_on(tr.pts, tr.cum, f * tr.cum[tr.cum.size() - 1])
