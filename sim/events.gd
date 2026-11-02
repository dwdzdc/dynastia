# SimEvents — dziennik zdarzeń, krytyczne pytania do gracza (auto-pauza) i efekty
# wizualne do odczytu przez widok. Sim tylko dopisuje; game/ui czyta i opróżnia fx.
class_name SimEvents
extends RefCounted


const MAX_LOG := 200

var entries: Array = []        # { day, tod, text, level: info|good|warn|critical, focus: Vector2|null }
var prompts: Array = []    # { id, kind, title, text, options: [{label, value}], data }
var fx: Array = []         # { pos: Vector2, text, kind }
var _next_prompt := 1


func add(day: int, tod: float, text: String, level: String = "info", focus: Variant = null) -> void:
	entries.append({ "day": day, "tod": tod, "text": text, "level": level, "focus": focus })
	if entries.size() > MAX_LOG:
		entries.pop_front()


func ask(kind: String, title: String, text: String, options: Array, data: Dictionary = {}) -> int:
	var id := _next_prompt
	_next_prompt += 1
	prompts.append({ "id": id, "kind": kind, "title": title, "text": text, "options": options, "data": data })
	return id


func blocking() -> bool:
	return not prompts.is_empty()


func pop_prompt(id: int) -> Dictionary:
	for i in prompts.size():
		if int(prompts[i]["id"]) == id:
			var p: Dictionary = prompts[i]
			prompts.remove_at(i)
			return p
	return {}


func float_text(pos: Vector2, text: String, kind: String = "info") -> void:
	fx.append({ "pos": pos, "text": text, "kind": kind })
	if fx.size() > 64:
		fx.pop_front()


func drain_fx() -> Array:
	var out := fx
	fx = []
	return out
