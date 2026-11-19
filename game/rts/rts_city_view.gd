# RtsCityView — zabudowa miast: bloki mieszkalne (ile ich, wynika z ludności) i
# budynki firm (kształt i kolor wg rodzaju, wielkość wg poziomu, stan: budowa,
# pożar). Dwie MultiMesh (prostopadłościany i walce) z kolorem na instancję.
# Przebudowa raz na dobę gry, gdy coś się zmieniło.
class_name RtsCityView
extends Node3D


const KM := 1000.0
const HOUSE_COLORS := [Color(0.82, 0.78, 0.7), Color(0.72, 0.7, 0.68), Color(0.78, 0.62, 0.5), Color(0.66, 0.68, 0.74), Color(0.86, 0.83, 0.76)]
const BUILDING_TINT := Color(0.55, 0.55, 0.55)
const BURNED := Color(0.12, 0.1, 0.09)
const PLAYER_ROOF := Color(1.0, 0.82, 0.3)
const FIELD_COLORS := [Color(0.8, 0.72, 0.35), Color(0.55, 0.68, 0.3), Color(0.6, 0.45, 0.28)]
const STREET := Color(0.38, 0.38, 0.4)
const STREET_W := 9.0
const STREET_Y := 0.45
const RING_SEGS := 28
const DRIVE_MAX_KM := 3.5

# Części budynku: [rodzaj ("box"/"cyl"), przesunięcie (x, z) m, wymiary (x, y, z) m albo (r, h, -), kolor]
const PARTS := {
	"services": [["box", Vector2(0, 0), Vector3(40, 16, 40), Color(0.6, 0.72, 0.85)]],
	"bakery": [["box", Vector2(0, 0), Vector3(30, 10, 24), Color(0.9, 0.62, 0.35)]],
	"mill": [["box", Vector2(0, 0), Vector3(30, 14, 26), Color(0.92, 0.9, 0.84)], ["cyl", Vector2(24, 0), Vector3(8, 30, 0), Color(0.85, 0.85, 0.8)]],
	"sawmill": [["box", Vector2(0, 0), Vector3(54, 10, 24), Color(0.6, 0.42, 0.26)], ["box", Vector2(0, 26), Vector3(40, 4, 14), Color(0.72, 0.55, 0.32)]],
	"furniture_factory": [["box", Vector2(0, 0), Vector3(64, 12, 40), Color(0.78, 0.66, 0.48)]],
	"appliance_factory": [["box", Vector2(0, 0), Vector3(84, 14, 52), Color(0.7, 0.76, 0.84)]],
	"vehicle_plant": [["box", Vector2(0, 0), Vector3(130, 18, 70), Color(0.6, 0.62, 0.66)], ["box", Vector2(0, 55), Vector3(90, 1, 30), Color(0.4, 0.4, 0.42)]],
	"refinery": [["cyl", Vector2(-22, 0), Vector3(12, 18, 0), Color(0.85, 0.85, 0.82)], ["cyl", Vector2(6, -14), Vector3(12, 18, 0), Color(0.85, 0.85, 0.82)], ["cyl", Vector2(6, 16), Vector3(4, 46, 0), Color(0.45, 0.45, 0.48)], ["box", Vector2(30, 6), Vector3(26, 10, 30), Color(0.55, 0.55, 0.6)]],
	"chemical_plant": [["cyl", Vector2(-14, 0), Vector3(10, 26, 0), Color(0.8, 0.86, 0.9)], ["box", Vector2(16, 0), Vector3(34, 12, 30), Color(0.62, 0.7, 0.78)]],
	"steelworks": [["box", Vector2(0, 0), Vector3(90, 26, 50), Color(0.38, 0.36, 0.36)], ["cyl", Vector2(52, -14), Vector3(4, 70, 0), Color(0.3, 0.28, 0.27)], ["cyl", Vector2(52, 12), Vector3(4, 70, 0), Color(0.3, 0.28, 0.27)]],
	"cement_works": [["cyl", Vector2(-12, 0), Vector3(10, 40, 0), Color(0.8, 0.8, 0.78)], ["cyl", Vector2(12, 0), Vector3(10, 40, 0), Color(0.8, 0.8, 0.78)], ["box", Vector2(0, 30), Vector3(46, 12, 20), Color(0.7, 0.7, 0.68)]],
	"grain_farm": [["field", Vector2(0, 0), Vector3(260, 1.2, 180), Color(0.82, 0.72, 0.34)], ["box", Vector2(-150, 0), Vector3(22, 10, 14), Color(0.66, 0.22, 0.18)]],
	"vegetable_farm": [["field", Vector2(0, 0), Vector3(220, 1.2, 160), Color(0.45, 0.64, 0.28)], ["box", Vector2(-130, 0), Vector3(18, 8, 12), Color(0.66, 0.22, 0.18)]],
	"livestock_farm": [["field", Vector2(0, 0), Vector3(240, 1.0, 200), Color(0.5, 0.62, 0.32)], ["box", Vector2(-140, 0), Vector3(40, 9, 16), Color(0.6, 0.3, 0.2)]],
	"oil_well": [["box", Vector2(0, 0), Vector3(6, 38, 6), Color(0.2, 0.2, 0.22)], ["box", Vector2(0, 0), Vector3(16, 3, 16), Color(0.3, 0.28, 0.25)], ["cyl", Vector2(18, 0), Vector3(6, 8, 0), Color(0.5, 0.48, 0.42)]],
	"iron_mine": [["cyl", Vector2(0, 0), Vector3(50, 10, 0), Color(0.48, 0.38, 0.3)], ["box", Vector2(40, 0), Vector3(20, 22, 20), Color(0.35, 0.35, 0.38)]],
	"quarry": [["cyl", Vector2(0, 0), Vector3(70, 1.5, 0), Color(0.78, 0.76, 0.7)], ["box", Vector2(60, 0), Vector3(14, 8, 14), Color(0.5, 0.5, 0.5)]],
	"logging_camp": [["box", Vector2(0, 0), Vector3(24, 8, 14), Color(0.48, 0.34, 0.22)], ["cyl", Vector2(22, 0), Vector3(5, 3, 0), Color(0.62, 0.46, 0.28)]],
	"haulage": [["box", Vector2(0, 0), Vector3(60, 10, 30), Color(0.3, 0.45, 0.7)], ["box", Vector2(0, 30), Vector3(70, 0.8, 30), Color(0.35, 0.35, 0.37)]],
}

var rts: RtsWorld
var lp: Dictionary               # data/economy.json → "layout"
var _boxes: MultiMeshInstance3D
var _cyls: MultiMeshInstance3D
var _sig := ""
var _streets: MeshInstance3D
var _home: Node3D


func build(world: RtsWorld) -> void:
	rts = world
	lp = world.econ.data["layout"]
	_boxes = _mmi(BoxMesh.new())
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	_cyls = _mmi(cyl)
	_streets = MeshInstance3D.new()
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_streets.material_override = smat
	add_child(_streets)
	_home = _home_node()
	add_child(_home)
	refresh(true)


func _mmi(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mmi.material_override = mat
	add_child(mmi)
	return mmi


# Podpis stanu: przebudowa tylko, gdy zmieniły się firmy albo ludność miast.
func _signature() -> String:
	var n := 0
	var acc := 0
	for b: EconBusiness in rts.econ.businesses.values():
		n += 1
		acc += b.id * (1 + b.level) * (3 if b.status == "active" else 7 if b.status == "building" else 11)
	for c: EconCity in rts.econ.cities:
		acc += int(c.population / float(lp["people_per_block"]))
	return "%d:%d" % [n, acc]


func refresh(force := false) -> void:
	var sig := _signature()
	if sig == _sig and not force:
		return
	_sig = sig
	var boxes: Array = []  # [Transform3D, Color]
	var cyls: Array = []
	for c: EconCity in rts.econ.cities:
		for hb: Array in EconLayout.housing(rts.econ, c):
			var p: Vector2 = hb[0]
			var size: float = hb[1]
			var hseed := SimRng.hash3(rts.econ.world_seed, int(p.x * 1000.0) * 31 + int(p.y * 1000.0), "house")
			var foot := 28.0 + float(hseed % 30) + size * 20.0
			var height := 8.0 + size * size * (10.0 + sqrt(c.population) * 0.12) * (0.6 + float(hseed % 10) / 10.0)
			var col: Color = HOUSE_COLORS[hseed % HOUSE_COLORS.size()]
			var rot := float(hseed % 4) * 0.08 + (p - c.pos).angle()
			boxes.append([_xf(p * KM, Vector3(foot, height, foot * 0.8), rot), col])
	for b: EconBusiness in rts.econ.businesses.values():
		if b.status == "closed":
			continue
		var parts: Array = PARTS.get(b.type, PARTS["services"])
		var p := rts.business_pos(b) * KM
		var grow := sqrt(maxf(1.0, float(b.level)))
		var mine := rts.player.businesses.has(b.id)
		var rot := float(b.id % 8) * 0.39
		for part: Array in parts:
			var kind: String = part[0]
			var off: Vector2 = (part[1] as Vector2).rotated(rot) * grow
			var dims: Vector3 = part[2]
			var col: Color = part[3]
			if b.status == "building":
				col = col.lerp(BUILDING_TINT, 0.7)
				dims.y *= 0.4
			elif b.status == "burned":
				col = BURNED
			if mine and kind != "field":
				col = col.lerp(PLAYER_ROOF, 0.45)
			var at := p + off
			match kind:
				"cyl":
					cyls.append([Transform3D(Basis().scaled(Vector3(dims.x * grow, dims.y, dims.x * grow)), Vector3(at.x, dims.y * 0.5, at.y)), col])
				"field":
					boxes.append([_xf(at, Vector3(dims.x * grow, dims.y, dims.z * grow), rot), col])
				_:
					var h := dims.y * (1.0 + 0.15 * (b.level - 1)) if b.type == "services" else dims.y
					boxes.append([_xf(at, Vector3(dims.x * grow, h, dims.z * grow), rot), col])
	_fill(_boxes.multimesh, boxes)
	_fill(_cyls.multimesh, cyls)
	_build_streets()
	var hp := rts.home_pos() * KM
	_home.position = Vector3(hp.x, 0, hp.y)


# Dom rodu gracza: dom ze złotym dachem.
func _home_node() -> Node3D:
	var n := Node3D.new()
	var walls := Gfx3D.box(Vector3(22, 9, 16), Color(0.92, 0.88, 0.8))
	walls.position.y = 4.5
	n.add_child(walls)
	var roof := Gfx3D.box(Vector3(24, 4, 18), PLAYER_ROOF)
	roof.position.y = 11.0
	n.add_child(roof)
	return n


# Ulice: obwodnica w większych miastach i dojazd od każdej firmy do jej drogi
# (ten sam, którym jeżdżą ciężarówki — EconLayout).
func _build_streets() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(STREET)
	var segs: Array = []  # [a, b] km — drogi, do których można się podpiąć
	for r: EconRoute in rts.econ.routes:
		for i in r.points.size() - 1:
			segs.append([r.points[i], r.points[i + 1]])
	for c: EconCity in rts.econ.cities:
		var rr := EconLayout.ring_radius(rts.econ, c)
		if rr <= 0.0:
			continue
		var prev := c.pos + Vector2(rr, 0)
		for k in range(1, RING_SEGS + 1):
			var ang := TAU * float(k) / RING_SEGS
			var p := c.pos + Vector2(cos(ang), sin(ang)) * rr
			_strip(st, prev * KM, p * KM, STREET_W)
			segs.append([prev, p])
			prev = p
	for b: EconBusiness in rts.econ.businesses.values():
		if b.status != "closed" and b.road >= 0:
			_strip(st, b.pos * KM, rts.econ.routes[b.road].point_at(b.city_id, b.road_s) * KM, STREET_W * 0.7)
	var drive: Array = [rts.home_pos()]
	for p: Vector2 in drive:
		var best := p
		var best_d := INF
		for sg: Array in segs:
			var q := Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])
			var d := p.distance_squared_to(q)
			if d < best_d:
				best_d = d
				best = q
		if sqrt(best_d) < DRIVE_MAX_KM:
			_strip(st, p * KM, best * KM, STREET_W * 0.7)
	_streets.mesh = st.commit()


static func _strip(st: SurfaceTool, a: Vector2, b: Vector2, width: float) -> void:
	if a.distance_to(b) < 0.5:
		return
	var side := (b - a).orthogonal().normalized() * width * 0.5
	var v := [a + side, a - side, b - side, b + side]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(Vector3(v[idx].x, STREET_Y, v[idx].y))


static func _xf(at: Vector2, size: Vector3, rot: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rot) * Basis.from_scale(size)
	return Transform3D(basis, Vector3(at.x, size.y * 0.5, at.y))


static func _fill(mm: MultiMesh, items: Array) -> void:
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
