# Podatek od dywidend: część każdej wypłaty z firmy do właściciela idzie do państwa.
extends EconPolicy


func tax_dividend(_w: EconWorld, _st: EconState, amount: float) -> float:
	return amount * float(params["rate"])
