# EconMap — generowanie sieci miast z seeda: położenie (rozrzut z minimalnym
# odstępem), ludność wg progów, drogi do k najbliższych + drzewo rozpinające
# (spójność), złoża (każdy zasób w co najmniej kilku miastach), najkrótsze ścieżki.
class_name EconMap
extends RefCounted


static func generate(w: EconWorld) -> void:
	var p: Dictionary = w.data["world"]
	var size_arr: Array = p["map_size"]
	var size := Vector2(float(size_arr[0]), float(size_arr[1]))
	var names: Array = (w.data["names"]["cities"] as Array).duplicate()
	w.rng.shuffle(names)
	var pops: Array[float] = []
	for tier: Dictionary in p["city_tiers"]:
		var r: Array = tier["pop"]
		for i in int(tier["count"]):
			pops.append(roundf(w.rng.next_float(float(r[0]), float(r[1]))))
	var count := mini(int(p["city_count"]), pops.size())
	var min_d := float(p["min_city_distance"])
	var margin := minf(size.x, size.y) * float(p.get("map_margin", 0.05))
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 400:
			pos = Vector2(w.rng.next_float(margin, size.x - margin), w.rng.next_float(margin, size.y - margin))
			var ok := true
			for c: EconCity in w.cities:
				if c.pos.distance_to(pos) < min_d * (1.0 if attempt < 300 else 0.6):
					ok = false
					break
			if ok:
				break
		w.cities.append(EconCity.new(i, str(names[i % names.size()]), pos, pops[i]))
	_routes(w, int(p["route_neighbors"]), float(p["route_detour"]))
	_bend_roads(w, int(p.get("road_bends", 0)), float(p.get("road_wobble", 0.0)))
	_resources(w, p["resources"], int(p["min_cities_per_resource"]))
	compute_distances(w)


static func _routes(w: EconWorld, k: int, detour: float) -> void:
	var n := w.cities.size()
	var pairs := {}  # "a:b" -> true
	var edges: Array = []  # [d, a, b] — kandydaci do drzewa rozpinającego
	for c: EconCity in w.cities:
		var others: Array = []
		for o: EconCity in w.cities:
			if o.id != c.id:
				others.append([c.pos.distance_to(o.pos), o.id])
				if o.id > c.id:
					edges.append([c.pos.distance_to(o.pos), c.id, o.id])
		others.sort_custom(func(x, y): return x[0] < y[0])
		for i in mini(k, others.size()):
			_add_route(w, pairs, c.id, int(others[i][1]), detour)
	# Spójność: Kruskal na wszystkich parach, dokładamy brakujące krawędzie drzewa.
	edges.sort_custom(func(x, y): return x[0] < y[0])
	var parent: Array[int] = []
	for i in n:
		parent.append(i)
	for r: EconRoute in w.routes:
		_union(parent, r.a, r.b)
	for e: Array in edges:
		var a: int = e[1]
		var b: int = e[2]
		if _find(parent, a) != _find(parent, b):
			_union(parent, a, b)
			_add_route(w, pairs, a, b, detour)


static func _add_route(w: EconWorld, pairs: Dictionary, a: int, b: int, detour: float) -> void:
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	if pairs.has(key):
		return
	pairs[key] = true
	var km := w.cities[a].pos.distance_to(w.cities[b].pos) * detour
	var r := EconRoute.new(w.routes.size(), mini(a, b), maxi(a, b), roundf(km))
	w.routes.append(r)
	w.cities[a].routes.append(r.id)
	w.cities[b].routes.append(r.id)


# Drogi jako łamane: kilka punktów pośrednich odsuniętych w bok (deterministycznie).
# Długość drogi = długość łamanej.
static func _bend_roads(w: EconWorld, bends: int, wobble: float) -> void:
	for r: EconRoute in w.routes:
		var a: Vector2 = w.cities[r.a].pos
		var b: Vector2 = w.cities[r.b].pos
		var side := (b - a).orthogonal().normalized()
		var pts := PackedVector2Array([a])
		for i in bends:
			var t := float(i + 1) / float(bends + 1)
			var off := w.rng.next_float(-wobble, wobble) * a.distance_to(b) * sin(t * PI)
			pts.append(a.lerp(b, t) + side * off)
		pts.append(b)
		r.points = pts
		var km := 0.0
		for i in pts.size() - 1:
			km += pts[i].distance_to(pts[i + 1])
		r.length = km


static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: Array[int], a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)


static func _resources(w: EconWorld, table: Dictionary, min_cities: int) -> void:
	for res: String in table.keys():
		var spec: Dictionary = table[res]
		var rich: Array = spec["richness"]
		var have := 0
		for c: EconCity in w.cities:
			if w.rng.chance(float(spec["chance"])):
				c.resources[res] = w.rng.next_float(float(rich[0]), float(rich[1]))
				have += 1
		# Każdy zasób musi gdzieś być: dokładamy w losowych miastach bez niego.
		var order: Array = range(w.cities.size())
		w.rng.shuffle(order)
		for i: int in order:
			if have >= min_cities:
				break
			var c: EconCity = w.cities[i]
			if not c.resources.has(res):
				c.resources[res] = w.rng.next_float(float(rich[0]), float(rich[1]))
				have += 1


# Odległości drogowe między wszystkimi parami (Floyd–Warshall; zamknięcia dróg
# pomijane — to szacunek do decyzji; faktyczną trasę liczy path()).
static func compute_distances(w: EconWorld) -> void:
	var n := w.cities.size()
	w.dist.clear()
	for i in n:
		var row := PackedFloat32Array()
		row.resize(n)
		row.fill(INF)
		row[i] = 0.0
		w.dist.append(row)
	for r: EconRoute in w.routes:
		w.dist[r.a][r.b] = minf(w.dist[r.a][r.b], r.length)
		w.dist[r.b][r.a] = minf(w.dist[r.b][r.a], r.length)
	for k in n:
		for i in n:
			var dik: float = w.dist[i][k]
			if dik == INF:
				continue
			for j in n:
				var alt: float = dik + w.dist[k][j]
				if alt < w.dist[i][j]:
					w.dist[i][j] = alt


# Najkrótsza trasa (lista id dróg) z pominięciem zamkniętych. [] gdy nie da się dojechać.
static func path(w: EconWorld, from_id: int, to_id: int) -> Array[int]:
	var out: Array[int] = []
	if from_id == to_id:
		return out
	var n := w.cities.size()
	var best := PackedFloat32Array()
	best.resize(n)
	best.fill(INF)
	var via: Array[int] = []
	via.resize(n)
	via.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	best[from_id] = 0.0
	for _iter in n:
		var u := -1
		for i in n:
			if done[i] == 0 and best[i] < INF and (u == -1 or best[i] < best[u]):
				u = i
		if u == -1 or u == to_id:
			break
		done[u] = 1
		for rid: int in w.cities[u].routes:
			var r: EconRoute = w.routes[rid]
			if r.is_closed(w.day):
				continue
			var v := r.other(u)
			if best[u] + r.length < best[v]:
				best[v] = best[u] + r.length
				via[v] = rid
	if best[to_id] == INF:
		return out
	var cur := to_id
	while cur != from_id:
		var rid: int = via[cur]
		out.push_front(rid)
		cur = w.routes[rid].other(cur)
	return out
