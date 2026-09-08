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


## A doubles field. The engine has always taken a slot count and nothing ever
## passed it two, so every rule that only differs between one slot a side and two
## — ordering within a side, a target that falls to an ally's attack — answered
## to nothing.
##
## `tied` makes both slots of a side equally fast, which is the only way a speed
## tie between allies can arise: singles cannot produce one, since a side never
## submits two commands.
func _doubles(fast_side: int = 0, tied: bool = false) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(2)
	var normal: PackedStringArray = PackedStringArray(["normal"])
	var moves: Array[String] = [TACKLE, QUICK, SPOOK]

	for side: int in range(VltBattleState.SIDE_COUNT):
		var speed: int = 150 if side == fast_side else 50
		for index: int in range(3):
			# The second slot is a step slower, so position order and speed order
			# are distinguishable rather than accidentally identical.
			var own: int = speed if tied or index == 0 else speed - 10
			state.sides[side].party.append(
				_creature("pair_%d_%d" % [side, index], normal, own, moves)
			)
		state.sides[side].slots[0].occupy(0)
		state.sides[side].slots[1].occupy(1)

	return state


func _scripted(roll: int = 15) -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = roll
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	return decider


func _move(side: int, index: int) -> VltCommand:
	return VltCommand.use_move(VltSlotRef.at(side, 0), index, VltSlotRef.at(1 - side, 0))


## A tackle from one named position at another, for fields wider than one slot.
func _strike(side: int, slot: int, target_side: int, target_slot: int) -> VltCommand:
	return VltCommand.use_move(
		VltSlotRef.at(side, slot), 0, VltSlotRef.at(target_side, target_slot)
	)


func _actor_order(log: VltBattleLog) -> PackedStringArray:
	var order: PackedStringArray = PackedStringArray()
	for event: VltLogEvent in log.events:
		if event.kind() == VltLogMoveUsed.KIND:
			var used: VltLogMoveUsed = event as VltLogMoveUsed
			order.append("%d:%d" % [used.actor.side, used.actor.slot])
	return order


func _switch_in_order(log: VltBattleLog) -> PackedInt32Array:
	var order: PackedInt32Array = PackedInt32Array()
	for event: VltLogEvent in log.events:
		if event.kind() == VltLogSwitchIn.KIND:
			order.append((event as VltLogSwitchIn).target.side)
	return order


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
	decider.speed_tie_winner = VltScriptedDecider.TieWinner.LATER

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0), _move(1, 0)], decider)
	assert_int(_first_move_used(outcome.log).actor.side).is_equal(1)


func test_a_settled_race_is_never_put_to_the_decider() -> void:
	# A tie needs priority AND speed to match. Asking about a pair that differs
	# on one of them would reorder a race that was already decided — and would
	# spend a decision the oracle never makes, which is the sequence the
	# differential compares.
	#
	# Only a policy that answers "the later one" can show it: with the default,
	# a spurious question gets an answer that happens to change nothing.
	var state: VltBattleState = _battle(1)
	var decider: VltScriptedDecider = _scripted()
	decider.speed_tie_winner = VltScriptedDecider.TieWinner.LATER

	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0), _move(1, 0)], decider)

	assert_int(_first_move_used(outcome.log).actor.side).override_failure_message(
		"side 1 is faster, so there is no tie here to decide"
	).is_equal(1)


func test_switches_resolve_in_canonical_order() -> void:
	# Switches are ordered by position alone — no speed, no decider. Submitting
	# them in reverse is the only way to tell the rule apart from "whatever order
	# they arrived in".
	var state: VltBattleState = _battle()
	var commands: Array[VltCommand] = [
		VltCommand.switch_to(VltSlotRef.at(1, 0), 1),
		VltCommand.switch_to(VltSlotRef.at(0, 0), 1),
	]

	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())
	assert_array(_switch_in_order(outcome.log)).is_equal(PackedInt32Array([0, 1]))


func test_a_doubles_turn_orders_four_commands_by_speed() -> void:
	# Four distinct speeds, so the order is decided entirely by the rules and
	# nothing falls through to a tie. Submitted backwards, so the result cannot
	# be the order they arrived in.
	var state: VltBattleState = _doubles(1)
	var commands: Array[VltCommand] = [
		_strike(0, 1, 1, 1), _strike(0, 0, 1, 0), _strike(1, 1, 0, 1), _strike(1, 0, 0, 0)
	]

	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	assert_array(_actor_order(outcome.log)).is_equal(
		PackedStringArray(["1:0", "1:1", "0:0", "0:1"])
	)


func test_two_allies_at_the_same_speed_are_a_tie_the_decider_answers() -> void:
	# Allies can tie, and only in doubles. The engine must ask rather than settle
	# it from position, which is what makes the answer reproducible.
	var state: VltBattleState = _doubles(0, true)
	var commands: Array[VltCommand] = [_strike(0, 0, 1, 0), _strike(0, 1, 1, 1)]

	# Two policies that answer this tie differently. If the engine settled it
	# from position instead of asking, both would give the same order.
	var favours_earlier: VltScriptedDecider = _scripted()
	favours_earlier.speed_tie_winner = VltScriptedDecider.TieWinner.EARLIER
	var favours_later: VltScriptedDecider = _scripted()
	favours_later.speed_tie_winner = VltScriptedDecider.TieWinner.LATER

	assert_array(
		_actor_order(_engine.resolve(state, commands, favours_earlier).log)
	).is_equal(PackedStringArray(["0:0", "0:1"]))
	assert_array(
		_actor_order(_engine.resolve(state, commands, favours_later).log)
	).is_equal(PackedStringArray(["0:1", "0:0"]))


func test_a_doubles_turn_is_deterministic() -> void:
	var state: VltBattleState = _doubles(0, true)
	var commands: Array[VltCommand] = [
		_strike(0, 0, 1, 0), _strike(0, 1, 1, 1), _strike(1, 0, 0, 0), _strike(1, 1, 0, 1)
	]

	var first: VltTurnOutcome = _engine.resolve(state, commands, VltSeededDecider.new(7))
	var second: VltTurnOutcome = _engine.resolve(state, commands, VltSeededDecider.new(7))

	assert_str(JSON.stringify(first.log.to_array())).is_equal(
		JSON.stringify(second.log.to_array())
	)
	assert_int(_actor_order(first.log).size()).is_equal(4)


func test_a_target_an_ally_already_knocked_out_is_not_hit_again() -> void:
	# Both slots aim at the same creature and the first one fells it. The second
	# must report that it had no target, not compute damage against a corpse —
	# and only doubles can produce that within one turn.
	var state: VltBattleState = _doubles(0)
	state.sides[1].party[0].current_hp = 1

	var commands: Array[VltCommand] = [_strike(0, 0, 1, 0), _strike(0, 1, 1, 0)]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	var reasons: PackedInt32Array = PackedInt32Array()
	for event: VltLogEvent in outcome.log.events:
		if event.kind() == VltLogMoveFailed.KIND:
			reasons.append((event as VltLogMoveFailed).reason)

	assert_array(reasons).override_failure_message(
		"the second attacker must report NO_TARGET"
	).is_equal(PackedInt32Array([VltLogMoveFailed.Reason.NO_TARGET]))


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


func test_a_replacement_must_answer_the_slot_that_was_asked() -> void:
	# Answering with a switch nobody asked for would let a side take a free
	# switch on its opponent's faint. Every rejection here leaves the suspended
	# state untouched, so the request can simply be answered again.
	var suspended: VltTurnOutcome = _suspend()
	var snapshot: String = JSON.stringify(suspended.state.to_dict())

	var wrong_slot: Array[VltCommand] = [VltCommand.switch_to(VltSlotRef.at(0, 0), 1)]
	_assert_rejected(suspended.state, wrong_slot, "a slot that was not asked")

	var not_a_switch: Array[VltCommand] = [_move(1, 0)]
	_assert_rejected(suspended.state, not_a_switch, "a replacement that is not a switch")

	var too_many: Array[VltCommand] = [
		VltCommand.switch_to(VltSlotRef.at(1, 0), 1),
		VltCommand.switch_to(VltSlotRef.at(0, 0), 1),
	]
	_assert_rejected(suspended.state, too_many, "more replacements than were asked for")

	_assert_rejected(suspended.state, [], "no replacement at all")

	assert_str(JSON.stringify(suspended.state.to_dict())).override_failure_message(
		"a rejected replacement must leave the suspended turn as it was"
	).is_equal(snapshot)


func test_a_replacement_cannot_send_out_a_fainted_creature() -> void:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 1
	state.sides[1].party[1].current_hp = 0

	# With nothing left to send, the turn is never suspended in the first place.
	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())
	assert_bool(outcome.is_complete()).is_true()

	# And a switch to a fainted creature is refused outside a suspension too.
	var fresh: VltBattleState = _battle()
	fresh.sides[0].party[1].current_hp = 0
	_assert_rejected(
		fresh, [VltCommand.switch_to(VltSlotRef.at(0, 0), 1)], "a switch to a fainted creature"
	)


func _suspend() -> VltTurnOutcome:
	var state: VltBattleState = _battle()
	state.sides[1].party[0].current_hp = 1
	var outcome: VltTurnOutcome = _engine.resolve(state, [_move(0, 0)], _scripted())
	assert_int(outcome.status).is_equal(VltTurnOutcome.Status.NEEDS_INPUT)
	return outcome


func _assert_rejected(
	state: VltBattleState, commands: Array[VltCommand], what: String
) -> void:
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())
	assert_int(outcome.status).override_failure_message(
		"%s must be rejected, got status %d" % [what, outcome.status]
	).is_equal(VltTurnOutcome.Status.REJECTED)
	assert_str(outcome.rejection).is_not_empty()


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
