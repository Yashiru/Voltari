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


# --- making one ---------------------------------------------------------------


func test_the_dock_writes_a_map_where_it_was_told_to() -> void:
	# The fields are the configuration and a test drives the same ones a person
	# types into, so this covers the wiring rather than the creating.
	var dock: VltMapDock = _dock()
	dock.folder_field().text = "user://map_dock_test"
	dock.new_id_field().text = "dock_made_this"
	dock.library_field().text = "res://game/maps/tiles.meshlib"
	dock.size_fields()[0].value = 3
	dock.size_fields()[1].value = 2
	DirAccess.make_dir_recursive_absolute("user://map_dock_test")

	var result: VltNewMap.Result = dock.new_map()

	assert_bool(result.worked()).override_failure_message(
		"the dock could not make a map: %s" % ", ".join(result.problems)
	).is_true()
	assert_str(result.path).is_equal("user://map_dock_test/dock_made_this.tscn")

	var packed: PackedScene = load(result.path) as PackedScene
	var map: VltWorldMap = auto_free(packed.instantiate() as VltWorldMap)
	assert_str(map.map_id).is_equal("dock_made_this")
	assert_bool(map.is_walkable(Vector2i(2, 1))).is_true()
	assert_bool(map.is_walkable(Vector2i(3, 0))).is_false()

	DirAccess.remove_absolute(result.path)
	DirAccess.remove_absolute("user://map_dock_test")


func test_a_map_the_dock_refuses_says_why() -> void:
	var dock: VltMapDock = _dock()
	dock.new_id_field().text = "Not An Id"

	var result: VltNewMap.Result = dock.new_map()
	assert_bool(result.worked()).is_false()
	assert_str(result.problems[0]).contains("not a map id")
