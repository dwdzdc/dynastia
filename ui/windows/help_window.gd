# Pomoc: cel gry i sterowanie.
extends TopicWindow


func build() -> void:
	section("Jak grać")
	text("Prowadzisz ród Wilków przez pokolenia. Karm rodzinę, zimą pal w piecu, płać czynsz, jeśli wynajmujecie.", UiKit.SMALL + 1)
	text("Pieniądze z drewna: drwal ścina → tracz tnie deski → tragarz sprzedaje na targu. Stolarz robi z desek krzesła. Pewny grosz: dniówka w dworze. Zbieracz przyniesie jedzenie z lasu.", UiKit.SMALL + 1)
	text("Ród trwa, dopóki żyje ktoś z krwi Wilków (♛ = głowa rodu).", UiKit.SMALL + 1)
	section("Ekran")
	text("Pasek po lewej: budowa, ród, kronika, ludzie, statystyki, pomoc. Chorągiewki u góry to meldunki: najedź, by przeczytać, kliknij, by zobaczyć miejsce. Kliknięta osoba albo budynek pokazuje się w karcie w prawym dolnym rogu; jej przyciski otwierają okna spraw. Naraz otwarte jest jedno okno.", UiKit.SMALL + 1)
	section("Sterowanie")
	text("LPM — zaznacz osobę / budynek\nPPM na budynek, pole, las — przydział i akcje miejsca; PPM gdzie indziej — idź / zetnij drzewo (Shift — do kolejki)\nPrzeciągnij LPM / ŚPM, WASD — kamera · kółko — zoom · Q / E — obrót\nSpacja — pauza · 1–4 — tempo · Tab — następna osoba z rodu\nB budowa · G ród · K kronika · L ludzie · F kamera za osobą · R głowa rodu · F1 pomoc · Esc — zamknij okno / odznacz", UiKit.SMALL + 1)
