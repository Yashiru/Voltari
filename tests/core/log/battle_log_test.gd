extends GdUnitTestSuite

## The three obligations of spec 07: completeness under replay, visibility
## filtering, and a vocabulary that cannot lose an event kind in serialisation.

const PARTY_SIZE: int = 2
const SIDE_ZERO: int = 0
const SIDE_ONE: int = 1


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 110, 90, 95, 85, 105])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50
	return VltBattleCreature.create(input, species, PackedStringArray(["normal"]))


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
	log.append(VltLogEffectiveness.create(target, 1))
	victim.current_hp -= 40
	log.append(VltLogDamage.create(target, 40, victim.current_hp, victim.max_hp()))

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
	log.append(VltLogSwitchIn.create(target, 1, state.creature_at(target).species_id))

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
