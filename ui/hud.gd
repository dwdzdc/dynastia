extends Control

const SimClock := preload("res://sim/time.gd")

@onready var time_label: Label = $TimeLabel
@onready var season_label: Label = $SeasonLabel
@onready var day_bar: ProgressBar = $DayBar
@onready var speed_label: Label = $SpeedLabel
@onready var resources_label: Label = $ResourcesLabel
@onready var agent_label: Label = $AgentLabel
@onready var help_label: Label = $HelpLabel

const HELP := """KAMERA: przytrzymaj ŚPM i przeciągnij / WASD / strzałki · kółko = zoom
LEWY KLIK na ludziku = zaznacz (info w panelu) · PRAWY KLIK na ziemi = każ iść
SPACE = pauza · 1/2/3 = tempo · ESC = odznacz

KOLOR LUDZIKA: niebieski = śpi · pomarańcz = pracuje · żółty = je
szary = wolny · jasnoniebieski = idzie · czerwony = przejęty

BUDYNKI: drewniany domek z dachem = chata · zielone stożki = las
stos kłód = tartak · czerwone zadaszenie = targ"""


func _ready() -> void:
	var outline := Color(0.0, 0.0, 0.0, 0.85)
	for lb in [time_label, season_label, speed_label, resources_label, agent_label, help_label]:
		lb.add_theme_color_override("font_outline_color", outline)
		lb.add_theme_constant_override("outline_size", 4)
	help_label.text = HELP


func update_view(clock: SimClock) -> void:
	var hm := clock.hour_minute()
	time_label.text = "Dzień %d  ·  %02d:%02d" % [clock.day_index(), hm.x, hm.y]
	season_label.text = "%s · Rok %d" % [clock.current_season(), clock.current_year()]
	day_bar.value = clock.time_of_day()
	var spd := "PAUZA" if clock.speed == 0 else "%dx" % clock.speed
	speed_label.text = "Prędkość: %s" % spd


func show_resources(wood: float) -> void:
	resources_label.text = "Drewno: %d" % int(wood)


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
