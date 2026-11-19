# RtsTerrain — teren ciągłej mapy (1 jednostka = 1 m): ziemia z teksturą liczoną z
# danych świata (pola wokół żyznych miast, lasy wokół leśnych, łąki), drzewa w lasach
# (MultiMesh) i drogi jako wstęgi po łamanych. Tylko render, czyta EconWorld.
class_name RtsTerrain
extends Node3D


const TEX_W := 640
const KM := 1000.0
const GRASS_A := Color(0.36, 0.52, 0.28)
const GRASS_B := Color(0.44, 0.58, 0.3)
const FIELD_COLORS := [Color(0.78, 0.7, 0.36), Color(0.62, 0.66, 0.3), Color(0.55, 0.42, 0.26), Color(0.7, 0.62, 0.32), Color(0.48, 0.6, 0.28)]
const FOREST := Color(0.16, 0.32, 0.17)
const TOWN_GROUND := Color(0.5, 0.5, 0.47)
const ROAD := Color(0.28, 0.28, 0.3)
const ROAD_CLOSED := Color(0.75, 0.2, 0.18)
const FIELD_CELL_KM := 0.35
const FIELD_RANGE := 3.2          # pola sięgają do tylu promieni miasta
const FOREST_RANGE_KM := 6.0
const TREE_STEP_KM := 0.16
const TREE_H := 18.0
const ROAD_MIN_W := 14.0
const ROAD_Y := 0.6
const MARGIN_KM := 4.0

var w: EconWorld

var _roads: MeshInstance3D
var _road_w := -1.0
var _want_w := ROAD_MIN_W
var _noise := FastNoiseLite.new()


func build(world: EconWorld) -> void:
	w = world
	_noise.seed = w.world_seed
	_noise.frequency = 0.18
	_ground()
	_trees()
	_roads = MeshInstance3D.new()
	add_child(_roads)
	update_roads(ROAD_MIN_W)


func _size_km() -> Vector2:
	var ms: Array = w.data["world"]["map_size"]
	return Vector2(float(ms[0]), float(ms[1]))


# Rodzaj ziemi w punkcie (km): "field:<i>", "forest", "town", "grass:<t>".
func ground_kind(p: Vector2) -> String:
	for c: EconCity in w.cities:
		var r := EconLayout.city_radius(w, c)
		var d := p.distance_to(c.pos)
		if d < r * 0.7:
			return "town"
	var forest := _noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var best_field := 0.0
	var fertile_city: EconCity = null
	for c: EconCity in w.cities:
		var d := p.distance_to(c.pos)
		var r := EconLayout.city_radius(w, c)
		if c.resources.has("fertile"):
			var f := 1.0 - (d - r) / (r * FIELD_RANGE + 1.2)
			if f > best_field:
				best_field = f
				fertile_city = c
		if c.resources.has("forest") and d < FOREST_RANGE_KM:
			forest += 0.35 * (1.0 - d / FOREST_RANGE_KM)
	if forest > 0.78:
		return "forest"
	if best_field > 0.0 and fertile_city != null:
		var cell := Vector2i(floori(p.x / FIELD_CELL_KM), floori(p.y / FIELD_CELL_KM))
		var h := SimRng.hash3(w.world_seed, cell.x * 7919 + cell.y, "field")
		if float(h % 1000) / 1000.0 < best_field + 0.2:
			return "field:%d" % (h % FIELD_COLORS.size())
	return "grass:%f" % (_noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.5 + 0.5)


func _ground() -> void:
	var size := _size_km() + Vector2.ONE * MARGIN_KM * 2.0
	var tex_h := int(TEX_W * size.y / size.x)
	var img := Image.create(TEX_W, tex_h, false, Image.FORMAT_RGB8)
	for y in tex_h:
		for x in TEX_W:
			var p := Vector2(float(x) / TEX_W * size.x, float(y) / tex_h * size.y) - Vector2.ONE * MARGIN_KM
			var k := ground_kind(p)
			var col := GRASS_A
			if k == "town":
				col = TOWN_GROUND
			elif k == "forest":
				col = FOREST
			elif k.begins_with("field:"):
				col = FIELD_COLORS[int(k.substr(6))]
			else:
				col = GRASS_A.lerp(GRASS_B, float(k.substr(6)))
			img.set_pixel(x, y, col)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = size * KM
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((size.x * 0.5 - MARGIN_KM) * KM, 0.0, (size.y * 0.5 - MARGIN_KM) * KM)
	add_child(mi)


func _trees() -> void:
	var pts: Array[Vector3] = []
	var size := _size_km()
	var y := 0.0
	while y < size.y:
		var x := 0.0
		while x < size.x:
			var jx := float(SimRng.hash3(w.world_seed, int(x * 100) * 9973 + int(y * 100), "tx") % 1000) / 1000.0 - 0.5
			var jy := float(SimRng.hash3(w.world_seed, int(x * 100) * 9973 + int(y * 100), "ty") % 1000) / 1000.0 - 0.5
			var p := Vector2(x + jx * TREE_STEP_KM, y + jy * TREE_STEP_KM)
			if ground_kind(p) == "forest":
				pts.append(Vector3(p.x * KM, 0.0, p.y * KM))
			x += TREE_STEP_KM
		y += TREE_STEP_KM
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = TREE_H * 0.4
	cone.height = TREE_H
	cone.radial_segments = 6
	cone.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := 0.7 + float(i % 7) * 0.1
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), pts[i] + Vector3(0, TREE_H * 0.5 * s, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Gfx3D.mat(Color(0.12, 0.3, 0.14))
	add_child(mmi)


# Drogi jako wstęgi; szerokość rośnie przy oddaleniu, żeby było je widać.
func update_roads(width: float) -> void:
	width = maxf(width, ROAD_MIN_W)
	_want_w = width
	if _road_w > 0.0 and absf(width / _road_w - 1.0) < 0.25 and _roads.mesh != null:
		return
	_road_w = width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: EconRoute in w.routes:
		var col := ROAD_CLOSED if r.is_closed(w.day) else ROAD
		for i in r.points.size() - 1:
			var a := r.points[i] * KM
			var b := r.points[i + 1] * KM
			var side := (b - a).orthogonal().normalized() * width * 0.5
			var v := [a + side, a - side, b - side, b + side]
			st.set_color(col)
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(Vector3(v[idx].x, ROAD_Y, v[idx].y))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_roads.mesh = st.commit()
	_roads.material_override = mat


func refresh_closures() -> void:
	_road_w = -1.0
	update_roads(_want_w)
