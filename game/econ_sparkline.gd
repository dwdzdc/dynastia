# EconSparkline — mały wykres linii (historia ceny, zadowolenia, ludności).
class_name EconSparkline
extends Control


const BG := Color(0.1, 0.13, 0.17)
const LINE := Color(0.5, 0.8, 1.0)
const BASE_LINE := Color(0.4, 0.45, 0.55, 0.6)

var values: Array = []
var baseline: float = NAN   # pozioma linia odniesienia (np. cena bazowa)
var color := LINE


func set_data(v: Array, base := NAN, col := LINE) -> void:
	values = v
	baseline = base
	color = col
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if values.size() < 2:
		return
	var lo := INF
	var hi := -INF
	for v: float in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if not is_nan(baseline):
		lo = minf(lo, baseline)
		hi = maxf(hi, baseline)
	if hi - lo < 1e-6:
		hi = lo + 1.0
	var pts := PackedVector2Array()
	for i in values.size():
		var x := float(i) / float(values.size() - 1) * size.x
		var y := size.y - (float(values[i]) - lo) / (hi - lo) * (size.y - 4.0) - 2.0
		pts.append(Vector2(x, y))
	if not is_nan(baseline):
		var by := size.y - (baseline - lo) / (hi - lo) * (size.y - 4.0) - 2.0
		draw_dashed_line(Vector2(0, by), Vector2(size.x, by), BASE_LINE, 1.0, 4.0)
	draw_polyline(pts, color, 2.0, true)
