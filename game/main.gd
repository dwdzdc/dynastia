extends Node2D

const DataLoader := preload("res://sim/data_loader.gd")
const SimClock := preload("res://sim/time.gd")

var clock: SimClock

@onready var sky: ColorRect = $Sky
@onready var hud: Control = $Hud

const NIGHT := Color(0.08, 0.10, 0.20)
const DAY := Color(0.72, 0.78, 0.86)


func _ready() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/balance.json")
	clock = SimClock.new(data)
	clock.speed = int(DataLoader.get_nested(data, "time.default_speed"))


func _process(delta: float) -> void:
	clock.advance(delta)
	sky.color = NIGHT.lerp(DAY, clock.light_factor())
	hud.update_view(clock)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				clock.toggle_pause()
			KEY_1:
				clock.set_speed(1)
			KEY_2:
				clock.set_speed(2)
			KEY_3:
				clock.set_speed(3)
