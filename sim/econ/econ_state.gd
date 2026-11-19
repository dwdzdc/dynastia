# EconState — państwo: kasa, miasta i lista polityk (EconPolicy) z danych
# (data/economy.json → "states"). Zamyka obieg pieniędzy: zbiera podatki i wydaje
# je na ludzi. Nic nie bierze się z powietrza: wydaje tylko to, co zebrało.
# Świat może mieć wiele państw; miasto należy do jednego (EconCity.state_id).
class_name EconState
extends RefCounted


# Rejestr klocków polityk: nowa polityka = nowy skrypt + jedna linia tutaj.
const POLICIES := {
	"dividend_tax": preload("res://sim/econ/policies/dividend_tax.gd"),
	"wealth_tax": preload("res://sim/econ/policies/wealth_tax.gd"),
	"public_jobs": preload("res://sim/econ/policies/public_jobs.gd"),
	"unemployment_benefit": preload("res://sim/econ/policies/unemployment_benefit.gd"),
	"pensions": preload("res://sim/econ/policies/pensions.gd"),
	"import_tariff": preload("res://sim/econ/policies/import_tariff.gd"),
}

var id: int
var name: String
var cash: float = 0.0
var income_today: float = 0.0
var income_ema: float = 0.0
var spend_of_savings: float = 0.02
var policies: Array[EconPolicy] = []


static func from_data(id_: int, spec: Dictionary) -> EconState:
	var st := EconState.new()
	st.id = id_
	st.name = str(spec.get("name", "Państwo"))
	st.spend_of_savings = float(spec.get("spend_of_savings", 0.02))
	for p: Dictionary in spec["policies"]:
		var script: GDScript = POLICIES.get(str(p["type"]))
		if script == null:
			push_error("EconState: nieznana polityka %s" % p["type"])
			continue
		st.policies.append((script.new() as EconPolicy).setup(p))
	return st


func has_city(city_id: int) -> bool:
	return city_id >= 0 and city_id < _cities_cache.size() and _cities_cache[city_id]


var _cities_cache: Array[bool] = []


func cities_of(w: EconWorld) -> Array:
	return w.cities.filter(func(c: EconCity) -> bool: return c.state_id == id)


func population(w: EconWorld) -> float:
	var s := 0.0
	for c: EconCity in cities_of(w):
		s += c.population
	return s


func collect(amount: float) -> void:
	cash += amount
	income_today += amount


func tax_dividend(w: EconWorld, amount: float) -> float:
	var tax := 0.0
	for p: EconPolicy in policies:
		tax += p.tax_dividend(w, self, amount)
	tax = minf(tax, amount)
	collect(tax)
	return tax


# Stawka cła przy wwozie (suma polityk celnych).
func import_rate() -> float:
	var r := 0.0
	for p: EconPolicy in policies:
		r += p.import_rate()
	return r


var tariffs_today: float = 0.0
var tariffs_total: float = 0.0


# Cło od wwiezionego towaru: zwraca, ile pobrano (płacący sam zdejmuje to ze swojej kasy).
func charge_import(value: float, can_pay: float) -> float:
	var duty := minf(value * import_rate(), maxf(can_pay, 0.0))
	if duty > 0.0:
		collect(duty)
		tariffs_total += duty
	return duty


# Doba państwa: podatki, potem wydatki wg udziałów polityk ("rest" dostaje resztę).
func step(w: EconWorld) -> void:
	_cities_cache.clear()
	for c: EconCity in w.cities:
		_cities_cache.append(c.state_id == id)
	for p: EconPolicy in policies:
		p.collect(w, self)
	income_ema = lerpf(income_ema, income_today, 0.05)
	income_today = 0.0
	var budget := minf(cash, income_ema + cash * spend_of_savings)
	if budget <= 0.0:
		for c: EconCity in cities_of(w):
			c.employed -= c.public_workers
			c.public_workers = 0.0
		return
	var spent := 0.0
	var rest: Array[EconPolicy] = []
	for p: EconPolicy in policies:
		var sh: Variant = p.share()
		if typeof(sh) == TYPE_STRING and str(sh) == "rest":
			rest.append(p)
		elif float(sh) > 0.0:
			spent += p.spend(w, self, budget * float(sh))
	var left := maxf(0.0, budget - spent)
	for p: EconPolicy in rest:
		spent += p.spend(w, self, left / rest.size())
	cash -= spent
