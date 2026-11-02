# SimHousehold — gospodarstwo domowe (S6): kto mieszka razem i ma wspólną kasę.
# Gotówka, dług, czynsz, cele zapasów, reputacja i (do H1) targ z nasyceniem dziennym.
# Spiżarnia i opał leżą w zapasie budynku domu (`home_id`). Ród ma 0..n gospodarstw.
class_name SimHousehold
extends RefCounted


var id: int
var home_id: String
var members: Array = []              # id osób

var cash: float
var debt: float = 0.0
var debt_interest: float             # na dobę
var debt_limit: float
var evict_days: int = 0              # ile dób z rzędu dług za dom przekracza próg eksmisji

var target_food: int
var target_firewood: int
var sell_planks: bool = true
var reputation: float = 0.0          # sfera: stolarstwo
var earned_today: float = 0.0
var spent_today: float = 0.0
var last_day_net: float = 0.0
var burn_acc: float = 0.0            # ułamek kłody opału do spalenia

var _prices: Dictionary
var _sold_today: Dictionary = {}     # good -> szt. (nasycenie rynku)
var _sat_per_unit: float
var _sat_min: float
var _rep_per_chair: float
var _rep_price_mult: float
var _rep_decay: float


func _init(p_id: int, p_home: String, eco: Dictionary, start_cash: float) -> void:
	id = p_id
	home_id = p_home
	cash = start_cash
	debt_interest = float(eco["debt_interest_per_day"])
	debt_limit = float(eco["debt_limit"])
	target_food = int(eco["default_target_food"])
	target_firewood = int(eco["default_target_firewood"])
	_prices = eco["prices"]
	_sat_per_unit = float(eco["saturation_per_unit"])
	_sat_min = float(eco["saturation_min"])
	_rep_per_chair = float(eco["reputation_per_chair"])
	_rep_price_mult = float(eco["reputation_price_mult"])
	_rep_decay = float(eco["reputation_decay_day"])


func food_price() -> float:
	return float(_prices["food"])


func firewood_price() -> float:
	return float(_prices["firewood"])


func saturation(good: String) -> float:
	return maxf(_sat_min, 1.0 - _sat_per_unit * float(_sold_today.get(good, 0)))


func plank_price() -> float:
	return float(_prices["plank"]) * saturation("plank")


func chair_price(quality: float) -> float:
	var base := float(_prices["chair_base"]) + float(_prices["chair_quality_mult"]) * quality
	return base * saturation("chair") * (1.0 + _rep_price_mult * reputation)


# Sprzedaż na targu; zwraca uzyskaną kwotę.
func sell(good: String, qty: int, qualities: Array) -> float:
	var total := 0.0
	for i in qty:
		if good == "chair":
			var q: float = float(qualities[i]) if i < qualities.size() else 0.3
			total += chair_price(q)
			reputation += _rep_per_chair * (q - 0.35) * 2.0
			reputation = maxf(reputation, -20.0)
		else:
			total += plank_price()
		_sold_today[good] = int(_sold_today.get(good, 0)) + 1
	_earn(total)
	return total


func can_afford(amount: float) -> bool:
	return cash >= amount


func pay(amount: float) -> void:
	cash -= amount
	spent_today += amount


func _earn(amount: float) -> void:
	# Zarobek najpierw spłaca dług.
	if debt > 0.0:
		var d := minf(debt, amount)
		debt -= d
		amount -= d
	cash += amount
	earned_today += amount


# Wydatek, na który nie ma odmowy (np. wesele): brakująca część idzie w dług.
func pay_or_debt(amount: float) -> void:
	var paid := minf(maxf(cash, 0.0), amount)
	cash -= paid
	spent_today += paid
	debt += amount - paid


func earn(amount: float) -> void:
	_earn(amount)


# Wywoływane raz na dobę: bilans, nasycenie targu, reputacja, odsetki.
func new_day() -> void:
	last_day_net = earned_today - spent_today
	earned_today = 0.0
	spent_today = 0.0
	_sold_today.clear()
	# Reputacja wraca powoli ku zeru (dobra słabnie, zła się zapomina).
	reputation = maxf(0.0, reputation - _rep_decay) if reputation > 0.0 else minf(0.0, reputation + _rep_decay)
	if debt > 0.0:
		debt *= 1.0 + debt_interest


# Opłata dzienna (czynsz): płaci z kasy, brak idzie w dług. Zwraca zapłaconą część.
func pay_due(amount: float) -> float:
	var paid := minf(maxf(cash, 0.0), amount)
	cash -= paid
	spent_today += paid
	debt += amount - paid
	return paid
