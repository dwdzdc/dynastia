# RtsMain — gra na ciągłej mapie (iteracja 6). Składa świat (RtsWorld), render
# (teren, miasta, jednostki), kamerę RTS i interfejs (RtsHud). Sterowanie jak w
# Cultures: LPM zaznacza, PPM wydaje rozkaz (idź / pracuj tu / jedź do miasta).
# WASD lub strzałki: przesuwanie, kółko: zoom, środkowy przycisk albo przeciąganie LPM: przesuwanie.
extends Node3D


const KM := 1000.0
const SPEEDS := [0.0, 1.0, 3.0, 10.0, 30.0]
const CAM_PITCH := deg_to_rad(52.0)
const CAM_YAW := deg_to_rad(35.0)
const CAM_MIN := 150.0
const CAM_MAX := 42000.0
const CAM_START := 2600.0
const PAN_SPEED := 0.9           # części szerokości widoku na sekundę
const ZOOM_STEP := 1.15
const DRAG_PX := 6.0
const PICK_UNIT_PX := 16.0
const PICK_TRUCK_PX := 12.0
const PICK_BUSINESS_PX := 16.0
const SKY := Color(0.62, 0.74, 0.86)

var rts: RtsWorld
var terrain: RtsTerrain
var cities: RtsCityView
var units: RtsUnitsView
var hud: RtsHud
var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_size := CAM_START
var speed_i := 1
var selected: Dictionary = {}       # { kind: unit/truck/business/city, id }
var _press_pos := Vector2.ZERO
var _dragging := false
var _last_day := -1


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 0.9
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 10.0
	camera.far = 200000.0
	add_child(camera)
	camera.make_current()
	hud = RtsHud.new()
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)
	hud.show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	var seed_env := OS.get_environment("RTS_SEED")
	var econ_data := DataLoader.load_json("res://data/economy.json")
	var seed := int(seed_env) if seed_env != "" else int(econ_data["world"]["seed"])
	rts = RtsWorld.new(seed, econ_data, DataLoader.load_json("res://data/rts.json"))
	terrain = RtsTerrain.new()
	add_child(terrain)
	terrain.build(rts.econ)
	cities = RtsCityView.new()
	add_child(cities)
	cities.build(rts)
	units = RtsUnitsView.new()
	add_child(units)
	units.build(rts)
	var home := rts.home_city()
	cam_target = Vector3(home.pos.x * KM, 0, home.pos.y * KM)
	hud.setup(self)
	_last_day = rts.econ.day


func _process(delta: float) -> void:
	if rts == null:
		return
	var speed := float(SPEEDS[speed_i])
	if speed > 0.0:
		rts.advance(delta * speed / float(rts.data["day_seconds"]))
	if rts.econ.day != _last_day:
		_last_day = rts.econ.day
		cities.refresh()
		terrain.refresh_closures()
	_update_camera(delta)
	terrain.update_roads(cam_size * 0.004)
	units.refresh(rts.time, cam_size, selected)
	hud.update_frame()


func set_speed(i: int) -> void:
	speed_i = clampi(i, 0, SPEEDS.size() - 1)
	hud.on_speed(speed_i)


# --- kamera ------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	if not hud.typing():
		var move := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if move != Vector2.ZERO:
			var right := Vector3(cos(CAM_YAW), 0, -sin(CAM_YAW))
			var fwd := Vector3(-sin(CAM_YAW), 0, -cos(CAM_YAW))
			cam_target += (right * move.x - fwd * move.y).normalized() * cam_size * PAN_SPEED * delta
	var ms: Array = rts.econ.data["world"]["map_size"]
	cam_target.x = clampf(cam_target.x, -2000.0, float(ms[0]) * KM + 2000.0)
	cam_target.z = clampf(cam_target.z, -2000.0, float(ms[1]) * KM + 2000.0)
	var dir := Vector3(sin(CAM_YAW) * cos(CAM_PITCH), sin(CAM_PITCH), cos(CAM_YAW) * cos(CAM_PITCH))
	camera.size = cam_size
	camera.position = cam_target + dir * 60000.0
	camera.look_at(cam_target, Vector3.UP)


func ground_at(screen: Vector2) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return cam_target
	return o + d * (-o.y / d.y)


func ground_km(screen: Vector2) -> Vector2:
	var g := ground_at(screen)
	return Vector2(g.x, g.z) / KM


func focus_km(p: Vector2, size: float = -1.0) -> void:
	cam_target = Vector3(p.x * KM, 0, p.y * KM)
	if size > 0.0:
		cam_size = size


func screen_of_km(p: Vector2, y := 0.0) -> Vector2:
	return camera.unproject_position(Vector3(p.x * KM, y, p.y * KM))


func _zoom(factor: float, at: Vector2) -> void:
	var before := ground_at(at)
	cam_size = clampf(cam_size * factor, CAM_MIN, CAM_MAX)
	_update_camera(0.0)
	var after := ground_at(at)
	cam_target += before - after


# --- wejście -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if rts == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(1.0 / ZOOM_STEP, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(ZOOM_STEP, mb.position)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press_pos = mb.position
					_dragging = false
				elif not _dragging:
					_left_click(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_right_click(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var drag_left := (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and mm.position.distance_to(_press_pos) > DRAG_PX
		if drag_left or (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_dragging = true
			var a := ground_at(mm.position - mm.relative)
			var b := ground_at(mm.position)
			cam_target += a - b
	elif event is InputEventKey and event.pressed and not event.echo:
		hud.on_key((event as InputEventKey).keycode)


# Co jest pod kursorem: { kind, id } albo {} — ludzie gracza, ciężarówki, firmy, miasta.
func pick(screen: Vector2) -> Dictionary:
	var best := {}
	var best_d := PICK_UNIT_PX
	for u: RtsUnit in rts.units.values():
		if u.inside >= 0:
			continue
		var d := screen_of_km(u.pos).distance_to(screen)
		if d < best_d:
			best_d = d
			best = {"kind": "unit", "id": u.id}
	if not best.is_empty():
		return best
	best_d = PICK_TRUCK_PX
	for tid: int in units.truck_ids:
		var tr: EconTruck = rts.econ.trucks.get(tid)
		if tr == null:
			continue
		var d := screen_of_km(rts.econ.truck_pos(tr, rts.time)).distance_to(screen)
		if d < best_d:
			best_d = d
			best = {"kind": "truck", "id": tid}
	if not best.is_empty():
		return best
	var g := ground_km(screen)
	var px_km := cam_size / get_viewport().get_visible_rect().size.y / KM
	var reach := maxf(PICK_BUSINESS_PX * px_km, 0.07)
	var best_km := reach
	for b: EconBusiness in rts.econ.businesses.values():
		if b.status == "closed":
			continue
		var d := rts.business_pos(b).distance_to(g)
		if d < best_km:
			best_km = d
			best = {"kind": "business", "id": b.id}
	if not best.is_empty():
		return best
	for c: EconCity in rts.econ.cities:
		var r := EconLayout.city_radius(rts.econ, c) * 1.3
		if c.pos.distance_to(g) < maxf(r, 24.0 * px_km):
			return {"kind": "city", "id": c.id}
	return {}


func nearest_city(km: Vector2) -> int:
	var best := -1
	var best_d := INF
	for c: EconCity in rts.econ.cities:
		var d := c.pos.distance_to(km)
		if d < best_d:
			best_d = d
			best = c.id
	return best


func _left_click(screen: Vector2) -> void:
	if hud.handle_pick_click(screen):
		return
	selected = pick(screen)
	hud.on_selection()


# PPM: rozkaz dla zaznaczonej jednostki (jak w Cultures: przejęcie ręczne).
func _right_click(screen: Vector2) -> void:
	if hud.cancel_pick():
		return
	var kind := str(selected.get("kind", ""))
	var target := pick(screen)
	if kind == "unit":
		var uid := int(selected["id"])
		if str(target.get("kind", "")) == "business":
			var why := rts.order_work(uid, int(target["id"]))
			hud.flash(why if why != "" else "Idzie do pracy.")
		else:
			rts.order_move(uid, ground_km(screen))
			hud.flash("Idzie we wskazane miejsce.")
	elif kind == "truck" and hud.is_mine_truck(int(selected["id"])):
		if str(target.get("kind", "")) == "business":
			var b: EconBusiness = rts.econ.business(int(target["id"]))
			var why_b := rts.truck_to_business(int(selected["id"]), b.id)
			hud.flash(why_b if why_b != "" else "Jedzie pod: %s." % b.name)
		else:
			var city: int = int(target["id"]) if str(target.get("kind", "")) == "city" else nearest_city(ground_km(screen))
			var why := rts.truck_go(int(selected["id"]), city)
			hud.flash(why if why != "" else "Jedzie do: %s." % rts.econ.cities[city].name)
	hud.on_selection()
