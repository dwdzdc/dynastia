# Gfx3D — prymitywne bryły 3D (placeholdery w stylu low-poly). Zero logiki, tylko render.
class_name Gfx3D
extends RefCounted


static func mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func glow(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.18, 0.15)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _mi(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	return mi


static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mi(bm, color)


static func cylinder(radius: float, height: float, color: Color, top: float = -1.0, segs: int = 10) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top < 0.0 else top
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	return _mi(cm, color)


static func cone(bottom: float, height: float, color: Color, segs: int = 8) -> MeshInstance3D:
	return cylinder(bottom, height, color, 0.0, segs)


static func sphere(radius: float, color: Color) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return _mi(sm, color)


static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 3
	return _mi(cm, color)


# Dach dwuspadowy: PrismMesh z grzbietem wzdłuż osi Z.
static func roof(size: Vector3, color: Color) -> MeshInstance3D:
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x, size.y, size.z)
	return _mi(pm, color)


static func set_color(mi: MeshInstance3D, color: Color) -> void:
	(mi.material_override as StandardMaterial3D).albedo_color = color
