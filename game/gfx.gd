# Gfx — prymitywne, kodowane kształty (placeholdery) do renderowania śwata.
# Tylko warstwa game/ — zero logiki. Zastąpiło nas wcześniej mikrokwadraciki,
# których nie dało się odczytać.
class_name Gfx
extends RefCounted


static func rect(x1: float, y1: float, x2: float, y2: float, color: Color) -> Polygon2D:
	return poly(PackedVector2Array([
		Vector2(x1, y1), Vector2(x2, y1), Vector2(x2, y2), Vector2(x1, y2),
	]), color)


static func poly(pts: PackedVector2Array, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = color
	return p


static func triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> Polygon2D:
	return poly(PackedVector2Array([a, b, c]), color)


static func circle(c: Vector2, r: float, color: Color, segs: int = 20) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return poly(pts, color)


static func line(pts: PackedVector2Array, color: Color, width: float) -> Line2D:
	var l := Line2D.new()
	l.points = pts
	l.width = width
	l.default_color = color
	return l


static func label(text: String, pos: Vector2, size: int, color: Color, outline: bool = true) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", size)
	lb.modulate = color
	if outline:
		lb.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		lb.add_theme_constant_override("outline_size", 4)
	return lb
