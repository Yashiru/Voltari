class_name VltDamageModifiers
extends RefCounted

## The ratio contributed to each stage of the damage pipeline.
##
## This is the interface between effects and the formula. The pipeline no longer
## knows what a burn is: a burn is an effect that contributes 1/2 at the BURN
## stage, exactly as a screen contributes 1/2 at MODIFIER_PHASE_1 and rain
## contributes 3/2 at WEATHER.
##
## Stage order comes from VltDamageStage, extracted from the oracle. Contributing
## to a stage cannot move a modifier across stages, which is what keeps the
## per-step rounding faithful (spec 06).

## Numerator and denominator per stage, both defaulting to 1 — no change.
var _numerators: PackedInt32Array = PackedInt32Array()
var _denominators: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var count: int = VltDamageStage.Stage.size()
	_numerators.resize(count)
	_denominators.resize(count)
	for stage: int in range(count):
		_numerators[stage] = 1
		_denominators[stage] = 1


## Ratios compose by multiplication, so two effects on one stage both apply.
## They are combined before the stage runs rather than applied one after the
## other, because each application would round again and change the result.
func contribute(stage: VltDamageStage.Stage, numerator: int, denominator: int) -> void:
	assert(denominator > 0, "a modifier denominator must be positive")
	_numerators[stage] *= numerator
	_denominators[stage] *= denominator


func numerator_for(stage: VltDamageStage.Stage) -> int:
	return _numerators[stage]


func denominator_for(stage: VltDamageStage.Stage) -> int:
	return _denominators[stage]


func is_neutral(stage: VltDamageStage.Stage) -> bool:
	return _numerators[stage] == _denominators[stage]
