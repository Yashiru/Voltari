extends GdUnitTestSuite

## Birth: a creature at a level, from a species (spec 10, section 2).

const SPECIES_DIR: String = "res://content/generated/species"
const MOVES_DIR: String = "res://content/generated/moves"
const NATURES_PAYLOAD: String = "res://content/generated/natures.json"
const CURVES_PAYLOAD: String = "res://content/generated/growth-curves.json"

var _species: Dictionary[String, VltSpecies]
var _moves: Dictionary[String, VltMoveDefinition]
var _natures: Array[PackedInt32Array]
var _curves: Dictionary[String, PackedInt32Array]


func before() -> void:
	_species = VltSpeciesLoader.from_entries(VltContentPayloads.read_indexed(SPECIES_DIR))
	_moves = VltMoveRegistryLoader.from_entries(VltContentPayloads.read_indexed(MOVES_DIR))
	_natures = VltNatureLoader.from_payload(VltContentPayloads.read_json(NATURES_PAYLOAD))
	_curves = VltGrowthCurveLoader.from_payload(VltContentPayloads.read_json(CURVES_PAYLOAD))


func _decider(iv: int = 31, nature: int = 0) -> VltScriptedGenerationDecider:
	var decider: VltScriptedGenerationDecider = VltScriptedGenerationDecider.new(iv)
	decider.nature_index = nature
	return decider


func _curve_of(id: String) -> PackedInt32Array:
	return _curves[_species[id].growth_rate]


func _born(id: String, level: int, decider: VltGenerationDecider) -> VltBattleCreature:
	return VltBirth.at_level(_species[id], level, _natures, _moves, _curve_of(id), decider)


func test_the_authored_species_load() -> void:
	assert_int(_species.size()).is_greater(0)
	for id: String in _species.keys():
		var species: VltSpecies = _species[id]
		assert_str(species.id).is_equal(id)
		assert_int(species.types.size()).is_between(1, 2)
		assert_int(species.base_stats.size()).is_equal(VltStats.STAT_COUNT)


func test_the_genderless_sentinel_cannot_be_a_real_ratio() -> void:
	# A gender ratio is eighths female, 0 to 8. If the sentinel ever fell inside
	# that range, a species with no gender would silently read as one-eighth
	# female — the same trap NO_SIDE carries in the log, and the same guard.
	assert_int(VltSpecies.GENDERLESS).override_failure_message(
		"GENDERLESS must sit outside the range of real ratios"
	).is_less(0)

	for eighths: int in range(9):
		assert_int(VltSpecies.GENDERLESS).is_not_equal(eighths)

	# And the authored species that declares none reads back as none.
	assert_int(_species["species_genderless"].gender_ratio).is_equal(VltSpecies.GENDERLESS)
	assert_int(_species["species_base"].gender_ratio).is_equal(4)


func test_a_creature_is_born_complete() -> void:
	# Nothing may be left to decide later: a half-built creature reaching the
	# core is a defect the core has no vocabulary to describe.
	var creature: VltBattleCreature = _born("species_base", 25, _decider())

	assert_str(creature.species_id).is_equal("species_base")
	assert_int(creature.level).is_equal(25)
	assert_int(creature.stats.size()).is_equal(VltStats.STAT_COUNT)
	assert_int(creature.current_hp).is_equal(creature.max_hp())
	assert_bool(creature.is_fainted()).is_false()
	assert_int(creature.moves.size()).is_greater(0)

	for stat: int in range(VltStats.STAT_COUNT):
		assert_int(creature.stats[stat]).override_failure_message(
			"stat %d was not derived" % stat
		).is_greater(0)


func test_the_same_answers_give_the_same_creature() -> void:
	# The property the whole decision interface exists for: no draw, so a birth
	# is reproducible from what was declared.
	var first: VltBattleCreature = _born("species_base", 40, _decider(17, 3))
	var second: VltBattleCreature = _born("species_base", 40, _decider(17, 3))

	assert_str(JSON.stringify(first.to_dict())).is_equal(JSON.stringify(second.to_dict()))


func test_the_individual_values_reach_the_stats() -> void:
	# A creature born with perfect values must outclass one born with none, or
	# the decider's answers are being collected and thrown away.
	var perfect: VltBattleCreature = _born("species_base", 50, _decider(31))
	var poorest: VltBattleCreature = _born("species_base", 50, _decider(0))

	for stat: int in range(VltStats.STAT_COUNT):
		assert_int(perfect.stats[stat]).override_failure_message(
			"stat %d ignored its individual value" % stat
		).is_greater(poorest.stats[stat])


func test_the_nature_reaches_the_stats() -> void:
	# Every nature in the table produces a creature, and at least one of them
	# moves a stat away from neutral.
	var spreads: Array[String] = []
	for index: int in range(_natures.size()):
		var creature: VltBattleCreature = _born("species_base", 50, _decider(31, index))
		spreads.append(str(creature.stats))

	assert_int(spreads.size()).is_equal(_natures.size())
	var distinct: Dictionary[String, bool] = {}
	for spread: String in spreads:
		distinct[spread] = true
	assert_int(distinct.size()).override_failure_message(
		"every nature produced the same spread, so none of them applied"
	).is_greater(1)


func test_a_creature_knows_the_moves_of_its_level() -> void:
	var early: VltBattleCreature = _born("species_base", 1, _decider())
	assert_int(early.moves.size()).is_equal(1)
	assert_str(early.moves[0].move_id).is_equal("basic_physical")

	var later: VltBattleCreature = _born("species_base", 13, _decider())
	assert_int(later.moves.size()).is_equal(3)


func test_a_move_starts_on_full_pp() -> void:
	var creature: VltBattleCreature = _born("species_base", 13, _decider())
	for slot: VltMoveSlot in creature.moves:
		assert_int(slot.pp).is_equal(_moves[slot.move_id].max_pp)
		assert_int(slot.pp).is_greater(0)


func test_only_the_last_four_moves_are_kept() -> void:
	# Built here rather than taken from the roster: no authored species learns
	# five moves yet, and a rule that only holds because nothing exercises it is
	# not a rule that has been tested.
	var crowded: VltSpecies = VltSpecies.create(
		"test_crowded",
		PackedStringArray(["normal"]),
		PackedInt32Array([100, 100, 100, 100, 100, 100])
	)
	crowded.learns(1, "basic_physical").learns(5, "basic_special")
	crowded.learns(9, "heavy_physical").learns(13, "water_special")
	crowded.learns(17, "ghost_special")

	var creature: VltBattleCreature = VltBirth.at_level(
		crowded, 20, _natures, _moves, _curve_of("species_base"), _decider()
	)

	assert_int(creature.moves.size()).is_equal(VltBirth.MOVE_LIMIT)
	var kept: PackedStringArray = PackedStringArray()
	for slot: VltMoveSlot in creature.moves:
		kept.append(slot.move_id)
	assert_array(kept).override_failure_message(
		"the earliest move should have been dropped, not the latest"
	).is_equal(
		PackedStringArray(["basic_special", "heavy_physical", "water_special", "ghost_special"])
	)


func test_a_move_learned_twice_occupies_one_slot() -> void:
	# A creature holding one move in two slots would be a defect nothing else
	# could explain.
	var repeater: VltSpecies = VltSpecies.create(
		"test_repeater",
		PackedStringArray(["normal"]),
		PackedInt32Array([100, 100, 100, 100, 100, 100])
	)
	repeater.learns(1, "basic_physical").learns(5, "basic_special")
	repeater.learns(9, "basic_physical")

	var creature: VltBattleCreature = VltBirth.at_level(
		repeater, 10, _natures, _moves, _curve_of("species_base"), _decider()
	)

	assert_int(creature.moves.size()).is_equal(2)
	# Relearned, so it takes the later position rather than the earlier one.
	assert_str(creature.moves[0].move_id).is_equal("basic_special")
	assert_str(creature.moves[1].move_id).is_equal("basic_physical")

	# Again with the repeat sitting further along the list. The first case only
	# ever finds it at position zero, and a check that happened to compare
	# against the wrong sentinel would pass that and duplicate this one.
	var later: VltSpecies = VltSpecies.create(
		"test_later_repeat",
		PackedStringArray(["normal"]),
		PackedInt32Array([100, 100, 100, 100, 100, 100])
	)
	later.learns(1, "basic_physical").learns(5, "basic_special")
	later.learns(9, "basic_special")

	var second: VltBattleCreature = VltBirth.at_level(later, 10, _natures, _moves, _curve_of("species_base"), _decider())

	assert_int(second.moves.size()).override_failure_message(
		"the relearned move was kept twice"
	).is_equal(2)
	assert_str(second.moves[0].move_id).is_equal("basic_physical")
	assert_str(second.moves[1].move_id).is_equal("basic_special")
