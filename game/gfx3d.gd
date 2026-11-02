# Gfx3D — prymitywne, kodowane bryły 3D (placeholdery). W stylu gierka:
# proste meshe + StandardMaterial3D z jednym kolorem. Zero logiki, tylko render.
class_name Gfx3D
extends RefCounted


static func mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(color)
	mi.mesh = bm
	return mi


static func cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.material = mat(color)
	mi.mesh = cm
	return mi


static func cone(bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 10
	cm.material = mat(color)
	mi.mesh = cm
	return mi


static func sphere(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	sm.material = mat(color)
	mi.mesh = sm
	return mi


static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 4
	cm.material = mat(color)
	mi.mesh = cm
	return mi


static func prism(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	pm.material = mat(color)
	mi.mesh = pm
	return mi


static func plane(size: Vector2, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.flip_faces = true  # PlaneMesh patrzy w -Y; od góry chcemy widzieć przednią ścianę
	pm.material = mat(color)
	mi.mesh = pm
	return mi


static func label3d(text: String, size: int = 28, color: Color = Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	l.modulate = color
	l.fixed_size = true
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
