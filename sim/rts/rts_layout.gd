# RtsLayout — gdzie na mapie stoją rzeczy (km). Deterministycznie z seeda i id:
# bloki mieszkalne w tarczy miasta (spirala złotego kąta — wygląda jak zabudowa),
# firmy w pierścieniach wg rodzaju (usługi w centrum, przetwórstwo dookoła,
# ciężki przemysł dalej, pola, szyby i kopalnie za miastem).
class_name RtsLayout
extends RefCounted


const GOLDEN := 2.39996323
const RING_OF := {
	"services": "services", "bakery": "processing", "mill": "processing", "sawmill": "processing",
	"furniture_factory": "processing", "appliance_factory": "heavy", "vehicle_plant": "heavy",
	"refinery": "heavy", "chemical_plant": "heavy", "steelworks": "heavy", "cement_works": "heavy",
	"haulage": "haulage",
}


static func city_radius(lp: Dictionary, c: EconCity) -> float:
	return float(lp["radius_base_km"]) + sqrt(c.population) * float(lp["radius_per_sqrt_pop_km"])


static func _h(seed: int, id: int, purpose: String) -> float:
	return float(SimRng.hash3(seed, id, purpose)) / 4294967295.0


# Pozycja firmy (km). Ten sam seed i id -> zawsze to samo miejsce.
static func business_pos(w: EconWorld, lp: Dictionary, b: EconBusiness) -> Vector2:
	var c := w.city_of(b)
	var ring_name: String = RING_OF.get(b.type, "raw")
	var ring: Array = lp["rings"][ring_name]
	var r := city_radius(lp, c)
	var t := _h(w.world_seed, b.id, "ring")
	var rad := r * lerpf(float(ring[0]), float(ring[1]), sqrt(t))
	var ang := _h(w.world_seed, b.id, "angle") * TAU
	return c.pos + Vector2(cos(ang), sin(ang)) * rad


# Bloki mieszkalne miasta: [pozycja km, wielkość 0..1] — liczba rośnie z ludnością.
static func housing(w: EconWorld, lp: Dictionary, c: EconCity) -> Array:
	var n := clampi(int(c.population / float(lp["people_per_block"])), int(lp["min_blocks"]), int(lp["max_blocks"]))
	var r := city_radius(lp, c) * 0.62
	var out: Array = []
	var rot := _h(w.world_seed, c.id, "rot") * TAU
	for i in n:
		var rr := r * sqrt((float(i) + 0.5) / float(n))
		var ang := float(i) * GOLDEN + rot
		var jitter := Vector2(_h(w.world_seed, c.id * 1000 + i, "jx") - 0.5, _h(w.world_seed, c.id * 1000 + i, "jy") - 0.5) * r * 0.08
		var size := 1.0 - rr / maxf(r, 1e-6) * 0.6
		out.append([c.pos + Vector2(cos(ang), sin(ang)) * rr + jitter, size])
	return out
