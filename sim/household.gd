# SimHousehold — gospodarstwo domowe (S6): kto mieszka razem i ma wspólną kasę.
# Gotówka, dług, cele zapasów i reputacja rzemieślnicza. Ceny i targ: SimMarket.
# Spiżarnia i opał leżą w zapasie budynku domu (`home_id`). Ród ma 0..n gospodarstw.
# Pieniądze (S14) leżą w skrzyni w domu (`chest`); `cash` to tylko podgląd skrzyni.
# Bez dachu nad głową gospodarstwo nosi je w tobołku.
class_name SimHousehold
extends RefCounted


var id: int
var home_id: String
var members: Array = []              # id osób

var chest: SimBuilding = null        # budynek ze skrzynią gospodarstwa (dom)
var _bundle := 0.0                   # pieniądze bez domu: tobołek
var cash: float:
	get:
		return float(chest.chests.get(id, 0.0)) if chest != null else _bundle
	set(v):
		if chest != null:
			chest.chests[id] = v
		else:
			_bundle = v
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

var _rep_decay: float


func _init(p_id: int, p_home: String, eco: Dictionary, start_cash: float) -> void:
	id = p_id
	home_id = p_home
	cash = start_cash
	debt_interest = float(eco["debt_interest_per_day"])
	debt_limit = float(eco["debt_limit"])
	target_food = int(eco["default_target_food"])
	target_firewood = int(eco["default_target_firewood"])
	_rep_decay = float(eco["reputation_decay_day"])


# Przeprowadzka: skrzynia jedzie z gospodarstwem (null = tobołek, bez domu).
func set_chest(b: SimBuilding) -> void:
	var c := cash
	if chest != null:
		chest.chests.erase(id)
	chest = b
	cash = c


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
