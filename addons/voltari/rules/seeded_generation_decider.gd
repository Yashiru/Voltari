class_name VltSeededGenerationDecider
extends VltGenerationDecider

## Production. Identical seed and identical call sequence give identical
## creatures.
##
## This arrives with spec 14, and not before: nothing generated a random
## creature until encounters did. Writing it earlier would have meant a second
## xorshift with no caller to justify it — which is now moot, because the
## generator is held rather than copied (`VltRandomSource`).

var _source: VltRandomSource


func _init(seed_value: int) -> void:
	_source = VltRandomSource.new(seed_value)


func individual_value(_stat: int) -> int:
	return _source.below(VltGenerationDecider.MAX_INDIVIDUAL_VALUE + 1)


func nature_choice(count: int) -> int:
	assert(count > 0, "the nature table is empty")
	return _source.below(count)
