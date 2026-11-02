## tools/screenshot.gd — narzędzie deweloperskie: odpala grę na prawdziwym wyświetlaczu
## (nie działa z --headless), przewija kilka scen i zapisuje zrzuty do SHOT_DIR
## (domyślnie user://shots). Uruchomienie:
##   SHOT_DIR=/ścieżka godot --audio-driver Dummy -s res://tools/screenshot.gd
extends SceneTree

var game: Node
var out_dir: String


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_shoot()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shoot() -> void:
	await _frames(10)
	game.hud._help.visible = false
	# Rano: start dnia, ludzie idą do pracy.
	game.world.step_sim(game.world.clock.day_seconds * 0.12)
	await _frames(30)
	_save("01_start.png")
	game.select_agent(game.world.family.root().agent_id, true)
	await _frames(20)
	_save("02_selected.png")
	game.selected_id = -1
	game.selected_building = "sawmill"
	game.cam_target = Vector3(30, 0, 24)
	game.cam_size = 28.0
	game.world.step_sim(game.world.clock.day_seconds * 0.15)
	await _frames(20)
	_save("03_sawmill.png")
	game.selected_building = ""
	game.cam_size = 70.0
	game.cam_target = Vector3(46, 0, 34)
	await _frames(20)
	_save("04_overview.png")
	# Dzień 3, przedpołudnie: osada w ruchu (pytania odklikane automatycznie).
	game.cam_size = 34.0
	game.cam_target = Vector3(42, 0, 30)
	var w = game.world
	while w.clock.now() < 2.45:
		w.step_sim(1.0)
		while w.events.blocking():
			var p: Dictionary = w.events.prompts[0]
			w.resolve_prompt(int(p["id"]), p["options"][0]["value"])
	await _frames(30)
	_save("06_day3.png")
	game.selected_building = "market"
	game.cam_target = Vector3(66, 0, 30)
	await _frames(20)
	_save("07_market.png")
	game.selected_building = ""
	# Noc i zima.
	game.world.clock.set_time(16, 0.9)
	await _frames(30)
	_save("05_winter_night.png")
	print("DONE")
	quit()


func _save(fname: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(fname))
	print("SAVED " + fname)
