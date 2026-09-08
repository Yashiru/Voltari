extends GdUnitTestSuite

## The effect system: scopes, stacking, ordering, and two effects proving the
## mechanism carries real behaviour.

const CHART_PAYLOAD: String = "res://content/generated/type-chart.json"
const PHYSICAL: String = "phys"
const SPECIAL: String = "spec"

var _chart: VltTypeChart
var _registry: VltEffectRegistry
var _moves: Dictionary[String, VltMoveDefinition]


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(_read_json(CHART_PAYLOAD))
	_registry = VltEffectRegistry.new()
	_registry.register(VltBurn.define())
	_registry.register(VltReflect.define())
	_moves = {
		PHYSICAL: VltMoveDefinition.create(
			PHYSICAL, "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
		SPECIAL: VltMoveDefinition.create(
			SPECIAL, "normal", VltMoveDefinition.Category.SPECIAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
	}


@warning_ignore_start("unsafe_cast")
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary
@warning_ignore_restore("unsafe_cast")


func _creature() -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([150, 100, 100, 100, 100, 100])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, "anonymous", PackedStringArray(["water"])
	)
	creature.moves.append(VltMoveSlot.create(PHYSICAL, 20))
	creature.moves.append(VltMoveSlot.create(SPECIAL, 20))
	return creature


func _battle() -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(_creature())
		state.sides[side].party.append(_creature())
		state.sides[side].slots[0].occupy(0)
	return state


func _engine() -> VltTurnEngine:
	return VltTurnEngine.new(_moves, _chart, _registry)


func _scripted() -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = 15
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	return decider


func _attack(state: VltBattleState, move_index: int) -> VltTurnOutcome:
	var command: VltCommand = VltCommand.use_move(
		VltSlotRef.at(0, 0), move_index, VltSlotRef.at(1, 0)
	)
	return _engine().resolve(state, [command], _scripted())


func _damage_dealt(outcome: VltTurnOutcome, at: VltSlotRef) -> int:
	for event: VltLogEvent in outcome.log.events:
		if event.kind() != VltLogDamage.KIND:
			continue
		var hit: VltLogDamage = event as VltLogDamage
		if hit.target.equals(at):
			return hit.amount
	return 0


# --- the effects themselves -------------------------------------------------


func test_a_burn_halves_physical_damage_but_not_special() -> void:
	var target: VltSlotRef = VltSlotRef.at(1, 0)

	var clean: int = _damage_dealt(_attack(_battle(), 0), target)

	var burned: VltBattleState = _battle()
	VltEffectDispatch.apply(burned, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)
	var reduced: int = _damage_dealt(_attack(burned, 0), target)

	assert_int(reduced).is_less(clean)
	assert_int(reduced).is_between(clean / 2 - 1, clean / 2 + 1)

	# The same burn must leave a special move untouched.
	var special_clean: int = _damage_dealt(_attack(_battle(), 1), target)
	var special_burned: VltBattleState = _battle()
	VltEffectDispatch.apply(special_burned, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)
	assert_int(_damage_dealt(_attack(special_burned, 1), target)).is_equal(special_clean)


func test_a_burn_contributes_nothing_outside_an_action() -> void:
	# The context declares actor, target and move as the action under way "when
	# there is one", so a modifier can be asked for its ratio with no action at
	# all. Each half of the guard has to hold on its own: reading a move that is
	# not there is not a smaller mistake than reading an actor that is not.
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)

	var no_move: VltDamageModifiers = VltEffectDispatch.collect_modifiers(
		state, _registry, at, VltSlotRef.at(1, 0), null
	)
	_assert_neutral(no_move, VltDamageStage.Stage.BURN, "an actor with no move")

	var no_actor: VltDamageModifiers = VltEffectDispatch.collect_modifiers(
		state, _registry, null, VltSlotRef.at(1, 0), _moves[PHYSICAL]
	)
	_assert_neutral(no_actor, VltDamageStage.Stage.BURN, "a move with no actor")


func test_a_screen_contributes_nothing_outside_an_action() -> void:
	# The same guard as the burn, on the other effect and the other stage. It
	# reads three things from the context and each has to be checked on its own.
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(1, 0)
	var actor: VltSlotRef = VltSlotRef.at(0, 0)
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, target, null)

	var no_move: VltDamageModifiers = VltEffectDispatch.collect_modifiers(
		state, _registry, actor, target, null
	)
	_assert_neutral(
		no_move, VltDamageStage.Stage.MODIFIER_PHASE_1, "a target with no move"
	)

	var no_target: VltDamageModifiers = VltEffectDispatch.collect_modifiers(
		state, _registry, actor, null, _moves[PHYSICAL]
	)
	_assert_neutral(
		no_target, VltDamageStage.Stage.MODIFIER_PHASE_1, "a move with no target"
	)


func _assert_neutral(
	modifiers: VltDamageModifiers, stage: VltDamageStage.Stage, what: String
) -> void:
	assert_int(
		modifiers.numerator_for(stage)
	).override_failure_message("%s must contribute nothing" % what).is_equal(1)
	assert_int(modifiers.denominator_for(stage)).is_equal(1)


func test_a_burn_does_not_touch_a_creature_that_already_fainted() -> void:
	# The residual runs after every action, so the creature it belongs to may
	# have been knocked out earlier in the same turn. Damaging it again would
	# report a second faint for one death.
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(1, 0)
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, target, null)
	state.sides[1].party[0].current_hp = 1

	var outcome: VltTurnOutcome = _attack(state, 0)

	var faints: int = 0
	for event: VltLogEvent in outcome.log.events:
		if event.kind() == VltLogFaint.KIND:
			faints += 1

	assert_int(faints).override_failure_message(
		"one death must be reported once"
	).is_equal(1)
	assert_int(outcome.state.creature_at(target).current_hp).is_equal(0)


func test_a_burn_costs_hp_at_the_end_of_the_turn() -> void:
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)

	var outcome: VltTurnOutcome = _attack(state, 0)
	var burned: VltBattleCreature = outcome.state.creature_at(VltSlotRef.at(0, 0))

	assert_int(burned.current_hp).is_less(burned.max_hp())
	assert_int(_damage_dealt(outcome, VltSlotRef.at(0, 0))).is_greater(0)


func test_residual_damage_replays() -> void:
	# Invariant 8 against an effect: a trigger that mutates without emitting
	# would break the replay, which is exactly how such a bug gets caught.
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)

	var outcome: VltTurnOutcome = _attack(state, 0)
	var replayed: VltBattleState = state.clone()
	outcome.log.replay_onto(replayed)

	assert_str(JSON.stringify(replayed.to_dict())).is_equal(
		JSON.stringify(outcome.state.to_dict())
	)


func test_a_screen_countdown_replays() -> void:
	# The regression: counting a screen down used to mutate `remaining` with no
	# event, so the replay produced a screen that had forgotten a turn passed.
	# The burn test above could not see it — its trigger emits damage, so the
	# state it changes travels in the log by accident of what it does.
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, VltSlotRef.at(1, 0), null)

	var outcome: VltTurnOutcome = _attack(state, 0)
	assert_int(outcome.state.sides[1].effects[0].remaining).is_equal(VltReflect.DURATION - 1)

	var replayed: VltBattleState = state.clone()
	outcome.log.replay_onto(replayed)

	assert_str(JSON.stringify(replayed.to_dict())).is_equal(
		JSON.stringify(outcome.state.to_dict())
	)


func test_an_expiring_screen_replays() -> void:
	# The other half: the removal must travel too, or the replay keeps a screen
	# the battle has already dropped.
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, VltSlotRef.at(1, 0), null)

	for _turn: int in range(VltReflect.DURATION - 1):
		state = _attack(state, 0).state

	var outcome: VltTurnOutcome = _attack(state, 0)
	assert_int(outcome.state.sides[1].effects.size()).is_equal(0)

	var replayed: VltBattleState = state.clone()
	outcome.log.replay_onto(replayed)
	assert_int(replayed.sides[1].effects.size()).is_equal(0)


func test_counting_down_never_goes_past_zero() -> void:
	# An effect already at zero is waiting to be dropped, not waiting to be
	# counted further. Ticking it again would make the duration negative, which
	# no expiry check would ever catch since it only asks for <= 0.
	var state: VltBattleState = _battle()
	var spent: VltEffectInstance = VltEffectInstance.create(VltReflect.ID, null, 1)
	spent.remaining = 0
	state.sides[0].effects.append(spent)

	var log: VltBattleLog = VltBattleLog.new()
	VltEffectDispatch.tick_durations(state, log)

	assert_int(spent.remaining).is_equal(0)
	assert_bool(log.is_empty()).override_failure_message(
		"an effect that did not move must not report that it did"
	).is_true()


func test_a_screen_protects_the_side_not_the_creature() -> void:
	# Side scope earning its keep: the screen keeps working after a switch.
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(1, 0)
	var clean: int = _damage_dealt(_attack(_battle(), 0), target)

	VltEffectDispatch.apply(state, _registry, VltReflect.ID, target, null)
	var screened: int = _damage_dealt(_attack(state, 0), target)
	assert_int(screened).is_less(clean)

	# Replace the defender; the screen belongs to the side, so it still applies.
	state.slot_at(target).vacate()
	state.slot_at(target).occupy(1)
	assert_int(_damage_dealt(_attack(state, 0), target)).is_equal(screened)


func test_a_screen_expires_after_its_duration() -> void:
	var state: VltBattleState = _battle()
	var target: VltSlotRef = VltSlotRef.at(1, 0)
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, target, null)

	for _turn: int in range(VltReflect.DURATION):
		assert_int(state.sides[1].effects.size()).is_equal(1)
		state = _attack(state, 0).state

	assert_int(state.sides[1].effects.size()).is_equal(0)


# --- the mechanism ----------------------------------------------------------


func test_stacking_rules_are_honoured() -> void:
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)

	# UNIQUE: reapplying does nothing and is not an error.
	assert_bool(VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)).is_true()
	assert_bool(VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)).is_false()
	assert_int(state.creature_at(at).effects.size()).is_equal(1)

	# REFRESH: reapplying restarts the duration.
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, at, null)
	state.sides[0].effects[0].remaining = 1
	assert_bool(VltEffectDispatch.apply(state, _registry, VltReflect.ID, at, null)).is_true()
	assert_int(state.sides[0].effects[0].remaining).is_equal(VltReflect.DURATION)
	assert_int(state.sides[0].effects.size()).is_equal(1)


## A registry of its own, for tests that need a definition the library has not
## got. The shared one is checked by the meta-test at the bottom, so registering
## a test double into it would be reported as unverified content.
func _own_registry() -> VltEffectRegistry:
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	registry.register(VltReflect.define())
	return registry


func test_stacking_adds_a_layer() -> void:
	# The third stacking rule, and the one no registered effect uses yet — so
	# nothing exercised it and reapplying could have done anything at all.
	var registry: VltEffectRegistry = _own_registry()
	registry.register(
		VltEffectDefinition.create(
			"test_stack",
			VltEffectDefinition.Scope.CREATURE,
			VltEffectDefinition.ResetRule.PERSISTS,
			VltEffectDefinition.Stacking.STACKING
		)
	)

	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)

	assert_bool(VltEffectDispatch.apply(state, registry, "test_stack", at, null)).is_true()
	assert_int(state.creature_at(at).effects[0].layers).is_equal(1)

	# Reapplying reports that something changed, unlike UNIQUE.
	assert_bool(VltEffectDispatch.apply(state, registry, "test_stack", at, null)).is_true()
	assert_int(state.creature_at(at).effects.size()).is_equal(1)
	assert_int(state.creature_at(at).effects[0].layers).is_equal(2)


func test_an_effect_needs_a_position_it_can_attach_to() -> void:
	# Every rejection path of the scope guard. Each returns false rather than
	# raising: applying an effect where it cannot go is a normal answer.
	var state: VltBattleState = _battle()
	var registry: VltEffectRegistry = _own_registry()

	assert_bool(
		VltEffectDispatch.apply(state, registry, VltBurn.ID, null, null)
	).override_failure_message("a creature-scoped effect needs a position").is_false()

	var off_field: VltSlotRef = VltSlotRef.at(0, 99)
	assert_bool(
		VltEffectDispatch.apply(state, registry, VltBurn.ID, off_field, null)
	).override_failure_message("%s is not a slot on this field" % off_field).is_false()

	assert_bool(
		VltEffectDispatch.remove(state, VltBurn.define(), null)
	).override_failure_message("removing from nowhere removes nothing").is_false()

	# Field scope is the exception: it belongs to no position, so a null one is
	# not a missing argument.
	registry.register(
		VltEffectDefinition.create("test_anywhere", VltEffectDefinition.Scope.FIELD)
	)
	assert_bool(VltEffectDispatch.apply(state, registry, "test_anywhere", null, null)).is_true()


func test_applying_during_a_turn_is_recorded() -> void:
	# The log parameter is what keeps invariant 8 true for effects applied mid
	# turn, so an application with a log must produce an event that replays.
	var state: VltBattleState = _battle()
	var log: VltBattleLog = VltBattleLog.new()
	var at: VltSlotRef = VltSlotRef.at(0, 0)

	var snapshot: VltBattleState = state.clone()
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null, log)

	assert_int(log.size()).is_equal(1)
	log.replay_onto(snapshot)
	assert_str(JSON.stringify(snapshot.to_dict())).is_equal(JSON.stringify(state.to_dict()))


func test_slot_scoped_state_clears_when_the_occupant_leaves() -> void:
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	state.slot_at(at).effects.append(VltEffectInstance.create(VltBurn.ID, null, 0))

	state.slot_at(at).occupy(1)
	assert_int(state.slot_at(at).effects.size()).is_equal(0)


func test_creature_scoped_effects_follow_the_creature() -> void:
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)

	state.slot_at(at).occupy(1)
	assert_int(state.sides[0].party[0].effects.size()).is_equal(1)
	assert_int(state.sides[0].party[1].effects.size()).is_equal(0)


func test_effects_survive_serialisation() -> void:
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, VltSlotRef.at(1, 0), null)

	var restored: VltBattleState = VltBattleState.from_dict(state.to_dict())
	assert_str(JSON.stringify(restored.to_dict())).is_equal(JSON.stringify(state.to_dict()))
	assert_int(restored.sides[1].effects[0].remaining).is_equal(VltReflect.DURATION)


func test_an_effect_cannot_attach_to_an_empty_slot() -> void:
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	state.slot_at(at).vacate()
	assert_bool(VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)).is_false()


func test_collection_order_is_stable() -> void:
	var state: VltBattleState = _battle()
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, VltSlotRef.at(0, 0), null)
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, VltSlotRef.at(1, 0), null)
	VltEffectDispatch.apply(state, _registry, VltReflect.ID, VltSlotRef.at(0, 0), null)

	var first: PackedStringArray = _collection_order(state)
	for _repeat: int in range(20):
		assert_array(_collection_order(state)).is_equal(first)


func test_removing_an_effect() -> void:
	var state: VltBattleState = _battle()
	var at: VltSlotRef = VltSlotRef.at(0, 0)
	VltEffectDispatch.apply(state, _registry, VltBurn.ID, at, null)

	assert_bool(VltEffectDispatch.remove(state, VltBurn.define(), at)).is_true()
	assert_int(state.creature_at(at).effects.size()).is_equal(0)

	# Removing what is not there reports so rather than pretending.
	assert_bool(VltEffectDispatch.remove(state, VltBurn.define(), at)).is_false()

	state.slot_at(at).vacate()
	assert_bool(VltEffectDispatch.remove(state, VltBurn.define(), at)).is_false()


func test_field_scoped_effects_belong_to_no_side() -> void:
	# Field scope was the one path nothing exercised, so the mutation harness
	# found it before a battle did.
	var weather: VltEffectDefinition = VltEffectDefinition.create(
		"test_field", VltEffectDefinition.Scope.FIELD
	)
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(weather)

	var state: VltBattleState = _battle()
	assert_bool(VltEffectDispatch.apply(state, registry, "test_field", null, null)).is_true()
	assert_int(state.effects.size()).is_equal(1)

	var active: Array[VltEffectDispatch.Active] = VltEffectDispatch.active_effects(state, registry)
	assert_int(active.size()).is_equal(1)
	assert_object(active[0].owner).override_failure_message(
		"a field effect must have no owner"
	).is_null()

	assert_bool(VltEffectDispatch.remove(state, weather, null)).is_true()
	assert_int(state.effects.size()).is_equal(0)


func test_every_registered_effect_is_exercised() -> void:
	# The meta-test of spec 06: an effect with no test is unverified content
	# wearing the costume of a feature.
	var covered: PackedStringArray = PackedStringArray([VltBurn.ID, VltReflect.ID])
	for id: String in _registry.ids():
		assert_bool(covered.has(id)).override_failure_message(
			"effect \"%s\" is registered but no test exercises it" % id
		).is_true()


func _collection_order(state: VltBattleState) -> PackedStringArray:
	var order: PackedStringArray = PackedStringArray()
	for active: VltEffectDispatch.Active in VltEffectDispatch.active_effects(state, _registry):
		var where: String = str(active.owner) if active.owner != null else "field"
		order.append("%s@%s" % [active.instance.definition_id, where])
	return order
