# AgentView — ludzik 3D: nogi, tułów (kolor ubrania osoby), głowa, włosy, ręce,
# niesiony towar i narzędzie. Proste animacje proceduralne: chód, rąbanie, piłowanie,
# heblowanie, zbieranie, zabawa. Tylko czyta SimAgent/SimPerson.
extends Node3D


# Ubranie to cecha osoby, nie zawodu: stały kolor z palety (po id osoby). Zawód widać
# po tym, co ktoś robi i niesie.
const CLOTH_COLORS := [
	Color(0.55, 0.42, 0.3), Color(0.42, 0.45, 0.32), Color(0.62, 0.55, 0.42), Color(0.4, 0.33, 0.28),
	Color(0.5, 0.36, 0.34), Color(0.36, 0.4, 0.44), Color(0.68, 0.62, 0.5), Color(0.46, 0.5, 0.4),
	Color(0.58, 0.46, 0.36), Color(0.34, 0.3, 0.26),
]
const CHILD_CLOTH := Color(0.93, 0.88, 0.8)


static func cloth_color(person_id: int) -> Color:
	return CLOTH_COLORS[posmod(person_id, CLOTH_COLORS.size())]


const SKIN := Color(0.93, 0.76, 0.6)
const HAIR := [Color(0.25, 0.16, 0.08), Color(0.55, 0.36, 0.16), Color(0.85, 0.7, 0.38), Color(0.12, 0.1, 0.08), Color(0.6, 0.25, 0.1)]
const GREY_HAIR := Color(0.82, 0.82, 0.8)

var agent: SimAgent
var person: SimPerson

var _pivot: Node3D
var _torso: MeshInstance3D
var _skirt: MeshInstance3D
var _head: MeshInstance3D
var _hair: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _carry: Node3D
var _tool: Node3D
var _ring: MeshInstance3D
var _crown: MeshInstance3D
var _band: MeshInstance3D

const CROWN_RADIUS := 0.24     # korona nad głową roota: większa, żeby było go widać z daleka
const CROWN_HEIGHT := 0.42
const CROWN_Y := 2.3
# Opaska na głowie w barwach rodu (G3): twoi mają złotą, obcy kolor swojego rodu.
const OUR_BAND := Color(1.0, 0.8, 0.2)
const LINEAGE_BANDS := [Color(0.25, 0.45, 0.85), Color(0.75, 0.2, 0.2), Color(0.3, 0.65, 0.35),
	Color(0.55, 0.3, 0.7), Color(0.15, 0.6, 0.65), Color(0.8, 0.45, 0.15)]
const BAND_RADIUS := 0.27
const BAND_HEIGHT := 0.11
const BAND_Y := 1.74
var _t := 0.0
var _last_carry := "-"
var _hair_color: Color


func setup(a: SimAgent, p: SimPerson) -> void:
	agent = a
	person = p
	_hair_color = HAIR[p.id % HAIR.size()]
	_pivot = Node3D.new()
	add_child(_pivot)

	_leg_l = _limb(Vector3(-0.12, 0.72, 0), 0.09, 0.72, Color(0.3, 0.24, 0.18))
	_leg_r = _limb(Vector3(0.12, 0.72, 0), 0.09, 0.72, Color(0.3, 0.24, 0.18))
	_torso = Gfx3D.capsule(0.24, 0.85, CLOTH_COLORS[0])
	_torso.position = Vector3(0, 1.08, 0)
	_pivot.add_child(_torso)
	_skirt = Gfx3D.cylinder(0.36, 0.6, CLOTH_COLORS[0], 0.2, 10)
	_skirt.position = Vector3(0, 0.62, 0)
	_skirt.visible = p.sex == "f"
	_pivot.add_child(_skirt)
	_arm_l = _limb(Vector3(-0.31, 1.38, 0), 0.07, 0.6, SKIN)
	_arm_r = _limb(Vector3(0.31, 1.38, 0), 0.07, 0.6, SKIN)
	_head = Gfx3D.sphere(0.24, SKIN)
	_head.position = Vector3(0, 1.68, 0)
	_pivot.add_child(_head)
	_hair = Gfx3D.sphere(0.255, _hair_color)
	_hair.scale = Vector3(1.0, 0.62, 1.0)
	_hair.position = Vector3(0, 1.78, -0.03)
	_pivot.add_child(_hair)

	_tool = Node3D.new()
	var handle := Gfx3D.cylinder(0.03, 0.7, Color(0.45, 0.3, 0.15))
	handle.position = Vector3(0, -0.35, 0)
	_tool.add_child(handle)
	var blade := Gfx3D.box(Vector3(0.05, 0.16, 0.22), Color(0.7, 0.72, 0.76))
	blade.position = Vector3(0, -0.66, 0.1)
	_tool.add_child(blade)
	_tool.position = Vector3(0, -0.55, 0.05)
	_tool.rotation_degrees = Vector3(90, 0, 0)
	_tool.visible = false
	_arm_r.add_child(_tool)

	_carry = Node3D.new()
	_carry.position = Vector3(0, 2.05, 0)
	_pivot.add_child(_carry)

	_ring = Gfx3D.cylinder(0.62, 0.04, Color(1.0, 0.85, 0.2), -1.0, 24)
	_ring.position = Vector3(0, 0.03, 0)
	_ring.visible = false
	add_child(_ring)

	_crown = Gfx3D.cone(CROWN_RADIUS, CROWN_HEIGHT, Color(1.0, 0.8, 0.15), 5)
	(_crown.material_override as StandardMaterial3D).emission_enabled = true
	(_crown.material_override as StandardMaterial3D).emission = Color(1.0, 0.75, 0.1)
	_crown.position = Vector3(0, CROWN_Y, 0)
	_crown.visible = false
	_pivot.add_child(_crown)
	_band = Gfx3D.cylinder(BAND_RADIUS, BAND_HEIGHT, OUR_BAND, -1.0, 12)
	_band.position = Vector3(0, BAND_Y, 0)
	_pivot.add_child(_band)


func _limb(at: Vector3, r: float, length: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	var m := Gfx3D.capsule(r, length, color)
	m.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(m)
	_pivot.add_child(pivot)
	return pivot


static func band_color(lineage_id: int, ours: bool) -> Color:
	return OUR_BAND if ours else LINEAGE_BANDS[lineage_id % LINEAGE_BANDS.size()]


func refresh(delta: float, stage: String, selected: bool, is_root: bool, band: Color) -> void:
	visible = agent.status == "active" and not agent.hidden
	if not visible:
		return
	_t += delta
	position = Vector3(agent.position.x, 0.0, agent.position.y)
	if agent.facing.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(agent.facing.x, agent.facing.y), minf(1.0, delta * 10.0))
	var sc := 1.35
	match stage:
		"child":
			sc = 0.85
		"teen":
			sc = 1.15
	scale = Vector3.ONE * sc
	var col: Color = CHILD_CLOTH if stage == "child" else cloth_color(agent.person_id)
	if agent.disabled():
		col = col.lerp(Color(0.6, 0.6, 0.6), 0.6)
	Gfx3D.set_color(_torso, col)
	Gfx3D.set_color(_skirt, col.darkened(0.15))
	Gfx3D.set_color(_hair, GREY_HAIR if stage == "elder" else _hair_color)
	_ring.visible = selected
	_crown.visible = is_root
	Gfx3D.set_color(_band, band)
	_update_carry()
	_animate()


func _animate() -> void:
	var act := agent.activity
	var bob := 0.0
	var leg := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var lean := 0.0
	var crouch := 0.0
	_tool.visible = false
	match act:
		"walk":
			var f := _t * 9.0
			leg = sin(f) * 0.6
			arm_l = -sin(f) * 0.5
			arm_r = sin(f) * 0.5
			bob = absf(sin(f)) * 0.06
			if agent.carrying != "":
				arm_l = -2.6
				arm_r = -2.6
		"chop":
			_tool.visible = true
			var c := fmod(_t * 1.6, 1.0)
			arm_r = -2.8 + 2.4 * smoothstep(0.55, 0.75, c) if c > 0.5 else -2.8 * smoothstep(0.0, 0.5, c)
			arm_l = arm_r * 0.8
			lean = 0.15 * smoothstep(0.55, 0.75, c)
		"saw":
			var s := sin(_t * 7.0)
			arm_l = -1.2 + s * 0.35
			arm_r = -1.2 + s * 0.35
			lean = 0.2
		"craft":
			arm_r = -1.0 - absf(sin(_t * 10.0)) * 0.9
			arm_l = -0.8
			lean = 0.25
		"forage":
			crouch = 0.3 + sin(_t * 2.0) * 0.05
			lean = 0.6
			arm_l = -0.9 + sin(_t * 5.0) * 0.3
			arm_r = -0.9 - sin(_t * 5.0) * 0.3
		"steal":
			lean = 0.3
			arm_l = -0.4
			arm_r = -0.9 + sin(_t * 3.0) * 0.4
			crouch = 0.12
		"play":
			bob = absf(sin(_t * 6.0)) * 0.35
			arm_l = -2.6
			arm_r = -2.6
		_:
			bob = sin(_t * 2.0) * 0.01
			if agent.alert:
				arm_l = 0.25
				arm_r = 0.25
				lean = -0.05
	_pivot.position.y = bob - crouch
	_pivot.rotation.x = lean
	_leg_l.rotation.x = leg
	_leg_r.rotation.x = -leg
	_arm_l.rotation.x = arm_l
	_arm_r.rotation.x = arm_r
	if agent.health < 40.0 or agent.disabled():
		_pivot.rotation.x += 0.25


func _update_carry() -> void:
	var key := "%s:%d" % [agent.carrying, mini(agent.carrying_qty, 6)]
	if key == _last_carry:
		return
	_last_carry = key
	for c in _carry.get_children():
		c.queue_free()
	match agent.carrying:
		"log":
			for i in agent.carrying_qty:
				var l := Gfx3D.cylinder(0.15, 1.5, Color(0.5, 0.33, 0.18))
				l.rotation_degrees = Vector3(0, 0, 90)
				l.position = Vector3(0, i * 0.28, 0)
				_carry.add_child(l)
		"plank":
			var p := Gfx3D.box(Vector3(0.4, 0.06 * mini(agent.carrying_qty, 6) + 0.04, 1.6), Color(0.85, 0.66, 0.4))
			_carry.add_child(p)
		"chair":
			for i in mini(agent.carrying_qty, 3):
				var ch := Gfx3D.box(Vector3(0.45, 0.4, 0.45), Color(0.62, 0.4, 0.2))
				ch.position = Vector3(0, i * 0.42, 0)
				_carry.add_child(ch)
		"food":
			var s := Gfx3D.sphere(0.28, Color(0.82, 0.72, 0.45))
			s.scale = Vector3(1, 0.8, 1)
			_carry.add_child(s)
