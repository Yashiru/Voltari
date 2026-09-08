class_name VltBurn
extends RefCounted

## Burn: halves physical damage dealt, and costs HP at the end of every turn.
##
## The first effect written on the system, and it exercises two of the three
## component types at once — a modifier and a trigger on the same definition.
##
## The pipeline never learns what a burn is. It receives 1/2 at the BURN stage
## and applies it where the oracle applies it (spec 06).
##
## Both numbers are backed by the oracle: the battle differential replays a
## burned attacker and compares event by event (battle/0005-burn). The residual
## is max HP divided by eight, floored, and it lands after every action rather
## than after the burned creature's own.

const ID: String = "burn"
const RESIDUAL_DIVISOR: int = 8


class HalvePhysical:
	extends VltModifier

	func _init() -> void:
		super(VltDamageStage.Stage.BURN)

	func contribute(context: VltEffectContext, modifiers: VltDamageModifiers) -> void:
		# Only when the burned creature is the one attacking, and only physically.
		if context.actor == null or context.move == null:
			return
		if not context.actor.equals(context.owner):
			return
		if context.move.category != VltMoveDefinition.Category.PHYSICAL:
			return
		modifiers.contribute(VltDamageStage.Stage.BURN, 1, 2)


class ResidualDamage:
	extends VltTrigger

	func _init() -> void:
		super(VltTurnAnchor.Anchor.RESIDUAL)

	func run(context: VltEffectContext) -> void:
		var creature: VltBattleCreature = context.owner_creature()
		if creature == null or creature.is_fainted():
			return

		var amount: int = maxi(1, creature.max_hp() / VltBurn.RESIDUAL_DIVISOR)
		var dealt: int = mini(amount, creature.current_hp)
		creature.current_hp -= dealt

		# Every mutation emits, or invariant 8 fails and the replay diverges.
		context.log.append(
			VltLogDamage.create(context.owner, dealt, creature.current_hp, creature.max_hp())
		)
		if creature.is_fainted():
			context.log.append(VltLogFaint.create(context.owner))


static func define() -> VltEffectDefinition:
	return (
		VltEffectDefinition
		. create(ID, VltEffectDefinition.Scope.CREATURE)
		. with_modifier(HalvePhysical.new())
		. with_trigger(ResidualDamage.new())
	)
