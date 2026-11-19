# Cło: przy wwozie towaru z innego państwa przewoźnik płaci część jego wartości
# (wg ceny w mieście docelowym) do skarbu państwa docelowego.
extends EconPolicy


func import_rate() -> float:
	return float(params["rate"])
