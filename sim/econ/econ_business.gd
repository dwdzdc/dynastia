# EconBusiness — firma: aktywo z właścicielem (EconActor), które może zmienić
# właściciela. Typ to przepis z data/economy.json ("recipes"). Firma przewozowa
# (haulage) zamiast produkcji ma ciężarówki (EconTruck).
class_name EconBusiness
extends RefCounted


var id: int
var type: String
var name: String
var city_id: int
var owner_id: int
var cash: float = 0.0
var level: int = 1
var workers: float = 0.0
var status: String = "active"     # building / active / burned / strike / closed
var status_until: int = -1
var founded_day: int = 0
var inputs: Dictionary = {}       # towar -> zapas wejść w magazynie
var trucks: Array[int] = []       # haulage: id ciężarówek
var extra_workers: float = 0.0    # ludzie gracza pracujący na miejscu (jednostki RTS)
var extra_payee: int = -1         # komu idą ich pensje (aktor-gracz)
var extra_paid: bool = true       # czy wczoraj dostali wypłatę
var steward: bool = true          # firma gracza: zarządca sam dokłada kapitał obrotowy

# Budowa albo rozbudowa: materiały do kupienia, potem dni pracy.
var project: Dictionary = {}      # { "materials": {towar: ile}, "days": int, "to_level": int }

# Księgowość (decyzje właściciela i kronika).
var revenue_today: float = 0.0
var cost_today: float = 0.0
var profit_ema: float = 0.0
var cost_ema: float = 0.0
var loss_days: int = 0
var broke_days: int = 0
var for_sale: bool = false
var listed_day: int = -1
var ask_price: float = 0.0
var produced_today: float = 0.0


func _init(id_: int, type_: String, city_id_: int, owner_id_: int) -> void:
	id = id_
	type = type_
	city_id = city_id_
	owner_id = owner_id_


func is_running() -> bool:
	return status == "active"


func is_open() -> bool:
	return status != "closed"
