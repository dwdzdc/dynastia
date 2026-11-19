# EconLayout — gdzie na mapie stoją rzeczy (km) i którędy jeździ się między nimi.
# Firmy stoją w pierścieniach wokół miasta wg rodzaju (usługi w centrum, przetwórstwo
# dookoła, ciężki przemysł dalej, pola i kopalnie za miastem); miejsce wynika z seeda
# i id, ustalane raz przy powstaniu firmy. Każda firma ma dojazd do najbliższej drogi
# swojego miasta. Ciężarówka jedzie od budynku do budynku: dojazd → droga → (obwodnica
# w większych miastach) → drogi między miastami → dojazd do odbiorcy.
#
# „Miejsce” (spot) to słownik { pos: Vector2, route: int, s: float, bid: int }:
# punkt postoju, droga, przy której leży, km tej drogi liczony od miasta i firma (albo -1).
class_name EconLayout
extends RefCounted


const GOLDEN := 2.39996323
const ARC_STEP := 0.2            # krok łuku obwodnicy (radiany)
const RING_OF := {
	"services": "services", "apartments": "housing", "bakery": "processing", "mill": "processing", "sawmill": "processing",
	"furniture_factory": "processing", "appliance_factory": "heavy", "vehicle_plant": "heavy",
	"refinery": "heavy", "chemical_plant": "heavy", "steelworks": "heavy", "cement_works": "heavy",
	"haulage": "haulage",
}


static func lp(w: EconWorld) -> Dictionary:
	return w.data["layout"]


static func city_radius(w: EconWorld, c: EconCity) -> float:
	var p := lp(w)
	return float(p["radius_base_km"]) + sqrt(c.population) * float(p["radius_per_sqrt_pop_km"])


# Promień obwodnicy (0 = miasto za małe na obwodnicę).
static func ring_radius(w: EconWorld, c: EconCity) -> float:
	if c.population < float(lp(w)["ring_min_pop"]):
		return 0.0
	return city_radius(w, c) * float(lp(w)["ring_at"])


static func _h(seed: int, id: int, purpose: String) -> float:
	return float(SimRng.hash3(seed, id, purpose)) / 4294967295.0


# Miejsce dla nowej firmy i jej dojazd do drogi (raz, przy powstaniu).
static func place(w: EconWorld, b: EconBusiness) -> void:
	var c := w.city_of(b)
	var ring_name: String = RING_OF.get(b.type, "raw")
	var ring: Array = lp(w)["rings"][ring_name]
	var r := city_radius(w, c)
	var t := _h(w.world_seed, b.id, "ring")
	var rad := r * lerpf(float(ring[0]), float(ring[1]), sqrt(t))
	var ang := _h(w.world_seed, b.id, "angle") * TAU
	b.pos = c.pos + Vector2(cos(ang), sin(ang)) * rad
	var acc := access(w, c, b.pos)
	b.road = int(acc[0])
	b.road_s = float(acc[1])


# Najbliższy punkt dróg miasta: [id drogi, km od miasta] (albo [-1, 0], gdy miasto bez dróg).
static func access(w: EconWorld, c: EconCity, p: Vector2) -> Array:
	var best: Array = [-1, 0.0]
	var best_d := INF
	for rid: int in c.routes:
		var r: EconRoute = w.routes[rid]
		var pts := r.points if r.a == c.id else r._reversed()
		var acc := 0.0
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := p.distance_squared_to(q)
			if d < best_d:
				best_d = d
				best = [rid, acc + pts[i].distance_to(q)]
			acc += pts[i].distance_to(pts[i + 1])
	return best


static func spot_of(b: EconBusiness) -> Dictionary:
	return {"pos": b.pos, "route": b.road, "s": b.road_s, "bid": b.id}


# Postój na skraju miasta przy drodze (parking dla ciężarówek bez celu w mieście).
static func parking(w: EconWorld, c: EconCity, route_id: int) -> Dictionary:
	if route_id < 0:
		return {"pos": c.pos, "route": -1, "s": 0.0, "bid": -1}
	var r: EconRoute = w.routes[route_id]
	var s := minf(city_radius(w, c) * float(lp(w)["parking_at"]), r.length * 0.45)
	return {"pos": r.point_at(c.id, s), "route": route_id, "s": s, "bid": -1}


# Punkty od miejsca `sp` w mieście `c` do drogi `rid` (wynik: [punkty, km na rid od miasta]).
static func _to_route(w: EconWorld, c: EconCity, sp: Dictionary, rid: int) -> Array:
	var pts := PackedVector2Array([sp["pos"]])
	var own := int(sp["route"])
	var s := float(sp["s"])
	if own < 0:
		pts.append(c.pos)
		return [pts, 0.0]
	var r: EconRoute = w.routes[own]
	if own == rid:
		pts.append(r.point_at(c.id, s))
		return [pts, s]
	var rr := ring_radius(w, c)
	if rr > 0.0 and s > rr and rid >= 0:
		pts.append_array(r.segment(c.id, s, rr))
		var a0 := (r.point_at(c.id, rr) - c.pos).angle()
		var a1 := (w.routes[rid].point_at(c.id, rr) - c.pos).angle()
		pts.append_array(_arc(c.pos, rr, a0, a1))
		return [pts, rr]
	pts.append_array(r.segment(c.id, s, 0.0))
	return [pts, 0.0]


static func _arc(center: Vector2, rad: float, a0: float, a1: float) -> PackedVector2Array:
	var d := wrapf(a1 - a0, -PI, PI)
	var steps := maxi(2, int(absf(d) / ARC_STEP))
	var out := PackedVector2Array()
	for i in range(1, steps):
		var a := a0 + d * float(i) / float(steps)
		out.append(center + Vector2(cos(a), sin(a)) * rad)
	return out


# Przejazd w obrębie jednego miasta: od miejsca do miejsca.
static func in_city(w: EconWorld, c: EconCity, from_sp: Dictionary, to_sp: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var to_r := int(to_sp["route"])
	if (from_sp["pos"] as Vector2).distance_to(to_sp["pos"]) < 1e-4:
		return PackedVector2Array([from_sp["pos"]])
	var a := _to_route(w, c, from_sp, to_r)
	pts.append_array(a[0])
	if to_r >= 0:
		pts.append_array(w.routes[to_r].segment(c.id, float(a[1]), float(to_sp["s"])))
	pts.append(to_sp["pos"])
	return pts


# Cały kurs: z miejsca w mieście c0 trasą `path` (id dróg) do miejsca w mieście c1.
static func trip(w: EconWorld, c0: EconCity, from_sp: Dictionary, path: Array[int], c1: EconCity, to_sp: Dictionary) -> PackedVector2Array:
	if path.is_empty():
		return in_city(w, c0, from_sp, to_sp)
	var out_r := path[0]
	var in_r := path[path.size() - 1]
	var a := _to_route(w, c0, from_sp, out_r)
	var b := _to_route(w, c1, to_sp, in_r)
	var pts := PackedVector2Array()
	pts.append_array(a[0])
	var cur := c0.id
	for i in path.size():
		var r: EconRoute = w.routes[path[i]]
		var k0 := float(a[1]) if i == 0 else 0.0
		var k1 := r.length - (float(b[1]) if i == path.size() - 1 else 0.0)
		pts.append_array(r.segment(cur, k0, maxf(k0, k1)))
		cur = r.other(cur)
	var back: PackedVector2Array = b[0]
	back.reverse()
	pts.append_array(back)
	return pts


# Długości narastająco (do pozycji w czasie i czasu przejazdu).
static func cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i - 1].distance_to(pts[i])
		cum[i] = acc
	return cum


static func point_on(pts: PackedVector2Array, cum: PackedFloat32Array, km: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if km <= 0.0:
		return pts[0]
	var i := cum.bsearch(km)
	if i >= pts.size():
		return pts[pts.size() - 1]
	var seg := cum[i] - cum[i - 1]
	return pts[i - 1].lerp(pts[i], (km - cum[i - 1]) / maxf(seg, 1e-6))


# Bloki mieszkalne miasta (podgląd): [pozycja km, wielkość 0..1] — liczba rośnie z ludnością.
static func housing(w: EconWorld, c: EconCity) -> Array:
	var p := lp(w)
	var n := clampi(int(c.population / float(p["people_per_block"])), int(p["min_blocks"]), int(p["max_blocks"]))
	var r := city_radius(w, c) * 0.62
	var out: Array = []
	var rot := _h(w.world_seed, c.id, "rot") * TAU
	for i in n:
		var rr := r * sqrt((float(i) + 0.5) / float(n))
		var ang := float(i) * GOLDEN + rot
		var jitter := Vector2(_h(w.world_seed, c.id * 1000 + i, "jx") - 0.5, _h(w.world_seed, c.id * 1000 + i, "jy") - 0.5) * r * 0.08
		var size := 1.0 - rr / maxf(r, 1e-6) * 0.6
		out.append([c.pos + Vector2(cos(ang), sin(ang)) * rr + jitter, size])
	return out
