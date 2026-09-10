class_name VltPostBattle
extends RefCounted

## What happens to a party once the battle is over (spec 10, section 5).
##
## L1: same purity as the core. It reads a finished battle and reports what
## changed; the core never learns that experience exists (decision 0028).
##
## Nothing here happens during a turn. A creature that would have levelled
## mid-battle benefits once the battle ends, which is the divergence that keeps
## the L0/L1 frontier a frontier.

## The one evolution trigger there is code for. Content can already express
## others (spec 09); each needs the code its trigger id names.
const LEVEL_TRIGGER: String = "level"

## What one creature gained.
class Award:
	extends RefCounted

	var party_index: int = 0
	var experience: int = 0
	var level_before: int = 1
	var level_after: int = 1

	## Moves taken without asking, because there was room for them.
	var learned: PackedStringArray = PackedStringArray()

	## Moves the creature has no room for. The choice is the player's, not this
	## layer's (spec 10, section 7), so they come back unanswered.
	var offered: PackedStringArray = PackedStringArray()

	## The species it was, and the one it became. Both, because "it evolved into
	## Y" is a sentence about two species and the creature only remembers one of
	## them afterwards.
	var evolved_from: String = ""
	var evolved_into: String = ""

	func _init(index: int, earned: int, before: int, after: int) -> void:
		party_index = index
		experience = earned
		level_before = before
		level_after = after

	func levelled() -> bool:
		return level_after > level_before

	## Every level the creature passed through, so a move learnable at 15 is
	## offered even when the battle ended at 18 (spec 10, section 5).
	func levels_gained() -> PackedInt32Array:
		var passed: PackedInt32Array = PackedInt32Array()
		for level: int in range(level_before + 1, level_after + 1):
			passed.append(level)
		return passed


## The whole pipeline, in the order spec 10 section 5 sets: experience, levels,
## stats, moves, evolution.
##
## `state` is mutated: it is the party after the battle, and this is what
## happens to it next. The awards are returned so a caller can show them.
static func resolve(
	initial: VltBattleState,
	log: VltBattleLog,
	state: VltBattleState,
	earning_side: int,
	species: Dictionary[String, VltSpecies],
	curves: Dictionary[String, PackedInt32Array],
	moves: Dictionary[String, VltMoveDefinition],
	from_trainer: bool
) -> Array[Award]:
	var earned: Dictionary[int, int] = _experience_earned(
		initial, log, earning_side, species, from_trainer
	)

	var awards: Array[Award] = []
	var party: Array[VltBattleCreature] = state.sides[earning_side].party

	for index: int in _sorted_keys(earned):
		var creature: VltBattleCreature = party[index]
		var before: int = creature.level

		creature.experience += earned[index]
		var curve: PackedInt32Array = curves[species[creature.species_id].growth_rate]
		creature.level = level_for(curve, creature.experience)

		if creature.level != before:
			_rederive(creature)

		var award: Award = Award.new(index, earned[index], before, creature.level)
		_offer_moves(creature, species[creature.species_id], award, moves)

		# Last, because it changes the species and everything above reads it —
		# including the learnset the offers just came from (spec 10, section 5).
		_evolve(creature, species, award)

		awards.append(award)

	return awards


## What the creature would have learned on the way up.
##
## Every level passed, not just the one it landed on: a move learnable at 15 is
## offered even when the battle ended at 18.
static func _offer_moves(
	creature: VltBattleCreature,
	species: VltSpecies,
	award: Award,
	moves: Dictionary[String, VltMoveDefinition]
) -> void:
	for level: int in award.levels_gained():
		for entry: VltSpecies.Learned in species.learnset:
			if entry.level != level or _knows(creature, entry.move_id):
				continue

			if creature.moves.size() < VltBirth.MOVE_LIMIT:
				creature.moves.append(
					VltMoveSlot.create(entry.move_id, moves[entry.move_id].max_pp)
				)
				award.learned.append(entry.move_id)
			else:
				award.offered.append(entry.move_id)


## Teaches an offered move in place of one the creature already knows.
##
## The answer to the question `offered` asks, and it lives beside it so that
## neither can be found without the other. A creature with room learns without
## being asked; this is only for the case where there is none.
##
## Declining is not a call. There is no "learn nothing" path, because a path
## that does nothing is a path somebody will one day make do something.
static func learn(
	creature: VltBattleCreature,
	move_id: String,
	replacing: int,
	moves: Dictionary[String, VltMoveDefinition]
) -> void:
	assert(moves.has(move_id), "no such move \"%s\"" % move_id)
	assert(
		replacing >= 0 and replacing < creature.moves.size(),
		"slot %d is not one of this creature's moves" % replacing
	)
	assert(not _knows(creature, move_id), "\"%s\" is already known" % move_id)

	creature.moves[replacing] = VltMoveSlot.create(move_id, moves[move_id].max_pp)


## Applies an evolution whose trigger is satisfied.
##
## The creature is the same individual wearing a different species: experience,
## individual values, effort and the moveset all survive (spec 10, section 8).
static func _evolve(
	creature: VltBattleCreature, species: Dictionary[String, VltSpecies], award: Award
) -> void:
	var current: VltSpecies = species[creature.species_id]

	for evolution: VltSpecies.Evolution in current.evolutions:
		if not _triggered(evolution, creature):
			continue

		var into: VltSpecies = species[evolution.into]
		award.evolved_from = creature.species_id
		creature.species_id = into.id
		creature.types = into.types.duplicate()
		creature.base = into.base_stats.duplicate()
		_rederive(creature)
		award.evolved_into = into.id
		return


static func _triggered(evolution: VltSpecies.Evolution, creature: VltBattleCreature) -> bool:
	# The trigger names code, never a condition written in the content
	# (spec 06, section 8). One trigger exists; the rest arrive with their own.
	match evolution.trigger:
		LEVEL_TRIGGER:
			return creature.level >= evolution.level
	return false


static func _knows(creature: VltBattleCreature, move_id: String) -> bool:
	for slot: VltMoveSlot in creature.moves:
		if slot.move_id == move_id:
			return true
	return false


## Answers an offer: the move goes into `slot`, and what was there is forgotten.
##
## Declining is simply never calling this. A rules layer that chose for the
## player would be making a decision it has no standing to make, and one that
## cannot be replayed.
static func learn_over(
	creature: VltBattleCreature,
	slot: int,
	move_id: String,
	moves: Dictionary[String, VltMoveDefinition]
) -> void:
	assert(slot >= 0 and slot < creature.moves.size(), "no move slot %d to replace" % slot)
	assert(moves.has(move_id), "unknown move \"%s\"" % move_id)
	assert(not _knows(creature, move_id), "\"%s\" is already known" % move_id)

	creature.moves[slot] = VltMoveSlot.create(move_id, moves[move_id].max_pp)


## The highest level `total` experience reaches.
##
## Walked rather than searched: a hundred entries is not a search problem, and a
## loop that anyone can read is worth more here than one nobody checks.
static func level_for(curve: PackedInt32Array, total: int) -> int:
	var level: int = 1
	for index: int in range(1, curve.size()):
		if total < curve[index]:
			break
		level = index + 1
	return level


## Stats after a level changed. Everything they derive from is stored on the
## creature, so this cannot go stale — and the current HP rises by exactly what
## the maximum did, so levelling never heals and never hurts.
static func _rederive(creature: VltBattleCreature) -> void:
	var input: VltStatInput = VltStatInput.new()
	input.level = creature.level
	input.base = creature.base
	input.ivs = creature.ivs
	input.evs = creature.evs
	input.nature_raised = creature.nature_raised
	input.nature_lowered = creature.nature_lowered

	var before: int = creature.max_hp()
	creature.stats = VltStats.derive_spread(input)

	if not creature.is_fainted():
		creature.current_hp += creature.max_hp() - before


# --- reading the battle ------------------------------------------------------


## Experience per party index, from the log (spec 10, section 4).
##
## Participation is read rather than tracked in the state: the log already
## records every switch-in and every faint, and invariant 8 keeps it complete.
static func _experience_earned(
	initial: VltBattleState,
	log: VltBattleLog,
	earning_side: int,
	species: Dictionary[String, VltSpecies],
	from_trainer: bool
) -> Dictionary[int, int]:
	var occupants: Array[PackedInt32Array] = _initial_occupants(initial)
	var faced: Dictionary[int, PackedInt32Array] = {}
	var fainted: Dictionary[int, bool] = {}
	var earned: Dictionary[int, int] = {}

	_record_facing(occupants, faced, earning_side)

	for event: VltLogEvent in log.events:
		match event.kind():
			VltLogSwitchIn.KIND:
				var arrival: VltLogSwitchIn = event as VltLogSwitchIn
				occupants[arrival.target.side][arrival.target.slot] = arrival.party_index
				_record_facing(occupants, faced, earning_side)

			VltLogFaint.KIND:
				var down: VltLogFaint = event as VltLogFaint
				var index: int = occupants[down.target.side][down.target.slot]

				if down.target.side == earning_side:
					fainted[index] = true
					continue

				_award_for(
					down.target.side, index, faced, fainted, earned,
					initial, earning_side, species, from_trainer
				)

	return earned


## Splits one defeat among the creatures that faced it and are still standing.
static func _award_for(
	defeated_side: int,
	defeated_index: int,
	faced: Dictionary[int, PackedInt32Array],
	fainted: Dictionary[int, bool],
	earned: Dictionary[int, int],
	initial: VltBattleState,
	earning_side: int,
	species: Dictionary[String, VltSpecies],
	from_trainer: bool
) -> void:
	if not faced.has(defeated_index):
		return

	var standing: PackedInt32Array = PackedInt32Array()
	for index: int in faced[defeated_index]:
		if not fainted.has(index):
			standing.append(index)

	if standing.is_empty():
		return

	var defeated: VltBattleCreature = initial.sides[defeated_side].party[defeated_index]
	var base_yield: int = species[defeated.species_id].base_experience

	for index: int in standing:
		var earner: VltBattleCreature = initial.sides[earning_side].party[index]
		var award: int = VltExperience.award(
			base_yield, defeated.level, earner.level, standing.size(), from_trainer
		)
		earned[index] = earned.get(index, 0) + award


static func _initial_occupants(state: VltBattleState) -> Array[PackedInt32Array]:
	var occupants: Array[PackedInt32Array] = []

	for side: int in range(VltBattleState.SIDE_COUNT):
		var per_slot: PackedInt32Array = PackedInt32Array()
		for slot: VltSlot in state.sides[side].slots:
			per_slot.append(slot.occupant)
		occupants.append(per_slot)

	return occupants


## Everyone currently on the field has now faced everyone opposite them.
##
## Recorded as the field changes rather than at the moment of the faint: a
## creature that fought an opponent and switched out still earned its share, and
## only the whole battle can say who that was.
static func _record_facing(
	occupants: Array[PackedInt32Array],
	faced: Dictionary[int, PackedInt32Array],
	earning_side: int
) -> void:
	var opposing: int = 1 - earning_side

	for foe: int in occupants[opposing]:
		if foe == VltSlot.EMPTY:
			continue
		if not faced.has(foe):
			faced[foe] = PackedInt32Array()

		for earner: int in occupants[earning_side]:
			if earner == VltSlot.EMPTY:
				continue
			if not faced[foe].has(earner):
				faced[foe].append(earner)


## Awards in party order, so the result never depends on dictionary iteration.
static func _sorted_keys(source: Dictionary[int, int]) -> PackedInt32Array:
	var keys: PackedInt32Array = PackedInt32Array()
	for key: int in source.keys():
		keys.append(key)
	keys.sort()
	return keys
