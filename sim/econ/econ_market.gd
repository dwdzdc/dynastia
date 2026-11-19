# EconMarket — rynek jednego towaru w jednym mieście.
# Towar leży w partiach należących do konkretnych sprzedawców (firm): kupujący
# płaci im proporcjonalnie do ich udziału, więc nie ma „kupca z nieskończoną kasą”.
# Cena to jedna kwota na dobę: rośnie, gdy zapas < kilka dób popytu albo popyt nie
# został zaspokojony, spada przy nadmiarze; widełki wokół ceny bazowej (jak w X4).
class_name EconMarket
extends RefCounted


var good: String
var base: float
var spoil: float = 0.0           # jaka część zapasu psuje się / przepada co dobę (usługi: całość)
var price: float
var lots: Dictionary = {}        # id sprzedawcy (firmy) -> ilość (zmieniać tylko metodami: suma w _total)
var _total: float = 0.0          # suma partii (stock() bez przeliczania)
var demand_today: float = 0.0    # ile chciano kupić dziś
var sold_today: float = 0.0
var short_today: float = 0.0     # ile zabrakło na półkach (popyt z pieniędzmi, bez towaru)
var supplied_today: float = 0.0  # ile dziś wystawiono
var demand_ema: float = 0.0
var use_today: float = 0.0       # popyt końcowy i produkcyjny (bez pośredników-przewoźników)
var use_ema: float = 0.0
var incoming: float = 0.0        # ile wiozą tu ciężarówki (żeby nie jechały wszystkie naraz)
var price_ema: float             # wolna średnia (kronika: skok / krach)
var history: Array[float] = []   # cena co `history_every` dób
var shock: String = ""           # ostatnia znana przyczyna zamieszania (dla kroniki)
var shock_until: int = -1


func _init(good_: String, base_: float, spoil_: float = 0.0) -> void:
	good = good_
	base = base_
	spoil = spoil_
	price = base_
	price_ema = base_


func stock() -> float:
	return maxf(_total, 0.0)


func stock_of(seller_id: int) -> float:
	return float(lots.get(seller_id, 0.0))


func add(seller_id: int, qty: float) -> void:
	if qty <= 0.0:
		return
	lots[seller_id] = float(lots.get(seller_id, 0.0)) + qty
	_total += qty
	supplied_today += qty


# Zdejmuje towar sprzedawcy z rynku (np. pożar magazynu). Zwraca, ile zdjęto.
func take_from(seller_id: int, qty: float) -> float:
	var have: float = float(lots.get(seller_id, 0.0))
	var got := minf(have, qty)
	if have - got <= 1e-6:
		lots.erase(seller_id)
		_total -= have
	else:
		lots[seller_id] = have - got
		_total -= got
	return got


# Kupno: najwyżej `qty`, najwyżej za `budget`. Płaci sprzedawcom przez `pay(seller_id, kwota)`.
# Zwraca [kupiona ilość, koszt]. Kupujący sam zdejmuje koszt ze swojej kasy.
# `exclude` — sprzedawca, od którego nie kupujemy (firma nie odkupuje własnego towaru).
func buy(qty: float, budget: float, pay: Callable, exclude: int = -1, is_trade: bool = false) -> Array:
	if qty <= 0.0 or budget <= 0.0 or price <= 0.0:
		return [0.0, 0.0]
	# Popyt to tylko to, na co kupujący ma pieniądze (inaczej biedni windują ceny).
	var effective := minf(qty, budget / price)
	demand_today += effective
	if not is_trade:
		use_today += effective
	var avail := stock() - stock_of(exclude)
	var want := minf(qty, budget / price)
	short_today += maxf(0.0, want - avail)
	var got := minf(want, avail)
	if got <= 1e-6:
		return [0.0, 0.0]
	var share := got / avail
	var cost := 0.0  # suma faktycznych wpłat: pieniądze zgadzają się co do grosza
	var taken := 0.0
	for s: int in lots.keys():
		if s == exclude:
			continue
		var q: float = lots[s]
		var take := q * share
		var amount := take * price
		cost += amount
		taken += take
		if q - take <= 1e-6:
			lots.erase(s)
			_total -= q
		else:
			lots[s] = q - take
			_total -= take
		pay.call(s, amount)
	sold_today += taken
	return [taken, cost]


# Sam popyt bez kupna (np. nikt nie ma ciężarówki na sprzedaż): podbija cenę.
func want(qty: float, budget: float) -> void:
	if qty <= 0.0 or budget <= 0.0 or price <= 0.0:
		return
	var effective := minf(qty, budget / price)
	demand_today += effective
	use_today += effective
	short_today += effective


# Raz na dobę: nowa cena z zapasu i niezaspokojonego popytu.
func end_day(p: Dictionary, record: bool) -> void:
	demand_ema = lerpf(demand_ema, demand_today, float(p["demand_ema"]))
	use_ema = lerpf(use_ema, use_today, float(p["demand_ema"]))
	# Jak w Port Royale: cena wynika z tego, na ile dób starcza zapas (pokrycie),
	# a nie narasta w nieskończoność. Pokrycie = target_days -> cena bazowa;
	# 0 -> maksimum; 3× target_days i więcej -> minimum. Cena dochodzi do celu stopniowo.
	var days := float(p["target_days"])
	var cover := (stock() + sold_today) / maxf(demand_ema, 1e-3)
	var mult := 1.0
	if cover < days:
		mult = pow(float(p["max_mult"]), 1.0 - cover / days)
	else:
		mult = pow(float(p["min_mult"]), minf(1.0, (cover - days) / (2.0 * days)))
	# Braki na półkach (popyt z pieniędzmi, bez towaru) dociskają cenę w górę.
	if demand_today > 1e-6:
		mult *= 1.0 + float(p["shortage_push"]) * clampf(short_today / demand_today, 0.0, 1.0)
	var goal := base * mult
	if demand_ema < 1e-3 and stock() < 1e-3:
		goal = price  # nikt nie kupuje i nic nie leży: cena bez zmian
	price = clampf(lerpf(price, goal, float(p["price_speed"])), base * float(p["min_mult"]), base * float(p["max_mult"]))
	price_ema = lerpf(price_ema, price, 0.02)
	if record:
		history.append(price)
		if history.size() > int(p["history_len"]):
			history.remove_at(0)
	if spoil > 0.0:
		for sid: int in lots.keys():
			var left: float = float(lots[sid]) * (1.0 - spoil)
			if left <= 1e-3:
				lots.erase(sid)
			else:
				lots[sid] = left
	# Raz na dobę liczymy sumę od nowa (bez narastania błędów zaokrągleń).
	_total = 0.0
	for q: float in lots.values():
		_total += q
	demand_today = 0.0
	use_today = 0.0
	short_today = 0.0
	sold_today = 0.0
	supplied_today = 0.0
