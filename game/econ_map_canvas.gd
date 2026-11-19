# EconMapCanvas — mapa świata w podglądzie gospodarki: drogi (zamknięte, z
# zbójcami), miasta (wielkość = ludność, kolor = wybrana miara), ciężarówki w
# drodze (kolor = rodzaj ładunku) i błysk przy mieście, o którym właśnie pisze
# kronika. Tylko czyta EconWorld. Kółko: zoom, przeciąganie: przesuwanie, klik: miasto.
class_name EconMapCanvas
extends Control


signal city_clicked(city_id: int)

const BG := Color(0.07, 0.09, 0.12)
const GRID := Color(0.12, 0.15, 0.2)
const ROAD := Color(0.3, 0.36, 0.45)
const ROAD_CLOSED := Color(0.9, 0.25, 0.25)
const ROAD_DANGER := Color(1.0, 0.6, 0.2)
const LABEL := Color(0.88, 0.92, 0.98)
const LABEL_DIM := Color(0.6, 0.66, 0.75)
const SELECT := Color(1.0, 0.95, 0.6)
const TRUCK_EMPTY := Color(0.55, 0.6, 0.7)
const CARGO := {
	"raw": Color(0.78, 0.6, 0.4), "food": Color(0.45, 0.85, 0.45), "part": Color(0.4, 0.8, 0.9),
	"energy": Color(1.0, 0.62, 0.2), "material": Color(0.75, 0.75, 0.8), "goods": Color(0.8, 0.55, 1.0),
}
const CITY_MIN_R := 5.0
const CITY_R_PER_SQRT := 0.045
const FLASH_DAYS := 2.0
const GRID_STEP := 100.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0

var w: EconWorld
var time: float = 0.0              # czas świata z ułamkiem doby (do płynnych ciężarówek)
var selected: int = -1
var mode: String = "prosperity"    # prosperity / unemployment / price
var price_good: String = "fuel"
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _base_scale() -> float:
	var ms: Array = w.data["world"]["map_size"]
	return minf(size.x / float(ms[0]), size.y / float(ms[1])) * 0.95


func to_screen(p: Vector2) -> Vector2:
	var ms: Array = w.data["world"]["map_size"]
	var s := _base_scale() * zoom
	var origin := size * 0.5 - Vector2(float(ms[0]), float(ms[1])) * 0.5 * s + pan
	return origin + p * s


func city_radius(c: EconCity) -> float:
	return (CITY_MIN_R + sqrt(c.population) * CITY_R_PER_SQRT) * sqrt(zoom)


func city_color(c: EconCity) -> Color:
	match mode:
		"unemployment":
			return _ramp(1.0 - clampf(c.unemployment() / 0.3, 0.0, 1.0))
		"price":
			# Tanio = zielony, drogo = czerwony — względem średniej w świecie (widać, gdzie
			# opłaca się kupić, a gdzie sprzedać).
			var r := log(c.market(price_good).price / _avg_price()) / log(2.0)
			return _ramp(clampf(0.5 - r * 0.5, 0.0, 1.0))
		_:
			return _ramp(c.prosperity())


func _avg_price() -> float:
	var s := 0.0
	for c: EconCity in w.cities:
		s += c.market(price_good).price
	return s / maxf(1.0, w.cities.size())


# 0 = czerwony, 0,5 = żółty, 1 = zielony.
static func _ramp(t: float) -> Color:
	var bad := Color(0.92, 0.3, 0.28)
	var mid := Color(0.95, 0.8, 0.3)
	var good := Color(0.35, 0.85, 0.45)
	return bad.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(good, (t - 0.5) * 2.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if w == null:
		return
	var ms: Array = w.data["world"]["map_size"]
	var x := 0.0
	while x <= float(ms[0]):
		draw_line(to_screen(Vector2(x, 0)), to_screen(Vector2(x, float(ms[1]))), GRID, 1.0)
		x += GRID_STEP
	var y := 0.0
	while y <= float(ms[1]):
		draw_line(to_screen(Vector2(0, y)), to_screen(Vector2(float(ms[0]), y)), GRID, 1.0)
		y += GRID_STEP
	for r: EconRoute in w.routes:
		var a := to_screen(w.cities[r.a].pos)
		var b := to_screen(w.cities[r.b].pos)
		if r.is_closed(w.day):
			draw_dashed_line(a, b, ROAD_CLOSED, 3.0, 8.0)
		else:
			draw_line(a, b, ROAD.lerp(ROAD_DANGER, clampf(r.danger * 2.0, 0.0, 1.0)), 2.0 + r.danger * 4.0, true)
	for tr: EconTruck in w.trucks.values():
		if not tr.moving:
			continue
		var col := TRUCK_EMPTY
		if tr.good != "":
			col = CARGO.get(str(w.goods[tr.good]["category"]), TRUCK_EMPTY)
		draw_circle(to_screen(w.truck_pos(tr, time)), 2.2 * sqrt(zoom), col)
	var flash := _recent_news_cities()
	for c: EconCity in w.cities:
		var p := to_screen(c.pos)
		var rad := city_radius(c)
		if flash.has(c.id):
			var k: float = flash[c.id]
			draw_arc(p, rad + 6.0 + (1.0 - k) * 14.0, 0.0, TAU, 32, Color(1, 1, 1, k * 0.8), 2.0)
		if c.id == selected:
			draw_circle(p, rad + 5.0, SELECT)
		draw_circle(p, rad + 1.5, BG)
		draw_circle(p, rad, city_color(c))
		var fs := 14 if c.population > 20000 else 12
		var label := c.name
		draw_string(_font, p + Vector2(rad + 4.0, 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL if c.population > 20000 else LABEL_DIM)


# Miasta, o których kronika pisała w ostatnich dobach (ważne wpisy) -> siła błysku 0..1.
func _recent_news_cities() -> Dictionary:
	var out := {}
	for i in range(w.news.entries.size() - 1, -1, -1):
		var e: Dictionary = w.news.entries[i]
		var age := time - float(e["day"])
		if age > FLASH_DAYS:
			break
		if int(e["severity"]) >= 1 and int(e["city"]) >= 0:
			out[int(e["city"])] = maxf(float(out.get(int(e["city"]), 0.0)), 1.0 - age / FLASH_DAYS)
	return out


func city_at(screen: Vector2) -> int:
	var best := -1
	var best_d := INF
	for c: EconCity in w.cities:
		var d := to_screen(c.pos).distance_to(screen)
		if d < city_radius(c) + 8.0 and d < best_d:
			best_d = d
			best = c.id
	return best


func _gui_input(event: InputEvent) -> void:
	if w == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var before := mb.position
				var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
				var new_zoom := clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
				# Zoom wokół kursora.
				var rel := before - (size * 0.5 + pan)
				pan += rel - rel * (new_zoom / zoom)
				zoom = new_zoom
				queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = false
			else:
				if not _drag:
					var id := city_at(mb.position)
					city_clicked.emit(id)
				_drag = false
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			if mm.relative.length() > 2.0 or _drag:
				_drag = true
				pan += mm.relative
				queue_redraw()
