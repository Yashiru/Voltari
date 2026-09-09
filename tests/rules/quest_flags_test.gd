extends GdUnitTestSuite

## What the world remembers (spec 15, section 3; decision 0042).
##
## Flags are the longest-lived data the game has: written once, read by every
## version afterwards, sitting in saves nobody can migrate. So the defaults and
## the survival of an unknown name matter more here than anywhere else.


func _sections(of: Array[VltSaveSection]) -> Array[VltSaveSection]:
	return of


func _round_trip(flags: VltQuestFlags) -> VltQuestFlags:
	var document: Dictionary = VltSaveCodec.write(
		_sections([VltQuestFlagsSection.new(flags)])
	)
	var read_back: VltQuestFlagsSection = VltQuestFlagsSection.new()
	VltSaveCodec.read(document, _sections([read_back]))
	return read_back.flags


# --- defaults ----------------------------------------------------------------


func test_a_flag_nobody_set_is_false() -> void:
	# What lets an older save meet a newer build's flag: it is simply not there.
	assert_bool(VltQuestFlags.new().is_set("never_written")).is_false()


func test_a_counter_nobody_set_is_zero() -> void:
	assert_int(VltQuestFlags.new().count("never_written")).is_equal(0)


func test_one_kind_alone_is_not_an_empty_set() -> void:
	# Found by mutation. `is_empty` decides whether a new game's first save has
	# anything to write, and an `or` in place of the `and` would report a world
	# holding every switch it has as empty.
	var switches: VltQuestFlags = VltQuestFlags.new()
	switches.raise("met_the_elder")
	assert_bool(switches.is_empty()).override_failure_message(
		"a set holding a switch reported itself empty"
	).is_false()

	var counters: VltQuestFlags = VltQuestFlags.new()
	counters.set_count("badges", 1)
	assert_bool(counters.is_empty()).override_failure_message(
		"a set holding a counter reported itself empty"
	).is_false()

	assert_bool(VltQuestFlags.new().is_empty()).is_true()


func test_a_lowered_flag_reads_the_same_as_one_never_set() -> void:
	# They must be indistinguishable to a reader, or a quest could depend on the
	# difference between "not yet" and "no longer".
	var flags: VltQuestFlags = VltQuestFlags.new()
	flags.raise("met_the_elder")
	flags.lower("met_the_elder")

	assert_bool(flags.is_set("met_the_elder")).is_equal(flags.is_set("never_written"))


# --- the two kinds -----------------------------------------------------------


func test_a_counter_holds_one_value_rather_than_several_flags() -> void:
	# The whole argument for the second kind: a stage cannot be in two places.
	var flags: VltQuestFlags = VltQuestFlags.new()

	flags.set_count("elder_quest", 2)
	flags.set_count("elder_quest", 4)

	assert_int(flags.count("elder_quest")).is_equal(4)
	assert_int(flags.counter_names().size()).override_failure_message(
		"advancing a stage created a second name"
	).is_equal(1)


func test_the_two_kinds_do_not_collide() -> void:
	# One name, two namespaces. If they shared one, a counter would read as a
	# boolean somewhere far from here.
	var flags: VltQuestFlags = VltQuestFlags.new()
	flags.raise("shared_name")
	flags.set_count("shared_name", 7)

	assert_bool(flags.is_set("shared_name")).is_true()
	assert_int(flags.count("shared_name")).is_equal(7)


# --- merging, which is how an event commits ----------------------------------


func test_merging_leaves_untouched_names_alone() -> void:
	# An event commits by merging its own set in one call (decision 0044), so a
	# merge must not behave like a replacement.
	var world: VltQuestFlags = VltQuestFlags.new()
	world.raise("already_here")
	world.set_count("progress", 3)

	var pending: VltQuestFlags = VltQuestFlags.new()
	pending.raise("just_happened")
	world.merge(pending)

	assert_bool(world.is_set("already_here")).is_true()
	assert_bool(world.is_set("just_happened")).is_true()
	assert_int(world.count("progress")).is_equal(3)


func test_merging_overwrites_what_it_does_mention() -> void:
	var world: VltQuestFlags = VltQuestFlags.new()
	world.set_count("progress", 1)

	var pending: VltQuestFlags = VltQuestFlags.new()
	pending.set_count("progress", 2)
	world.merge(pending)

	assert_int(world.count("progress")).is_equal(2)


func test_merging_can_lower_a_flag() -> void:
	# A merge carries false as deliberately as it carries true; treating false as
	# "nothing to say" would make a flag impossible to clear.
	var world: VltQuestFlags = VltQuestFlags.new()
	world.raise("door_open")

	var pending: VltQuestFlags = VltQuestFlags.new()
	pending.lower("door_open")
	world.merge(pending)

	assert_bool(world.is_set("door_open")).is_false()


# --- the save ----------------------------------------------------------------


func test_flags_round_trip() -> void:
	# Declaring a section earns this test rather than remembering to write one
	# (spec 13, section 8).
	var flags: VltQuestFlags = VltQuestFlags.new()
	flags.raise("met_the_elder")
	flags.lower("door_open")
	flags.set_count("badges", 3)

	var read_back: VltQuestFlags = _round_trip(flags)

	assert_bool(read_back.is_set("met_the_elder")).is_true()
	assert_bool(read_back.is_set("door_open")).is_false()
	assert_int(read_back.count("badges")).is_equal(3)


func test_a_flag_this_build_never_heard_of_survives() -> void:
	# Decision 0042, and decision 0036's argument one level down: a build that
	# lost a quest must not erase the player's progress through it.
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {
			VltQuestFlagsSection.KEY: {
				VltSaveCodec.VERSION_KEY: VltQuestFlagsSection.VERSION,
				VltSaveCodec.DATA_KEY: {
					VltQuestFlagsSection.SWITCHES_FIELD: {"from_a_later_build": true},
					VltQuestFlagsSection.COUNTERS_FIELD: {"unknown_quest": 5},
				},
			},
		},
	}

	var section: VltQuestFlagsSection = VltQuestFlagsSection.new()
	VltSaveCodec.read(document, _sections([section]))

	assert_bool(section.flags.is_set("from_a_later_build")).override_failure_message(
		"an unrecognised flag was filtered out on read"
	).is_true()
	assert_int(section.flags.count("unknown_quest")).is_equal(5)

	var rewritten: Dictionary = VltSaveCodec.write(_sections([section]))
	var again: VltQuestFlagsSection = VltQuestFlagsSection.new()
	VltSaveCodec.read(rewritten, _sections([again]))
	assert_bool(again.flags.is_set("from_a_later_build")).override_failure_message(
		"an unrecognised flag was dropped on the next write"
	).is_true()


func test_flags_survive_the_json_round_trip() -> void:
	# JSON turns every integer into a float, so a counter read straight back
	# would be 3.0. The reason VltSaveSection.read_int accepts a float.
	var flags: VltQuestFlags = VltQuestFlags.new()
	flags.set_count("badges", 3)
	flags.raise("met_the_elder")

	var document: Dictionary = VltSaveCodec.write(
		_sections([VltQuestFlagsSection.new(flags)])
	)
	var through_json: Variant = JSON.parse_string(JSON.stringify(document))

	var section: VltQuestFlagsSection = VltQuestFlagsSection.new()
	@warning_ignore("unsafe_cast")
	VltSaveCodec.read(through_json as Dictionary, _sections([section]))

	assert_int(section.flags.count("badges")).is_equal(3)
	assert_bool(section.flags.is_set("met_the_elder")).is_true()


func test_an_empty_set_of_flags_round_trips() -> void:
	# A new game. The section must produce something readable rather than
	# something absent, or the first save of every playthrough reads incomplete.
	var read_back: VltQuestFlags = _round_trip(VltQuestFlags.new())
	assert_bool(read_back.is_empty()).is_true()


func test_a_document_does_not_depend_on_the_order_flags_were_set() -> void:
	# Two identical worlds must produce identical documents, or the round-trip
	# comparison in the codec suite is comparing insertion order.
	var one: VltQuestFlags = VltQuestFlags.new()
	one.raise("a")
	one.raise("b")

	var two: VltQuestFlags = VltQuestFlags.new()
	two.raise("b")
	two.raise("a")

	assert_str(JSON.stringify(VltQuestFlagsSection.new(one).write())).is_equal(
		JSON.stringify(VltQuestFlagsSection.new(two).write())
	)


func test_a_malformed_section_reads_as_no_flags_rather_than_crashing() -> void:
	var section: VltQuestFlagsSection = VltQuestFlagsSection.new()
	section.read({VltQuestFlagsSection.SWITCHES_FIELD: "not a group of fields"}, 1)

	assert_bool(section.flags.is_empty()).is_true()
