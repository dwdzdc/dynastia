extends Node3D

const DataLoader := preload("res://sim/data_loader.gd")
const SimWorld := preload("res://sim/world.gd")
const AgentNode := preload("res://game/agent_node.gd")
const Gfx3D := preload("res://game/gfx3d.gd")

const S := 0.12                 # skala renderu: jednostki sim -> jednostki sceny 3D
const CLICK_RADIUS := 1.6       # render-units
const CAM_YAW := deg_to_rad(45.0)
const CAM_PITCH := deg_to_rad(55.0)

const GRASS := Color(0.44, 0.58, 0.33)
const DIRT := Color(0.62, 0.50, 0.34)
const FOREST_FLOOR := Color(0.30, 0.42, 0.24)
const WOOD := Color(0.55, 0.37, 0.22)
const ROOF := Color(0.42, 0.26, 0.14)
const TREE := Color(0.20, 0.38, 0.14)
const TRUNK := Color(0.42, 0.28, 0.16)
const AWNING := Color(0.62, 0.24, 0.18)

const DAY_SKY := Color(0.42, 0.62, 0.9)
const NIGHT_SKY := Color(0.03, 0.05, 0.12)
const WARM := Color(1.0, 0.92, 0.82)
const COOL := Color(0.42, 0.5, 0.7)

var world: SimWorld
var move_speed: float = 90.0
var map_data: Dictionary = {}
var _place_by_id: Dictionary = {}

var agent_nodes: Array = []
var selected: RefCounted = null
var _selected_node: Node3D = null

var cam_target := Vector3.ZERO
var cam_dist := 120.0
var _manual_target: Vector2
var _has_manual_target := false
var _dragging := false
var _drag_start := Vector3.ZERO
var _env: Environment

@onready var sun: DirectionalLight3D = $Sun
@onready var camera: Camera3D = $Camera3D
@onready var hud: Control = $UI/Hud
@onready var world_root: Node3D = $WorldRoot


func _ready() -> void:
	var balance: Dictionary = DataLoader.load_json("res://data/balance.json")
	map_data = DataLoader.load_json("res://data/map.json")
	world = SimWorld.new(int(balance["world_seed"]), balance, map_data)
	move_speed = float(DataLoader.get_nested(balance, "movement.speed"))

	for p in map_data["places"]:
		_place_by_id[p["id"]] = p

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = DAY_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = WARM
	_env.ambient_light_energy = 0.55
	$WorldEnvironment.environment = _env

	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.shadow_enabled = true

	_build_world()
	_spawn_agents()

	camera.make_current()
	camera.fov = 50.0
	var ws: Array = map_data["world_size"]
	cam_target = Vector3(float(ws[0]) * 0.5 * S, 0.0, float(ws[1]) * 0.5 * S)
	_update_camera()


func _process(delta: float) -> void:
	world.tick(delta)
	_update_manual(delta)
	_update_camera_pan(delta)
	_update_camera()

	for an in agent_nodes:
		an.refresh()

	var l := world.clock.light_factor()
	sun.light_energy = lerpf(0.04, 1.2, l)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(0.45, 0.5, 0.9), 1.0 - l)
	_env.background_color = DAY_SKY.lerp(NIGHT_SKY, 1.0 - l)
	_env.ambient_light_color = WARM.lerp(COOL, 1.0 - l)
	_env.ambient_light_energy = lerpf(0.16, 0.55, l)

	hud.update_view(world.clock)
	hud.show_resources(float(world.resources["wood"]))
	hud.show_agent(_selected_info())


# --- Budowa świata 3D ---

func _build_world() -> void:
	var ws: Array = map_data["world_size"]
	var cx := float(ws[0]) * 0.5 * S
	var cz := float(ws[1]) * 0.5 * S
	# Duży teren (trawa) — płaski box zamiast PlaneMesh (orientacja PlaneMesh sprawiała,
	# że teren stał pionowo/cullowany i kadr zalewał niebem). Box renderuje się pewnie.
	var ground := Gfx3D.box(Vector3(1400.0, 0.5, 1400.0), GRASS)
	ground.position = Vector3(cx, -0.25, cz)
	world_root.add_child(ground)

	var forest := _pos("forest")
	var market := _pos("market")
	var village := _village_center()

	# drogi
	_road(village, forest)
	_road(village, market)

	# plac wioski
	var plaza := Gfx3D.box(Vector3(22, 0.06, 22), DIRT)
	plaza.position = Vector3(village.x * S, 0.03, village.y * S)
	world_root.add_child(plaza)

	# podszycie lasu + drzewa
	var ffloor := Gfx3D.box(Vector3(34, 0.06, 34), FOREST_FLOOR)
	ffloor.position = Vector3(forest.x * S, 0.02, forest.y * S)
	world_root.add_child(ffloor)
	for off in [
		Vector2(-11, -9), Vector2(4, -12), Vector2(12, -6), Vector2(-5, 4),
		Vector2(7, 6), Vector2(14, 2), Vector2(-13, 5), Vector2(0, 12),
		Vector2(14, 12), Vector2(-9, -1), Vector2(2, -2), Vector2(10, 8),
	]:
		_draw_tree(Vector2(forest.x + off.x, forest.y + off.y), 1.0)

	# budynki + etykiety
	for p in map_data["places"]:
		var pos := Vector2(float(p["x"]), float(p["y"]))
		match String(p["type"]):
			"house":
				_draw_house(pos)
			"work":
				_draw_lumber_camp(pos)
			"food":
				_draw_market(pos)
		var lbl := Gfx3D.label3d(String(p["name"]), 24, Color(1, 1, 0.95))
		lbl.position = Vector3(pos.x * S, 4.6, pos.y * S)
		world_root.add_child(lbl)


func _road(a: Vector2, b: Vector2) -> void:
	var pa := Vector3(a.x * S, 0, a.y * S)
	var pb := Vector3(b.x * S, 0, b.y * S)
	var mid := (pa + pb) * 0.5
	var length := pa.distance_to(pb)
	var yaw := atan2(pb.x - pa.x, pb.z - pa.z)
	var road := Gfx3D.box(Vector3(2.4, 0.06, length), DIRT)
	road.position = mid + Vector3(0, 0.035, 0)
	road.rotation_degrees = Vector3(0, rad_to_deg(yaw), 0)
	world_root.add_child(road)


func _draw_tree(at: Vector2, sc: float) -> void:
	var x := at.x * S
	var z := at.y * S
	var trunk := Gfx3D.cylinder(0.18 * sc, 1.3 * sc, TRUNK)
	trunk.position = Vector3(x, 0.65 * sc, z)
	world_root.add_child(trunk)
	var crown := Gfx3D.cone(1.7 * sc, 3.4 * sc, TREE)
	crown.position = Vector3(x, 1.3 * sc + 1.7 * sc, z)
	world_root.add_child(crown)


func _draw_house(at: Vector2) -> void:
	var x := at.x * S
	var z := at.y * S
	var base := Gfx3D.box(Vector3(3.4, 2.1, 3.4), WOOD)
	base.position = Vector3(x, 1.05, z)
	world_root.add_child(base)
	var roof := Gfx3D.prism(Vector3(4.0, 1.5, 4.0), ROOF)
	roof.position = Vector3(x, 2.1 + 0.75, z)
	world_root.add_child(roof)
	var door := Gfx3D.box(Vector3(0.8, 1.6, 0.12), Color(0.32, 0.2, 0.1))
	door.position = Vector3(x, 0.8, z - 1.7)
	world_root.add_child(door)


func _draw_lumber_camp(at: Vector2) -> void:
	var x := at.x * S
	var z := at.y * S
	var shed := Gfx3D.box(Vector3(3.6, 2.2, 2.6), ROOF)
	shed.position = Vector3(x, 1.1, z)
	world_root.add_child(shed)
	for i in 3:
		var log := Gfx3D.box(Vector3(4.4, 0.55, 0.55), WOOD)
		log.position = Vector3(x + 1.5, 0.28 + i * 0.55, z + 1.7)
		world_root.add_child(log)


func _draw_market(at: Vector2) -> void:
	var x := at.x * S
	var z := at.y * S
	var stall := Gfx3D.box(Vector3(5.0, 1.2, 3.0), WOOD)
	stall.position = Vector3(x, 0.6, z)
	world_root.add_child(stall)
	var awning := Gfx3D.box(Vector3(5.6, 0.2, 3.4), AWNING)
	awning.position = Vector3(x, 1.6, z)
	world_root.add_child(awning)
	for i in 2:
		var post := Gfx3D.cylinder(0.12, 2.0, TRUNK)
		post.position = Vector3(x - 2.3 + i * 4.6, 1.0, z + 1.2)
		world_root.add_child(post)


func _pos(id: String) -> Vector2:
	var p: Dictionary = _place_by_id[id]
	return Vector2(float(p["x"]), float(p["y"]))


func _village_center() -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for p in map_data["places"]:
		if String(p["type"]) == "house":
			acc += Vector2(float(p["x"]), float(p["y"]))
			n += 1
	return acc / float(n)


func _spawn_agents() -> void:
	for a in world.agents:
		var node := AgentNode.new()
		node.sim_agent = a
		node.render_scale = S
		world_root.add_child(node)
		agent_nodes.append(node)


# --- Kamera ---

func _update_camera() -> void:
	var dh := cam_dist * cos(CAM_PITCH)
	var dv := cam_dist * sin(CAM_PITCH)
	var off := Vector3(sin(CAM_YAW) * dh, dv, cos(CAM_YAW) * dh)
	camera.position = cam_target + off
	camera.look_at(cam_target, Vector3.UP)


func _update_camera_pan(delta: float) -> void:
	var b := camera.global_transform.basis
	var fwd := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= right
	cam_target += dir * 30.0 * delta


func _mouse_to_ground() -> Vector3:
	var mpos := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mpos)
	var dir := camera.project_ray_normal(mpos)
	if absf(dir.y) < 0.0001:
		return cam_target
	var t := -origin.y / dir.y
	return origin + dir * t


# --- Wejście ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = clampf(cam_dist * 0.9, 25.0, 240.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = clampf(cam_dist / 0.9, 25.0, 240.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_left_click(_mouse_to_ground())
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right_click(_mouse_to_ground())
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			if _dragging:
				_drag_start = _mouse_to_ground()
	elif event is InputEventMouseMotion and _dragging:
		var g := _mouse_to_ground()
		cam_target += _drag_start - g
		_drag_start = g
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		match key.keycode:
			KEY_SPACE:
				world.clock.toggle_pause()
			KEY_1:
				world.clock.set_speed(1)
			KEY_2:
				world.clock.set_speed(2)
			KEY_3:
				world.clock.set_speed(3)
			KEY_ESCAPE:
				_deselect()


func _agent_at3(g: Vector3) -> Node3D:
	for an in agent_nodes:
		if Vector2(an.position.x - g.x, an.position.z - g.z).length() <= CLICK_RADIUS:
			return an
	return null


func _on_left_click(g: Vector3) -> void:
	var hit := _agent_at3(g)
	if hit != null:
		_select_agent(hit)
	else:
		_deselect()


func _on_right_click(g: Vector3) -> void:
	if selected == null:
		return
	_start_manual_move(g)


func _select_agent(node: Node3D) -> void:
	_deselect()
	selected = node.sim_agent
	_selected_node = node
	node.set_selected(true)


func _deselect() -> void:
	if _selected_node != null:
		_selected_node.set_selected(false)
	if selected != null:
		selected.controlled = false
		selected.activity = "free"
		selected.pending_activity = ""
	selected = null
	_selected_node = null
	_has_manual_target = false


func _start_manual_move(g: Vector3) -> void:
	selected.controlled = true
	selected.activity = "free"
	selected.pending_activity = ""
	_manual_target = Vector2(g.x / S, g.z / S)
	_has_manual_target = true


func _update_manual(delta: float) -> void:
	if selected == null or not selected.controlled or not _has_manual_target:
		return
	var step := move_speed * delta
	if selected.position.distance_to(_manual_target) <= step:
		selected.position = _manual_target
		_has_manual_target = false
		selected.controlled = false
		selected.activity = "free"
	else:
		selected.position = selected.position.move_toward(_manual_target, step)


func _selected_info() -> Dictionary:
	if selected == null:
		return {}
	return {
		"name": selected.name,
		"id": selected.id,
		"age": selected.age,
		"reason": (selected.idle_reason if selected.idle_reason != "" else selected.activity),
		"needs": selected.needs,
		"skills": selected.skills,
		"controlled": selected.controlled,
	}
