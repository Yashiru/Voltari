extends GdUnitTestSuite

## What an event scene cannot guarantee about itself (spec 15, section 7).
##
## The flag checks are the reason this exists. A name misspelled at one of its
## two sites reads perfectly, sets perfectly, and gates something forever — and
## no test of any single event finds it, because each half is correct alone.


func _tables() -> PackedStringArray:
	return PackedStringArray(["meadow"])


## Sound in every way this file is not about, rest point included — the validator
## is one pass and its other complaints would land in these results too.
func _map(id: String = "field") -> VltWorldMap:
	var built: VltWorldMap = auto_free(
		VltFixtureMap.map(id, VltFixtureMap.filled(Vector2i(4, 4)))
	)
	built.add_child(VltFixtureMap.rest(Vector2i(0, 0)))
	return built


func _maps(of: Array[VltWorldMap]) -> Array[VltWorldMap]:
	return of


func _steps(of: Array[VltEventStep]) -> Array[VltEventStep]:
	return of


func _problems(maps: Array[VltWorldMap], lines: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	return VltMapValidator.check(maps, _tables(), "", lines)


func _complains_about(problems: PackedStringArray, fragment: String) -> bool:
	for problem: String in problems:
		if problem.contains(fragment):
			return true
	return false


# --- a map that is fine ------------------------------------------------------


func test_a_sound_event_reports_nothing() -> void:
	# Without this, every test below would pass on a validator that complains
	# about everything.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch("met_the_elder", VltFixtureEvent.say("again")),
					VltFixtureEvent.set_flag("met_the_elder"),
				]
			)
		)
	)

	assert_array(_problems(_maps([map]))).is_empty()


# --- the two halves of a typo -----------------------------------------------


func test_a_branch_on_a_flag_nothing_sets_is_reported() -> void:
	# The door that never opens.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_steps([VltFixtureEvent.branch("has_key", VltFixtureEvent.say("it_opens"))])
		)
	)

	assert_bool(
		_complains_about(_problems(_maps([map])), "which nothing ever sets")
	).is_true()


func test_a_flag_nothing_reads_is_reported() -> void:
	# Usually the other half of the same typo.
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.set_flag("has_kye")])))

	assert_bool(
		_complains_about(_problems(_maps([map])), "which nothing ever reads")
	).is_true()


func test_a_misspelling_reports_both_halves() -> void:
	# What the pair actually looks like in practice, and the shape that makes the
	# mistake obvious rather than merely detected.
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.set_flag("has_kye")])))
	map.add_child(
		VltFixtureEvent.event(
			_steps([VltFixtureEvent.branch("has_key", VltFixtureEvent.say("it_opens"))]),
			VltEvent.Trigger.INTERACT,
			Vector2i(1, 1)
		)
	)

	var problems: PackedStringArray = _problems(_maps([map]))
	assert_bool(_complains_about(problems, "has_kye")).is_true()
	assert_bool(_complains_about(problems, "has_key")).is_true()


func test_a_flag_set_on_one_map_and_read_on_another_is_fine() -> void:
	# The check is global on purpose. A per-map check would report every quest
	# that spans two rooms.
	var first: VltWorldMap = _map("field")
	var second: VltWorldMap = _map("cave")
	first.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.set_flag("has_key")])))
	second.add_child(
		VltFixtureEvent.event(
			_steps([VltFixtureEvent.branch("has_key", VltFixtureEvent.say("it_opens"))])
		)
	)

	assert_array(_problems(_maps([first, second]))).is_empty()


func test_a_counter_counts_as_a_write() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.set_counter("elder_quest", 1)])))
	map.add_child(
		VltFixtureEvent.event(
			_steps([VltFixtureEvent.branch("elder_quest", VltFixtureEvent.say("onwards"))]),
			VltEvent.Trigger.INTERACT,
			Vector2i(2, 2)
		)
	)

	assert_array(_problems(_maps([map]))).is_empty()


func test_a_flag_inside_a_branch_arm_is_seen() -> void:
	# Arms are children of the branch, so a walk that stopped at the top level
	# would miss half of every conditional event.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch(
						"met_the_elder",
						VltFixtureEvent.sequence(_steps([VltFixtureEvent.set_flag("buried_deep")]))
					),
					VltFixtureEvent.set_flag("met_the_elder"),
				]
			)
		)
	)

	assert_bool(
		_complains_about(_problems(_maps([map])), "buried_deep")
	).override_failure_message("a flag inside a branch arm was never looked at").is_true()


# --- shape -------------------------------------------------------------------


func test_an_event_with_no_steps_is_reported() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([])))

	assert_bool(_complains_about(_problems(_maps([map])), "has no steps")).is_true()


func test_a_branch_with_no_arm_at_all_is_reported() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.branch("met_the_elder")])))

	assert_bool(_complains_about(_problems(_maps([map])), "no arm at all")).is_true()


func test_a_line_with_no_id_is_reported() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.say("")])))

	assert_bool(_complains_about(_problems(_maps([map])), "a line with no id")).is_true()


func test_a_set_flag_step_with_no_flag_is_reported() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.set_flag("")])))

	assert_bool(
		_complains_about(_problems(_maps([map])), "set-flag step with no flag")
	).is_true()


# --- lines -------------------------------------------------------------------


func test_an_unknown_line_is_reported_when_a_table_is_supplied() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.say("elder_greeting")])))

	assert_bool(
		_complains_about(
			_problems(_maps([map]), PackedStringArray(["something_else"])), "unknown line"
		)
	).is_true()


func test_lines_are_not_checked_without_a_table() -> void:
	# There is no localisation format yet (spec 15, open points). The check is
	# absent rather than guessing, the same way reachability is.
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event(_steps([VltFixtureEvent.say("elder_greeting")])))

	assert_array(_problems(_maps([map]))).is_empty()
