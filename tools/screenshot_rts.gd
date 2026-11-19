## tools/screenshot_rts.gd — zrzuty gry na mapie (iteracja 6). Wymaga wyświetlacza:
##   SHOT_DIR=/ścieżka godot --audio-driver Dummy -s res://tools/screenshot_rts.gd
extends SceneTree

var game: Node
var out_dir: String


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = (load("res://game/rts/rts_main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_shoot()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
	print("zapisano ", name)


func _shoot() -> void:
	while game.get("rts") == null or game.get("hud") == null or game.hud.rts == null:
		await process_frame
	game.set_speed(0)
	var rts: RtsWorld = game.rts
	for i in 20:
		rts.advance(0.5)
	rts.advance(0.37)
	game.cities.refresh()
	var home := rts.home_city()
	game.focus_km(home.pos, 2600.0)
	await _frames(8)
	_save("r01_town.png")
	game.focus_km(home.pos + Vector2(0.3, 0.2), 700.0)
	await _frames(5)
	_save("r02_close.png")
	game.focus_km(home.pos, 12000.0)
	await _frames(5)
	_save("r03_region.png")
	var ms: Array = rts.econ.data["world"]["map_size"]
	game.focus_km(Vector2(float(ms[0]), float(ms[1])) * 0.5, 34000.0)
	await _frames(5)
	_save("r04_map.png")
	game.focus_km(home.pos, 2600.0)
	game.selected = {"kind": "city", "id": home.id}
	game.hud.on_selection()
	await _frames(5)
	_save("r05_city.png")
	var moving: Array = rts.econ.trucks.values().filter(func(t: EconTruck) -> bool: return t.moving)
	if not moving.is_empty():
		var tr: EconTruck = moving[0]
		game.selected = {"kind": "truck", "id": tr.id}
		game.focus_km(rts.econ.truck_pos(tr, rts.time), 900.0)
		game.hud.on_selection()
		await _frames(5)
		_save("r06_truck.png")
	var u: RtsUnit = rts.units.values()[0]
	game.selected = {"kind": "unit", "id": u.id}
	game.focus_km(u.pos, 500.0)
	game.hud.on_selection()
	await _frames(5)
	_save("r07_unit.png")
	game.hud.open_build(home.id)
	await _frames(5)
	_save("r08_build.png")
	game.hud.close_window()
	# Sprawdzenie klików: PPM na firmie wysyła zaznaczonego człowieka do pracy.
	var job: EconBusiness = null
	for b: EconBusiness in rts.econ.businesses.values():
		if b.city_id == home.id and b.status == "active" and b.type == "services":
			job = b
			break
	game.focus_km(rts.business_pos(job), 900.0)
	await _frames(3)
	game.selected = {"kind": "unit", "id": u.id}
	game._right_click(game.screen_of_km(rts.business_pos(job)))
	print("klik PPM na firmie -> rozkaz: ", u.order, " / ", u.reason)
	for i in 30:
		rts.advance(0.02)
	print("po chwili: w środku=", u.inside == job.id, " / ", u.reason)
	await _frames(3)
	_save("r09_working.png")
	# Ciężarówka gracza: kupno i karta z rozkazami.
	for b: EconBusiness in rts.econ.businesses.values():
		if b.type == "vehicle_plant":
			rts.econ.city_of(b).market("trucks").add(b.id, 1.0)
			break
	print("kupno ciężarówki: '", rts.buy_truck(), "'")
	var mine := rts.player_trucks()
	if not mine.is_empty():
		var tr: EconTruck = mine[0]
		game.selected = {"kind": "truck", "id": tr.id}
		game.focus_km(rts.econ.truck_pos(tr, rts.time), 1500.0)
		game.hud.on_selection()
		await _frames(5)
		_save("r10_my_truck.png")
	quit(0)
