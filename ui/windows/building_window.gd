# Wspólna baza okien budynku. for_building() woła się przed init_window().
extends TopicWindow


var b: SimBuilding


func for_building(p_b: SimBuilding) -> TopicWindow:
	b = p_b
	anchor = "card"
	return self
