# DataLoader — wczytywanie i parsowanie JSON z data/.
# Czysta logika (RefCounted), bez zależności od Node; działa także headless.
class_name DataLoader
extends RefCounted


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: cannot open %s (err=%s)" % [path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: invalid JSON in %s" % path)
		return {}
	return parsed as Dictionary


# Wygodny dostęp do stałej zagnieżdżonej po ścieżce "a.b.c" (np. "time.day_seconds").
static func get_nested(data: Dictionary, path: String) -> Variant:
	var parts := path.split(".")
	var cur: Variant = data
	for p in parts:
		if typeof(cur) != TYPE_DICTIONARY or not (cur as Dictionary).has(p):
			push_error("DataLoader: missing key '%s' in %s" % [p, path])
			return null
		cur = (cur as Dictionary)[p]
	return cur
