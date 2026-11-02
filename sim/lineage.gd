# SimLineage — ród jako byt prawno-społeczny (S1): nazwa, root (kotwica grafu) i członkowie.
# Przynależność zmieniają tylko zdarzenia (narodziny, ślub, odejście). Zmarli zostają
# w `members` jako historia rodu. Gospodarstwo (kto mieszka razem, kasa) to osobny byt.
class_name SimLineage
extends RefCounted


var id: int
var name: String
var surname: String       # nazwisko, które dostają dzieci rodu
var root_id: int = -1
var role: String = ""     # rola w okolicy z danych (np. „merchant”); pusta = zwykły ród
var members: Array = []   # id osób, w kolejności dołączenia


func _init(p_id: int, p_name: String, p_surname: String = "") -> void:
	id = p_id
	name = p_name
	surname = p_surname if p_surname != "" else p_name


func has(pid: int) -> bool:
	return pid in members


func add(p: SimPerson) -> void:
	if not p.id in members:
		members.append(p.id)
	p.lineage_id = id


func remove(p: SimPerson) -> void:
	members.erase(p.id)
	if root_id == p.id:
		root_id = -1
	if p.lineage_id == id:
		p.lineage_id = -1
