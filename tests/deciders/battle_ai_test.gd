extends GdUnitTestSuite

## The opponent's policy (spec 12).
##
## Every parameter owes a test showing what it changes: a parameter nobody can
## see the effect of is a parameter nobody can tune.

const OURS: int = 0
const THEIRS: int = 1

const WEAK: String = "weak"
const STRONG: String = "strong"
const RESISTED: String = "resisted"
const IMMUNE: String = "immune"
const STATUS: String = "status"

var _moves: Dictionary[String, VltMoveDefinition]
var _species: Dictionary[String, VltSpecies]
var _chart: VltTypeChart


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(
		VltContentPayloads.read_json("res://content/generated/type-chart.json")
	)
	_moves = {
		WEAK: VltMoveDefinition.create(
			WEAK, "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
		STRONG: VltMoveDefinition.create(
			STRONG, "normal", VltMoveDefinition.Category.PHYSICAL, 120,
			VltMoveDefinition.ALWAYS_HITS
		),
		RESISTED: VltMoveDefinition.create(
			RESISTED, "fire", VltMoveDefinition.Category.SPECIAL, 120,
			VltMoveDefinition.ALWAYS_HITS
		),
		IMMUNE: VltMoveDefinition.create(
			IMMUNE, "normal", VltMoveDefinition.Category.PHYSICAL, 150,
			VltMoveDefinition.ALWAYS_HITS
		),
		STATUS: VltMoveDefinition.create(
			STATUS, "normal", VltMoveDefinition.Category.STATUS, 0,
			VltMoveDefinition.ALWAYS_HITS
		),
	}

	_species = {}
	_species["attacker"] = VltSpecies.create(
		"attacker", PackedStringArray(["normal"]), PackedInt32Array([120, 120, 90, 90, 90, 90])
	)
	_species["defender"] = VltSpecies.create(
		"defender", PackedStringArray(["water"]), PackedInt32Array([120, 90, 90, 90, 90, 90])
	)
	_species["ghost"] = VltSpecies.create(
		"ghost", PackedStringArray(["ghost"]), PackedInt32Array([120, 90, 90, 90, 90, 90])
	)


func _creature(species: String, move_ids: Array[String]) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = _species[species].base_stats
	input.ivs = PackedInt32Array([15, 15, 15, 15, 15, 15])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, _species[species].types
	)
	for id: String in move_ids:
		creature.moves.append(VltMoveSlot.create(id, 10))
	return creature


## The view needs one to tell a major status from any other effect.
func _registry() -> VltEffectRegistry:
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	return registry


func _battle(mine: Array[String], defender: String = "defender") -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	state.sides[OURS].party.append(_creature("attacker", mine))
	var theirs: Array[String] = [WEAK]
	state.sides[THEIRS].party.append(_creature(defender, theirs))
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].slots[0].occupy(0)
	return state


func _choose(
	state: VltBattleState,
	difficulty: VltBattleAi.Difficulty,
	decider: VltPolicyDecider = VltScriptedPolicyDecider.new()
) -> VltCommand:
	return VltBattleAi.choose(
		VltBattleView.of(state, _registry(), OURS), 0, _moves, _species, _chart, difficulty, decider
	)


func _chosen_move(state: VltBattleState, command: VltCommand) -> String:
	return state.creature_at(VltSlotRef.at(OURS, 0)).moves[command.move_index].move_id


# --- it plays well -----------------------------------------------------------


func test_it_takes_the_move_that_hurts_most() -> void:
	var ids: Array[String] = [WEAK, STRONG]
	var state: VltBattleState = _battle(ids)

	var command: VltCommand = _choose(state, VltBattleAi.expert())
	assert_str(_chosen_move(state, command)).is_equal(STRONG)


func test_it_reads_the_type_chart_not_the_power() -> void:
	# A resisted 120 must lose to a neutral 40, or the AI is reading numbers off
	# the move rather than estimating what it would do.
	var ids: Array[String] = [WEAK, RESISTED]
	var state: VltBattleState = _battle(ids)

	assert_str(_chosen_move(state, _choose(state, VltBattleAi.expert()))).is_equal(WEAK)


func test_it_never_throws_a_move_the_target_is_immune_to() -> void:
	var ids: Array[String] = [WEAK, IMMUNE]
	var state: VltBattleState = _battle(ids, "ghost")

	assert_str(_chosen_move(state, _choose(state, VltBattleAi.expert()))).is_equal(WEAK)


func test_a_lethal_hit_is_not_beaten_by_a_bigger_one() -> void:
	# Overkill is worth no more than a kill. Without the cap the AI would pass up
	# a move that already wins for one that wins by more.
	var ids: Array[String] = [WEAK, STRONG]
	var state: VltBattleState = _battle(ids)
	state.creature_at(VltSlotRef.at(THEIRS, 0)).current_hp = 1

	var command: VltCommand = _choose(
		state, VltBattleAi.expert(), VltScriptedPolicyDecider.new(true, 0)
	)
	# Both kill, so both tie for best and the decider picks the first.
	assert_str(_chosen_move(state, command)).is_equal(WEAK)


func test_it_skips_a_move_with_no_pp() -> void:
	var ids: Array[String] = [WEAK, STRONG]
	var state: VltBattleState = _battle(ids)
	state.creature_at(VltSlotRef.at(OURS, 0)).moves[1].pp = 0

	assert_str(_chosen_move(state, _choose(state, VltBattleAi.expert()))).is_equal(WEAK)


func test_it_skips_a_move_the_registry_does_not_know() -> void:
	# Both halves of the guard hold on their own: PP left is not enough if the
	# move is not in the registry, and being in the registry is not enough with
	# no PP. Reaching for an unknown move would fail somewhere far from here.
	var ids: Array[String] = [WEAK]
	var state: VltBattleState = _battle(ids)
	state.creature_at(VltSlotRef.at(OURS, 0)).moves.append(
		VltMoveSlot.create("not_in_the_registry", 10)
	)

	var command: VltCommand = _choose(state, VltBattleAi.expert())
	assert_str(_chosen_move(state, command)).override_failure_message(
		"the AI reached for a move nothing declares"
	).is_equal(WEAK)


func test_it_aims_past_a_position_with_nobody_standing_in_it() -> void:
	# Both halves again, and only a wider field can show them: an empty slot and
	# a fallen occupant are different reasons not to aim there, and either one
	# alone must be enough. Singles never poses it, because the only opponent is
	# the one that is there.
	var state: VltBattleState = VltBattleState.create(2)
	var ids: Array[String] = [WEAK]
	for slot: int in range(2):
		state.sides[OURS].party.append(_creature("attacker", ids))
		state.sides[THEIRS].party.append(_creature("defender", ids))
		state.sides[OURS].slots[slot].occupy(slot)
		state.sides[THEIRS].slots[slot].occupy(slot)

	# Nobody in the first position at all.
	state.sides[THEIRS].slots[0].vacate()
	var past_empty: VltCommand = _choose(state, VltBattleAi.expert())
	assert_int(past_empty.target.slot).override_failure_message(
		"the AI aimed at an empty position"
	).is_equal(1)

	# Someone there, but already down.
	state.sides[THEIRS].slots[0].occupy(0)
	state.creature_at(VltSlotRef.at(THEIRS, 0)).current_hp = 0
	var past_fallen: VltCommand = _choose(state, VltBattleAi.expert())
	assert_int(past_fallen.target.slot).override_failure_message(
		"the AI aimed at a creature that had already fallen"
	).is_equal(1)


# --- each parameter changes something ----------------------------------------


func test_confidence_decides_whether_it_plays_the_best_line() -> void:
	var ids: Array[String] = [WEAK, STRONG]
	var state: VltBattleState = _battle(ids)

	var plays_best: VltCommand = _choose(
		state, VltBattleAi.expert(), VltScriptedPolicyDecider.new(true, 0)
	)
	var wanders: VltCommand = _choose(
		state, VltBattleAi.reckless(), VltScriptedPolicyDecider.new(false, 0)
	)

	assert_str(_chosen_move(state, plays_best)).is_equal(STRONG)
	assert_str(_chosen_move(state, wanders)).override_failure_message(
		"a decider that declined the best line still took it"
	).is_equal(WEAK)


func test_status_worth_decides_whether_a_status_move_is_ever_chosen() -> void:
	# Against a target it can barely dent, a status move is worth taking — but
	# only if the difficulty says a status is worth anything at all.
	var ids: Array[String] = [WEAK, STATUS]
	var state: VltBattleState = _battle(ids)
	state.creature_at(VltSlotRef.at(THEIRS, 0)).stats[VltStats.Stat.DEF] = 9999

	var values_it: VltBattleAi.Difficulty = VltBattleAi.Difficulty.new(100, 40)
	var does_not: VltBattleAi.Difficulty = VltBattleAi.Difficulty.new(100, 0)

	assert_str(_chosen_move(state, _choose(state, values_it))).is_equal(STATUS)
	assert_str(_chosen_move(state, _choose(state, does_not))).override_failure_message(
		"a difficulty that values statuses at nothing still chose one"
	).is_equal(WEAK)


func test_the_presets_differ_from_one_another() -> void:
	# Three names for one behaviour would be three ways of saying nothing.
	assert_int(VltBattleAi.reckless().confidence).is_less(VltBattleAi.plain().confidence)
	assert_int(VltBattleAi.plain().confidence).is_less(VltBattleAi.expert().confidence)
	assert_int(VltBattleAi.reckless().status_worth).is_less(VltBattleAi.expert().status_worth)


# --- the guarantees ----------------------------------------------------------


func test_the_same_view_and_answers_give_the_same_command() -> void:
	var ids: Array[String] = [WEAK, STRONG, STATUS]
	var state: VltBattleState = _battle(ids)

	var first: VltCommand = _choose(state, VltBattleAi.plain())
	for _repeat: int in range(20):
		var again: VltCommand = _choose(state, VltBattleAi.plain())
		assert_int(again.move_index).is_equal(first.move_index)
		assert_bool(again.target.equals(first.target)).is_true()


func test_a_tie_goes_to_the_decider_not_to_declaration_order() -> void:
	var ids: Array[String] = [WEAK, WEAK]
	var state: VltBattleState = _battle(ids)

	var first: VltCommand = _choose(
		state, VltBattleAi.expert(), VltScriptedPolicyDecider.new(true, 0)
	)
	var second: VltCommand = _choose(
		state, VltBattleAi.expert(), VltScriptedPolicyDecider.new(true, 1)
	)

	assert_int(first.move_index).is_equal(0)
	assert_int(second.move_index).override_failure_message(
		"two equal moves were settled by which was declared first"
	).is_equal(1)


func test_the_estimate_and_the_engine_never_forked() -> void:
	# What decision 0035 rests on. The AI predicts with the same pipeline the
	# engine runs; playing its choice must deal what it predicted. Without this,
	# sharing the code is an intention rather than a fact — the two could still
	# be handed different arguments.
	var ids: Array[String] = [STRONG]
	var state: VltBattleState = _battle(ids)

	var view: VltBattleView = VltBattleView.of(state, _registry(), OURS)
	var predicted: int = VltBattleAi._score(
		view.mine[0], view.theirs[0], _moves[STRONG], _species, _chart,
		VltBattleAi.expert()
	)

	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = VltBattleAi.AVERAGE_ROLL - 85
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER

	var outcome: VltTurnOutcome = VltTurnEngine.new(_moves, _chart).resolve(
		state, [_choose(state, VltBattleAi.expert())], decider
	)

	var dealt: int = 0
	for event: VltLogEvent in outcome.log.events:
		if event.kind() == VltLogDamage.KIND:
			dealt = (event as VltLogDamage).amount

	assert_int(dealt).override_failure_message(
		"the AI predicted %d and the engine dealt %d" % [predicted, dealt]
	).is_equal(predicted)
