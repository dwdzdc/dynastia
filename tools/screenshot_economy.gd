## tools/screenshot_economy.gd — zrzuty podglądu świata (E9). Wymaga wyświetlacza:
##   SHOT_DIR=/ścieżka godot --audio-driver Dummy -s res://tools/screenshot_economy.gd
extends SceneTree

var view: Control
var out_dir: String


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	view = (load("res://game/economy_view.tscn") as PackedScene).instantiate()
	root.add_child(view)
	_shoot()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
	print("zapisano ", name)


func _shoot() -> void:
	while view.get("w") == null:
		await process_frame
	view.call("_set_speed", 0)
	var w: EconWorld = view.get("w")
	for i in 120:
		w.step_day()
	view.set("accum", 0.4)
	await _frames(10)
	view.call("_refresh_all")
	await _frames(5)
	_save("e01_world.png")
	var biggest: EconCity = w.cities[0]
	view.call("_on_city", biggest.id)
	await _frames(5)
	_save("e02_city.png")
	(view.get("_mode") as OptionButton).select(2)
	view.call("_on_mode", 2)
	await _frames(5)
	_save("e03_fuel_price.png")
	quit(0)
