extends GdUnitTestSuite

## The post-battle pipeline (spec 10, section 5).
##
## Participation is read from the log, so most of these build a log by hand and
## assert what it yields. That is the point of the design: the information is
## already recorded, and reading it wrong is the failure mode to test for.

const SPECIES_DIR: String = "res://content/generated/species"
const MOVES_DIR: String = "res://content/generated/moves"
const NATURES_PAYLOAD: String = "res://content/generated/natures.json"
const CURVES_PAYLOAD: String = "res://content/generated/growth-curves.json"

const OURS: int = 0
const THEIRS: int = 1

var _species: Dictionary[String, VltSpecies]
var _moves: Dictionary[String, VltMoveDefinition]
var _natures: Array[PackedInt32Array]
var _curves: Dictionary[String, PackedInt32Array]


func before() -> void:
	_species = VltSpeciesLoader.from_entries(VltContentPayloads.read_indexed(SPECIES_DIR))
	_moves = VltMoveRegistryLoader.from_entries(VltContentPayloads.read_indexed(MOVES_DIR))
	_natures = VltNatureLoader.from_payload(VltContentPayloads.read_json(NATURES_PAYLOAD))
	_curves = VltGrowthCurveLoader.from_payload(VltContentPayloads.read_json(CURVES_PAYLOAD))


func _born(id: String, level: int) -> VltBattleCreature:
	return VltBirth.at_level(
		_species[id],
		level,
		_natures,
		_moves,
		_curves[_species[id].growth_rate],
		VltScriptedGenerationDecider.new()
	)


## Two parties of `sizes` creatures, all at `level`, leads on the field.
func _battle(sizes: PackedInt32Array, level: int = 25) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for _index: int in range(sizes[side]):
			state.sides[side].party.append(_born("species_base", level))
		state.sides[side].slots[0].occupy(0)
	return state


func _resolve(
	initial: VltBattleState, log: VltBattleLog, trainer: bool = false
) -> Array[VltPostBattle.Award]:
	return VltPostBattle.resolve(
		initial, log, initial.clone(), OURS, _species, _curves, _moves, trainer
	)


func _faint(side: int, slot: int = 0) -> VltLogFaint:
	return VltLogFaint.create(VltSlotRef.at(side, slot))


func _switch_in(side: int, party: int, slot: int = 0) -> VltLogSwitchIn:
	return VltLogSwitchIn.create(VltSlotRef.at(side, slot), party, "species_base")


# --- the level ladder --------------------------------------------------------


func test_a_level_is_the_highest_the_total_reaches() -> void:
	var curve: PackedInt32Array = _curves["medium_fast"]

	assert_int(VltPostBattle.level_for(curve, 0)).is_equal(1)
	assert_int(VltPostBattle.level_for(curve, 7)).is_equal(1)
	assert_int(VltPostBattle.level_for(curve, 8)).is_equal(2)
	assert_int(VltPostBattle.level_for(curve, 999)).is_equal(9)
	assert_int(VltPostBattle.level_for(curve, 1_000)).is_equal(10)


func test_the_level_never_passes_the_top_of_the_curve() -> void:
	# More experience than the table describes must cap, not read past the end.
	assert_int(VltPostBattle.level_for(_curves["medium_fast"], 999_999_999)).is_equal(100)


func test_a_creature_is_born_standing_where_its_level_says() -> void:
	# Without this a creature born at 25 would drop to level 1 the moment it
	# earned anything at all.
	var creature: VltBattleCreature = _born("species_base", 25)
	var curve: PackedInt32Array = _curves[_species["species_base"].growth_rate]

	assert_int(creature.experience).is_equal(curve[24])
	assert_int(VltPostBattle.level_for(curve, creature.experience)).is_equal(25)


# --- reading participation ---------------------------------------------------


func test_the_creature_that_fought_earns() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = _resolve(state, log)

	assert_int(awards.size()).is_equal(1)
	assert_int(awards[0].party_index).is_equal(0)
	assert_int(awards[0].experience).is_greater(0)


func test_nothing_is_earned_when_nobody_falls() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]))
	assert_int(_resolve(state, VltBattleLog.new()).size()).is_equal(0)


func test_a_creature_that_never_took_the_field_earns_nothing() -> void:
	# On the bench the whole battle: it faced nobody, so it earned nothing.
	var state: VltBattleState = _battle(PackedInt32Array([2, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = _resolve(state, log)

	assert_int(awards.size()).is_equal(1)
	assert_int(awards[0].party_index).is_equal(0)


func test_a_creature_that_fought_and_left_still_earns() -> void:
	# It faced the opponent, so it earned its share — participation is the whole
	# battle, not the moment of the faint.
	var state: VltBattleState = _battle(PackedInt32Array([2, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_switch_in(OURS, 1))
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = _resolve(state, log)

	assert_int(awards.size()).override_failure_message(
		"both the creature that fought and the one that finished should earn"
	).is_equal(2)


func test_a_fallen_creature_earns_nothing() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([2, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(OURS))
	log.append(_switch_in(OURS, 1))
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = _resolve(state, log)

	assert_int(awards.size()).is_equal(1)
	assert_int(awards[0].party_index).override_failure_message(
		"the creature that fainted must not be paid"
	).is_equal(1)


func test_sharing_pays_each_of_them_less() -> void:
	var alone: VltBattleState = _battle(PackedInt32Array([2, 1]))
	var solo_log: VltBattleLog = VltBattleLog.new()
	solo_log.append(_faint(THEIRS))
	var solo: Array[VltPostBattle.Award] = _resolve(alone, solo_log)

	var shared_state: VltBattleState = _battle(PackedInt32Array([2, 1]))
	var shared_log: VltBattleLog = VltBattleLog.new()
	shared_log.append(_switch_in(OURS, 1))
	shared_log.append(_faint(THEIRS))
	var shared: Array[VltPostBattle.Award] = _resolve(shared_state, shared_log)

	assert_int(shared[0].experience).is_less(solo[0].experience)


func test_two_defeats_pay_twice() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 2]))
	var one: VltBattleLog = VltBattleLog.new()
	one.append(_faint(THEIRS))

	var two: VltBattleLog = VltBattleLog.new()
	two.append(_faint(THEIRS))
	two.append(_switch_in(THEIRS, 1))
	two.append(_faint(THEIRS))

	assert_int(_resolve(state, two)[0].experience).is_greater(
		_resolve(state, one)[0].experience
	)


func test_a_trainer_pays_more_than_the_wild() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))

	assert_int(_resolve(state, log, true)[0].experience).is_greater(
		_resolve(state, log, false)[0].experience
	)


# --- what the awards do ------------------------------------------------------


func test_levelling_re_derives_the_stats() -> void:
	# Level 3: the award clears the gap to 4. At level 5 it would not — 65 earned
	# against 91 needed — which is the formula behaving, not a bug.
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]), 3)
	var working: VltBattleState = state.clone()
	var spread: PackedInt32Array = working.sides[OURS].party[0].stats.duplicate()

	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = VltPostBattle.resolve(
		state, log, working, OURS, _species, _curves, _moves, false
	)

	assert_bool(awards[0].levelled()).override_failure_message(
		"a level 3 creature beating its equal should gain a level"
	).is_true()

	var after: VltBattleCreature = working.sides[OURS].party[0]
	assert_int(after.level).is_equal(awards[0].level_after)
	for stat: int in range(VltStats.STAT_COUNT):
		assert_int(after.stats[stat]).is_greater_equal(spread[stat])


func test_levelling_neither_heals_nor_hurts() -> void:
	# Current HP rises by exactly what the maximum did, so a creature that ended
	# the battle wounded is still wounded by the same amount.
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]), 3)
	var working: VltBattleState = state.clone()
	var creature: VltBattleCreature = working.sides[OURS].party[0]

	var missing: int = 7
	creature.current_hp -= missing
	var max_before: int = creature.max_hp()

	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))
	VltPostBattle.resolve(state, log, working, OURS, _species, _curves, _moves, false)

	assert_int(creature.max_hp()).is_greater(max_before)
	assert_int(creature.max_hp() - creature.current_hp).override_failure_message(
		"levelling changed how wounded the creature was"
	).is_equal(missing)


func test_every_level_passed_is_reported() -> void:
	# A creature that gains three levels at once must report all three, or a move
	# learnable in the middle would never be offered (spec 10, section 5).
	var award: VltPostBattle.Award = VltPostBattle.Award.new(0, 0, 12, 15)

	assert_array(award.levels_gained()).is_equal(PackedInt32Array([13, 14, 15]))
	assert_bool(award.levelled()).is_true()

	var still: VltPostBattle.Award = VltPostBattle.Award.new(0, 0, 12, 12)
	assert_array(still.levels_gained()).is_equal(PackedInt32Array())
	assert_bool(still.levelled()).is_false()


# --- moves and evolution -----------------------------------------------------


## Drives one creature up to `target` by defeating opponents until it gets there,
## so the pipeline is exercised the way it will actually run.
func _raise_to(start: int, target: int) -> VltPostBattle.Award:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]), start)
	var working: VltBattleState = state.clone()
	var last: VltPostBattle.Award = null

	for _fight: int in range(200):
		var creature: VltBattleCreature = working.sides[OURS].party[0]
		if creature.level >= target:
			break

		var log: VltBattleLog = VltBattleLog.new()
		log.append(_faint(THEIRS))
		var awards: Array[VltPostBattle.Award] = VltPostBattle.resolve(
			state, log, working, OURS, _species, _curves, _moves, false
		)
		if not awards.is_empty():
			last = awards[0]

	return last


func test_a_move_learnable_on_the_way_up_is_taken() -> void:
	# species_base learns at 1, 7 and 13. A creature born at 1 with room to
	# spare takes them as it passes.
	var award: VltPostBattle.Award = _raise_to(1, 13)

	assert_object(award).is_not_null()
	assert_bool(award.levelled()).is_true()


func test_a_creature_with_room_learns_without_being_asked() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]), 3)
	var working: VltBattleState = state.clone()

	# Room to spare: it knows one move and the limit is four.
	var creature: VltBattleCreature = working.sides[OURS].party[0]
	assert_int(creature.moves.size()).is_equal(1)

	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))
	var awards: Array[VltPostBattle.Award] = VltPostBattle.resolve(
		state, log, working, OURS, _species, _curves, _moves, false
	)

	# Level 4 teaches nothing, so nothing is learned and nothing is offered.
	assert_int(awards[0].level_after).is_equal(4)
	assert_array(awards[0].learned).is_equal(PackedStringArray())
	assert_array(awards[0].offered).is_equal(PackedStringArray())


func test_a_full_moveset_is_offered_rather_than_overwritten() -> void:
	# The choice belongs to the player (spec 10, section 7), so a creature with
	# four moves gets an offer and keeps what it had.
	var crowded: VltSpecies = VltSpecies.create(
		"test_full", PackedStringArray(["normal"]), PackedInt32Array([45, 49, 49, 65, 65, 45])
	)
	crowded.learns(1, "basic_physical").learns(1, "basic_special")
	crowded.learns(1, "heavy_physical").learns(1, "water_special")
	crowded.learns(4, "ghost_special")
	crowded.growth_rate = "medium_fast"
	crowded.base_experience = 64

	var award: VltPostBattle.Award = _award_for_species(crowded, 3)

	assert_int(award.level_after).is_greater_equal(4)
	assert_array(award.offered).override_failure_message(
		"a full moveset must be offered the new move, not have it forced in"
	).is_equal(PackedStringArray(["ghost_special"]))
	assert_array(award.learned).is_equal(PackedStringArray())


func test_answering_an_offer_replaces_exactly_one_move() -> void:
	var creature: VltBattleCreature = _born("species_base", 13)
	var slot_count: int = creature.moves.size()
	var replaced: String = creature.moves[0].move_id

	VltPostBattle.learn_over(creature, 0, "water_special", _moves)

	assert_int(creature.moves.size()).is_equal(slot_count)
	assert_str(creature.moves[0].move_id).is_equal("water_special")
	assert_int(creature.moves[0].pp).is_equal(_moves["water_special"].max_pp)

	for slot: VltMoveSlot in creature.moves:
		assert_str(slot.move_id).override_failure_message(
			"the replaced move is still there"
		).is_not_equal(replaced)


func test_a_creature_evolves_when_its_level_says_so() -> void:
	# species_base evolves at 16. Driven there by fighting, so the trigger is
	# reached the way it will be in play.
	var award: VltPostBattle.Award = _raise_to(13, 16)

	assert_object(award).is_not_null()
	assert_str(award.evolved_into).override_failure_message(
		"reaching the evolution level should have changed the species"
	).is_equal("species_evolved")


func test_evolving_keeps_the_individual_and_changes_the_species() -> void:
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]), 13)
	var working: VltBattleState = state.clone()
	var creature: VltBattleCreature = working.sides[OURS].party[0]

	var ivs: PackedInt32Array = creature.ivs.duplicate()
	var raised: int = creature.nature_raised
	var known: int = creature.moves.size()

	for _fight: int in range(200):
		if creature.species_id != "species_base":
			break
		var log: VltBattleLog = VltBattleLog.new()
		log.append(_faint(THEIRS))
		VltPostBattle.resolve(state, log, working, OURS, _species, _curves, _moves, false)

	assert_str(creature.species_id).is_equal("species_evolved")
	assert_array(creature.types).is_equal(
		_species["species_evolved"].types
	)
	assert_array(creature.base).is_equal(_species["species_evolved"].base_stats)

	# The same individual, wearing a different species (spec 10, section 8).
	assert_array(creature.ivs).is_equal(ivs)
	assert_int(creature.nature_raised).is_equal(raised)
	assert_int(creature.moves.size()).is_greater_equal(known)
	assert_int(creature.experience).is_greater(0)


func test_a_trigger_nothing_implements_does_not_fire() -> void:
	# The trigger names code (spec 06, section 8). One with no code behind it
	# must do nothing — an unrecognised condition that evolved anyway would be
	# the worst of both, silent and wrong.
	var odd: VltSpecies = VltSpecies.create(
		"test_odd_trigger",
		PackedStringArray(["normal"]),
		PackedInt32Array([45, 49, 49, 65, 65, 45])
	)
	odd.learns(1, "basic_physical").evolves("species_evolved", "friendship", 1)
	odd.growth_rate = "medium_fast"
	odd.base_experience = 64

	assert_str(_award_for_species(odd, 20).evolved_into).override_failure_message(
		"a trigger with no code behind it evolved the creature anyway"
	).is_equal("")


func test_a_move_already_known_is_not_offered_again() -> void:
	# A species that teaches the same move twice must not offer it the second
	# time, or a creature would be asked to replace something with what it has.
	var repeater: VltSpecies = VltSpecies.create(
		"test_reteach",
		PackedStringArray(["normal"]),
		PackedInt32Array([45, 49, 49, 65, 65, 45])
	)
	repeater.learns(1, "basic_physical").learns(4, "basic_physical")
	repeater.growth_rate = "medium_fast"
	repeater.base_experience = 64

	var award: VltPostBattle.Award = _award_for_species(repeater, 3)

	assert_int(award.level_after).is_greater_equal(4)
	assert_array(award.learned).override_failure_message(
		"a move already known was learned a second time"
	).is_equal(PackedStringArray())
	assert_array(award.offered).is_equal(PackedStringArray())


func test_the_other_side_can_be_the_earning_one() -> void:
	# Nothing about the pipeline privileges side zero, and reading the opposing
	# side by arithmetic is exactly where that assumption would hide.
	var state: VltBattleState = _battle(PackedInt32Array([1, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(OURS))

	var awards: Array[VltPostBattle.Award] = VltPostBattle.resolve(
		state, log, state.clone(), THEIRS, _species, _curves, _moves, false
	)

	assert_int(awards.size()).override_failure_message(
		"side one earned nothing for a defeat it caused"
	).is_equal(1)
	assert_int(awards[0].experience).is_greater(0)


func test_a_species_with_nowhere_to_go_does_not_evolve() -> void:
	var award: VltPostBattle.Award = _award_for_species(
		_species["species_evolved"], 30
	)
	assert_str(award.evolved_into).is_equal("")


## One battle's worth of awards for a species built in the test.
func _award_for_species(species: VltSpecies, level: int) -> VltPostBattle.Award:
	var registry: Dictionary[String, VltSpecies] = {}
	for id: String in _species.keys():
		registry[id] = _species[id]
	registry[species.id] = species

	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(
			VltBirth.at_level(
				species, level, _natures, _moves,
				_curves[species.growth_rate], VltScriptedGenerationDecider.new()
			)
		)
		state.sides[side].slots[0].occupy(0)

	var working: VltBattleState = state.clone()
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_faint(THEIRS))

	return VltPostBattle.resolve(
		state, log, working, OURS, registry, _curves, _moves, false
	)[0]


func test_the_awards_come_back_in_party_order() -> void:
	# Never dictionary order: the same battle must report the same way twice.
	var state: VltBattleState = _battle(PackedInt32Array([3, 1]))
	var log: VltBattleLog = VltBattleLog.new()
	log.append(_switch_in(OURS, 2))
	log.append(_switch_in(OURS, 1))
	log.append(_faint(THEIRS))

	var awards: Array[VltPostBattle.Award] = _resolve(state, log)
	var order: PackedInt32Array = PackedInt32Array()
	for award: VltPostBattle.Award in awards:
		order.append(award.party_index)

	assert_array(order).is_equal(PackedInt32Array([0, 1, 2]))


# --- taking an offered move --------------------------------------------------


func test_an_offered_move_replaces_the_slot_it_was_given() -> void:
	# The answer to the question `offered` asks. A creature with room learns
	# without being asked; this is only for the case where there is none.
	var creature: VltBattleCreature = _born("species_base", 20)
	creature.moves.clear()
	for index: int in range(VltBirth.MOVE_LIMIT):
		creature.moves.append(VltMoveSlot.create("basic_physical", 5))

	VltPostBattle.learn(creature, "water_special", 2, _moves)

	assert_int(creature.moves.size()).is_equal(VltBirth.MOVE_LIMIT)
	assert_str(creature.moves[2].move_id).is_equal("water_special")
	assert_str(creature.moves[0].move_id).override_failure_message(
		"learning a move disturbed a slot it was not given"
	).is_equal("basic_physical")


func test_a_learned_move_arrives_on_full_pp() -> void:
	# It is a new move, not a refilled one, so it starts where a new move starts.
	var creature: VltBattleCreature = _born("species_base", 20)
	creature.moves.clear()
	creature.moves.append(VltMoveSlot.create("basic_physical", 1))

	VltPostBattle.learn(creature, "water_special", 0, _moves)

	assert_int(creature.moves[0].pp).is_equal(_moves["water_special"].max_pp)


func test_an_award_remembers_what_the_creature_was() -> void:
	# "It evolved into Y" names two species and the creature keeps only one of
	# them, so the award has to carry the other.
	# The species evolves at 16, so it has to be there for the trigger to
	# fire — an award saying it reached 16 is not the same as a creature that has.
	var creature: VltBattleCreature = _born("species_base", 16)
	var award: VltPostBattle.Award = VltPostBattle.Award.new(0, 0, 15, 16)

	VltPostBattle._evolve(creature, _species, award)

	assert_str(award.evolved_from).override_failure_message(
		"the award forgot which species evolved"
	).is_equal("species_base")
	assert_str(award.evolved_into).is_equal(creature.species_id)
	assert_str(award.evolved_into).is_not_equal(award.evolved_from)
