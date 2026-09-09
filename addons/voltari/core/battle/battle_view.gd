class_name VltBattleView
extends RefCounted

## What one side can perceive of a battle (spec 12, section 2).
##
## A distinct type, not a battle state with fields blanked. A blanked state is
## the same type as a real one, so nothing would stop it reaching the engine or
## an AI holding the wrong one without noticing. The type is what makes "the AI
## cannot cheat" something the compiler enforces rather than something the
## reviewer checks (decision 0034).
##
## Always **derived**, never authored: one function from a state and a viewpoint.
## A view widens by convenience, one field at a time, and each widening looks
## reasonable on its own — so the test that says what it hides is the one that
## matters here.
##
## Asymmetric on purpose. A player knows their own creature exactly and reads the
## opponent's health off a bar.

## One position, as the viewer perceives it.
class Combatant:
	extends RefCounted

	## What is not known is absent, not zeroed: a caller that forgets to check
	## gets a sentinel it cannot mistake for a real value.
	const UNKNOWN: int = -1

	var reference: VltSlotRef = null
	var present: bool = false

	## Public whichever side it is on. A species is announced when it enters.
	var species_id: String = ""
	var types: PackedStringArray = PackedStringArray()
	var level: int = 1
	var status: VltBattleCreature.Status = VltBattleCreature.Status.NONE
	var fainted: bool = false

	## Out of a hundred, for either side. It is what a health bar shows.
	var health: int = 0

	## Stat stages are announced as they happen, so both sides know them.
	var stat_stages: PackedInt32Array = PackedInt32Array()

	## Exact figures, and the full move set with its PP. The viewer's own side
	## only; UNKNOWN and empty for the opponent.
	var current_hp: int = UNKNOWN
	var max_hp: int = UNKNOWN
	var stats: PackedInt32Array = PackedInt32Array()
	var moves: Array[VltMoveSlot] = []

	## Moves of the opponent's that have been seen. Empty for your own side,
	## where `moves` carries them in full.
	var revealed_moves: PackedStringArray = PackedStringArray()

	func knows_exact_health() -> bool:
		return current_hp != UNKNOWN


var viewpoint: int = 0
var turn: int = 0

## Indexed by slot, in position order.
var mine: Array[Combatant] = []
var theirs: Array[Combatant] = []


## The battle as `side` perceives it.
##
## `revealed` names the opposing moves the viewer has seen. It is passed in
## rather than derived here because nothing in the state records what has been
## witnessed — the battle log does, and accumulating it across a battle belongs
## to whoever owns the battle, not to a view of one moment.
static func of(
	state: VltBattleState, side: int, revealed: PackedStringArray = PackedStringArray()
) -> VltBattleView:
	assert(side >= 0 and side < VltBattleState.SIDE_COUNT, "no side %d to look from" % side)

	var view: VltBattleView = VltBattleView.new()
	view.viewpoint = side
	view.turn = state.turn

	for slot: int in range(state.slots_per_side()):
		view.mine.append(_combatant(state, VltSlotRef.at(side, slot), true, revealed))
		view.theirs.append(
			_combatant(state, VltSlotRef.at(1 - side, slot), false, revealed)
		)

	return view


static func _combatant(
	state: VltBattleState, at: VltSlotRef, own: bool, revealed: PackedStringArray
) -> Combatant:
	var combatant: Combatant = Combatant.new()
	combatant.reference = VltSlotRef.at(at.side, at.slot)

	var creature: VltBattleCreature = state.creature_at(at)
	if creature == null:
		return combatant

	combatant.present = true
	combatant.species_id = creature.species_id
	combatant.types = creature.types.duplicate()
	combatant.level = creature.level
	combatant.status = creature.status
	combatant.fainted = creature.is_fainted()
	combatant.health = VltLogEvent.scaled_health(creature.current_hp, creature.max_hp())
	combatant.stat_stages = state.slot_at(at).stat_stages.duplicate()

	if not own:
		for slot: VltMoveSlot in creature.moves:
			if revealed.has(slot.move_id):
				combatant.revealed_moves.append(slot.move_id)
		return combatant

	combatant.current_hp = creature.current_hp
	combatant.max_hp = creature.max_hp()
	combatant.stats = creature.stats.duplicate()
	for slot: VltMoveSlot in creature.moves:
		combatant.moves.append(slot.clone())

	return combatant
