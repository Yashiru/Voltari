class_name VltReflect
extends RefCounted

## A screen halving physical damage taken by one side.
##
## Side-scoped, so it survives switching — which is the whole reason side scope
## exists (spec 03). It is written here to prove the scope works, not because
## the roster needs it yet.
##
## The duration is backed by the oracle: battle/0006-screen runs six turns, so
## the differential sees the damage jump back up when the screen lapses.

const ID: String = "reflect"
const DURATION: int = 5


class HalvePhysical:
	extends VltModifier

	func _init() -> void:
		super(VltDamageStage.Stage.MODIFIER_PHASE_1)

	func contribute(context: VltEffectContext, modifiers: VltDamageModifiers) -> void:
		# Guards the side it belongs to, whoever is standing in its slots.
		if context.target == null or context.move == null or context.owner == null:
			return
		if context.target.side != context.owner.side:
			return
		if context.move.category != VltMoveDefinition.Category.PHYSICAL:
			return
		modifiers.contribute(VltDamageStage.Stage.MODIFIER_PHASE_1, 1, 2)


class CountDown:
	extends VltTrigger

	func _init() -> void:
		super(VltTurnAnchor.Anchor.RESIDUAL)

	func run(context: VltEffectContext) -> void:
		if context.instance.remaining > 0:
			context.instance.remaining -= 1


static func define() -> VltEffectDefinition:
	return (
		VltEffectDefinition
		. create(
			ID,
			VltEffectDefinition.Scope.SIDE,
			VltEffectDefinition.ResetRule.PERSISTS,
			VltEffectDefinition.Stacking.REFRESH,
			DURATION
		)
		. with_modifier(HalvePhysical.new())
		. with_trigger(CountDown.new())
	)
