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

	## The major status effect's id, or empty. An identifier rather than an enum:
	## the effect already has a name, and a second vocabulary for the same set
	## would be one more thing to keep in step (spec 07, section 6).
	var status_id: String = ""

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
## The registry is required rather than optional: a status is derived from the
## effects present, and a view built without one would report every creature
## healthy — quietly, and only in whatever forgot to pass it.
static func of(
	state: VltBattleState,
	registry: VltEffectRegistry,
	side: int,
	revealed: PackedStringArray = PackedStringArray()
) -> VltBattleView:
	assert(side >= 0 and side < VltBattleState.SIDE_COUNT, "no side %d to look from" % side)

	var view: VltBattleView = VltBattleView.new()
	view.viewpoint = side
	view.turn = state.turn

	for slot: int in range(state.slots_per_side()):
		view.mine.append(
			_combatant(state, registry, VltSlotRef.at(side, slot), true, revealed)
		)
		view.theirs.append(
			_combatant(state, registry, VltSlotRef.at(1 - side, slot), false, revealed)
		)

	return view


static func _combatant(
	state: VltBattleState,
	registry: VltEffectRegistry,
	at: VltSlotRef,
	own: bool,
	revealed: PackedStringArray
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
	combatant.status_id = VltEffectDispatch.major_status(state, registry, at)
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


# --- advancing by the log ----------------------------------------------------
#
# The other way to reach a view, and the one the UI uses (decision 0049).
#
# Not an alternative construction: a *continuation* of one. Invariant 8 says
# replaying a log onto the initial state reproduces the final state, and this is
# the same sentence about a view — start from `of()` at the opening position,
# then advance. A view conjured from a log alone could not exist, because a log
# never announces what was already on the field when it started.
#
# `species` supplies types, which no event carries: a switch announces an
# identifier and types are a property of the species, not of the moment.


## Advances this view by one event, as this viewpoint perceives it.
##
## Events that change nothing observable are ignored on purpose rather than by
## omission — effectiveness, a failed move, a shake, a request for input.
## `own_party` is the viewpoint's own party. The log does not announce your own
## creature's moves or exact stats when it enters — and correctly so: they were
## never a battle event, they are simply yours. The reader supplies them.
func advance(
	event: VltLogEvent,
	registry: VltEffectRegistry,
	species: Dictionary[String, VltSpecies] = {},
	own_party: Array[VltBattleCreature] = []
) -> void:
	if event is VltLogTurnStart:
		turn = (event as VltLogTurnStart).number
	elif event is VltLogSwitchIn:
		_arrive(event as VltLogSwitchIn, species, own_party)
	elif event is VltLogSwitchOut:
		_leave((event as VltLogSwitchOut).target)
	elif event is VltLogDamage:
		var hurt: VltLogDamage = event as VltLogDamage
		_set_health(hurt.target, hurt.current_hp, hurt.max_hp)
	elif event is VltLogHeal:
		var healed: VltLogHeal = event as VltLogHeal
		_set_health(healed.target, healed.current_hp, healed.max_hp)
	elif event is VltLogFaint:
		var down: Combatant = _at((event as VltLogFaint).target)
		if down != null:
			down.fainted = true
			down.health = 0
			if down.knows_exact_health():
				down.current_hp = 0
	elif event is VltLogStatChange:
		var changed: VltLogStatChange = event as VltLogStatChange
		var moved: Combatant = _at(changed.target)
		if moved != null and changed.stat < moved.stat_stages.size():
			moved.stat_stages[changed.stat] = changed.stage_after
	elif event is VltLogEffectChanged:
		_restate_status(event as VltLogEffectChanged, registry)
	elif event is VltLogMoveUsed:
		_reveal(event as VltLogMoveUsed)
	elif event is VltLogCaptureResult:
		var caught: VltLogCaptureResult = event as VltLogCaptureResult
		if caught.captured:
			_leave(caught.target)


## The combatant at a position, whichever side it is on, or null.
func _at(reference: VltSlotRef) -> Combatant:
	if reference == null:
		return null
	var row: Array[Combatant] = mine if reference.side == viewpoint else theirs
	if reference.slot >= row.size():
		return null
	return row[reference.slot]


func _arrive(
	event: VltLogSwitchIn,
	species: Dictionary[String, VltSpecies],
	own_party: Array[VltBattleCreature]
) -> void:
	var seat: Combatant = _at(event.target)
	if seat == null:
		return

	# A fresh combatant rather than an edited one: stages, status and revealed
	# moves belong to whoever just left, and carrying one of them over would be
	# invisible until the moment it mattered.
	var arriving: Combatant = Combatant.new()
	arriving.reference = event.target
	arriving.present = true
	arriving.species_id = event.species_id
	arriving.level = event.level
	arriving.stat_stages = _no_stages()
	if species.has(event.species_id):
		arriving.types = species[event.species_id].types.duplicate()

	var own: bool = event.target.side == viewpoint
	if own and event.party_index < own_party.size():
		var entering: VltBattleCreature = own_party[event.party_index]
		arriving.types = entering.types.duplicate()
		arriving.stats = entering.stats.duplicate()
		for slot: VltMoveSlot in entering.moves:
			arriving.moves.append(slot.clone())

	var row: Array[Combatant] = mine if own else theirs
	row[event.target.slot] = arriving
	_set_health(event.target, event.current_hp, event.max_hp)


func _leave(reference: VltSlotRef) -> void:
	var seat: Combatant = _at(reference)
	if seat == null:
		return
	var empty: Combatant = Combatant.new()
	empty.reference = reference
	var row: Array[Combatant] = mine if reference.side == viewpoint else theirs
	row[reference.slot] = empty


## A reduced event already carries hundredths, so the same arithmetic serves
## both forms: rescaling a proportion out of a hundred returns it unchanged.
func _set_health(reference: VltSlotRef, current: int, maximum: int) -> void:
	var seat: Combatant = _at(reference)
	if seat == null:
		return

	seat.health = VltLogEvent.scaled_health(current, maximum)
	if reference.side == viewpoint:
		seat.current_hp = current
		seat.max_hp = maximum
	if current > 0:
		seat.fainted = false


func _restate_status(event: VltLogEffectChanged, registry: VltEffectRegistry) -> void:
	if event.owner == null or not registry.has(event.definition_id):
		return
	if not registry.definition(event.definition_id).is_major_status:
		return

	var seat: Combatant = _at(event.owner)
	if seat == null:
		return
	seat.status_id = "" if event.removed else event.definition_id


func _reveal(event: VltLogMoveUsed) -> void:
	var seat: Combatant = _at(event.actor)
	if seat == null:
		return

	if event.actor.side != viewpoint:
		if not seat.revealed_moves.has(event.move_id):
			seat.revealed_moves.append(event.move_id)
		return

	# Your own side reports PP exactly, and the event already carries what is
	# left rather than what was spent. The sentinel is what a reduced event
	# carries; assigning it would read as a move with minus one PP.
	if event.pp_after == VltLogMoveUsed.UNKNOWN_PP:
		return
	if event.move_index < seat.moves.size():
		seat.moves[event.move_index].pp = event.pp_after


static func _no_stages() -> PackedInt32Array:
	var stages: PackedInt32Array = PackedInt32Array()
	stages.resize(VltStats.STAT_COUNT)
	return stages
