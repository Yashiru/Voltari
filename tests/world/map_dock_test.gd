extends GdUnitTestSuite

## The validator, reachable from where a map is painted.
##
## It existed and was only reachable from a test — which is not where anybody is
## standing when they paint a door. What is asserted here is not the panel but
## the answer it gives, because a panel that reported nothing wrong about nothing
## would look exactly like a panel that worked.


func _dock() -> VltMapDock:
	return auto_free(VltMapDock.new())


func test_it_finds_the_committed_maps_sound() -> void:
	# The same answer the suite already gets from the same validator. If these
	# two ever disagree, the dock is checking something else.
	var dock: VltMapDock = _dock()
	var problems: PackedStringArray = dock.validate()

	assert_array(problems).override_failure_message(
		"the dock reports the shipped maps as broken:\n  %s" % "\n  ".join(problems)
	).is_empty()


func test_an_empty_folder_is_a_problem_rather_than_a_pass() -> void:
	# Asking to check a folder and being told nothing is wrong with nothing is
	# the answer most likely to be misread — a typo in the path would read as
	# success.
	var dock: VltMapDock = _dock()
	dock.folder_field().text = "res://game/maps/nowhere"

	var problems: PackedStringArray = dock.validate()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("no maps found")


func test_without_an_entry_map_it_checks_everything_else() -> void:
	# Reachability is skipped rather than guessed at (spec 14, section 7), and
	# the rest of the pass still runs.
	var dock: VltMapDock = _dock()
	dock.entry_field().text = ""

	assert_array(dock.validate()).is_empty()


func test_an_entry_map_that_does_not_exist_is_caught_here_too() -> void:
	# The check that proves the entry field is read rather than decorative.
	var dock: VltMapDock = _dock()
	dock.entry_field().text = "not_a_map"

	var problems: PackedStringArray = dock.validate()
	assert_bool(problems.is_empty()).override_failure_message(
		"a typo in the entry map passed silently"
	).is_false()
