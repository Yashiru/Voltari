class_name VltSeededDecider
extends VltDecider

## Production and fuzzing. Identical seed and identical call sequence give
## identical answers.
##
## The generator itself lives in `VltRandomSource`, held rather than inherited:
## four vocabularies need randomness and only one of them can be this class's
## base. Everything here is the battle vocabulary expressed in terms of two
## primitives, `below` and `happens`.

const DAMAGE_ROLL_COUNT: int = 16

var _source: VltRandomSource


func _init(seed_value: int) -> void:
	_source = VltRandomSource.new(seed_value)


## Exposed so a battle can be saved and resumed without losing its sequence.
func state() -> int:
	return _source.state()


func restore(value: int) -> void:
	_source.restore(value)


func damage_roll() -> int:
	return _source.below(DAMAGE_ROLL_COUNT)


func accuracy_check(chance: int) -> bool:
	return _source.happens(chance, 100)


func critical_hit(numerator: int, denominator: int) -> bool:
	return _source.happens(numerator, denominator)


func secondary_triggers(chance: int) -> bool:
	return _source.happens(chance, 100)


## One draw in [0, 65536), passing below the threshold. A threshold of 65536 is
## therefore certain without the caller special-casing it (spec 11, section 2).
func capture_shake(threshold: int) -> bool:
	return _source.below(CAPTURE_DRAW_RANGE) < threshold


func speed_tie(first: VltSlotRef, second: VltSlotRef) -> VltSlotRef:
	return first if _source.below(2) == 0 else second


func multi_hit_count(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "multi hit range is inverted")
	return minimum + _source.below(maximum - minimum + 1)


func status_duration(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "status duration range is inverted")
	return minimum + _source.below(maximum - minimum + 1)
