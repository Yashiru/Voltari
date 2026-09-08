class_name VltModifier
extends VltEffectComponent

## Contributes a ratio to one stage of a formula.
##
## It contributes rather than returning a value, so several modifiers on one
## stage compose *before* the stage runs. Applying them one after another would
## round at each application and change the result — and per-step rounding is
## the specification, not an implementation detail (spec 08).
##
## Modifiers attach to formula stages, not to turn phases: a turn phase has no
## value to modify. Vetoes and triggers are the ones that attach to anchors.

var stage: VltDamageStage.Stage = VltDamageStage.Stage.MODIFIER_PHASE_1


func _init(at: VltDamageStage.Stage, order: int = 0) -> void:
	super(order)
	stage = at


## Adds this modifier's ratio for `stage`. Contributing nothing is legitimate:
## a modifier that only applies under some condition simply returns early.
func contribute(_context: VltEffectContext, _modifiers: VltDamageModifiers) -> void:
	assert(false, "VltModifier is abstract")
