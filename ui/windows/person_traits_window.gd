# Cechy (ciało i talent) i charakter osoby.
extends "res://ui/windows/person_window.gd"


func build() -> void:
	var p := person
	var fam := world.family
	set_title("Cechy: " + p.name)
	section("Ciało i talent")
	text("brak szczególnych" if p.traits.is_empty() else ", ".join(p.traits.map(func(t): return fam.trait_label(t))), UiKit.SMALL + 2)
	section("Charakter")
	text("nic szczególnego" if p.character.is_empty() else ", ".join(p.character.map(func(c): return fam.character_label(c))), UiKit.SMALL + 2)
