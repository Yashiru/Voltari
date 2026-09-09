extends GdUnitTestSuite

## The first real save section (spec 14, section 8; decision 0040).
##
## It proves the conversion, not the world. A section can round-trip perfectly
## while reading the wrong node, so this guards the save format and leaves the
## world's behaviour to the world's own tests.


func _walker(at: Vector2i, turned: VltFacing.Direction) -> VltGridWalker:
	var map: VltWorldMap = auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(5, 5)))
	)
	var walker: VltGridWalker = auto_free(VltGridWalker.new())
	walker.map = map
	walker.place(at, turned)
	return walker


func _sections(of: Array[VltSaveSection]) -> Array[VltSaveSection]:
	return of


## A written section is a dictionary of Variants. Narrowing it here keeps the
## casts in one place, the way the loaders do.
@warning_ignore_start("unsafe_cast")
func _int_in(written: Dictionary, field: String) -> int:
	return written[field] as int


func _string_in(written: Dictionary, field: String) -> String:
	return written[field] as String
@warning_ignore_restore("unsafe_cast")


func test_the_world_round_trips() -> void:
	# Declaring a section earns this test rather than remembering to write one
	# (spec 13, section 8).
	var live: VltWorldSaveSection = VltWorldSaveSection.new(
		_walker(Vector2i(3, 2), VltFacing.Direction.WEST)
	)
	var document: Dictionary = VltSaveCodec.write(_sections([live]))

	var read_back: VltWorldSaveSection = VltWorldSaveSection.new()
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([read_back]))

	assert_bool(report.complete()).is_true()
	assert_str(read_back.map_id).is_equal("field")
	assert_vector(read_back.cell).is_equal(Vector2i(3, 2))
	assert_int(read_back.facing).is_equal(VltFacing.Direction.WEST)


func test_writing_reads_the_live_world_not_a_stale_copy() -> void:
	# The failure this catches is the section that saves where the player started
	# instead of where they are — silent, and only visible on the next load.
	var walker: VltGridWalker = _walker(Vector2i(1, 1), VltFacing.Direction.NORTH)
	var section: VltWorldSaveSection = VltWorldSaveSection.new(walker)

	walker.step(VltFacing.Direction.EAST)
	walker.step(VltFacing.Direction.SOUTH)

	var written: Dictionary = section.write()
	assert_int(_int_in(written, VltWorldSaveSection.CELL_X_FIELD)).is_equal(2)
	assert_int(_int_in(written, VltWorldSaveSection.CELL_Z_FIELD)).is_equal(2)
	assert_int(_int_in(written, VltWorldSaveSection.FACING_FIELD)).is_equal(
		VltFacing.Direction.SOUTH
	)


func test_a_section_with_no_world_carries_what_it_read() -> void:
	# Not laziness: a section never given a world writes back what it read rather
	# than inventing a position, the same instinct as decision 0036.
	var section: VltWorldSaveSection = VltWorldSaveSection.new()
	section.read(
		{
			VltWorldSaveSection.MAP_FIELD: "cave",
			VltWorldSaveSection.CELL_X_FIELD: 7,
			VltWorldSaveSection.CELL_Z_FIELD: 9,
			VltWorldSaveSection.FACING_FIELD: int(VltFacing.Direction.EAST),
		},
		VltWorldSaveSection.VERSION
	)

	var written: Dictionary = section.write()
	assert_str(_string_in(written, VltWorldSaveSection.MAP_FIELD)).is_equal("cave")
	assert_int(_int_in(written, VltWorldSaveSection.CELL_X_FIELD)).is_equal(7)


func test_an_absent_field_takes_a_default() -> void:
	var section: VltWorldSaveSection = VltWorldSaveSection.new()
	section.read({VltWorldSaveSection.MAP_FIELD: "cave"}, VltWorldSaveSection.VERSION)

	assert_vector(section.cell).is_equal(Vector2i.ZERO)
	assert_int(section.facing).is_equal(VltFacing.Direction.SOUTH)


func test_a_facing_naming_no_direction_falls_back() -> void:
	# It would index past the deltas the first time the player pressed a key —
	# a crash on load, from a file somebody edited by hand.
	var section: VltWorldSaveSection = VltWorldSaveSection.new()

	for nonsense: int in [-1, 4, 9999]:
		section.read(
			{VltWorldSaveSection.FACING_FIELD: nonsense}, VltWorldSaveSection.VERSION
		)
		assert_int(section.facing).override_failure_message(
			"a stored facing of %d was accepted" % nonsense
		).is_equal(VltFacing.Direction.SOUTH)


func test_a_position_survives_the_json_round_trip() -> void:
	# JSON turns every integer into a float, so a cell read straight back would
	# be (3.0, 2.0). This is why VltSaveSection.read_int accepts a float, and the
	# test that would notice if it stopped.
	var live: VltWorldSaveSection = VltWorldSaveSection.new(
		_walker(Vector2i(3, 2), VltFacing.Direction.EAST)
	)
	var document: Dictionary = VltSaveCodec.write(_sections([live]))
	var through_json: Variant = JSON.parse_string(JSON.stringify(document))

	var read_back: VltWorldSaveSection = VltWorldSaveSection.new()
	@warning_ignore("unsafe_cast")
	VltSaveCodec.read(through_json as Dictionary, _sections([read_back]))

	assert_vector(read_back.cell).is_equal(Vector2i(3, 2))
	assert_int(read_back.facing).is_equal(VltFacing.Direction.EAST)
