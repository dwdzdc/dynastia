# AgentNode — placeholder "ludzika" (głowa + ciało) z etykietą i dymkiem stanu.
# Kolor ciała = stan agenta; hovering pokazuje powód bezczynności (idle_reason).
extends Node2D

const Gfx := preload("res://game/gfx.gd")

var sim_agent

var _body: Polygon2D
var _head: Polygon2D
var _ring: Polygon2D
var _name_label: Label
var _act_label: Label
var _bubble: Node2D

const SKIN := Color(0.91, 0.78, 0.62)
const STATE_COLORS := {
	"sleep": Color(0.40, 0.50, 0.85),
	"work": Color(0.85, 0.50, 0.20),
	"eat": Color(0.85, 0.76, 0.16),
	"free": Color(0.62, 0.64, 0.66),
	"commute": Color(0.42, 0.64, 0.85),
	"manual": Color(0.85, 0.25, 0.25),
}
const STATE_TEXT := {
	"sleep": "śpi", "work": "pracuje", "eat": "je",
	"free": "wolny", "commute": "idzie", "manual": "ręcznie",
}


func _ready() -> void:
	_body = Gfx.circle(Vector2.ZERO, 8.0, STATE_COLORS["free"])
	add_child(_body)
	_head = Gfx.circle(Vector2(0, -9), 4.6, SKIN)
	add_child(_head)

	_ring = Gfx.circle(Vector2.ZERO, 12.5, Color(1.0, 0.9, 0.25, 0.45))
	_ring.visible = false
	add_child(_ring)

	_name_label = Gfx.label(String(sim_agent.name), Vector2(-20, -34), 13, Color(1, 1, 1))
	add_child(_name_label)
	_act_label = Gfx.label("", Vector2(-14, -20), 10, Color(1, 0.92, 0.6))
	add_child(_act_label)

	_bubble = Node2D.new()
	_bubble.position = Vector2(0, -52)
	_bubble.visible = false
	_bubble.add_child(Gfx.rect(-78, -9, 78, 9, Color(0.08, 0.08, 0.08, 0.9)))
	var bt := Gfx.label("", Vector2(-74, -5), 11, Color(1, 1, 1), false)
	bt.name = "BubbleText"
	_bubble.add_child(bt)
	add_child(_bubble)


func _state_key() -> String:
	if sim_agent.controlled:
		return "manual"
	return String(sim_agent.activity)


func refresh() -> void:
	position = sim_agent.position
	var k := _state_key()
	_body.color = STATE_COLORS.get(k, STATE_COLORS["free"])
	if sim_agent.controlled:
		_act_label.text = "▶ ręcznie"
		_act_label.modulate = Color(1.0, 0.4, 0.4)
	else:
		_act_label.text = STATE_TEXT.get(k, "")
		_act_label.modulate = Color(1, 0.92, 0.6)


func set_selected(sel: bool) -> void:
	_ring.visible = sel


func set_hovered(hov: bool) -> void:
	_bubble.visible = hov
	if hov and _bubble.has_node("BubbleText"):
		var bt := _bubble.get_node("BubbleText") as Label
		bt.text = String(sim_agent.idle_reason)
