# EconTruck — ciężarówka firmy przewozowej. Stoi w mieście albo jedzie trasą
# (lista dróg) z ładunkiem; pozycja do podglądu wynika z czasu odjazdu i przyjazdu.
class_name EconTruck
extends RefCounted


var id: int
var company_id: int
var city_id: int                  # gdzie stoi (albo skąd wyjechała)
var moving: bool = false
var path: Array[int] = []         # id dróg
var to_city: int = -1
var depart_time: float = 0.0
var arrive_time: float = 0.0
var good: String = ""
var spot: Dictionary = {}         # gdzie stoi (EconLayout: pos, route, s, bid)
var dest_spot: Dictionary = {}    # dokąd jedzie (budynek odbiorcy albo parking)
var pts: PackedVector2Array = PackedVector2Array()   # przebieg kursu (km), od budynku do budynku
var cum: PackedFloat32Array = PackedFloat32Array()   # długości narastająco
var from_bid: int = -1            # skąd ładunek (firma), do podglądu
var to_bid: int = -1              # do kogo (firma)
var deliver_to: int = -1          # dostawa prosto do magazynu firmy (własna firma gracza)
var qty: float = 0.0
var cost_basis: float = 0.0       # ile kosztował ładunek + paliwo (zysk z kursu)
var mode: String = "auto"         # auto (sama szuka kursów) / manual / route (rozkazy gracza)
var route: Dictionary = {}         # trasa stała: { from, to, good }
var tank: float = 0.0             # paliwo w baku (tankuje do pełna tam, gdzie jest)
var next_plan_day: int = 0        # po nieudanym szukaniu kursu czeka kilka dób
var stuck_days: int = 0           # ile dób stoi bez paliwa
var retire_day: int = 0
var trips: int = 0
var profit_total: float = 0.0


func _init(id_: int, company_id_: int, city_id_: int) -> void:
	id = id_
	company_id = company_id_
	city_id = city_id_
