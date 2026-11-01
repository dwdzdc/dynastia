# AgentNode3D — placeholder "ludzika" w 3D: kapsuła (ciało) + głowa + etykieta 3D.
# Kolor ciała = stan; etykieta zawsze pokazuje imię i co robi. Selekcja = złoty krążek.
extends Node3D

const Gfx3D := preload("res://game/gfx3d.gd")

var sim_agent
var render_scale := 1.0

var _body: MeshInstance3D
var _head: MeshInstance3D
var _disc: MeshInstance3D
var _label: Label3D

const SKIN := Color(0.91, 0.78, 0.62)
const STATE_COLORS := {
	"sleep": Color(0.40, 0.50, 0.85),
	"work": Color(0.85, 0.50, 0.22),
	"eat": Color(0.86, 0.76, 0.16),
	"free": Color(0.62, 0.64, 0.66),
	"commute": Color(0.42, 0.64, 0.85),
	"manual": Color(0.85, 0.28, 0.28),
}
const STATE_TEXT := {
	"sleep": "śpi", "work": "pracuje", "eat": "je",
	"free": "wolny", "commute": "idzie", "manual": "ręcznie",
}


func _ready() -> void:
	_body = Gfx3D.capsule(0.42, 1.5, STATE_COLORS["free"])
	_body.position = Vector3(0, 0.75, 0)
	add_child(_body)

	_head = Gfx3D.sphere(0.24, SKIN)
	_head.position = Vector3(0, 1.62, 0)
	add_child(_head)

	_disc = Gfx3D.cylinder(0.85, 0.06, Color(1.0, 0.85, 0.2))
	_disc.position = Vector3(0, 0.05, 0)
	_disc.visible = false
	add_child(_disc)

	_label = Gfx3D.label3d("", 26)
	_label.position = Vector3(0, 2.3, 0)
	add_child(_label)


func _state_key() -> String:
	if sim_agent.controlled:
		return "manual"
	return String(sim_agent.activity)


func refresh() -> void:
	position = Vector3(sim_agent.position.x * render_scale, 0.0, sim_agent.position.y * render_scale)
	var k := _state_key()
	var mat: StandardMaterial3D = _body.mesh.material
	mat.albedo_color = STATE_COLORS.get(k, STATE_COLORS["free"])
	_label.text = "%s · %s" % [String(sim_agent.name), STATE_TEXT.get(k, "")]
	if sim_agent.controlled:
		_label.modulate = Color(1.0, 0.5, 0.5)
	else:
		_label.modulate = Color(1, 1, 1)


func set_selected(sel: bool) -> void:
	_disc.visible = sel
