extends Node2D

const DataLoader := preload("res://sim/data_loader.gd")
const SimWorld := preload("res://sim/world.gd")
const AgentNode := preload("res://game/agent_node.gd")
const Gfx := preload("res://game/gfx.gd")

const NIGHT := Color(0.07, 0.09, 0.18)
const DAY := Color(0.72, 0.78, 0.86)
const CLICK_RADIUS := 22.0

const DIRT := Color(0.66, 0.53, 0.36)
const GRASS := Color(0.46, 0.60, 0.34)
const FOREST_GROUND := Color(0.33, 0.46, 0.26)
const WOOD := Color(0.55, 0.37, 0.22)
const ROOF := Color(0.42, 0.26, 0.14)
const TREE := Color(0.20, 0.38, 0.14)
const AWNING := Color(0.62, 0.24, 0.18)

var world: SimWorld
var move_speed: float = 90.0
var map_data: Dictionary = {}
var _place_by_id: Dictionary = {}

var agent_nodes: Array = []
var selected: RefCounted = null
var _selected_node: Node2D = null
var _hovered: Node2D = null
var _manual_target: Vector2
var _has_manual_target := false

@onready var sky: ColorRect = $UIBackground/Sky
@onready var shade: ColorRect = $UIWorld/Shade
@onready var hud: Control = $UI/Hud
@onready var camera: Camera2D = $Camera2D
@onready var world_root: Node2D = $WorldRoot


func _ready() -> void:
	var balance: Dictionary = DataLoader.load_json("res://data/balance.json")
	map_data = DataLoader.load_json("res://data/map.json")
	world = SimWorld.new(int(balance["world_seed"]), balance, map_data)
	move_speed = float(DataLoader.get_nested(balance, "movement.speed"))

	for p in map_data["places"]:
		_place_by_id[p["id"]] = p

	_build_map()
	_spawn_agents()
	camera.make_current()
	camera.position = _village_center()


func _process(delta: float) -> void:
	world.tick(delta)
	_update_manual(delta)
	_update_camera(delta)
	_update_hover()

	for an in agent_nodes:
		an.refresh()

	var light := world.clock.light_factor()
	sky.color = NIGHT.lerp(DAY, light)
	shade.color = Color(0.0, 0.0, 0.1, (1.0 - light) * 0.45)
	hud.update_view(world.clock)
	hud.show_agent(_selected_info())


# --- Budowa mapy (placeholdery, ale czytelne) ---

func _build_map() -> void:
	var size: Array = map_data["world_size"]
	var w := float(size[0])
	var h := float(size[1])
	world_root.add_child(Gfx.rect(0, 0, w, h, GRASS))

	var forest := _pos("forest")
	var market := _pos("market")
	var village := _village_center()

	# drogi najpierw (pod wszystkim)
	world_root.add_child(Gfx.line(PackedVector2Array([village, forest]), DIRT, 22.0))
	world_root.add_child(Gfx.line(PackedVector2Array([village, market]), DIRT, 22.0))

	# plac wioski
	world_root.add_child(Gfx.rect(village.x - 130, village.y - 90, village.x + 130, village.y + 90, DIRT))

	# strefa lasu + drzewa
	world_root.add_child(Gfx.rect(forest.x - 150, forest.y - 120, forest.x + 160, forest.y + 140, FOREST_GROUND))
	for off in [
		Vector2(-90, -70), Vector2(30, -90), Vector2(90, -40), Vector2(-40, 20),
		Vector2(50, 40), Vector2(110, 10), Vector2(-110, 40), Vector2(0, 95),
		Vector2(120, 95), Vector2(-80, -20),
	]:
		_draw_tree(forest + off, 1.0)

	# budynki
	for p in map_data["places"]:
		var pos := Vector2(float(p["x"]), float(p["y"]))
		match String(p["type"]):
			"house":
				_draw_house(pos)
			"work":
				_draw_lumber_camp(pos)
			"food":
				_draw_market(pos)
		var lbl := Gfx.label(String(p["name"]), pos + Vector2(-22, 30), 15, Color(1, 1, 0.95))
		world_root.add_child(lbl)


func _draw_tree(at: Vector2, s: float) -> void:
	var trunk := Gfx.rect(at.x - 2 * s, at.y - 4 * s, at.x + 2 * s, at.y + 8 * s, WOOD)
	world_root.add_child(trunk)
	var crown := Gfx.triangle(
		Vector2(at.x, at.y - 40 * s), Vector2(at.x - 16 * s, at.y + 2 * s), Vector2(at.x + 16 * s, at.y + 2 * s), TREE)
	world_root.add_child(crown)


func _draw_house(at: Vector2) -> void:
	var base := Gfx.rect(at.x - 26, at.y - 8, at.x + 26, at.y + 18, WOOD)
	world_root.add_child(base)
	var roof := Gfx.triangle(
		Vector2(at.x - 30, at.y - 6), Vector2(at.x + 30, at.y - 6), Vector2(at.x, at.y - 30), ROOF)
	world_root.add_child(roof)
	var door := Gfx.rect(at.x - 5, at.y + 6, at.x + 5, at.y + 18, Color(0.32, 0.2, 0.1))
	world_root.add_child(door)


func _draw_lumber_camp(at: Vector2) -> void:
	# składowane kłody
	for i in 3:
		world_root.add_child(Gfx.rect(at.x - 40, at.y + 4 + i * 10, at.x + 40, at.y + 10 + i * 10, WOOD))
	world_root.add_child(Gfx.rect(at.x - 45, at.y - 10, at.x + 45, at.y + 44, Color(0.28, 0.19, 0.11)))


func _draw_market(at: Vector2) -> void:
	world_root.add_child(Gfx.rect(at.x - 45, at.y - 6, at.x + 45, at.y + 20, WOOD))
	world_root.add_child(Gfx.rect(at.x - 52, at.y - 26, at.x + 52, at.y - 12, AWNING))
	for i in 2:
		world_root.add_child(Gfx.rect(at.x - 45 + i * 50, at.y + 6, at.x - 35 + i * 50, at.y + 20, Color(0.7, 0.6, 0.4)))


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
		world_root.add_child(node)
		agent_nodes.append(node)


func _agent_at(wp: Vector2) -> Node2D:
	for an in agent_nodes:
		if an.position.distance_to(wp) <= CLICK_RADIUS:
			return an
	return null


func _update_hover() -> void:
	var hov := _agent_at(get_global_mouse_position())
	if hov == _hovered:
		return
	if _hovered != null:
		_hovered.set_hovered(false)
	_hovered = hov
	if _hovered != null:
		_hovered.set_hovered(true)


# --- Wejście ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(get_global_mouse_position())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.3, 0.3), Vector2(3.0, 3.0))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.3, 0.3), Vector2(3.0, 3.0))
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
			KEY_T:
				_toggle_control()
			KEY_ESCAPE:
				_deselect()


func _on_left_click(wp: Vector2) -> void:
	var hit := _agent_at(wp)
	if hit != null:
		_select_agent(hit)
	elif selected != null and selected.controlled:
		_start_manual_move(wp)
	else:
		_deselect()


func _select_agent(node: Node2D) -> void:
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


func _toggle_control() -> void:
	if selected == null:
		return
	if selected.controlled:
		selected.controlled = false
		selected.activity = "free"
		selected.pending_activity = ""
		_has_manual_target = false
	else:
		selected.controlled = true
		selected.activity = "free"
		selected.pending_activity = ""
		_has_manual_target = false


func _start_manual_move(wp: Vector2) -> void:
	_manual_target = wp
	_has_manual_target = true


func _update_manual(delta: float) -> void:
	if selected == null or not selected.controlled or not _has_manual_target:
		return
	var step := move_speed * delta
	if selected.position.distance_to(_manual_target) <= step:
		selected.position = _manual_target
		_has_manual_target = false
	else:
		selected.position = selected.position.move_toward(_manual_target, step)


func _update_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	camera.position += dir * 400.0 * delta


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
