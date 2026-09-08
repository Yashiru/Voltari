extends GdUnitTestSuite

## The order dispatch runs effects in, and the veto path.
##
## Both were unverified. Burn and reflect never contend for a position in the
## order, and neither declares a veto, so every rule in the comparator and the
## whole veto path could have been wrong without a single test noticing.

const ANCHOR: VltTurnAnchor.Anchor = VltTurnAnchor.Anchor.RESIDUAL
const VETO_ANCHOR: VltTurnAnchor.Anchor = VltTurnAnchor.Anchor.MOVE_VETO

var _registry: VltEffectRegistry


func before_test() -> void:
	_registry = VltEffectRegistry.new()
	VltRecordingEffects.reset()


func _creature(speed_base: int) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([150, 100, 100, 100, 100, speed_base])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50
	return VltBattleCreature.create(input, "anonymous", PackedStringArray(["water"]))


## Both sides identical unless a speed is given, so any difference in the
## resulting order comes from what the test set up and nothing else.
func _battle(speed_zero: int = 100, speed_one: int = 100) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	var speeds: PackedInt32Array = PackedInt32Array([speed_zero, speed_one])
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(_creature(speeds[side]))
		state.sides[side].slots[0].occupy(0)
	return state


func _register(definition: VltEffectDefinition) -> VltEffectDefinition:
	_registry.register(definition)
	return definition


func _apply(state: VltBattleState, id: String, at: VltSlotRef) -> void:
	assert_bool(VltEffectDispatch.apply(state, _registry, id, at, null)).override_failure_message(
		"the test could not attach \"%s\"" % id
	).is_true()


func _run(state: VltBattleState) -> PackedStringArray:
	VltRecordingEffects.reset()
	VltEffectDispatch.run_triggers(state, _registry, ANCHOR, null, VltBattleLog.new())
	return VltRecordingEffects.trace


# --- ordering ---------------------------------------------------------------


func test_declared_priority_decides_before_anything_else() -> void:
	# Both on the same creature, so speed and position are identical and only
	# priority can separate them. The low one is attached first, so collection
	# order contradicts the expected result — otherwise the assertion would hold
	# just as well with no comparator at all.
	_register(VltRecordingEffects.trigger_effect(
		"low", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"high", VltEffectDefinition.Scope.CREATURE, ANCHOR, 10
	))

	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	_apply(state, "low", at)
	_apply(state, "high", at)

	assert_array(_run(state)).is_equal(PackedStringArray(["high", "low"]))


func test_speed_breaks_a_priority_tie() -> void:
	# Equal priority, side one faster. Collection order would run side zero
	# first, so only the speed rule can produce this.
	_register(VltRecordingEffects.trigger_effect(
		"slower", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"faster", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))

	var state: VltBattleState = _battle(50, 200)
	_apply(state, "slower", VltSlotRef.at(0, 0))
	_apply(state, "faster", VltSlotRef.at(1, 0))

	assert_array(_run(state)).is_equal(PackedStringArray(["faster", "slower"]))


func test_priority_outranks_speed() -> void:
	# The slow one declares the higher priority and must still go first, which
	# is what "priority, then speed" means as opposed to "whichever is larger".
	_register(VltRecordingEffects.trigger_effect(
		"slow_but_urgent", VltEffectDefinition.Scope.CREATURE, ANCHOR, 10
	))
	_register(VltRecordingEffects.trigger_effect(
		"fast_but_patient", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))

	var state: VltBattleState = _battle(50, 200)
	_apply(state, "slow_but_urgent", VltSlotRef.at(0, 0))
	_apply(state, "fast_but_patient", VltSlotRef.at(1, 0))

	assert_array(_run(state)).is_equal(
		PackedStringArray(["slow_but_urgent", "fast_but_patient"])
	)


func test_a_stat_stage_changes_the_order() -> void:
	# Speed is read through the stage, not from the raw stat, so a slot buffed
	# past its opponent moves ahead of it.
	_register(VltRecordingEffects.trigger_effect(
		"buffed", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"plain", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))

	var state: VltBattleState = _battle(100, 120)
	_apply(state, "buffed", VltSlotRef.at(0, 0))
	_apply(state, "plain", VltSlotRef.at(1, 0))

	assert_array(_run(state)).override_failure_message(
		"without a stage, the faster side must go first"
	).is_equal(PackedStringArray(["plain", "buffed"]))

	state.slot_at(VltSlotRef.at(0, 0)).set_stage(VltStats.Stat.SPE, 2)
	assert_array(_run(state)).is_equal(PackedStringArray(["buffed", "plain"]))


func test_a_field_effect_has_no_speed_and_goes_last() -> void:
	# Field effects belong to no position, so there is no creature to read a
	# speed from. Collection puts them first; the order must not.
	_register(VltRecordingEffects.trigger_effect(
		"weather", VltEffectDefinition.Scope.FIELD, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"held", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))

	var state: VltBattleState = _battle()
	_apply(state, "weather", null)
	_apply(state, "held", VltSlotRef.at(0, 0))

	assert_array(_run(state)).is_equal(PackedStringArray(["held", "weather"]))


func test_an_empty_slot_contributes_no_speed() -> void:
	# A side-scoped effect outlives its occupant. With the slot empty there is no
	# speed to read, and reading one anyway would be an error rather than a zero.
	_register(VltRecordingEffects.trigger_effect(
		"abandoned", VltEffectDefinition.Scope.SIDE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"occupied", VltEffectDefinition.Scope.SIDE, ANCHOR, 0
	))

	var state: VltBattleState = _battle()
	_apply(state, "abandoned", VltSlotRef.at(0, 0))
	_apply(state, "occupied", VltSlotRef.at(1, 0))
	state.slot_at(VltSlotRef.at(0, 0)).vacate()

	assert_array(_run(state)).is_equal(PackedStringArray(["occupied", "abandoned"]))


func test_the_order_is_the_same_every_time() -> void:
	# Determinism is the point of the tiebreak rules: equal effects must not
	# come back in whatever order the containers happened to yield.
	_register(VltRecordingEffects.trigger_effect(
		"first", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"second", VltEffectDefinition.Scope.CREATURE, ANCHOR, 0
	))
	_register(VltRecordingEffects.trigger_effect(
		"third", VltEffectDefinition.Scope.FIELD, ANCHOR, 0
	))

	var state: VltBattleState = _battle()
	_apply(state, "first", VltSlotRef.at(0, 0))
	_apply(state, "second", VltSlotRef.at(1, 0))
	_apply(state, "third", null)

	var reference: PackedStringArray = _run(state)
	assert_int(reference.size()).is_equal(3)
	for _repeat: int in range(20):
		assert_array(_run(state)).is_equal(reference)


func test_modifiers_are_ordered_by_the_same_rules() -> void:
	# collect_modifiers shares the comparator with triggers. Ratios multiply, so
	# the damage cannot reveal the order — only the calls can.
	_register(VltRecordingEffects.modifier_effect(
		"second_modifier", VltEffectDefinition.Scope.CREATURE,
		VltDamageStage.Stage.MODIFIER_PHASE_1, 0
	))
	_register(VltRecordingEffects.modifier_effect(
		"first_modifier", VltEffectDefinition.Scope.CREATURE,
		VltDamageStage.Stage.MODIFIER_PHASE_1, 5
	))

	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	_apply(state, "second_modifier", at)
	_apply(state, "first_modifier", at)

	VltRecordingEffects.reset()
	VltEffectDispatch.collect_modifiers(state, _registry, at, VltSlotRef.at(1, 0), null)

	assert_array(VltRecordingEffects.trace).is_equal(
		PackedStringArray(["first_modifier", "second_modifier"])
	)


# --- vetoes -----------------------------------------------------------------


func test_a_veto_blocks() -> void:
	_register(VltRecordingEffects.veto_effect(
		"wall", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 0, true
	))

	var state: VltBattleState = _battle()
	_apply(state, "wall", VltSlotRef.at(0, 0))

	assert_bool(_vetoed(state)).is_true()
	assert_array(VltRecordingEffects.trace).is_equal(PackedStringArray(["wall"]))


func test_a_veto_that_declines_does_not_block() -> void:
	_register(VltRecordingEffects.veto_effect(
		"bystander", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 0, false
	))

	var state: VltBattleState = _battle()
	_apply(state, "bystander", VltSlotRef.at(0, 0))

	assert_bool(_vetoed(state)).is_false()
	assert_array(VltRecordingEffects.trace).override_failure_message(
		"the veto must be consulted even when it declines"
	).is_equal(PackedStringArray(["bystander"]))


func test_a_veto_at_another_anchor_is_never_consulted() -> void:
	# The anchor filter is the whole reason an effect can carry several vetoes.
	_register(VltRecordingEffects.veto_effect(
		"elsewhere", VltEffectDefinition.Scope.CREATURE,
		VltTurnAnchor.Anchor.BEFORE_ACTION, 0, true
	))

	var state: VltBattleState = _battle()
	_apply(state, "elsewhere", VltSlotRef.at(0, 0))

	assert_bool(_vetoed(state)).is_false()
	assert_array(VltRecordingEffects.trace).override_failure_message(
		"a veto declared at another anchor must not run here"
	).is_equal(PackedStringArray())


func test_the_first_veto_to_block_ends_the_question() -> void:
	# Asking on would let a later veto have a side effect after the answer was
	# already decided, which is why evaluation stops.
	_register(VltRecordingEffects.veto_effect(
		"decides", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 10, true
	))
	_register(VltRecordingEffects.veto_effect(
		"never_asked", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 0, true
	))

	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	_apply(state, "never_asked", at)
	_apply(state, "decides", at)

	assert_bool(_vetoed(state)).is_true()
	assert_array(VltRecordingEffects.trace).is_equal(PackedStringArray(["decides"]))


func test_a_declining_veto_lets_the_next_one_answer() -> void:
	_register(VltRecordingEffects.veto_effect(
		"declines", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 10, false
	))
	_register(VltRecordingEffects.veto_effect(
		"blocks", VltEffectDefinition.Scope.CREATURE, VETO_ANCHOR, 0, true
	))

	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	_apply(state, "blocks", at)
	_apply(state, "declines", at)

	assert_bool(_vetoed(state)).is_true()
	assert_array(VltRecordingEffects.trace).is_equal(
		PackedStringArray(["declines", "blocks"])
	)


func test_nothing_registered_blocks_nothing() -> void:
	assert_bool(_vetoed(_battle())).is_false()


func _vetoed(state: VltBattleState) -> bool:
	VltRecordingEffects.reset()
	return VltEffectDispatch.is_vetoed(
		state, _registry, VETO_ANCHOR, VltSlotRef.at(0, 0), VltSlotRef.at(1, 0), null
	)
