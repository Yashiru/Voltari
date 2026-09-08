extends GdUnitTestSuite

## The turn machine, end to end: validation, ordering, execution, suspension.

const TACKLE: String = "tackle"
const QUICK: String = "quick"
const SPOOK: String = "spook"

var _engine: VltTurnEngine
var _chart: VltTypeChart


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(_payload())
	var moves: Dictionary[String, VltMoveDefinition] = {
		TACKLE: VltMoveDefinition.create(
			TACKLE, "normal", VltMoveDefinition.Category.PHYSICAL, 40, VltMoveDefinition.ALWAYS_HITS
		),
		QUICK: VltMoveDefinition.create(
			QUICK, "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS, 1
		),
		SPOOK: VltMoveDefinition.create(
			SPOOK, "ghost", VltMoveDefinition.Category.SPECIAL, 80, VltMoveDefinition.ALWAYS_HITS
		),
	}
	_engine = VltTurnEngine.new(moves, _chart)


@warning_ignore_start("unsafe_cast")
func _payload() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://content/generated/type-chart.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary
@warning_ignore_restore("unsafe_cast")


func _creature(species: String, types: PackedStringArray, speed_base: int, move_ids: Array[String]) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 100, 100, 100, 100, speed_base])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var creature: VltBattleCreature = VltBattleCreature.create(input, species, types)
	for id: String in move_ids:
		creature.moves.append(VltMoveSlot.create(id, 10))
	return creature


func _battle(fast_side: int = 0) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	var normal: PackedStringArray = PackedStringArray(["normal"])

	for side: int in range(VltBattleState.SIDE_COUNT):
		var speed: int = 150 if side == fast_side else 50
		var moves: Array[String] = [TACKLE, QUICK, SPOOK]
		state.sides[side].party.append(_creature("lead_%d" % side, normal, speed, moves))
		state.sides[side].party.append(_creature("bench_%d" % side, normal, speed, moves))
		state.sides[side].slots[0].occupy(0)

	return state


func _scripted(roll: int = 15) -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = roll
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	return decider


func _move(side: int, index: int) -> VltCommand:
	return VltCommand.use_move(VltSlotRef.at(side, 0), index, VltSlotRef.at(1 - side, 0))


func test_a_turn_deals_damage_and_leaves_the_input_state_untouched() -> void:
	var state: VltBattleState = _battle()
	var snapshot: String = JSON.stringify(state.to_dict())

	var commands: Array[VltCommand] = [_move(0, 0)]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	assert_bool(outcome.is_complete()).is_true()
	assert_str(JSON.stringify(state.to_dict())).override_failure_message(
		"resolve() mutated its input state"
	).is_equal(snapshot)

	var target: VltBattleCreature = outcome.state.creature_at(VltSlotRef.at(1, 0))
	assert_int(target.current_hp).is_less(target.max_hp())


func test_the_log_replays_onto_the_starting_state() -> void:
	# Invariant 8, now against a log the engine produced rather than a hand-built one.
	var state: VltBattleState = _battle()
	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())

	var replayed: VltBattleState = state.clone()
	outcome.log.replay_onto(replayed)

	assert_str(JSON.stringify(replayed.to_dict())).is_equal(
		JSON.stringify(outcome.state.to_dict())
	)


func test_the_faster_side_acts_first() -> void:
	var state: VltBattleState = _battle(1)
	var commands: Array[VltCommand] = [_move(0, 0), _move(1, 0)]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	var first: VltLogMoveUsed = _first_move_used(outcome.log)
	assert_int(first.actor.side).is_equal(1)


func test_priority_beats_speed() -> void:
	var state: VltBattleState = _battle(1)
	# Side 0 is slower but uses the priority move.
	var commands: Array[VltCommand] = [_move(0, 1), _move(1, 0)]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	var first: VltLogMoveUsed = _first_move_used(outcome.log)
	assert_int(first.actor.side).is_equal(0)


func test_a_speed_tie_is_decided_not_drawn() -> void:
	var state: VltBattleState = VltBattleState.create(1)
	var normal: PackedStringArray = PackedStringArray(["normal"])
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(_creature("lead_%d" % side, normal, 100, [TACKLE]))
		state.sides[side].party.append(_creature("bench_%d" % side, normal, 100, [TACKLE]))
		state.sides[side].slots[0].occupy(0)

	var decider: VltScriptedDecider = _scripted()
	decider.speed_tie_winner_side = 1

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0), _move(1, 0)], decider)
	assert_int(_first_move_used(outcome.log).actor.side).is_equal(1)


func test_an_immune_target_blocks_the_move_upstream() -> void:
	# Normal cannot touch Ghost. A veto, not a zero: no damage event at all.
	var state: VltBattleState = _battle()
	state.sides[1].party[0].types = PackedStringArray(["ghost"])

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())

	var kinds: PackedStringArray = _kinds(outcome.log)
	assert_bool(kinds.has(VltLogMoveFailed.KIND)).is_true()
	assert_bool(kinds.has(VltLogDamage.KIND)).is_false()


func test_a_missed_move_reports_a_miss() -> void:
	var state: VltBattleState = _battle()
	var decider: VltScriptedDecider = _scripted()
	decider.accuracy = VltScriptedDecider.Answer.NEVER

	var moves: Dictionary[String, VltMoveDefinition] = {
		TACKLE: VltMoveDefinition.create(TACKLE, "normal", VltMoveDefinition.Category.PHYSICAL, 40, 50)
	}
	var engine: VltTurnEngine = VltTurnEngine.new(moves, _chart)
	var outcome: VltTurnOutcome = engine.resolve(state, [_move(0, 0)], decider)

	assert_bool(_kinds(outcome.log).has(VltLogDamage.KIND)).is_false()
	assert_bool(_kinds(outcome.log).has(VltLogMoveFailed.KIND)).is_true()


func test_using_a_move_costs_pp() -> void:
	var state: VltBattleState = _battle()
	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())
	assert_int(outcome.state.creature_at(VltSlotRef.at(0, 0)).moves[0].pp).is_equal(9)


func test_a_faint_suspends_the_turn_for_a_replacement() -> void:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 1

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())

	assert_int(outcome.status).is_equal(VltTurnOutcome.Status.NEEDS_INPUT)
	assert_int(outcome.request_kind).is_equal(VltTurnOutcome.RequestKind.REPLACEMENT)
	assert_int(outcome.request_slots.size()).is_equal(1)
	assert_int(outcome.request_slots[0].side).is_equal(1)

	# The suspension point is part of the state, so it survives serialisation.
	var restored: VltBattleState = VltBattleState.from_dict(outcome.state.to_dict())
	assert_int(restored.awaiting_replacement.size()).is_equal(1)


func test_the_turn_finishes_once_the_replacement_arrives() -> void:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 1

	var suspended: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())
	var replacement: Array[VltCommand] = [VltCommand.switch_to(VltSlotRef.at(1, 0), 1)]
	var finished: VltTurnOutcome = _engine.resolve(suspended.state, replacement, _scripted())

	assert_bool(finished.is_complete()).is_true()
	assert_int(finished.state.slot_at(VltSlotRef.at(1, 0)).occupant).is_equal(1)
	assert_bool(finished.state.awaiting_replacement.is_empty()).is_true()


func test_a_side_with_nothing_left_is_not_asked_to_replace() -> void:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 1
	state.sides[1].party[1].current_hp = 0

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())
	assert_bool(outcome.is_complete()).is_true()


func test_illegal_commands_are_rejected_without_touching_the_state() -> void:
	var state: VltBattleState = _battle()
	var snapshot: String = JSON.stringify(state.to_dict())

	var cases: Array[VltCommand] = [
		VltCommand.use_move(VltSlotRef.at(0, 0), 99, VltSlotRef.at(1, 0)),
		VltCommand.use_move(VltSlotRef.at(5, 0), 0, VltSlotRef.at(1, 0)),
		VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(9, 9)),
		VltCommand.switch_to(VltSlotRef.at(0, 0), 42),
		VltCommand.switch_to(VltSlotRef.at(0, 0), 0),
	]

	for command: VltCommand in cases:
		var outcome: VltTurnOutcome = _engine.resolve(state, [command], _scripted())
		assert_int(outcome.status).override_failure_message(
			"expected a rejection, got status %d" % outcome.status
		).is_equal(VltTurnOutcome.Status.REJECTED)
		assert_str(outcome.rejection).is_not_empty()

	assert_str(JSON.stringify(state.to_dict())).is_equal(snapshot)


func test_two_commands_for_one_slot_are_rejected() -> void:
	var state: VltBattleState = _battle()
	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0), _move(0, 0)], _scripted())
	assert_int(outcome.status).is_equal(VltTurnOutcome.Status.REJECTED)


func test_the_same_inputs_always_produce_the_same_turn() -> void:
	# Invariant 6: determinism, bit for bit, log included.
	var state: VltBattleState = _battle()
	var commands: Array[VltCommand] = [_move(0, 0), _move(1, 0)]

	var first: VltTurnOutcome = _engine.resolve(state, commands, VltSeededDecider.new(1234))
	var second: VltTurnOutcome = _engine.resolve(state, commands, VltSeededDecider.new(1234))

	assert_str(JSON.stringify(first.state.to_dict())).is_equal(
		JSON.stringify(second.state.to_dict())
	)
	assert_str(JSON.stringify(first.log.to_array())).is_equal(
		JSON.stringify(second.log.to_array())
	)


func test_hp_stays_within_bounds_over_a_whole_battle() -> void:
	# Invariants 1 and 2, driven to completion rather than asserted on one turn.
	var state: VltBattleState = _battle()
	var decider: VltSeededDecider = VltSeededDecider.new(99)
	var commands: Array[VltCommand] = [_move(0, 0), _move(1, 0)]

	for _turn: int in range(40):
		var outcome: VltTurnOutcome = _engine.resolve(state, commands, decider)
		if outcome.status == VltTurnOutcome.Status.REJECTED:
			break
		state = outcome.state

		for reference: VltSlotRef in state.all_refs():
			var creature: VltBattleCreature = state.creature_at(reference)
			if creature == null:
				continue
			assert_int(creature.current_hp).is_between(0, creature.max_hp())
			assert_bool(creature.is_fainted()).is_equal(creature.current_hp == 0)

		if outcome.status == VltTurnOutcome.Status.NEEDS_INPUT:
			var replacements: Array[VltCommand] = []
			for reference: VltSlotRef in outcome.request_slots:
				replacements.append(VltCommand.switch_to(reference, 1))
			var resumed: VltTurnOutcome = _engine.resolve(state, replacements, decider)
			if resumed.status == VltTurnOutcome.Status.REJECTED:
				break
			state = resumed.state


func _first_move_used(log: VltBattleLog) -> VltLogMoveUsed:
	for event: VltLogEvent in log.events:
		if event.kind() == VltLogMoveUsed.KIND:
			return event as VltLogMoveUsed
	return null


func _kinds(log: VltBattleLog) -> PackedStringArray:
	var kinds: PackedStringArray = PackedStringArray()
	for event: VltLogEvent in log.events:
		kinds.append(event.kind())
	return kinds
