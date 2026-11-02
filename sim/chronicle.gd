# SimChronicle — kronika rodu (C5): trwały zapis ważnych zdarzeń (narodziny, śluby,
# śmierci, odejścia), oddzielony od bieżącego dziennika (SimEvents). Nic nie wyskakuje.
class_name SimChronicle
extends RefCounted


var entries: Array = []   # { day, kind, text, who: [id osób], lineage }


func add(day: float, kind: String, text: String, who: Array, lineage: int) -> void:
	entries.append({ "day": day, "kind": kind, "text": text, "who": who.duplicate(), "lineage": lineage })


func of_kind(kind: String) -> Array:
	return entries.filter(func(e): return e["kind"] == kind)
