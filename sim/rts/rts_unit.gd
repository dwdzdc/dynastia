# RtsUnit — człowiek gracza na mapie (wąski krąg). Chodzi płynnie (km), dostaje
# ogólne zadanie jak w Cultures (praca w firmie) albo rozkaz ręczny (idź tam).
# Zawsze umie powiedzieć, co robi i czemu stoi (`reason`).
class_name RtsUnit
extends RefCounted


var id: int
var first: String
var last: String
var female: bool
var pos: Vector2
var target := Vector2.ZERO
var walking := false
var order: Dictionary = {"kind": "idle"}   # idle / move {to} / work {business}
var inside: int = -1                       # id firmy, w której pracuje
var reason: String = "czeka na zadanie"
var earned: float = 0.0                    # zarobione łącznie


func _init(id_: int) -> void:
	id = id_


func full_name() -> String:
	return "%s %s" % [first, last]
