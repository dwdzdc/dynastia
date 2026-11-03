# UiKit — wspólne kolory, style i kontrolki interfejsu (S44). Każde okno i pasek
# buduje się z tych samych klocków, żeby całość wyglądała spójnie.
class_name UiKit
extends RefCounted


const BG := Color(0.11, 0.09, 0.07, 0.92)
const BORDER := Color(0.55, 0.42, 0.25)
const TEXT := Color(0.95, 0.91, 0.82)
const DIM := Color(0.72, 0.67, 0.58)
const TITLE := Color(1.0, 0.85, 0.45)
const GOOD := Color(0.55, 0.88, 0.45)
const WARN := Color(1.0, 0.78, 0.3)
const BAD := Color(1.0, 0.42, 0.35)
const CARD_BG := Color(0.2, 0.16, 0.12)
const CARD_SEL := Color(0.42, 0.32, 0.16)

const FONT := 18          # domyślny rozmiar tekstu
const SMALL := 15         # podpisy, podpowiedzi
const HEAD := 22          # tytuły okien
const PANEL_PAD := 12


static func box(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = FONT
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_color", "Button", TEXT)
	th.set_stylebox("normal", "Button", box(Color(0.25, 0.19, 0.13), BORDER.darkened(0.3), 4, 6))
	th.set_stylebox("hover", "Button", box(Color(0.36, 0.27, 0.17), BORDER, 4, 6))
	th.set_stylebox("pressed", "Button", box(Color(0.5, 0.36, 0.18), Color(1, 0.85, 0.4), 4, 6))
	th.set_stylebox("disabled", "Button", box(Color(0.16, 0.14, 0.12), Color(0.25, 0.22, 0.2), 4, 6))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("panel", "PanelContainer", box(BG, BORDER, 8, PANEL_PAD))
	th.set_stylebox("background", "ProgressBar", box(Color(0.2, 0.17, 0.14), Color(0, 0, 0, 0), 3, 0))
	return th


static func label(text: String, size := 0, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# Etykieta zawijana do szerokości kontenera (minimum szerokości 0, więc nie rozpycha okna).
static func wrap(text: String, size := 0, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, cb: Callable, size := 0) -> Button:
	var b := Button.new()
	b.text = text
	if size > 0:
		b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func row(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func grid(columns: int, sep := 6) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	return g
