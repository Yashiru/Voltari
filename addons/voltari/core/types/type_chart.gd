class_name VltTypeChart
extends RefCounted

## Type matchup lookup.
##
## Immunity and effectiveness are two questions, not one. An immune defender
## takes no damage at all — the move is blocked upstream, and the log records a
## block rather than a zero (spec 06). So `is_immune` is a veto query, asked and
## answered before `exponent` is ever relevant.
##
## Receives its table already parsed and typed; parsing lives in a loader
## outside the core (spec 03).

enum Outcome {
	NEUTRAL,
	SUPER_EFFECTIVE,
	RESISTED,
	IMMUNE,
}

const KEY_SEPARATOR: String = ">"

## Non-neutral pairs only, keyed "attacking>defending". Absent means neutral,
## exactly as in the authored source.
var _outcomes: Dictionary[String, int] = {}
var _types: PackedStringArray = PackedStringArray()


func _init(types: PackedStringArray, outcomes: Dictionary[String, int]) -> void:
	_types = types
	_outcomes = outcomes


static func key_for(attacking: String, defending: String) -> String:
	return attacking + KEY_SEPARATOR + defending


func known_types() -> PackedStringArray:
	return _types


func outcome_for(attacking: String, defending: String) -> Outcome:
	var key: String = key_for(attacking, defending)
	if not _outcomes.has(key):
		return Outcome.NEUTRAL
	return _outcomes[key] as Outcome


## A veto: one immune defending type is enough, whatever the other contributes.
func is_immune(attacking: String, defending: PackedStringArray) -> bool:
	for type: String in defending:
		if outcome_for(attacking, type) == Outcome.IMMUNE:
			return true
	return false


## Doublings when positive, halvings when negative. Only meaningful once the
## immunity veto has not fired, which the caller is required to have checked.
func exponent(attacking: String, defending: PackedStringArray) -> int:
	assert(not is_immune(attacking, defending), "exponent() on an immune matchup; check is_immune() first")

	var total: int = 0
	for type: String in defending:
		match outcome_for(attacking, type):
			Outcome.SUPER_EFFECTIVE:
				total += 1
			Outcome.RESISTED:
				total -= 1

	return total
