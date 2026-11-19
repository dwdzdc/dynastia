# RtsUnitsView — jednostki na mapie: wszystkie ciężarówki świata (MultiMesh,
# kolor = firma; ciężarówki gracza złote), ludzie gracza (kapsuły) i znacznik
# zaznaczenia. Przy oddaleniu jednostki rosną, żeby było je widać.
class_name RtsUnitsView
extends Node3D


const KM := 1000.0
const TRUCK_SIZE := Vector3(14, 5, 5)
const PERSON_R := 0.8
const PERSON_H := 2.2
const PLAYER_COLOR := Color(1.0, 0.8, 0.25)
const UNIT_COLOR := Color(1.0, 0.85, 0.35)
const SELECT_COLOR := Color(1.0, 1.0, 0.7)
const HEADING_DT := 0.002
const ZOOM_REF := 600.0      # przy jakim rozmiarze kamery jednostki mają naturalną wielkość
const PIN_H := 6.0           # wysokość drzewca chorągiewki nad człowiekiem gracza
const PERSON_ZOOM := 4.0     # ludzie gracza rosną mocniej niż ciężarówki (żeby ich nie zgubić)

var rts: RtsWorld
var _trucks: MultiMeshInstance3D
var _people: Dictionary = {}   # id jednostki -> Node3D (ciało + chorągiewka)
var _ring: MeshInstance3D
var truck_ids: Array[int] = [] # kolejność instancji (do zaznaczania)


func build(world: RtsWorld) -> void:
	rts = world
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	_trucks = MultiMeshInstance3D.new()
	_trucks.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	_trucks.material_override = mat
	add_child(_trucks)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = Gfx3D.glow(SELECT_COLOR, 2.0)
	_ring.visible = false
	add_child(_ring)


# Człowiek gracza: kapsuła i złota chorągiewka nad nim (widać ją z daleka).
func _person_node() -> Node3D:
	var n := Node3D.new()
	var body := Gfx3D.capsule(PERSON_R, PERSON_H, UNIT_COLOR)
	body.position.y = PERSON_H * 0.5
	n.add_child(body)
	var pole := Gfx3D.cylinder(0.12, PIN_H, Color(0.9, 0.9, 0.9))
	pole.position.y = PERSON_H + PIN_H * 0.5
	n.add_child(pole)
	var flag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 1.3, 0.1)
	flag.mesh = bm
	flag.material_override = Gfx3D.glow(PLAYER_COLOR, 1.2)
	flag.position = Vector3(1.1, PERSON_H + PIN_H - 0.65, 0)
	n.add_child(flag)
	return n


static func company_color(id: int) -> Color:
	var h := float(SimRng.hash3(7, id, "color") % 1000) / 1000.0
	return Color.from_hsv(h, 0.55, 0.85)


func zoom_scale(cam_size: float) -> float:
	return maxf(1.0, cam_size / ZOOM_REF)


func refresh(t: float, cam_size: float, selected: Dictionary) -> void:
	var s := zoom_scale(cam_size)
	var mm := _trucks.multimesh
	var list: Array = rts.econ.trucks.values().filter(func(tr: EconTruck) -> bool: return tr.moving)
	var player_comp := rts.haulage()
	var mine: Array = rts.player_trucks().filter(func(tr: EconTruck) -> bool: return not tr.moving)
	list.append_array(mine)  # stojące ciężarówki gracza też widać
	mm.instance_count = list.size()
	truck_ids.clear()
	for i in list.size():
		var tr: EconTruck = list[i]
		var p := rts.econ.truck_pos(tr, t) * KM
		var ahead := rts.econ.truck_pos(tr, t + HEADING_DT) * KM
		var dir := ahead - p
		var yaw := atan2(-dir.y, dir.x) if dir.length() > 0.01 else 0.0
		var size := TRUCK_SIZE * s
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(size)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, size.y * 0.5 + 1.0, p.y)))
		var col := PLAYER_COLOR if player_comp != null and tr.company_id == player_comp.id else company_color(tr.company_id)
		mm.set_instance_color(i, col)
		truck_ids.append(tr.id)
	for u: RtsUnit in rts.units.values():
		var node: Node3D = _people.get(u.id)
		if node == null:
			node = _person_node()
			add_child(node)
			_people[u.id] = node
		var at := u.pos
		if u.inside >= 0:
			var b: EconBusiness = rts.econ.business(u.inside)
			if b != null:
				at = rts.business_pos(b)
		node.scale = Vector3.ONE * maxf(1.0, s * PERSON_ZOOM)
		node.position = Vector3(at.x * KM, 0.0, at.y * KM)
		(node.get_child(0) as Node3D).visible = u.inside < 0  # w pracy widać tylko chorągiewkę
	_ring.visible = false
	var at := Vector3.ZERO
	var rad := 0.0
	match str(selected.get("kind", "")):
		"unit":
			var u: RtsUnit = rts.units.get(int(selected["id"]))
			if u != null:
				at = Vector3(u.pos.x * KM, 0.5, u.pos.y * KM)
				rad = 6.0 * s
		"truck":
			var tr: EconTruck = rts.econ.trucks.get(int(selected["id"]))
			if tr != null:
				var p := rts.econ.truck_pos(tr, t) * KM
				at = Vector3(p.x, 0.5, p.y)
				rad = 14.0 * s
		"business":
			var b: EconBusiness = rts.econ.business(int(selected["id"]))
			if b != null:
				var p := rts.business_pos(b) * KM
				at = Vector3(p.x, 0.5, p.y)
				rad = 60.0 * maxf(1.0, s * 0.5)
	if rad > 0.0:
		_ring.visible = true
		_ring.position = at
		_ring.scale = Vector3(rad, rad * 0.3, rad)
