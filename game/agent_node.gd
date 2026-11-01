# AgentNode — wizualna reprezentacja SimAgenta (placeholder: kolorowy kwadrat + etykieta).
# Nie zawiera logiki; tylko czyta stan sim i pokazuje go na scenie.
extends Node2D


var sim_agent  # SimAgent (RefCounted)
var _body: Polygon2D
var _label: Label

const NORMAL := Color(0.86, 0.56, 0.24)
const SELECTED := Color(1.0, 0.90, 0.25)


func _ready() -> void:
	_body = Polygon2D.new()
	_body.polygon = _square(8.0)
	_body.color = NORMAL
	add_child(_body)

	_label = Label.new()
	_label.position = Vector2(-20, -22)
	_label.text = String(sim_agent.name)
	_label.add_theme_font_size_override("font_size", 12)
	add_child(_label)


func set_selected(sel: bool) -> void:
	_body.color = SELECTED if sel else NORMAL


func refresh() -> void:
	position = sim_agent.position


static func _square(r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r),
	])
