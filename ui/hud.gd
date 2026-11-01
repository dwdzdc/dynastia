extends Control

const SimClock := preload("res://sim/time.gd")

@onready var time_label: Label = $TimeLabel
@onready var season_label: Label = $SeasonLabel
@onready var day_bar: ProgressBar = $DayBar
@onready var speed_label: Label = $SpeedLabel
@onready var agent_label: Label = $AgentLabel


func update_view(clock: SimClock) -> void:
	var hm := clock.hour_minute()
	time_label.text = "Dzień %d  ·  %02d:%02d" % [clock.day_index(), hm.x, hm.y]
	season_label.text = "%s · Rok %d · Dzień sezonu %d/%d" % [
		clock.current_season(), clock.current_year(),
		clock.day_of_season() + 1, clock.days_per_season,
	]
	day_bar.value = clock.time_of_day()
	var spd := "PAUZA" if clock.speed == 0 else "%dx" % clock.speed
	speed_label.text = "Prędkość: %s   [SPACE] pauza · [1/2/3] tempo · [T] przejęcie · [ESC] anuluj" % spd


func show_agent(info: Dictionary) -> void:
	if info.is_empty():
		agent_label.text = ""
		return
	var lines: Array = []
	var ctrl := "  (PRZEJĘTA)" if bool(info.get("controlled", false)) else ""
	lines.append("%s  ·  id %d  ·  lat %d%s" % [
		info.get("name", ""), int(info.get("id", 0)), int(info.get("age", 0)), ctrl,
	])
	lines.append("Stan: %s" % info.get("reason", ""))
	var needs: Dictionary = info.get("needs", {})
	lines.append("Sen %d%%  ·  Jedzenie %d%%" % [
		int(round(float(needs["sleep"]))), int(round(float(needs["food"]))),
	])
	var skills: Dictionary = info.get("skills", {})
	for k in skills:
		lines.append("%s: %d" % [k, int(skills[k])])
	agent_label.text = "\n".join(lines)
