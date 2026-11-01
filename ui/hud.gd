extends Control

const SimClock := preload("res://sim/time.gd")

@onready var time_label: Label = $TimeLabel
@onready var season_label: Label = $SeasonLabel
@onready var day_bar: ProgressBar = $DayBar
@onready var speed_label: Label = $SpeedLabel


func update_view(clock: SimClock) -> void:
	var hm := clock.hour_minute()
	time_label.text = "Dzień %d  ·  %02d:%02d" % [clock.day_index(), hm.x, hm.y]
	season_label.text = "%s · Rok %d · Dzień sezonu %d/%d" % [
		clock.current_season(), clock.current_year(),
		clock.day_of_season() + 1, clock.days_per_season,
	]
	day_bar.value = clock.time_of_day()
	var spd := "PAUZA" if clock.speed == 0 else "%dx" % clock.speed
	speed_label.text = "Prędkość: %s   [SPACE] pauza   [1/2/3] tempo" % spd
