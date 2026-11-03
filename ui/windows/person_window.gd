# Wspólna baza okien osoby: trzyma, o kogo chodzi. Hud zamyka okno, gdy zaznaczenie
# przejdzie na kogoś innego. for_agent() woła się przed init_window().
extends TopicWindow


var agent: SimAgent
var person: SimPerson


func for_agent(a: SimAgent, p: SimPerson) -> TopicWindow:
	agent = a
	person = p
	anchor = "card"
	return self
