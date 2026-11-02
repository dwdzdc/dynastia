# Main — spina sim, widok 3D i HUD: kamera izometryczna (ortho), wejście, wybór
# obiektów, światło dnia/nocy. Logika gry jest w sim/; tu tylko sterowanie i odczyt.
extends Node3D


const WorldView := preload("res://game/world_view.gd")

const CAM_PITCH := deg_to_rad(38.0)
const SKY_DAY := Color(0.55, 0.7, 0.85)
const SKY_NIGHT := Color(0.06, 0.08, 0.16)
const TREE_PICK_RADIUS := 1.6   # m od pnia, w którym PPM trafia w drzewo

var world: SimWorld
var view: Node3D
var selected_id := -1
var selected_building := ""
var hover_id := -1

var cam_target := Vector3.ZERO
var cam_size := 42.0
var cam_yaw := deg_to_rad(45.0)
var _yaw_goal := deg_to_rad(45.0)
var _press_pos := Vector2.ZERO
var _press_ground := Vector3.ZERO
var _lmb_down := false
var _dragging := false
var _mmb_down := false
var _env: Environment
var _seed := 0

@onready var sun: DirectionalLight3D = $Sun
@onready var camera: Camera3D = $Camera3D
@onready var hud: Control = $UI/Hud


func _ready() -> void:
	var balance := DataLoader.load_json("res://data/balance.json")
	if _seed == 0:
		_seed = int(balance["world_seed"])
	world = SimWorld.new(_seed, balance, DataLoader.load_json("res://data/map.json"), DataLoader.load_json("res://data/people.json"), DataLoader.load_json("res://data/memories.json"))

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	$WorldEnvironment.environment = _env
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.rotation_degrees = Vector3(-55, -30, 0)

	view = WorldView.new()
	add_child(view)
	view.build(world)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.5
	camera.far = 400.0
	camera.make_current()
	var home := world.home().position
	cam_target = Vector3(home.x - 6.0, 0, home.y - 4.0)
	hud.setup(self, world, camera)


func _process(delta: float) -> void:
	world.tick(delta)
	_update_camera(delta)
	_update_light()
	var night := 1.0 - world.clock.light_factor()
	view.refresh(delta, selected_id, night)
	hud.push_fx(world.events.drain_fx())
	hover_id = _agent_under_mouse()
	# Zaznaczona osoba zmarła — odznacz.
	if selected_id >= 0:
		var a := world.agent_by_id(selected_id)
		if a == null or a.status == "dead":
			selected_id = -1


func _update_light() -> void:
	var l := world.clock.light_factor()
	var season := world.clock.current_season()
	sun.light_energy = lerpf(0.15, 0.78, l)
	sun.light_color = Color(0.55, 0.62, 0.95).lerp(Color(1.0, 0.95, 0.86), l)
	_env.background_color = SKY_NIGHT.lerp(SKY_DAY, l)
	_env.ambient_light_color = Color(0.45, 0.5, 0.75).lerp(Color(0.95, 0.92, 0.85), l)
	_env.ambient_light_energy = lerpf(0.38, 0.32, l)
	view.set_season(season, delta_season())


func delta_season() -> float:
	# Płynne przejście koloru terenu przez pół pierwszej doby sezonu (nie na starcie gry).
	var c := world.clock
	if c.day_index() < c.days_per_season:
		return 1.0
	return clampf((float(c.day_of_season()) + c.time_of_day()) * 2.0, 0.0, 1.0)


# --- Kamera ---

func _update_camera(delta: float) -> void:
	var move := Vector3.ZERO
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move -= fwd
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= right
	cam_target += move.normalized() * cam_size * 0.9 * delta
	var ws: Array = world.map["world_size"]
	cam_target.x = clampf(cam_target.x, -10.0, float(ws[0]) + 10.0)
	cam_target.z = clampf(cam_target.z, -10.0, float(ws[1]) + 10.0)
	cam_yaw = lerp_angle(cam_yaw, _yaw_goal, minf(1.0, delta * 8.0))
	_apply_camera()


func _apply_camera() -> void:
	var dir := Vector3(sin(cam_yaw) * cos(CAM_PITCH), sin(CAM_PITCH), cos(cam_yaw) * cos(CAM_PITCH))
	camera.size = cam_size
	camera.position = cam_target + dir * 120.0
	camera.look_at(cam_target, Vector3.UP)


func _ground_at(screen: Vector2) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return cam_target
	return o + d * (-o.y / d.y)


func focus_on(p: Vector2) -> void:
	cam_target = Vector3(p.x, 0, p.y)


# --- Wybór ---

func _agent_under_mouse() -> int:
	var mp := get_viewport().get_mouse_position()
	var ppm := get_viewport().get_visible_rect().size.y / cam_size
	var radius := maxf(14.0, 0.45 * ppm)
	var best := -1
	var bd := INF
	for a in world.agents:
		if a.status != "active" or a.hidden:
			continue
		var feet := camera.unproject_position(Vector3(a.position.x, 0.2, a.position.y))
		var head := camera.unproject_position(Vector3(a.position.x, 1.8, a.position.y))
		var d := _seg_dist(mp, feet, head)
		if d < radius and d < bd:
			bd = d
			best = a.id
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _building_at(g: Vector3) -> String:
	var best := ""
	var bd := INF
	for id in world.buildings:
		var b: SimBuilding = world.buildings[id]
		var r := 5.5 if b.type in ["manor", "market"] else 3.6
		var d := b.position.distance_to(Vector2(g.x, g.z))
		if d < r and d < bd:
			bd = d
			best = id
	return best


func select_agent(id: int, focus := false) -> void:
	selected_id = id
	selected_building = ""
	if focus:
		var a := world.agent_by_id(id)
		if a != null:
			focus_on(a.position if not a.hidden else world.building(a.inside).position if a.inside != "" else a.position)


func set_speed(i: int) -> void:
	world.clock.set_speed(i)


func answer_prompt(id: int, kind: String, value: Variant) -> void:
	if kind == "game_over":
		get_tree().reload_current_scene()
		return
	world.resolve_prompt(id, value)


# --- Wejście ---

func _unhandled_input(event: InputEvent) -> void:
	if world.events.blocking():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					cam_size = clampf(cam_size * 0.9, 14.0, 90.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					cam_size = clampf(cam_size / 0.9, 14.0, 90.0)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb_down = true
					_dragging = false
					_press_pos = mb.position
					_press_ground = _ground_at(mb.position)
				else:
					if _lmb_down and not _dragging:
						_on_left_click(mb.position)
					_lmb_down = false
					_dragging = false
			MOUSE_BUTTON_MIDDLE:
				_mmb_down = mb.pressed
				_press_ground = _ground_at(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_on_right_click(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _lmb_down and not _dragging and mm.position.distance_to(_press_pos) > 8.0:
			_dragging = true
		if _dragging or _mmb_down:
			_apply_camera()
			var g := _ground_at(mm.position)
			cam_target += _press_ground - g
			_apply_camera()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		cam_target += (right * pg.delta.x - fwd * pg.delta.y) * cam_size * 0.02
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		cam_size = clampf(cam_size / mg.factor, 14.0, 90.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				world.clock.toggle_pause()
			KEY_1:
				set_speed(1)
			KEY_2:
				set_speed(2)
			KEY_3:
				set_speed(3)
			KEY_4:
				set_speed(4)
			KEY_Q:
				_yaw_goal += PI / 2.0
			KEY_E:
				_yaw_goal -= PI / 2.0
			KEY_TAB:
				_select_next()
			KEY_F1:
				hud._help.visible = not hud._help.visible
			KEY_ESCAPE:
				selected_id = -1
				selected_building = ""
				hud._help.visible = false


func _select_next() -> void:
	var living := world.family.living()
	if living.is_empty():
		return
	var idx := -1
	for i in living.size():
		if living[i].agent_id == selected_id:
			idx = i
	select_agent(living[(idx + 1) % living.size()].agent_id, true)


func _on_left_click(pos: Vector2) -> void:
	hud._help.visible = false
	var hit := _agent_under_mouse()
	if hit >= 0:
		select_agent(hit)
		return
	var b := _building_at(_ground_at(pos))
	if b != "":
		selected_building = b
		selected_id = -1
		return
	selected_id = -1
	selected_building = ""


# PPM: rozkaz ręczny (zastępuje kolejkę), Shift+PPM: dopisz do kolejki.
func _on_right_click(pos: Vector2, append: bool) -> void:
	if selected_id < 0:
		return
	var g := _ground_at(pos)
	var t: SimTree = view.tree_at(Vector2(g.x, g.z), TREE_PICK_RADIUS)
	if t != null:
		world.manual_chop(selected_id, t.id, append)
	else:
		world.manual_move(selected_id, Vector2(g.x, g.z), append)
