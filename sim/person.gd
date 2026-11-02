# SimPerson — warstwa tożsamości nad ciałem (SimAgent): imię, płeć, wiek, krew,
# drzewo genealogiczne, cechy i charakter. Fakty drzewa (rodzice, małżeństwo) nie są kasowane —
# śmierć ustawia tylko death_day (intro §4.2).
class_name SimPerson
extends RefCounted


var id: int
var name: String
var surname: String
var sex: String                 # m | f
var birth_day: float            # doba narodzin (może być ujemna dla starszyzny)
var death_day: float = -1.0
var death_cause: String = ""
var mother_id: int = -1
var father_id: int = -1
var spouse_id: int = -1
var blood: bool = false         # krew rodu (linia, którą czyta sukcesja i game over)
var attached: bool = false      # wżeniony małżonek
var lineage_id: int = -1        # ród, do którego należy (S1); -1 = żaden
var purse: float = 0.0          # pieniądze przy sobie (S5, S14)
var held: float = 0.0           # z tego: pieniądze gospodarstwa wzięte ze skrzyni (do oddania ponad kieszonkowe)
var household_id: int = -1      # gospodarstwo, w którym mieszka (S6)
var weak_days: int = 0          # ile dób z rzędu siła przynależności jest poniżej progu
var traits: Array = []          # cechy ciała i talentu (silny, chorowity…), z wpływem na ciało
var character: Array = []       # charakter (lojalny, porywczy…), wpływa na więzi i wolę
var agent_id: int = -1
var seeking_spouse: bool = false
var pregnant_left: float = -1.0 # doby do porodu; <0 = nie w ciąży
var children: Array = []
var unions: Array = []          # { spouse, start, end } — historia małżeństw, nic nie jest kasowane


func alive() -> bool:
	return death_day < 0.0


func full_name() -> String:
	return "%s %s" % [name, surname]


# Przeżyte doby. Wiek w latach to tylko etykieta liczona z etapów (SimFamily.age_of).
func days_lived(now_day: float) -> float:
	var end := death_day if death_day >= 0.0 else now_day
	return end - birth_day
