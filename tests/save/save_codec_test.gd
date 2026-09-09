extends GdUnitTestSuite

## The save mechanism (spec 13).
##
## No files here: the codec deals in dictionaries, and keeping it that way is
## what lets every rule about saving be tested without a filesystem.

const NEWER: int = VltSaveCodec.FORMAT_VERSION + 1


func _counter(steps: int = 0, name: String = "") -> VltExampleSaveSections.Counter:
	var section: VltExampleSaveSections.Counter = VltExampleSaveSections.Counter.new()
	section.steps = steps
	section.name = name
	return section


func _sections(of: Array[VltSaveSection]) -> Array[VltSaveSection]:
	return of


func _payload(document: Dictionary, key: String) -> Dictionary:
	@warning_ignore("unsafe_cast")
	return (document[VltSaveCodec.SECTIONS_KEY] as Dictionary)[key] as Dictionary


# --- the round trip ----------------------------------------------------------


func test_a_section_survives_a_round_trip() -> void:
	var written: VltExampleSaveSections.Counter = _counter(42, "voltari")
	var document: Dictionary = VltSaveCodec.write(_sections([written]))

	var read_back: VltExampleSaveSections.Counter = _counter()
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([read_back]))

	assert_bool(report.complete()).is_true()
	assert_int(read_back.steps).is_equal(42)
	assert_str(read_back.name).is_equal("voltari")


func test_every_declared_section_round_trips() -> void:
	# The generic property that answers the hazard of opting in: a system which
	# declares a section earns this test rather than remembering to write one.
	# Written, read back, written again — the two documents must be identical.
	var sections: Array[VltSaveSection] = [_counter(7, "first"), VltExampleSaveSections.Distance.new()]
	var first: Dictionary = VltSaveCodec.write(sections)

	var fresh: Array[VltSaveSection] = [
		VltExampleSaveSections.Counter.new(), VltExampleSaveSections.Distance.new()
	]
	VltSaveCodec.read(first, fresh)
	var second: Dictionary = VltSaveCodec.write(fresh)

	assert_str(JSON.stringify(second)).override_failure_message(
		"a section did not come back the way it went in"
	).is_equal(JSON.stringify(first))


func test_an_absent_field_takes_a_default() -> void:
	# The common change: a version adds a field and an older save has none.
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {
			"counter": {VltSaveCodec.VERSION_KEY: 1, VltSaveCodec.DATA_KEY: {"steps": 5}},
		},
	}

	var section: VltExampleSaveSections.Counter = _counter(999, "stale")
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([section]))

	assert_bool(report.complete()).is_true()
	assert_int(section.steps).is_equal(5)
	assert_str(section.name).is_equal("")


func test_a_changed_meaning_is_handled_by_the_version_not_a_default() -> void:
	# Version 1 stored steps, version 2 stores metres. The value is present and
	# valid either way — only the version says which it means, and reading it
	# wrong would produce a number nothing could flag.
	var older: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {
			"distance": {VltSaveCodec.VERSION_KEY: 1, VltSaveCodec.DATA_KEY: {"travelled": 100}},
		},
	}

	var section: VltExampleSaveSections.Distance = VltExampleSaveSections.Distance.new()
	VltSaveCodec.read(older, _sections([section]))

	assert_int(section.metres).override_failure_message(
		"a version 1 payload was read as though it were version 2"
	).is_equal(50)


# --- what it cannot read -----------------------------------------------------


func test_an_unknown_section_is_kept_and_written_back() -> void:
	# Decision 0036. Without this, a partly-understood save is rewritten complete
	# and everything unread is gone, weeks before the player notices.
	var stranger: Dictionary = {VltSaveCodec.VERSION_KEY: 3, VltSaveCodec.DATA_KEY: {"a": 1}}
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {"from_a_later_build": stranger},
	}

	var section: VltExampleSaveSections.Counter = _counter()
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([section]))

	assert_bool(report.complete()).is_false()
	assert_bool(report.unread.has("from_a_later_build")).is_true()

	var rewritten: Dictionary = VltSaveCodec.write(_sections([section]), report.preserved)
	assert_str(JSON.stringify(_payload(rewritten, "from_a_later_build"))).override_failure_message(
		"a section this build does not understand was dropped"
	).is_equal(JSON.stringify(stranger))


func test_a_section_from_a_newer_build_is_kept_not_guessed_at() -> void:
	var ahead: Dictionary = {
		VltSaveCodec.VERSION_KEY: 99, VltSaveCodec.DATA_KEY: {"steps": 5},
	}
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {"counter": ahead},
	}

	var section: VltExampleSaveSections.Counter = _counter(1, "untouched")
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([section]))

	assert_bool(report.unread.has("counter")).is_true()
	assert_int(section.steps).override_failure_message(
		"a payload from a newer build was read anyway"
	).is_equal(1)


func test_a_malformed_section_does_not_take_the_others_down() -> void:
	# Sections are read independently, which is a constraint on the format and
	# not only on the reader.
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {
			"counter": "this is not a section at all",
			"distance": {VltSaveCodec.VERSION_KEY: 2, VltSaveCodec.DATA_KEY: {"travelled": 12}},
		},
	}

	var counter: VltExampleSaveSections.Counter = _counter()
	var distance: VltExampleSaveSections.Distance = VltExampleSaveSections.Distance.new()
	var report: VltSaveCodec.Report = VltSaveCodec.read(
		document, _sections([counter, distance])
	)

	assert_bool(report.unread.has("counter")).is_true()
	assert_int(distance.metres).override_failure_message(
		"one malformed section stopped another from being read"
	).is_equal(12)


func test_a_newer_envelope_reads_as_incomplete_not_as_damaged() -> void:
	# The two say different things to the player, so they must not be conflated.
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: NEWER,
		VltSaveCodec.SECTIONS_KEY: {
			"counter": {VltSaveCodec.VERSION_KEY: 1, VltSaveCodec.DATA_KEY: {"steps": 3}},
		},
	}

	var section: VltExampleSaveSections.Counter = _counter()
	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([section]))

	assert_bool(report.newer_format).is_true()
	assert_bool(report.complete()).is_false()
	# Still walked: what this build can read, it reads.
	assert_int(section.steps).is_equal(3)


func test_nothing_recognisable_is_reported_rather_than_crashed_on() -> void:
	var report: VltSaveCodec.Report = VltSaveCodec.read({}, _sections([_counter()]))
	assert_bool(report.complete()).is_false()

	var garbage: VltSaveCodec.Report = VltSaveCodec.read(
		{VltSaveCodec.SECTIONS_KEY: "not a dictionary"}, _sections([_counter()])
	)
	assert_bool(garbage.complete()).is_false()


func test_every_unread_section_is_also_preserved() -> void:
	# The invariant the whole design rests on: reported and kept are the same
	# set, so nothing can be flagged as lost without also being carried.
	var document: Dictionary = {
		VltSaveCodec.FORMAT_KEY: VltSaveCodec.FORMAT_VERSION,
		VltSaveCodec.SECTIONS_KEY: {
			"unknown_one": {VltSaveCodec.VERSION_KEY: 1, VltSaveCodec.DATA_KEY: {}},
			"unknown_two": 7,
			"counter": {VltSaveCodec.VERSION_KEY: 9, VltSaveCodec.DATA_KEY: {}},
		},
	}

	var report: VltSaveCodec.Report = VltSaveCodec.read(document, _sections([_counter()]))

	assert_int(report.unread.size()).is_equal(3)
	for key: String in report.unread:
		assert_bool(report.preserved.has(key)).override_failure_message(
			"\"%s\" was reported unread but not kept" % key
		).is_true()
