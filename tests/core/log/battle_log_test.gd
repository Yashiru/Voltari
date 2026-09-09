extends GdUnitTestSuite

## The three obligations of spec 07: completeness under replay, visibility
## filtering, and a vocabulary that cannot lose an event kind in serialisation.

const PARTY_SIZE: int = 2
const SIDE_ZERO: int = 0
const SIDE_ONE: int = 1
const FIELD_EFFECT: String = "test_field"


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 110, 90, 95, 85, 105])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50
	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["normal"])
	)
	creature.moves.append(VltMoveSlot.create("move_0", 10))
	return creature


func _battle() -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for index: int in range(PARTY_SIZE):
			state.sides[side].party.append(_creature("species_%d_%d" % [side, index]))
		state.sides[side].slots[0].occupy(0)
	return state


func _fingerprint(state: VltBattleState) -> String:
	return JSON.stringify(state.to_dict())


## A battle's worth of events, produced against `state` so the recorded values
## match what actually happened.
func _play(state: VltBattleState) -> VltBattleLog:
	var log: VltBattleLog = VltBattleLog.new()
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	var attacker: VltSlotRef = VltSlotRef.at(SIDE_ZERO, 0)

	state.turn = 1
	log.append(VltLogTurnStart.create(1))

	var victim: VltBattleCreature = state.creature_at(target)
	state.creature_at(attacker).moves[0].pp = 9
	log.append(VltLogMoveUsed.create(attacker, "move_0", 0, 9, target))
	log.append(VltLogEffectiveness.create(target, 1))
	victim.current_hp -= 40
	log.append(VltLogDamage.create(target, 40, victim.current_hp, victim.max_hp()))

	log.append(VltLogMoveFailed.create(target, VltLogMoveFailed.Reason.MISSED))

	state.slot_at(attacker).set_stage(VltStats.Stat.ATK, 2)
	log.append(VltLogStatChange.create(attacker, VltStats.Stat.ATK, 2, 2))

	var healer: VltBattleCreature = state.creature_at(attacker)
	healer.current_hp -= 30
	log.append(VltLogDamage.create(attacker, 30, healer.current_hp, healer.max_hp()))
	healer.current_hp += 10
	log.append(VltLogHeal.create(attacker, 10, healer.current_hp, healer.max_hp()))

	victim.current_hp = 0
	log.append(VltLogFaint.create(target))

	state.slot_at(target).vacate()
	log.append(VltLogSwitchOut.create(target, 0))
	state.slot_at(target).occupy(1)
	log.append(
		VltLogSwitchIn.create(
			target, 1, state.creature_at(target).species_id, state.creature_at(target).level
		)
	)

	# An effect appearing and then counting down, so replay exercises both
	# creating an instance and reassigning one that is already there.
	var screen: VltEffectInstance = VltEffectInstance.create(
		VltReflect.ID, attacker, VltReflect.DURATION
	)
	state.sides[SIDE_ONE].effects.append(screen)
	log.append(VltLogEffectChanged.create(screen, VltEffectDefinition.Scope.SIDE, target))
	screen.remaining -= 1
	log.append(VltLogEffectChanged.create(screen, VltEffectDefinition.Scope.SIDE, target))

	# And one going away, at field scope, which has no owning position.
	var weather: VltEffectInstance = VltEffectInstance.create(FIELD_EFFECT, null, 1)
	state.effects.append(weather)
	log.append(VltLogEffectChanged.create(weather, VltEffectDefinition.Scope.FIELD, null))
	state.effects.remove_at(0)
	log.append(VltLogEffectChanged.removal(FIELD_EFFECT, VltEffectDefinition.Scope.FIELD, null))

	# A throw that shook twice and came loose. Nothing moves, so the state stays
	# as it is — the vacating path is exercised where capture is.
	log.append(VltLogCaptureShake.create(target, 1))
	log.append(VltLogCaptureShake.create(target, 2))
	log.append(VltLogCaptureResult.create(target, 1, false))

	state.awaiting_replacement = [VltSlotRef.at(SIDE_ONE, 0)]
	log.append(VltLogPendingInput.create(state.awaiting_replacement))

	return log


func test_replaying_the_log_reproduces_the_final_state() -> void:
	# Invariant 8 of spec 05, and the reason an effect that mutates state without
	# emitting an event fails a test rather than surfacing months later in the UI.
	var initial: VltBattleState = _battle()
	var played: VltBattleState = initial.clone()
	var log: VltBattleLog = _play(played)

	var replayed: VltBattleState = initial.clone()
	log.replay_onto(replayed)

	assert_str(_fingerprint(replayed)).is_equal(_fingerprint(played))


func test_an_unlogged_mutation_breaks_the_replay() -> void:
	# Proves the invariant has teeth: it is not vacuously true.
	var initial: VltBattleState = _battle()
	var played: VltBattleState = initial.clone()
	var log: VltBattleLog = _play(played)

	played.creature_at(VltSlotRef.at(SIDE_ZERO, 0)).current_hp -= 7

	var replayed: VltBattleState = initial.clone()
	log.replay_onto(replayed)

	assert_str(_fingerprint(replayed)).is_not_equal(_fingerprint(played))


func test_an_opponent_sees_scaled_health_not_exact_health() -> void:
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	var creature: VltBattleCreature = state.creature_at(target)
	creature.current_hp = creature.max_hp() / 2

	var event: VltLogDamage = VltLogDamage.create(
		target, 40, creature.current_hp, creature.max_hp()
	)

	var owner_view: VltLogDamage = event.for_viewer(SIDE_ONE) as VltLogDamage
	assert_int(owner_view.current_hp).is_equal(creature.current_hp)
	assert_int(owner_view.max_hp).is_equal(creature.max_hp())

	var opponent_view: VltLogDamage = event.for_viewer(SIDE_ZERO) as VltLogDamage
	assert_int(opponent_view.max_hp).is_equal(VltLogDamage.REDUCED_SCALE)
	assert_int(opponent_view.current_hp).is_between(49, 51)
	assert_int(opponent_view.current_hp).is_not_equal(creature.current_hp)


func test_a_survivor_never_reads_as_zero_to_an_opponent() -> void:
	# Rounding a sliver of HP down to 0% would tell the opponent the target is
	# dead when it is not — a lie the UI cannot recover from.
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	var event: VltLogDamage = VltLogDamage.create(target, 399, 1, 400)
	var opponent_view: VltLogDamage = event.for_viewer(SIDE_ZERO) as VltLogDamage
	assert_int(opponent_view.current_hp).is_equal(1)


func test_a_heal_reads_as_a_percentage_to_an_opponent() -> void:
	# Heal reduces by the same rule as damage and had no test of its own, so its
	# scaling answered to nothing — the damage tests would have passed either way.
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	var event: VltLogHeal = VltLogHeal.create(target, 50, 150, 200)

	var owner_view: VltLogHeal = event.for_viewer(SIDE_ONE) as VltLogHeal
	assert_int(owner_view.current_hp).is_equal(150)
	assert_int(owner_view.max_hp).is_equal(200)

	var opponent_view: VltLogHeal = event.for_viewer(SIDE_ZERO) as VltLogHeal
	assert_int(opponent_view.max_hp).is_equal(VltLogHeal.REDUCED_SCALE)
	assert_int(opponent_view.current_hp).is_equal(75)
	assert_int(opponent_view.amount).is_equal(25)


func test_a_sliver_of_healing_never_reads_as_none_at_all() -> void:
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	var event: VltLogHeal = VltLogHeal.create(target, 1, 1, 400)
	assert_int((event.for_viewer(SIDE_ZERO) as VltLogHeal).amount).is_equal(1)


func test_replaying_a_move_whose_actor_is_gone_changes_nothing() -> void:
	# A log outlives the state it describes: it is replayed onto snapshots, and a
	# viewer replays a filtered copy of it. An event whose slot has emptied, or
	# whose index the occupant does not have, must do nothing rather than reach
	# for what is not there.
	var state: VltBattleState = _battle()
	var actor: VltSlotRef = VltSlotRef.at(SIDE_ZERO, 0)
	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)

	var event: VltLogMoveUsed = VltLogMoveUsed.create(actor, "move_0", 0, 3, target)
	state.slot_at(actor).vacate()
	event.apply(state)
	assert_bool(state.slot_at(actor).is_empty()).is_true()

	state.slot_at(actor).occupy(0)

	# One past the last move, not far past it: the boundary is where an index
	# check is wrong or right, and any larger number would pass either way.
	var beyond: VltLogMoveUsed = VltLogMoveUsed.create(
		actor, "move_0", state.creature_at(actor).moves.size(), 3, target
	)
	beyond.apply(state)
	assert_int(state.creature_at(actor).moves[0].pp).override_failure_message(
		"an index the occupant does not have must leave its moves alone"
	).is_equal(10)


func test_no_side_cannot_collide_with_a_real_side() -> void:
	# NO_SIDE marks an event belonging to no side. If it ever equalled a real
	# side index, a field event would silently acquire an owner and visibility
	# filtering would start reducing or hiding it for one of the players.
	assert_int(VltLogEvent.NO_SIDE).override_failure_message(
		"NO_SIDE must be outside the range of real side indices"
	).is_less(0)

	for side: int in range(VltBattleState.SIDE_COUNT):
		assert_int(VltLogEvent.NO_SIDE).is_not_equal(side)


func test_owner_only_events_are_dropped_for_the_other_side() -> void:
	var event: VltLogTurnStart = VltLogTurnStart.create(4)
	event.visibility = VltLogEvent.Visibility.OWNER_ONLY
	event.owner_side = SIDE_ZERO

	assert_object(event.for_viewer(SIDE_ZERO)).is_not_null()
	assert_object(event.for_viewer(SIDE_ONE)).is_null()


func test_a_filtered_log_reproduces_what_that_viewer_can_observe() -> void:
	# The filtered analogue of invariant 8. Public and transformed events all
	# still apply, so the opponent's replay tracks every position and stage.
	var initial: VltBattleState = _battle()
	var played: VltBattleState = initial.clone()
	var log: VltBattleLog = _play(played)

	var opponent_log: VltBattleLog = log.for_viewer(SIDE_ZERO)
	assert_int(opponent_log.size()).is_equal(log.size())

	var replayed: VltBattleState = initial.clone()
	opponent_log.replay_onto(replayed)

	var target: VltSlotRef = VltSlotRef.at(SIDE_ONE, 0)
	assert_int(replayed.slot_at(target).occupant).is_equal(
		played.slot_at(target).occupant
	)
	assert_int(replayed.slot_at(VltSlotRef.at(SIDE_ZERO, 0)).stat_stages[VltStats.Stat.ATK]).is_equal(2)


func test_the_log_serialises_and_restores() -> void:
	var state: VltBattleState = _battle()
	var log: VltBattleLog = _play(state)
	var restored: VltBattleLog = VltBattleLog.from_array(log.to_array())

	assert_int(restored.size()).is_equal(log.size())
	assert_str(JSON.stringify(restored.to_array())).is_equal(JSON.stringify(log.to_array()))


func test_every_declared_event_kind_appears_in_the_log_and_round_trips() -> void:
	# Meta-test: a kind added without its deserialiser, or without ever being
	# emitted, fails here instead of losing data in silence.
	var state: VltBattleState = _battle()
	var log: VltBattleLog = _play(state)

	var emitted: PackedStringArray = PackedStringArray()
	for event: VltLogEvent in log.events:
		if not emitted.has(event.kind()):
			emitted.append(event.kind())

	for kind: String in VltBattleLog.KINDS:
		assert_bool(emitted.has(kind)).override_failure_message(
			"kind \"%s\" is declared but never emitted by the reference play" % kind
		).is_true()

	var restored: VltBattleLog = VltBattleLog.from_array(log.to_array())
	for index: int in range(log.size()):
		assert_str(restored.events[index].kind()).is_equal(log.events[index].kind())


func test_a_switch_announces_the_level() -> void:
	# A creature that entered mid-battle has no other way of saying it, and a
	# HUD that cannot show the opponent's level is a HUD missing the number the
	# player decides on.
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(0, 0)
	var creature: VltBattleCreature = state.creature_at(target)

	var event: VltLogSwitchIn = VltLogSwitchIn.create(
		target, 1, creature.species_id, creature.level
	)

	assert_int(event.level).is_equal(creature.level)
	assert_int(event.visibility).override_failure_message(
		"the level is public knowledge and the event says otherwise"
	).is_equal(VltLogEvent.Visibility.PUBLIC)
