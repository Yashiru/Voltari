extends GdUnitTestSuite

## The validator, reachable from where a map is painted.
##
## It existed and was only reachable from a test — which is not where anybody is
## standing when they paint a door. What is asserted here is not the panel but
## the answer it gives, because a panel that reported nothing wrong about nothing
## would look exactly like a panel that worked.


const TILES: String = "res://game/maps/tiles.meshlib"
const FIXTURES: String = "user://dock_maps"


func before_test() -> void:
	_forget()


func after_test() -> void:
	_forget()


func _forget() -> void:
	var directory: DirAccess = DirAccess.open(FIXTURES)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute("%s/%s" % [FIXTURES, file])
	DirAccess.remove_absolute(FIXTURES)


func _dock() -> VltMapDock:
	return auto_free(VltMapDock.new())


## A folder of maps built for this suite rather than the one the game ships.
##
## Pointing these tests at `game/maps` made them assert something about whatever
## anybody happened to be painting — a half-finished map failed the dock's test
## suite, which is the dock working and the test lying.
func _sound_folder() -> String:
	DirAccess.make_dir_recursive_absolute(FIXTURES)
	VltNewMap.create("dock_a", Vector2i(4, 4), TILES, "", FIXTURES)
	_add_camp("%s/dock_a.tscn" % FIXTURES)
	return FIXTURES


## A map with nowhere to send a defeated player is refused (spec 14, section 9),
## so a fixture that is meant to be sound needs one.
func _add_camp(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	var map: VltWorldMap = packed.instantiate() as VltWorldMap

	var camp: VltRestPoint = VltRestPoint.new()
	camp.name = "Camp"
	camp.cell = Vector2i(0, 0)
	map.add_child(camp)
	camp.owner = map

	var again: PackedScene = PackedScene.new()
	again.pack(map)
	ResourceSaver.save(again, path)
	map.free()


func _aimed_at_the_fixtures(dock: VltMapDock) -> VltMapDock:
	dock.folder_field().text = _sound_folder()
	dock.entry_field().text = "dock_a"
	return dock


func test_it_finds_a_sound_folder_sound() -> void:
	# Without this, every test below would pass on a dock that complains about
	# everything.
	var dock: VltMapDock = _aimed_at_the_fixtures(_dock())
	var problems: PackedStringArray = dock.validate()

	assert_array(problems).override_failure_message(
		"the dock reports a sound map as broken:\n  %s" % "\n  ".join(problems)
	).is_empty()


func test_it_gives_the_same_answer_as_the_suite_about_the_shipped_maps() -> void:
	# The assertion that matters: the dock and the validator agree about the same
	# maps. Which maps those are is not this test's business, so it asserts
	# agreement rather than soundness — the folder holds whatever is being
	# painted today.
	var dock: VltMapDock = _dock()
	var through_the_dock: PackedStringArray = dock.validate()

	var maps: Array[VltWorldMap] = []
	for path: String in ["res://game/maps/starter_field.tscn", "res://game/maps/starter_cave.tscn"]:
		maps.append(auto_free((load(path) as PackedScene).instantiate() as VltWorldMap))
	var directly: PackedStringArray = VltMapValidator.check(
		maps, VltContentPayloads.ids_in("res://content/generated/encounters"),
		"starter_field", VltTranslationTable.all_keys()
	)

	for problem: String in directly:
		assert_bool(through_the_dock.has(problem)).override_failure_message(
			"the validator reports \"%s\" and the dock does not" % problem
		).is_true()


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
	var dock: VltMapDock = _aimed_at_the_fixtures(_dock())
	dock.entry_field().text = ""

	assert_array(dock.validate()).is_empty()


func test_an_entry_map_that_does_not_exist_is_caught_here_too() -> void:
	# The check that proves the entry field is read rather than decorative.
	var dock: VltMapDock = _aimed_at_the_fixtures(_dock())
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
