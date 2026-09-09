extends GdUnitTestSuite

## Stage three: the throw, as the turn machine resolves it (spec 11, section 1).
##
## The core is handed a threshold and knows nothing else. Every test here builds
## one directly rather than through the rules layer, which is the point — if the
## core needed a ball to be tested, it would know what a ball is.

const TACKLE: String = "tackle"
const CERTAIN: int = 65536
const NEVER: int = 0

var _engine: VltTurnEngine
var _chart: VltTypeChart


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(
		VltContentPayloads.read_json("res://content/generated/type-chart.json")
	)
	var moves: Dictionary[String, VltMoveDefinition] = {
		TACKLE: VltMoveDefinition.create(
			TACKLE, "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
	}
	_engine = VltTurnEngine.new(moves, _chart)


func _creature() -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 100, 100, 100, 100])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, "anonymous", PackedStringArray(["normal"])
	)
	creature.moves.append(VltMoveSlot.create(TACKLE, 10))
	return creature


func _battle(party: int = 1) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for _index: int in range(party):
			state.sides[side].party.append(_creature())
		state.sides[side].slots[0].occupy(0)
	return state


## Answers every shake the same way, which is what makes a throw testable.
func _decider(lands: bool) -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = 15
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	decider.capture = (
		VltScriptedDecider.Answer.ALWAYS if lands else VltScriptedDecider.Answer.NEVER
	)
	return decider


func _throw(threshold: int = CERTAIN) -> VltCommand:
	return VltCommand.throw_ball(VltSlotRef.at(0, 0), VltSlotRef.at(1, 0), threshold)


func _kinds(log: VltBattleLog) -> PackedStringArray:
	var kinds: PackedStringArray = PackedStringArray()
	for event: VltLogEvent in log.events:
		kinds.append(event.kind())
	return kinds


func _result(log: VltBattleLog) -> VltLogCaptureResult:
	for event: VltLogEvent in log.events:
		if event.kind() == VltLogCaptureResult.KIND:
			return event as VltLogCaptureResult
	return null


func _shakes(log: VltBattleLog) -> int:
	var count: int = 0
	for event: VltLogEvent in log.events:
		if event.kind() == VltLogCaptureShake.KIND:
			count += 1
	return count


func test_a_throw_that_lands_empties_the_slot() -> void:
	var outcome: VltTurnOutcome = _engine.resolve(_battle(), [_throw()], _decider(true))

	assert_bool(_result(outcome.log).captured).is_true()
	assert_bool(outcome.state.slot_at(VltSlotRef.at(1, 0)).is_empty()).override_failure_message(
		"a captured creature must leave the field"
	).is_true()


func test_a_landed_throw_shakes_four_times() -> void:
	var outcome: VltTurnOutcome = _engine.resolve(_battle(), [_throw()], _decider(true))
	assert_int(_shakes(outcome.log)).is_equal(VltTurnEngine.CAPTURE_SHAKES)


func test_a_throw_that_fails_shakes_none_and_leaves_it_standing() -> void:
	var outcome: VltTurnOutcome = _engine.resolve(_battle(), [_throw()], _decider(false))

	assert_int(_shakes(outcome.log)).is_equal(0)
	assert_bool(_result(outcome.log).captured).is_false()
	assert_bool(outcome.state.slot_at(VltSlotRef.at(1, 0)).is_empty()).is_false()


func test_the_result_names_the_creature() -> void:
	# The state carries no mark of what was caught, so the log is how the rules
	# layer knows which party member to take (spec 11, section 7).
	var state: VltBattleState = _battle(2)
	state.sides[1].slots[0].vacate()
	state.sides[1].slots[0].occupy(1)

	var outcome: VltTurnOutcome = _engine.resolve(state, [_throw()], _decider(true))
	assert_int(_result(outcome.log).party_index).is_equal(1)


func test_a_capture_replays() -> void:
	# Invariant 8 against the one event here that changes the state.
	var state: VltBattleState = _battle()
	var outcome: VltTurnOutcome = _engine.resolve(state, [_throw()], _decider(true))

	var replayed: VltBattleState = state.clone()
	outcome.log.replay_onto(replayed)

	assert_str(JSON.stringify(replayed.to_dict())).is_equal(
		JSON.stringify(outcome.state.to_dict())
	)


func test_a_throw_costs_the_turn_and_the_opponent_still_acts() -> void:
	# The reason capture is a command at all. A failed throw must leave the
	# thrower having been attacked.
	var state: VltBattleState = _battle()
	var commands: Array[VltCommand] = [
		_throw(),
		VltCommand.use_move(VltSlotRef.at(1, 0), 0, VltSlotRef.at(0, 0)),
	]

	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _decider(false))
	var thrower: VltBattleCreature = outcome.state.creature_at(VltSlotRef.at(0, 0))

	assert_int(thrower.current_hp).override_failure_message(
		"the opponent should have acted while the ball was thrown"
	).is_less(thrower.max_hp())


func test_a_landed_throw_ends_the_turn_where_it_stands() -> void:
	# Nothing is left to resolve against, so the opponent's move never happens.
	var state: VltBattleState = _battle()
	var commands: Array[VltCommand] = [
		_throw(),
		VltCommand.use_move(VltSlotRef.at(1, 0), 0, VltSlotRef.at(0, 0)),
	]

	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _decider(true))
	var thrower: VltBattleCreature = outcome.state.creature_at(VltSlotRef.at(0, 0))

	assert_int(thrower.current_hp).is_equal(thrower.max_hp())
	assert_bool(_kinds(outcome.log).has(VltLogMoveUsed.KIND)).override_failure_message(
		"the opponent acted after it had already been caught"
	).is_false()


func test_a_throw_resolves_before_a_move() -> void:
	# It sits in the switch bracket, so a faster opponent does not get in first.
	var state: VltBattleState = _battle()
	state.sides[1].party[0].stats[VltStats.Stat.SPE] = 999

	var commands: Array[VltCommand] = [
		_throw(),
		VltCommand.use_move(VltSlotRef.at(1, 0), 0, VltSlotRef.at(0, 0)),
	]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _decider(true))

	assert_str(_kinds(outcome.log)[1]).override_failure_message(
		"a faster opponent acted before the ball landed"
	).is_equal(VltLogCaptureShake.KIND)


func test_a_throw_at_an_empty_slot_reports_no_target() -> void:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 0

	var outcome: VltTurnOutcome = _engine.resolve(state, [_throw()], _decider(true))

	assert_bool(_kinds(outcome.log).has(VltLogMoveFailed.KIND)).is_true()
	assert_bool(_kinds(outcome.log).has(VltLogCaptureResult.KIND)).is_false()


func test_a_throw_at_your_own_side_is_rejected() -> void:
	var command: VltCommand = VltCommand.throw_ball(
		VltSlotRef.at(0, 0), VltSlotRef.at(0, 0), CERTAIN
	)
	var outcome: VltTurnOutcome = _engine.resolve(_battle(), [command], _decider(true))

	assert_int(outcome.status).is_equal(VltTurnOutcome.Status.REJECTED)
	assert_str(outcome.rejection).is_not_empty()


func test_a_threshold_outside_the_draw_range_is_rejected() -> void:
	# The core checks the shape of the number, never where it came from.
	for threshold: int in [-1, VltDecider.CAPTURE_DRAW_RANGE + 1]:
		var outcome: VltTurnOutcome = _engine.resolve(
			_battle(), [_throw(threshold)], _decider(true)
		)
		assert_int(outcome.status).override_failure_message(
			"threshold %d should have been rejected" % threshold
		).is_equal(VltTurnOutcome.Status.REJECTED)


func test_a_throw_survives_serialisation() -> void:
	var thrown: VltCommand = _throw(41234)
	var restored: VltCommand = VltCommand.from_dict(thrown.to_dict())

	assert_int(restored.kind).is_equal(VltCommand.Kind.CATCH)
	assert_int(restored.capture_threshold).is_equal(41234)
	assert_bool(restored.target.equals(thrown.target)).is_true()


func test_a_certain_threshold_lands_through_the_seeded_decider() -> void:
	# The property the whole design rests on: a threshold equal to the draw range
	# passes every check, with no special case anywhere.
	for seed_value: int in range(1, 30):
		var outcome: VltTurnOutcome = _engine.resolve(
			_battle(), [_throw(CERTAIN)], VltSeededDecider.new(seed_value)
		)
		assert_bool(_result(outcome.log).captured).override_failure_message(
			"seed %d: a certain throw did not land" % seed_value
		).is_true()


func test_a_threshold_of_nothing_never_lands() -> void:
	for seed_value: int in range(1, 30):
		var outcome: VltTurnOutcome = _engine.resolve(
			_battle(), [_throw(NEVER)], VltSeededDecider.new(seed_value)
		)
		assert_bool(_result(outcome.log).captured).is_false()
		assert_int(_shakes(outcome.log)).is_equal(0)
