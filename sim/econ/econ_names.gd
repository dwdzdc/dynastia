# EconNames — imiona, nazwiska (z formą żeńską) i nazwy firm po polsku.
class_name EconNames
extends RefCounted


const FEMALE_FIRST_ENDING := "a"
const MALE_EXCEPTIONS := ["Jakub", "Barnaba", "Kuba"]


static func is_female_first(first: String) -> bool:
	return first.ends_with(FEMALE_FIRST_ENDING) and not first in MALE_EXCEPTIONS


static func surname_for(last: String, female: bool) -> String:
	if not female:
		return last
	for end in ["ski", "cki", "dzki"]:
		if last.ends_with(end):
			return last.substr(0, last.length() - 1) + "a"
	return last


# Dopełniacz liczby mnogiej rodu: Kowalski → Kowalskich, Nowak → Nowaków.
static func family_genitive(last: String) -> String:
	for end in ["ski", "cki", "dzki"]:
		if last.ends_with(end):
			return last.substr(0, last.length() - 1) + "ich"
	if last.ends_with("a"):
		return last.substr(0, last.length() - 1) + "ów"
	return last + "ów"


static func business_name(recipe_name: String, last: String) -> String:
	return "%s %s" % [recipe_name.substr(0, 1).to_upper() + recipe_name.substr(1), family_genitive(last)]
