# EconPolicy — jedna polityka państwa (klocek). Nowa polityka = nowy skrypt w
# sim/econ/policies/ dziedziczący po tej klasie + wpis w EconState.POLICIES +
# wpis w data/economy.json ("states" → "policies"). Zaczepy:
#   collect(w, st)            — codzienne podatki (pieniądze do st.cash przez st.collect)
#   tax_dividend(w, st, kwota) — ile podatku od wypłaty dywidendy
#   spend(w, st, budżet)      — wydatki (pieniądze z kasy państwa do ludzi); zwraca wydane
#   import_rate()             — stawka cła od wartości towaru wwożonego z innego państwa
# Parametr "share" mówi, jaką część dziennego budżetu dostaje polityka ("rest" = reszta).
class_name EconPolicy
extends RefCounted


var params: Dictionary


func setup(p: Dictionary) -> EconPolicy:
	params = p
	return self


func collect(_w: EconWorld, _st: EconState) -> void:
	pass


func tax_dividend(_w: EconWorld, _st: EconState, _amount: float) -> float:
	return 0.0


func spend(_w: EconWorld, _st: EconState, _budget: float) -> float:
	return 0.0


func import_rate() -> float:
	return 0.0


func share() -> Variant:
	return params.get("share", 0.0)
