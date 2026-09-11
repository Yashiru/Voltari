extends GdUnitTestSuite

## The player's creatures, as a save section (spec 13, section 8).
##
## The third system to declare one, and the first whose contents are the point
## of the game — so the round trip has to carry everything a battle changed, not
## merely enough to look right.

const MOVE: String = "tackle"


func _creature(species: String, level: int) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 90, 80, 70, 60])
	input.ivs = PackedInt32Array([31, 30, 29, 28, 27, 26])
	input.evs = PackedInt32Array([4, 8, 12, 16, 20, 24])
	input.level = level
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var made: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["water", "normal"])
	)
	made.moves.append(VltMoveSlot.create(MOVE, 20))
	return made


func _sections(of: Array[VltSaveSection]) -> Array[VltSaveSection]:
	return of


func _round_trip(party: Array[VltBattleCreature]) -> Array[VltBattleCreature]:
	var document: Dictionary = VltSaveCodec.write(
		_sections([VltPartySaveSection.new(party)])
	)
	var read_back: VltPartySaveSection = VltPartySaveSection.new()
	VltSaveCodec.read(document, _sections([read_back]))
	return read_back.members


func test_a_party_survives_a_round_trip() -> void:
	var party: Array[VltBattleCreature] = [
		_creature("species_base", 12), _creature("species_evolved", 30)
	]

	var back: Array[VltBattleCreature] = _round_trip(party)

	assert_int(back.size()).is_equal(2)
	assert_str(back[0].species_id).is_equal("species_base")
	assert_int(back[1].level).is_equal(30)


func test_it_carries_what_a_battle_changed() -> void:
	# The reason a party section is not the same as a list of species: a save
	# that lost the wounds would give the player a free heal every time they
	# quit, which is a bug that plays as a feature until somebody notices.
	var creature: VltBattleCreature = _creature("species_base", 12)
	creature.current_hp -= 9
	creature.moves[0].pp -= 4
	creature.experience += 250

	var back: Array[VltBattleCreature] = _round_trip(
		[creature] as Array[VltBattleCreature]
	)

	assert_int(back[0].current_hp).is_equal(creature.current_hp)
	assert_int(back[0].moves[0].pp).is_equal(16)
	assert_int(back[0].experience).is_equal(creature.experience)


func test_it_reads_in_place() -> void:
	# The array handed over is the one that ends up holding the party, so
	# nothing has to be given back and nothing can be given back to the wrong
	# place.
	var mine: Array[VltBattleCreature] = []
	var section: VltPartySaveSection = VltPartySaveSection.new(mine)

	section.read({VltPartySaveSection.MEMBERS_FIELD: [
		_creature("species_base", 5).to_dict()
	]}, VltPartySaveSection.VERSION)

	assert_int(mine.size()).override_failure_message(
		"the party was read into somewhere else"
	).is_equal(1)


func test_an_empty_party_round_trips() -> void:
	# A new game, before anything is caught. It has to produce something
	# readable rather than nothing, or the first save of every playthrough
	# reads incomplete.
	assert_int(_round_trip([] as Array[VltBattleCreature]).size()).is_equal(0)


func test_a_creature_that_will_not_read_is_dropped_and_the_rest_kept() -> void:
	# The opposite of what a whole section does (decision 0036), and
	# deliberately: a party with a hole in the middle would renumber every
	# creature after it, and party indices are what a save's other halves point
	# at.
	var section: VltPartySaveSection = VltPartySaveSection.new()
	section.read({VltPartySaveSection.MEMBERS_FIELD: [
		_creature("species_base", 5).to_dict(),
		"this is not a creature",
		_creature("species_evolved", 9).to_dict(),
	]}, VltPartySaveSection.VERSION)

	assert_int(section.members.size()).is_equal(2)
	assert_str(section.members[1].species_id).is_equal("species_evolved")


func test_a_malformed_section_reads_as_no_party() -> void:
	var section: VltPartySaveSection = VltPartySaveSection.new()
	section.read({VltPartySaveSection.MEMBERS_FIELD: "not a list"}, 1)
	assert_int(section.members.size()).is_equal(0)


func test_a_party_survives_the_json_round_trip() -> void:
	# JSON turns every integer into a float. A creature is almost entirely
	# integers, so this is where that would show.
	var creature: VltBattleCreature = _creature("species_base", 12)
	creature.current_hp -= 5

	var document: Dictionary = VltSaveCodec.write(
		_sections([VltPartySaveSection.new([creature] as Array[VltBattleCreature])])
	)
	var through_json: Variant = JSON.parse_string(JSON.stringify(document))

	var section: VltPartySaveSection = VltPartySaveSection.new()
	@warning_ignore("unsafe_cast")
	VltSaveCodec.read(through_json as Dictionary, _sections([section]))

	assert_int(section.members[0].current_hp).is_equal(creature.current_hp)
	assert_int(section.members[0].level).is_equal(12)
