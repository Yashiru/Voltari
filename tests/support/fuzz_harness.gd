class_name VltFuzzHarness
extends RefCounted

## Generates battles, drives them, and checks the eleven invariants of spec 05.
##
## A case is `(seed, turn count)` and nothing else: the whole battle — teams,
## moves, commands — is derived from the seed, so a failure is reproducible from
## one integer and shrinks to a smaller integer pair.
##
## The fuzzer exists to VIOLATE the invariants. A run that finds nothing is only
## evidence that this generator did not reach the bug, which is why the
## generator deliberately submits malformed commands too.

const MAX_PARTY: int = 3
const MAX_SLOTS: int = 1
const TURN_CAP: int = 60


## The outcome of one case: empty `failure` means the invariants held.
class Report:
	var failure: String = ""

	## Turns that resolved. Rejected turns are attempted but not played, so the
	## two counts differ and reporting only one is misleading.
	var turns_played: int = 0
	var turns_attempted: int = 0

	func failed() -> bool:
		return failure != ""


static func run_case(
	seed_value: int, turns: int, moves: Dictionary[String, VltMoveDefinition],
	chart: VltTypeChart, effects: VltEffectRegistry
) -> Report:
	var generator: VltFuzzDecider = VltFuzzDecider.new(seed_value)
	var state: VltBattleState = _generate_battle(generator, moves, effects)
	var engine: VltTurnEngine = VltTurnEngine.new(moves, chart, effects)
	var decider: VltSeededDecider = VltSeededDecider.new(seed_value ^ 0x5BF03635)

	var report: Report = Report.new()

	for turn: int in range(mini(turns, TURN_CAP)):
		report.turns_attempted = turn + 1
		var problem: String = _check_state(state, "before turn %d" % turn)
		if problem != "":
			report.failure = problem
			return report

		var commands: Array[VltCommand] = _generate_commands(generator, state, moves)
		var snapshot: String = JSON.stringify(state.to_dict())
		var outcome: VltTurnOutcome = engine.resolve(state, commands, decider)

		# Invariant 7: resolve() must not touch the state it was given.
		if JSON.stringify(state.to_dict()) != snapshot:
			report.failure = "turn %d: resolve() mutated its input state" % turn
			return report

		# Invariant 10: a malformed command is refused, never a crash or a
		# corrupted battle.
		if outcome.status == VltTurnOutcome.Status.REJECTED:
			if outcome.rejection == "":
				report.failure = "turn %d: rejected without a reason" % turn
				return report
			continue

		# Invariant 8: the log replays onto the state the turn started from.
		var replayed: VltBattleState = state.clone()
		outcome.log.replay_onto(replayed)
		if JSON.stringify(replayed.to_dict()) != JSON.stringify(outcome.state.to_dict()):
			report.failure = "turn %d: replaying the log did not reproduce the state" % turn
			return report

		# Invariant 4: a request must name at least one answerable slot.
		if outcome.status == VltTurnOutcome.Status.NEEDS_INPUT:
			if outcome.request_slots.is_empty():
				report.failure = "turn %d: NeedsInput named no slot" % turn
				return report
			state = outcome.state
			var answered: VltTurnOutcome = engine.resolve(
				state, _replacements(generator, state, outcome.request_slots), decider
			)
			if answered.status == VltTurnOutcome.Status.REJECTED:
				report.failure = "turn %d: valid replacements rejected: %s" % [
					turn, answered.rejection
				]
				return report
			state = answered.state
		else:
			state = outcome.state

		report.turns_played += 1

		problem = _check_state(state, "after turn %d" % turn)
		if problem != "":
			report.failure = problem
			return report

		if _battle_over(state):
			break

	return report


## Invariants 1, 2, 3, 9 and 11, checked on a settled state.
static func _check_state(state: VltBattleState, when: String) -> String:
	# Invariant 9: serialisation round-trips.
	var restored: VltBattleState = VltBattleState.from_dict(state.to_dict())
	if JSON.stringify(restored.to_dict()) != JSON.stringify(state.to_dict()):
		return "%s: serialisation did not round-trip" % when

	for side: int in range(VltBattleState.SIDE_COUNT):
		for creature: VltBattleCreature in state.sides[side].party:
			if creature.current_hp < 0 or creature.current_hp > creature.max_hp():
				return "%s: hp %d outside [0, %d]" % [when, creature.current_hp, creature.max_hp()]
			if creature.is_fainted() != (creature.current_hp == 0):
				return "%s: fainted and hp disagree" % when
			for slot: VltMoveSlot in creature.moves:
				if slot.pp < 0 or slot.pp > slot.max_pp:
					return "%s: pp %d outside [0, %d]" % [when, slot.pp, slot.max_pp]

	for reference: VltSlotRef in state.all_refs():
		var slot: VltSlot = state.slot_at(reference)
		for stat: int in range(VltStats.STAT_COUNT):
			var stage: int = slot.stat_stages[stat]
			if stage < -VltSlot.STAGE_LIMIT or stage > VltSlot.STAGE_LIMIT:
				return "%s: stat stage %d out of range" % [when, stage]

		# Invariant 11: an empty slot carries no slot-scoped state.
		if slot.is_empty():
			if not slot.effects.is_empty():
				return "%s: empty slot still holds effects" % when
			for stat: int in range(VltStats.STAT_COUNT):
				if slot.stat_stages[stat] != 0:
					return "%s: empty slot still holds stat stages" % when

	return ""


static func _battle_over(state: VltBattleState) -> bool:
	for side: int in range(VltBattleState.SIDE_COUNT):
		var standing: bool = false
		for creature: VltBattleCreature in state.sides[side].party:
			if not creature.is_fainted():
				standing = true
		if not standing:
			return true
	return false


# --- generation -------------------------------------------------------------


static func _generate_battle(
	generator: VltFuzzDecider,
	moves: Dictionary[String, VltMoveDefinition],
	effects: VltEffectRegistry
) -> VltBattleState:
	var move_ids: Array[String] = []
	for id: String in moves.keys():
		move_ids.append(id)
	move_ids.sort()

	var state: VltBattleState = VltBattleState.create(MAX_SLOTS)
	for side: int in range(VltBattleState.SIDE_COUNT):
		var party_size: int = generator.next_in_range(1, MAX_PARTY)
		for _index: int in range(party_size):
			state.sides[side].party.append(_generate_creature(generator, move_ids))
		state.sides[side].slots[0].occupy(0)

	_seed_effects(generator, state, effects)
	return state


## Puts registered effects on the field before the first turn.
##
## Without this the fuzzer registered effects and applied none, so no generated
## battle ever held one: the effect system sat outside the reach of every
## invariant while looking covered. Timed effects also count down and expire over
## a run, which is how invariant 8 reaches them at all.
static func _seed_effects(
	generator: VltFuzzDecider, state: VltBattleState, effects: VltEffectRegistry
) -> void:
	var ids: Array[String] = effects.ids()
	if ids.is_empty():
		return

	for reference: VltSlotRef in state.all_refs():
		if not generator.chance(50):
			continue
		@warning_ignore("return_value_discarded")
		VltEffectDispatch.apply(state, effects, generator.pick_string(ids), reference, null)


static func _generate_creature(
	generator: VltFuzzDecider, move_ids: Array[String]
) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	for stat: int in range(VltStats.STAT_COUNT):
		input.base[stat] = generator.next_in_range(5, 180)
		input.ivs[stat] = generator.next_in_range(0, 31)
		input.evs[stat] = generator.next_in_range(0, 252)
	input.level = generator.next_in_range(1, 100)

	var types: PackedStringArray = PackedStringArray(["normal"])
	var creature: VltBattleCreature = VltBattleCreature.create(input, "fuzz", types)

	var move_count: int = generator.next_in_range(1, mini(4, move_ids.size()))
	for _slot: int in range(move_count):
		var id: String = generator.pick_string(move_ids)
		creature.moves.append(VltMoveSlot.create(id, generator.next_in_range(1, 10)))

	return creature


## Deliberately generates illegal commands part of the time: invariant 10 is
## about what happens then, so a generator that only produced legal input would
## never exercise it.
static func _generate_commands(
	generator: VltFuzzDecider, state: VltBattleState, _moves: Dictionary[String, VltMoveDefinition]
) -> Array[VltCommand]:
	var commands: Array[VltCommand] = []

	for reference: VltSlotRef in state.all_refs():
		var creature: VltBattleCreature = state.creature_at(reference)
		if creature == null:
			continue

		if generator.chance(15):
			commands.append(
				VltCommand.switch_to(reference, generator.next_in_range(-1, MAX_PARTY))
			)
			continue

		var target: VltSlotRef = VltSlotRef.at(
			generator.next_in_range(0, VltBattleState.SIDE_COUNT - 1), 0
		)
		var index: int = generator.next_in_range(-1, creature.moves.size())
		commands.append(VltCommand.use_move(reference, index, target))

	return commands


static func _replacements(
	generator: VltFuzzDecider, state: VltBattleState, slots: Array[VltSlotRef]
) -> Array[VltCommand]:
	var commands: Array[VltCommand] = []
	for reference: VltSlotRef in slots:
		var side: VltSide = state.sides[reference.side]
		var available: Array[int] = []
		for index: int in range(side.party.size()):
			if side.party[index].is_fainted():
				continue
			var on_field: bool = false
			for slot: VltSlot in side.slots:
				if slot.occupant == index:
					on_field = true
			if not on_field:
				available.append(index)
		if available.is_empty():
			continue
		commands.append(VltCommand.switch_to(reference, generator.pick_int(available)))
	return commands


# --- shrinking --------------------------------------------------------------


## Reduces a failing case by delta-debugging on the turn count, then reports the
## smallest one that still fails.
##
## Cheap here for a structural reason: the engine is deterministic and replayable
## by construction, so replaying a truncated case is trivial. That is a dividend
## of the pure-core architecture, not a property of the shrinker.
static func shrink(
	seed_value: int, turns: int, moves: Dictionary[String, VltMoveDefinition],
	chart: VltTypeChart, effects: VltEffectRegistry
) -> int:
	return _shrink(
		turns,
		func(candidate: int) -> bool:
			return run_case(seed_value, candidate, moves, chart, effects).failed()
	)


## Demonstrates the shrinker against a predicate whose answer is known, so its
## usefulness is shown rather than assumed. A shrinker that always returned its
## input would otherwise look like it worked.
static func shrink_probe(turns: int) -> int:
	const FAILS_FROM: int = 3
	return _shrink(turns, func(candidate: int) -> bool: return candidate >= FAILS_FROM)


## Halve while it still fails, then walk up from one to land on the exact
## boundary rather than a power of two.
static func _shrink(turns: int, still_fails: Callable) -> int:
	var smallest: int = turns
	var candidate: int = turns / 2

	while candidate >= 1 and still_fails.call(candidate):
		smallest = candidate
		candidate /= 2

	for shorter: int in range(1, smallest):
		if still_fails.call(shorter):
			return shorter

	return smallest
