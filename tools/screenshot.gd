## tools/screenshot.gd — narzędzie deweloperskie.
## Odpala grę na prawdziwym wyświetlaczu (nie działa z --headless), zapisuje 3 zrzuty
## do /tmp/opencode/ i kończy. Do szybkiego podglądu kadru przez dewelopera.
## Uruchomienie:  godot --audio-driver Dummy -s res://tools/screenshot.gd
extends SceneTree

var game: Node


func _initialize() -> void:
	game = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_shoot()


func _shoot() -> void:
	for i in 20:
		await process_frame

	# południe, żeby kadr był dzienny i czytelny
	game.world.clock.set_time(0, 0.5)

	game.cam_target = Vector3(96, 0, 72); game.cam_dist = 120  # cała mapa
	for i in 8:
		await process_frame
	_save("dynastia_overview.png")

	game.cam_target = Vector3(26.4, 0, 24); game.cam_dist = 45  # las
	for i in 8:
		await process_frame
	_save("dynastia_forest.png")

	game.cam_target = Vector3(88.8, 0, 91.2); game.cam_dist = 58  # wioska
	for i in 8:
		await process_frame
	_save("dynastia_village.png")

	print("DONE")
	quit()


func _save(fname: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("/tmp/opencode/" + fname)
	print("SAVED " + fname + " " + str(img.get_size()))
