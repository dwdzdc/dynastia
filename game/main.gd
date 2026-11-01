extends Node2D

const DataLoader := preload("res://sim/data_loader.gd")
const SimWorld := preload("res://sim/world.gd")
const AgentNode := preload("res://game/agent_node.gd")

const NIGHT := Color(0.08, 0.10, 0.20)
const DAY := Color(0.72, 0.78, 0.86)
const CLICK_RADIUS := 22.0

var world: SimWorld
var move_speed: float = 90.0
var map_data: Dictionary = {}

var agent_nodes: Array = []
var selected: RefCounted = null          # SimAgent
var _selected_node: Node2D = null
var _manual_target: Vector2
var _has_manual_target := false

@onready var sky: ColorRect = $UIBackground/Sky
@onready var hud: Control = $UI/Hud
@onready var camera: Camera2D = $Camera2D
@onready var world_root: Node2D = $WorldRoot

const PLACE_COLORS := {
	"house": Color(0.55, 0.38, 0.22),
	"work": Color(0.20, 0.55, 0.30),
	"food": Color(0.55, 0.45, 0.38),
}
const PLACE_SIZES := { "house": 44.0, "work": 130.0, "food": 90.0 }


func _ready() -> void:
	var balance: Dictionary = DataLoader.load_json("res://data/balance.json")
	map_data = DataLoader.load_json("res://data/map.json")
	world = SimWorld.new(int(balance["world_seed"]), balance, map_data)
	move_speed = float(DataLoader.get_nested(balance, "movement.speed"))

	_build_map()
	_spawn_agents()
	camera.make_current()


func _process(delta: float) -> void:
	world.tick(delta)
	_update_manual(delta)
	_update_camera(delta)

	for an in agent_nodes:
		an.refresh()

	sky.color = NIGHT.lerp(DAY, world.clock.light_factor())
	hud.update_view(world.clock)
	hud.show_agent(_selected_info())


func _build_map() -> void:
	var size: Array = map_data["world_size"]
	var ground := Polygon2D.new()
	ground.polygon = _rect(0.0, 0.0, float(size[0]), float(size[1]))
	ground.color = Color(0.16, 0.18, 0.16)
	world_root.add_child(ground)

	for p in map_data["places"]:
		var pos := Vector2(float(p["x"]), float(p["y"]))
		var half: float = PLACE_SIZES.get(String(p["type"]), 40.0) * 0.5
		var marker := Polygon2D.new()
		marker.polygon = _rect(pos.x - half, pos.y - half, pos.x + half, pos.y + half)
		marker.color = PLACE_COLORS.get(String(p["type"]), Color(0.5, 0.5, 0.5))
		world_root.add_child(marker)

		var lbl := Label.new()
		lbl.text = String(p["name"])
		lbl.position = pos + Vector2(-half, half + 4)
		lbl.add_theme_font_size_override("font_size", 12)
		world_root.add_child(lbl)


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


static func _rect(x1: float, y1: float, x2: float, y2: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x1, y1), Vector2(x2, y1), Vector2(x2, y2), Vector2(x1, y2),
	])
