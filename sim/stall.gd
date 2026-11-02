# SimStall — stragan (S16, M1): lada w konkretnym miejscu, właściciel (gospodarstwo)
# i towar. Towar leży w zapasie straganu albo budynku, przy którym stoi (np. dwór
# sprzedaje ze spichrza). Sprzedaje i skupuje tylko wtedy, gdy ktoś stoi za ladą.
# Na noc sprzedawca go zwija; niezwinięty i niepilnowany kusi złodziei (faza P).
class_name SimStall
extends RefCounted


var id: String
var building: SimBuilding      # gdzie stoi lada
var stock: SimBuilding         # skąd bierze się towar (sam stragan albo budynek obok)
var owner: int                 # id gospodarstwa
var goods: Array = []          # czym handluje
var keeper: int = -1           # agent za ladą (-1 = nikogo)
var packed := true             # zwinięty na noc (towar schowany)
var buys: Array = []           # co skupuje (reszta tylko na sprzedaż)
var wants: Dictionary = {}     # limit skupu: towar -> ile jeszcze weźmie (brak klucza = bez limitu)
var temporary := false         # wóz kupca wędrownego: znika po odjeździe
var last_deal: float = 0.0     # kiedy ostatnio ktoś coś tu kupił albo sprzedał (doby)


func _init(p_building: SimBuilding, p_stock: SimBuilding, p_owner: int, p_goods: Array) -> void:
	id = p_building.id
	building = p_building
	stock = p_stock
	owner = p_owner
	goods = p_goods.duplicate()


func counter() -> Vector2:
	return building.door()


func is_open() -> bool:
	return keeper >= 0 and not packed


func deals_in(good: String) -> bool:
	return good in goods
