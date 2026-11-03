# Zapasy domu: spiżarnia, opał, ile trzymać (tragarze i domownicy dokupią i doniosą).
extends "res://ui/windows/building_window.gd"


const STEP := 2           # krok progu zapasu


func build() -> void:
	set_title("Zapasy: " + b.name)
	var hh: SimHousehold = world.household_at(b.id)
	dyn(func(): return "Spiżarnia: %d / %d posiłków\nOpał: %d / %d kłód (zużycie: %s/dzień)" % [
		b.amount("food"), int(b.capacity["food"]), b.amount("log"), int(b.capacity["log"]),
		str(world.balance["economy"]["firewood_per_day"].get(world.clock.current_season(), 0))], UiKit.FONT)
	if hh != world.household:
		return
	add(HSeparator.new())
	text("Ile trzymać w zapasie:", UiKit.SMALL + 1, UiKit.DIM)
	stepper("Jedzenie", func(): return hh.target_food, func(d): hh.target_food = clampi(hh.target_food + d * STEP, 0, int(b.capacity["food"])))
	stepper("Opał", func(): return hh.target_firewood, func(d): hh.target_firewood = clampi(hh.target_firewood + d * STEP, 0, int(b.capacity["log"])))
