extends GdUnitTestSuite

## What a side can perceive (spec 12, section 2).
##
## The load-bearing tests here are the ones about what is ABSENT. A view widens
## by convenience, one field at a time, and each widening looks reasonable on its
## own — so every field the AI must not see gets a test saying it cannot.

const OURS: int = 0
const THEIRS: int = 1
const TACKLE: String = "tackle"
const SECRET: String = "secret_move"


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 90, 80, 70, 60])
	input.ivs = PackedInt32Array([31, 30, 29, 28, 27, 26])
	input.evs = PackedInt32Array([4, 8, 12, 16, 20, 24])
	input.level = 50
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["water", "normal"])
	)
	creature.moves.append(VltMoveSlot.create(TACKLE, 20))
	creature.moves.append(VltMoveSlot.create(SECRET, 10))
	return creature


func _battle(slots: int = 1) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(slots)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for index: int in range(slots):
			state.sides[side].party.append(_creature("species_%d_%d" % [side, index]))
			state.sides[side].slots[index].occupy(index)
	return state


# --- what it shows -----------------------------------------------------------


func test_your_own_creature_is_shown_exactly() -> void:
	var state: VltBattleState = _battle()
	var creature: VltBattleCreature = state.creature_at(VltSlotRef.at(OURS, 0))
	creature.current_hp -= 13

	var mine: VltBattleView.Combatant = VltBattleView.of(state, OURS).mine[0]

	assert_bool(mine.knows_exact_health()).is_true()
	assert_int(mine.current_hp).is_equal(creature.current_hp)
	assert_int(mine.max_hp).is_equal(creature.max_hp())
	assert_array(mine.stats).is_equal(creature.stats)
	assert_int(mine.moves.size()).is_equal(2)
	assert_int(mine.moves[0].pp).is_equal(20)


func test_both_sides_show_what_is_announced() -> void:
	# Species, types, level, status and stat stages are all perceived in play,
	# so hiding them would make the AI blinder than a player.
	var state: VltBattleState = _battle()
	state.creature_at(VltSlotRef.at(THEIRS, 0)).status = VltBattleCreature.Status.BURN
	state.slot_at(VltSlotRef.at(THEIRS, 0)).set_stage(VltStats.Stat.ATK, -2)

	var theirs: VltBattleView.Combatant = VltBattleView.of(state, OURS).theirs[0]

	assert_bool(theirs.present).is_true()
	assert_str(theirs.species_id).is_equal("species_1_0")
	assert_array(theirs.types).is_equal(PackedStringArray(["water", "normal"]))
	assert_int(theirs.level).is_equal(50)
	assert_int(theirs.status).is_equal(VltBattleCreature.Status.BURN)
	assert_int(theirs.stat_stages[VltStats.Stat.ATK]).is_equal(-2)


func test_health_reads_as_a_proportion_for_both() -> void:
	var state: VltBattleState = _battle()
	var creature: VltBattleCreature = state.creature_at(VltSlotRef.at(THEIRS, 0))
	creature.current_hp = creature.max_hp() / 2

	var view: VltBattleView = VltBattleView.of(state, OURS)

	assert_int(view.theirs[0].health).is_between(49, 51)
	assert_int(view.mine[0].health).is_equal(100)


func test_a_survivor_never_reads_as_dead() -> void:
	# The same rule the log follows: rounding a sliver to nothing would say a
	# creature is dead when it is not.
	var state: VltBattleState = _battle()
	state.creature_at(VltSlotRef.at(THEIRS, 0)).current_hp = 1

	var theirs: VltBattleView.Combatant = VltBattleView.of(state, OURS).theirs[0]

	assert_int(theirs.health).is_equal(1)
	assert_bool(theirs.fainted).is_false()


func test_an_empty_slot_is_absent_not_blank() -> void:
	var state: VltBattleState = _battle()
	state.slot_at(VltSlotRef.at(THEIRS, 0)).vacate()

	var theirs: VltBattleView.Combatant = VltBattleView.of(state, OURS).theirs[0]

	assert_bool(theirs.present).is_false()
	assert_str(theirs.species_id).is_empty()


# --- what it hides -----------------------------------------------------------


func test_the_opponents_exact_health_is_not_there() -> void:
	var state: VltBattleState = _battle()
	var theirs: VltBattleView.Combatant = VltBattleView.of(state, OURS).theirs[0]

	assert_bool(theirs.knows_exact_health()).override_failure_message(
		"the view handed over exact health for the other side"
	).is_false()
	assert_int(theirs.current_hp).is_equal(VltBattleView.Combatant.UNKNOWN)
	assert_int(theirs.max_hp).is_equal(VltBattleView.Combatant.UNKNOWN)


func test_the_opponents_stats_are_not_there() -> void:
	# Which is what stops the AI reading individual values and effort through
	# the derived spread.
	var theirs: VltBattleView.Combatant = VltBattleView.of(_battle(), OURS).theirs[0]

	assert_bool(theirs.stats.is_empty()).override_failure_message(
		"the view handed over the other side's derived stats"
	).is_true()


func test_an_unseen_move_is_not_there() -> void:
	var state: VltBattleState = _battle()

	var blind: VltBattleView.Combatant = VltBattleView.of(state, OURS).theirs[0]
	assert_bool(blind.moves.is_empty()).is_true()
	assert_array(blind.revealed_moves).override_failure_message(
		"a move nobody has seen was handed over"
	).is_equal(PackedStringArray())

	var seen: VltBattleView.Combatant = VltBattleView.of(
		state, OURS, PackedStringArray([TACKLE])
	).theirs[0]
	assert_array(seen.revealed_moves).is_equal(PackedStringArray([TACKLE]))
	assert_bool(seen.revealed_moves.has(SECRET)).override_failure_message(
		"an unrevealed move leaked in with a revealed one"
	).is_false()


func test_the_opposing_bench_is_not_there() -> void:
	# The view carries positions, never parties. An AI cannot count what is left
	# to send out, because a player cannot either.
	var state: VltBattleState = _battle()
	state.sides[THEIRS].party.append(_creature("hidden_reserve"))

	var view: VltBattleView = VltBattleView.of(state, OURS)

	assert_int(view.theirs.size()).is_equal(state.slots_per_side())
	for combatant: VltBattleView.Combatant in view.theirs:
		assert_str(combatant.species_id).is_not_equal("hidden_reserve")


# --- the shape of it ---------------------------------------------------------


func test_the_two_viewpoints_mirror_each_other() -> void:
	var state: VltBattleState = _battle()

	var ours: VltBattleView = VltBattleView.of(state, OURS)
	var theirs: VltBattleView = VltBattleView.of(state, THEIRS)

	assert_str(ours.mine[0].species_id).is_equal(theirs.theirs[0].species_id)
	assert_str(ours.theirs[0].species_id).is_equal(theirs.mine[0].species_id)
	assert_bool(ours.mine[0].knows_exact_health()).is_true()
	assert_bool(theirs.theirs[0].knows_exact_health()).is_false()


func test_a_view_covers_every_position() -> void:
	var view: VltBattleView = VltBattleView.of(_battle(2), OURS)

	assert_int(view.mine.size()).is_equal(2)
	assert_int(view.theirs.size()).is_equal(2)
	for slot: int in range(2):
		assert_int(view.mine[slot].reference.slot).is_equal(slot)
		assert_int(view.mine[slot].reference.side).is_equal(OURS)
		assert_int(view.theirs[slot].reference.side).is_equal(THEIRS)


func test_a_view_is_a_copy_and_not_a_window() -> void:
	# Holding a view must not be a way to reach the battle. Changing the state
	# after the fact leaves the view as it was.
	var state: VltBattleState = _battle()
	var view: VltBattleView = VltBattleView.of(state, OURS)
	var before: int = view.mine[0].current_hp

	state.creature_at(VltSlotRef.at(OURS, 0)).current_hp -= 20
	state.slot_at(VltSlotRef.at(OURS, 0)).set_stage(VltStats.Stat.SPE, 3)

	assert_int(view.mine[0].current_hp).is_equal(before)
	assert_int(view.mine[0].stat_stages[VltStats.Stat.SPE]).is_equal(0)
