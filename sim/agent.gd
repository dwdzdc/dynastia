# SimAgent — ciało w świecie: pozycja, potrzeby, zdrowie, przydział pracy, niesiony
# towar i kolejka kroków planu. Warstwa logistyki (ADR-0001): nie zna rodziny ani
# więzi — warstwa tożsamości (sim/family.gd) ustawia tylko modyfikatory
# (work_mult, speed_mult, is_child) i czyta zdrowie.
#
# Plan to kolejka kroków (Dictionary):
#   { t = "walk", to: Vector2, why }                 — idź
#   { t = "act", act, left, why, inside?, at? }      — czynność przez `left` sekund sim
#   { t = "do", fn, arg }                            — natychmiastowy efekt w SimJobs
class_name SimAgent
extends RefCounted


const WORK_ACTS := ["chop", "saw", "craft", "forage"]

var id: int
var person_id: int = -1
var position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
var home_id: String = "home"

var job: String = "none"            # none | woodcutter | sawyer | carpenter | carrier | laborer
var skills: Dictionary = {}         # chop | saw | craft -> 0..max
var needs: Dictionary = { "food": 100.0, "sleep": 100.0 }
var health: float = 100.0
var sick_days: float = 0.0
var injured_days: float = 0.0
var status: String = "active"       # active | jailed | dead
var jail_days: float = 0.0

var carrying: String = ""
var carrying_qty: int = 0
var carrying_qualities: Array = []

var steps: Array = []
var plan_kind: String = ""          # eat | sleep | work | chore | rest | child | sick | manual
var claims: Array = []              # rezerwacje (np. "tree:12", "chore:food")

# Stan do odczytu przez widok
var activity: String = "idle"       # walk | chop | saw | craft | labor | sleep | eat | rest | play | wait | idle
var idle_reason: String = ""
var alert: bool = false             # problem wymagający uwagi gracza
var hidden: bool = false            # wewnątrz budynku
var inside: String = ""             # id budynku, w którym jest
var controlled: bool = false
var hungry_no_food: bool = false
var cold: bool = false
var dinner_day: int = -1            # doba ostatniej kolacji przy wspólnym stole
var follow_id: int = -1             # dziecko: za kim chodzi z nakazu gracza (id osoby); -1 = z sympatii

# Modyfikatory od warstwy tożsamości
var is_child: bool = false
var age_eff: float = 1.0
var work_mult: Dictionary = {}      # act -> mnożnik (z traitów), klucz "all" dla wszystkiego
var speed_mult: float = 1.0
var accident_mult: float = 1.0
var quality_bonus: float = 0.0
var sick_mult: float = 1.0
var regen_mult: float = 1.0


func _init(p_id: int) -> void:
	id = p_id


func is_active() -> bool:
	return status == "active"


func disabled() -> bool:
	return sick_days > 0.0 or injured_days > 0.0


func can_work() -> bool:
	return not is_child and age_eff > 0.0 and not disabled()


func inside_home() -> bool:
	return inside == home_id


func skill(name: String) -> float:
	return float(skills.get(name, 0.0))


func trait_mult(act: String) -> float:
	return float(work_mult.get("all", 1.0)) * float(work_mult.get(act, 1.0))


func clear_carry() -> void:
	carrying = ""
	carrying_qty = 0
	carrying_qualities = []


func current_step() -> Dictionary:
	if steps.is_empty():
		return {}
	return steps[0]


# Krok, który można przerwać bez utraty wykonanej pracy.
# `drop_work`: czy wolno też przerwać rozpoczętą robotę (np. na kolację) — postęp czynności przepada.
func interruptible(drop_work := false) -> bool:
	if steps.is_empty():
		return true
	var s: Dictionary = steps[0]
	if s["t"] == "walk":
		return true
	if s["t"] == "act":
		var act := String(s["act"])
		if drop_work and act in WORK_ACTS:
			return true
		return act in ["wait", "rest", "sleep", "labor", "play", "idle", "dine", "watch"]
	return false
