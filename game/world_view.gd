# WorldView — scena 3D świata: teren, drogi, las, budynki, sterty towarów, ludziki.
# Statyka budowana raz; zapasy, drzewa i ludzie odświeżani co klatkę ze stanu sim.
extends Node3D


const AgentView := preload("res://game/agent_view.gd")

const GRASS := Color(0.42, 0.55, 0.28)
const GRASS_DARK := Color(0.34, 0.47, 0.24)
const DIRT := Color(0.5, 0.4, 0.27)
const FOREST_FLOOR := Color(0.27, 0.38, 0.2)
const WOOD := Color(0.5, 0.33, 0.2)
const WOOD_DARK := Color(0.4, 0.26, 0.14)
const ROOF := Color(0.5, 0.26, 0.16)
const THATCH := Color(0.62, 0.5, 0.28)
const STONE := Color(0.62, 0.6, 0.56)
const PLASTER := Color(0.88, 0.84, 0.74)
const LEAVES := [Color(0.2, 0.4, 0.16), Color(0.24, 0.45, 0.18), Color(0.17, 0.36, 0.17)]
const TRUNK := Color(0.4, 0.27, 0.15)
const LOG := Color(0.52, 0.35, 0.19)
const PLANK := Color(0.86, 0.68, 0.42)
const SOIL := Color(0.42, 0.3, 0.18)         # zaorane pole
const FALLOW := Color(0.45, 0.47, 0.27)      # ugór
const STUBBLE := Color(0.72, 0.64, 0.4)      # ściernisko
const CROP_YOUNG := Color(0.38, 0.6, 0.22)
const CROP_RIPE := Color(0.88, 0.74, 0.3)
const CROP_MAX_H := 0.9                      # wysokość dojrzałego zboża
const SHEAF := Color(0.85, 0.7, 0.32)

var world: SimWorld
var agent_views: Dictionary = {}   # agent id -> AgentView
var _trees: Dictionary = {}        # tree id -> { node, crown, last }
var _piles: Dictionary = {}        # "bid:good" -> { node, last }
var _windows: Array = []           # okna chaty (świecą nocą)
var _ground: MeshInstance3D
var _floor: MeshInstance3D
var _tufts: Array = []
var _fields: Dictionary = {}       # field id -> { base, rows, heap, last }
const SEASON_GRASS := {
	"spring": Color(0.33, 0.45, 0.22), "summer": Color(0.4, 0.46, 0.21),
	"autumn": Color(0.47, 0.41, 0.22), "winter": Color(0.84, 0.86, 0.9),
}
const SEASON_FLOOR := {
	"spring": Color(0.22, 0.31, 0.16), "summer": Color(0.24, 0.31, 0.15),
	"autumn": Color(0.34, 0.27, 0.15), "winter": Color(0.74, 0.77, 0.8),
}


func build(w: SimWorld) -> void:
	world = w
	var ws: Array = w.map["world_size"]
	var cx := float(ws[0]) * 0.5
	var cz := float(ws[1]) * 0.5
	var ground := Gfx3D.box(Vector3(float(ws[0]) + 60.0, 0.4, float(ws[1]) + 60.0), GRASS)
	ground.position = Vector3(cx, -0.2, cz)
	add_child(ground)
	_ground = ground

	var f: Dictionary = w.map["forest"]
	var floor := Gfx3D.box(Vector3(float(f["w"]) + 6.0, 0.05, float(f["h"]) + 6.0), FOREST_FLOOR)
	floor.position = Vector3(float(f["x"]) + float(f["w"]) * 0.5, 0.01, float(f["y"]) + float(f["h"]) * 0.5)
	add_child(floor)
	_floor = floor

	for r in w.map["roads"]:
		_road(w.building(String(r[0])).door(), w.building(String(r[1])).door())

	_scatter_decor()
	for id in w.buildings:
		_building(w.buildings[id])
	for t in w.trees:
		_tree(t)
	for fl: SimField in w.fields:
		_field(fl)


# Pole (L1, L2): ugór pod spodem, na nim zagony — każdy z własną glebą i zbożem.
func _field(f: SimField) -> void:
	var n := Node3D.new()
	add_child(n)
	_add(n, Gfx3D.box(Vector3(f.rect.size.x, 0.04, f.rect.size.y), FALLOW), Vector3(f.center().x, 0.02, f.center().y))
	var cs: Array = world.balance["fields"]["cell"]
	var cells: Array = []
	for c: Dictionary in f.cells:
		var mid: Vector2 = ((c["start"] as Vector2) + (c["end"] as Vector2)) * 0.5
		var length: float = (c["start"] as Vector2).distance_to(c["end"]) + SimField.EDGE
		var soil := _add(n, Gfx3D.box(Vector3(length, 0.06, float(cs[1]) * 0.8), FALLOW), Vector3(mid.x, 0.04, mid.y))
		var crop := _add(n, Gfx3D.box(Vector3(length - 0.3, 1.0, float(cs[1]) * 0.45), CROP_YOUNG), Vector3(mid.x, 0.0, mid.y))
		cells.append({ "soil": soil, "crop": crop, "last": "" })
	var hs := f.heap_spot()
	var heap := _add(n, Gfx3D.cylinder(0.6, 1.0, SHEAF, 0.35, 8), Vector3(hs.x, 0.5, hs.y))
	_fields[f.id] = { "cells": cells, "heap": heap }


func _refresh_field(f: SimField) -> void:
	var d: Dictionary = _fields[f.id]
	for i in f.cells.size():
		var c: Dictionary = f.cells[i]
		var v: Dictionary = d["cells"][i]
		var key := "%s|%.2f" % [c["stage"], c["growth"]]
		if key == v["last"]:
			continue
		v["last"] = key
		var stage := String(c["stage"])
		var soil: Color = FALLOW
		match stage:
			"plowed", "sown", "ripe":
				soil = SOIL
			"stubble":
				soil = STUBBLE
		Gfx3D.set_color(v["soil"], soil)
		var g := float(c["growth"])
		var crop: MeshInstance3D = v["crop"]
		crop.visible = stage in ["sown", "ripe"] and g > 0.0
		var h := maxf(0.05, CROP_MAX_H * g)
		crop.scale = Vector3(1, h, 1)
		crop.position.y = h * 0.5
		Gfx3D.set_color(crop, CROP_YOUNG.lerp(CROP_RIPE, clampf((g - 0.6) / 0.4, 0.0, 1.0)) if stage == "sown" else CROP_RIPE)
	(d["heap"] as MeshInstance3D).visible = f.heap > 0


func _road(a: Vector2, b: Vector2) -> void:
	var pa := Vector3(a.x, 0, a.y)
	var pb := Vector3(b.x, 0, b.y)
	var length := pa.distance_to(pb)
	var road := Gfx3D.box(Vector3(1.8, 0.04, length + 1.8), DIRT)
	road.position = (pa + pb) * 0.5 + Vector3(0, 0.03, 0)
	road.rotation.y = atan2(pb.x - pa.x, pb.z - pa.z)
	add_child(road)


# Kępy trawy, krzaki i kamienie dla tekstury terenu (deterministycznie).
func _scatter_decor() -> void:
	var rng := SimRng.new(SimRng.hash3(int(world.balance["world_seed"]), 1, "decor"))
	var ws: Array = world.map["world_size"]
	for i in 160:
		var p := Vector3(rng.next_float(-10, float(ws[0]) + 10), 0, rng.next_float(-10, float(ws[1]) + 10))
		if _near_building(Vector2(p.x, p.z), 6.0):
			continue
		var kind := rng.next_int(0, 9)
		if kind < 6:
			var tuft := Gfx3D.cone(0.35, 0.4, GRASS_DARK, 5)
			tuft.position = p + Vector3(0, 0.2, 0)
			add_child(tuft)
			_tufts.append(tuft)
		elif kind < 8:
			var bush := Gfx3D.sphere(rng.next_float(0.5, 0.9), LEAVES[i % 3].lightened(0.1))
			bush.scale = Vector3(1, 0.7, 1)
			bush.position = p + Vector3(0, 0.3, 0)
			add_child(bush)
		else:
			var rock := Gfx3D.sphere(rng.next_float(0.25, 0.5), STONE)
			rock.scale = Vector3(1.3, 0.6, 1)
			rock.position = p + Vector3(0, 0.1, 0)
			add_child(rock)


func _near_building(p: Vector2, r: float) -> bool:
	for id in world.buildings:
		if world.buildings[id].position.distance_to(p) < r:
			return true
	for fl: SimField in world.fields:
		if fl.rect.grow(2.0).has_point(p):
			return true
	var f: Dictionary = world.map["forest"]
	return Rect2(float(f["x"]) - 3, float(f["y"]) - 3, float(f["w"]) + 6, float(f["h"]) + 6).has_point(p)


func _at(b: SimBuilding) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(b.position.x, 0, b.position.y)
	add_child(n)
	return n


func _add(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


func _building(b: SimBuilding) -> void:
	var n := _at(b)
	match b.type:
		"home":
			_house(n, Vector3(5.0, 2.6, 4.0), WOOD, THATCH, true)
			_pile_slot(b, "log", n, Vector3(3.4, 0, 0.6))
			_pile_slot(b, "food", n, Vector3(-3.3, 0, 1.2))
		"decor_house":
			_house(n, Vector3(4.4, 2.4, 3.6), WOOD.darkened(0.08), THATCH.darkened(0.1), false)
		"decor_town":
			_house(n, Vector3(5.0, 4.4, 4.6), PLASTER, ROOF, false)
		"workshop":
			_add(n, Gfx3D.box(Vector3(4.2, 0.15, 3.4), WOOD_DARK), Vector3(0, 0.07, 0))
			for x in [-1.9, 1.9]:
				for z in [-1.5, 1.5]:
					_add(n, Gfx3D.cylinder(0.12, 2.4, WOOD_DARK), Vector3(x, 1.2, z))
			_add(n, Gfx3D.roof(Vector3(4.8, 1.0, 4.0), ROOF), Vector3(0, 2.9, 0))
			_add(n, Gfx3D.box(Vector3(2.0, 0.9, 0.9), WOOD), Vector3(0, 0.45, -0.6))   # warsztat
			_pile_slot(b, "plank", n, Vector3(-3.0, 0, 1.6))
			_pile_slot(b, "chair", n, Vector3(2.8, 0, 1.8))
		"sawmill":
			_add(n, Gfx3D.box(Vector3(5.0, 0.15, 3.0), WOOD_DARK), Vector3(0, 0.07, 0))
			for x in [-2.3, 2.3]:
				for z in [-1.3, 1.3]:
					_add(n, Gfx3D.cylinder(0.14, 2.6, WOOD_DARK), Vector3(x, 1.3, z))
			_add(n, Gfx3D.roof(Vector3(5.6, 1.1, 3.6), THATCH.darkened(0.15)), Vector3(0, 3.1, 0))
			_add(n, Gfx3D.box(Vector3(3.2, 0.7, 0.8), WOOD), Vector3(0, 0.6, 0))         # kozioł
			_add(n, Gfx3D.box(Vector3(0.05, 1.1, 0.6), Color(0.75, 0.76, 0.8)), Vector3(0.4, 1.3, 0))  # piła
			_pile_slot(b, "log", n, Vector3(-4.0, 0, 0.8))
			_pile_slot(b, "plank", n, Vector3(4.0, 0, 0.8))
		"market":
			var colors := [Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7), Color(0.85, 0.7, 0.2)]
			for i in 3:
				var s := Node3D.new()
				s.position = Vector3(-4.0 + i * 4.0, 0, -0.5 if i == 1 else 0.5)
				n.add_child(s)
				_add(s, Gfx3D.box(Vector3(2.8, 1.0, 1.4), WOOD), Vector3(0, 0.5, 0))
				for x in [-1.3, 1.3]:
					_add(s, Gfx3D.cylinder(0.07, 2.4, WOOD_DARK), Vector3(x, 1.2, -0.6))
				var aw := _add(s, Gfx3D.box(Vector3(3.2, 0.12, 2.0), colors[i]), Vector3(0, 2.4, 0))
				aw.rotation.x = 0.2
				_add(s, Gfx3D.sphere(0.3, Color(0.85, 0.5, 0.2)), Vector3(-0.6, 1.15, 0))
				_add(s, Gfx3D.sphere(0.28, Color(0.5, 0.7, 0.25)), Vector3(0.5, 1.12, 0.1))
		"manor":
			_house(n, Vector3(9.0, 4.0, 6.0), PLASTER, Color(0.45, 0.2, 0.15), false)
			_add(n, Gfx3D.box(Vector3(2.2, 6.5, 2.2), PLASTER), Vector3(-3.2, 3.25, 0))
			_add(n, Gfx3D.cone(1.8, 2.4, Color(0.45, 0.2, 0.15), 4), Vector3(-3.2, 7.7, 0), PI / 4)
		"jail":
			_house(n, Vector3(6.0, 3.6, 5.0), STONE, Color(0.35, 0.33, 0.32), false)
			_add(n, Gfx3D.box(Vector3(1.6, 5.8, 1.6), STONE.darkened(0.1)), Vector3(2.4, 2.9, -1.4))
			for i in 3:
				_add(n, Gfx3D.box(Vector3(0.1, 1.0, 0.1), Color(0.15, 0.15, 0.15)), Vector3(-1.0 + i * 0.3, 2.0, 2.52))


func _house(n: Node3D, size: Vector3, wall: Color, roof_col: Color, lit: bool) -> void:
	_add(n, Gfx3D.box(size, wall), Vector3(0, size.y * 0.5, 0))
	_add(n, Gfx3D.roof(Vector3(size.x + 0.7, size.y * 0.55 + 0.6, size.z + 0.7), roof_col), Vector3(0, size.y + (size.y * 0.55 + 0.6) * 0.5, 0))
	_add(n, Gfx3D.box(Vector3(0.95, 1.7, 0.1), WOOD_DARK.darkened(0.2)), Vector3(0, 0.85, size.z * 0.5 + 0.03))
	for x in [-size.x * 0.3, size.x * 0.3]:
		var win := _add(n, Gfx3D.box(Vector3(0.7, 0.6, 0.08), Color(0.2, 0.18, 0.15)), Vector3(x, size.y * 0.6, size.z * 0.5 + 0.03))
		if lit:
			win.material_override = Gfx3D.glow(Color(1.0, 0.75, 0.35), 0.0)
			_windows.append(win)
	_add(n, Gfx3D.box(Vector3(0.5, 1.6, 0.5), STONE), Vector3(size.x * 0.3, size.y + 1.2, -size.z * 0.15))


func _tree(t: SimTree) -> void:
	var n := Node3D.new()
	n.position = Vector3(t.position.x, 0, t.position.y)
	n.rotation.y = float(t.id) * 1.7
	add_child(n)
	var trunk := Gfx3D.cylinder(0.22, 1.6, TRUNK)
	trunk.position = Vector3(0, 0.8, 0)
	n.add_child(trunk)
	var crown := Node3D.new()
	n.add_child(crown)
	var col: Color = LEAVES[t.id % LEAVES.size()]
	var c1 := Gfx3D.cone(1.6, 2.4, col)
	c1.position = Vector3(0, 2.5, 0)
	crown.add_child(c1)
	var c2 := Gfx3D.cone(1.15, 2.0, col.lightened(0.08))
	c2.position = Vector3(0, 3.6, 0)
	crown.add_child(c2)
	var stump := Gfx3D.cylinder(0.26, 0.35, TRUNK.lightened(0.15))
	stump.position = Vector3(0, 0.17, 0)
	n.add_child(stump)
	_trees[t.id] = { "node": n, "crown": crown, "trunk": trunk, "stump": stump, "last": -1.0 }


func _pile_slot(b: SimBuilding, good: String, parent: Node3D, at: Vector3) -> void:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	_piles["%s:%s" % [b.id, good]] = { "node": n, "b": b, "good": good, "last": -1 }


func _refresh_pile(p: Dictionary) -> void:
	var b: SimBuilding = p["b"]
	var good := String(p["good"])
	var amt := b.amount(good)
	if amt == int(p["last"]):
		return
	p["last"] = amt
	var n: Node3D = p["node"]
	for c in n.get_children():
		c.queue_free()
	match good:
		"log":
			for i in mini(amt, 12):
				var row := i / 4
				var col := i % 4
				var l := Gfx3D.cylinder(0.2, 1.8, LOG)
				l.rotation_degrees = Vector3(90, 0, 0)
				l.position = Vector3((col - 1.5) * 0.42 + row * 0.21, 0.2 + row * 0.36, 0)
				n.add_child(l)
		"plank":
			var layers := int(ceil(amt / 2.0))
			for i in mini(layers, 12):
				var pl := Gfx3D.box(Vector3(0.9, 0.08, 2.2), PLANK if i % 2 == 0 else PLANK.darkened(0.08))
				pl.position = Vector3(0, 0.06 + i * 0.09, 0)
				n.add_child(pl)
		"chair":
			for i in mini(amt, 6):
				var ch := Node3D.new()
				ch.position = Vector3((i % 3) * 0.7 - 0.7, 0, (i / 3) * 0.7)
				ch.add_child(_chair_mesh())
				n.add_child(ch)
		"food":
			for i in mini(int(ceil(amt / 3.0)), 10):
				var s := Gfx3D.sphere(0.32, Color(0.82, 0.72, 0.45).darkened((i % 3) * 0.06))
				s.scale = Vector3(1, 0.85, 1)
				s.position = Vector3((i % 4) * 0.55 - 0.8, 0.27 + (i / 4) * 0.45, 0)
				n.add_child(s)


func _chair_mesh() -> Node3D:
	var c := Node3D.new()
	var seat := Gfx3D.box(Vector3(0.5, 0.08, 0.5), Color(0.62, 0.4, 0.2))
	seat.position = Vector3(0, 0.45, 0)
	c.add_child(seat)
	var back := Gfx3D.box(Vector3(0.5, 0.5, 0.07), Color(0.62, 0.4, 0.2))
	back.position = Vector3(0, 0.72, -0.22)
	c.add_child(back)
	for x in [-0.2, 0.2]:
		for z in [-0.2, 0.2]:
			var l := Gfx3D.box(Vector3(0.06, 0.45, 0.06), Color(0.5, 0.32, 0.16))
			l.position = Vector3(x, 0.22, z)
			c.add_child(l)
	return c


# Kolor terenu wg sezonu (zima = śnieg), płynnie na początku sezonu.
func set_season(season: String, blend: float) -> void:
	var seasons: Array = world.clock.seasons
	var prev: String = seasons[(seasons.find(season) + seasons.size() - 1) % seasons.size()]
	var g: Color = (SEASON_GRASS[prev] as Color).lerp(SEASON_GRASS[season], blend)
	Gfx3D.set_color(_ground, g)
	Gfx3D.set_color(_floor, (SEASON_FLOOR[prev] as Color).lerp(SEASON_FLOOR[season], blend))
	for t in _tufts:
		Gfx3D.set_color(t, g.darkened(0.15))


func refresh(delta: float, selected_id: int, night: float) -> void:
	for f: SimField in world.fields:
		_refresh_field(f)
	var regrow: float = world.regrow_total()
	for t: SimTree in world.trees:
		var g: float = t.growth(regrow)
		var d: Dictionary = _trees[t.id]
		if absf(g - float(d["last"])) < 0.01:
			continue
		d["last"] = g
		var crown: Node3D = d["crown"]
		var trunk: Node3D = d["trunk"]
		var alive: bool = g > 0.04
		crown.visible = alive
		trunk.visible = alive
		(d["stump"] as Node3D).visible = not alive or t.wood <= 0
		var s := maxf(g, 0.05)
		crown.scale = Vector3.ONE * s
		trunk.scale = Vector3(1, s, 1)
		trunk.position.y = 0.8 * s
	for k in _piles:
		_refresh_pile(_piles[k])
	for win in _windows:
		var m: StandardMaterial3D = win.material_override
		m.emission_energy_multiplier = night * 2.5

	for a in world.agents:
		if not agent_views.has(a.id):
			var p := world.person_of(a)
			var v := AgentView.new()
			add_child(v)
			v.setup(a, p)
			agent_views[a.id] = v
	var root_id: int = world.family.root_id
	for id in agent_views:
		var v = agent_views[id]
		var p: SimPerson = v.person
		v.refresh(delta, world.family.stage_of(p), id == selected_id, p.id == root_id,
			AgentView.band_color(p.lineage_id, world.family.is_ours(p)))


func tree_at(pos: Vector2, radius: float) -> SimTree:
	var best: SimTree = null
	var bd := radius
	for t: SimTree in world.trees:
		if t.wood <= 0:
			continue
		var d: float = t.position.distance_to(pos)
		if d < bd:
			bd = d
			best = t
	return best
