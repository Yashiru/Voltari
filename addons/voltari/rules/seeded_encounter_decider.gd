class_name VltSeededEncounterDecider
extends VltEncounterDecider

## Production. Identical seed and identical call sequence give identical
## encounters.
##
## It holds a `VltRandomSource` rather than being one — four vocabularies need
## randomness and only one of them could inherit the generator.
##
## **One instance lives as long as the session**, not one per step. A decider
## built fresh each step would be seeded from something that changes slowly, and
## consecutive seeds give correlated first draws — the exact failure the seed
## scattering in `VltRandomSource` exists to fix, reintroduced from the outside.

var _source: VltRandomSource


func _init(seed_value: int) -> void:
	_source = VltRandomSource.new(seed_value)


func encounter_occurs(rate: int) -> bool:
	return _source.happens(rate, RATE_DENOMINATOR)


func encounter_slot(total_weight: int) -> int:
	return _source.below(total_weight)


func encounter_level(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "encounter level range is inverted")
	return minimum + _source.below(maximum - minimum + 1)
