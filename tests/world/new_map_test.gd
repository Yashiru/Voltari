extends GdUnitTestSuite

## A map to start from.
##
## Assembling one by hand is a scene, a VltWorldMap, three GridMaps and three
## exports wired in the inspector. What is asserted here is that what comes out
## is a map the rest of the engine recognises — the parts that are easy to get
## right by eye and impossible to notice missing.

const FOLDER: String = "user://new_map_test"
const TILES: String = "res://game/maps/tiles.meshlib"


func before_test() -> void:
	_forget()
	DirAccess.make_dir_recursive_absolute(FOLDER)


func after_test() -> void:
	_forget()


func _forget() -> void:
	var directory: DirAccess = DirAccess.open(FOLDER)
	if directory != null:
		for file: String in directory.get_files():
			DirAccess.remove_absolute("%s/%s" % [FOLDER, file])
	DirAccess.remove_absolute(FOLDER)


func _create(map_id: String = "meadow", size: Vector2i = Vector2i(4, 3)) -> VltNewMap.Result:
	return VltNewMap.create(map_id, size, TILES, "", FOLDER)


func _opened(result: VltNewMap.Result) -> VltWorldMap:
	var packed: PackedScene = load(result.path) as PackedScene
	assert_object(packed).override_failure_message("nothing at %s" % result.path).is_not_null()
	return auto_free(packed.instantiate() as VltWorldMap)


# --- what comes out ----------------------------------------------------------


func test_it_writes_a_map_the_engine_recognises() -> void:
	var result: VltNewMap.Result = _create()

	assert_bool(result.worked()).override_failure_message(
		"creation failed: %s" % ", ".join(result.problems)
	).is_true()

	var map: VltWorldMap = _opened(result)
	assert_str(map.map_id).is_equal("meadow")
	assert_object(map.terrain).is_not_null()
	assert_object(map.blocking).is_not_null()
	assert_object(map.decor).override_failure_message(
		"the decoration layer was not wired, so there is nowhere to paint one"
	).is_not_null()


func test_the_terrain_is_the_rectangle_that_was_asked_for() -> void:
	# A map whose terrain is empty exists nowhere — every cell would be off the
	# map — so a new one is filled rather than left to be painted.
	var map: VltWorldMap = _opened(_create("meadow", Vector2i(4, 3)))

	for x: int in range(4):
		for z: int in range(3):
			assert_bool(map.is_walkable(Vector2i(x, z))).override_failure_message(
				"(%d, %d) is not walkable on a fresh map" % [x, z]
			).is_true()

	assert_bool(map.is_walkable(Vector2i(4, 0))).override_failure_message(
		"the rectangle ran one cell past its width"
	).is_false()
	assert_bool(map.is_walkable(Vector2i(0, 3))).is_false()


func test_nothing_blocks_and_nothing_is_decorated() -> void:
	var map: VltWorldMap = _opened(_create())

	assert_int(map.blocking.get_used_cells().size()).is_equal(0)
	assert_int(map.decor.get_used_cells().size()).is_equal(0)


func test_every_layer_can_be_painted_into() -> void:
	# A layer with no library cannot hold a cell at all, which would make two
	# thirds of a new map unusable until somebody worked out why.
	var map: VltWorldMap = _opened(_create())

	for layer: GridMap in [map.terrain, map.blocking, map.decor]:
		assert_object(layer.mesh_library).override_failure_message(
			"%s has no tile library" % layer.name
		).is_not_null()


func test_the_layers_survived_being_packed() -> void:
	# Godot packs only nodes whose owner is the scene root. The file saves
	# without error and comes back holding nothing.
	var map: VltWorldMap = _opened(_create())

	assert_int(map.get_child_count()).is_equal(3)


# --- what it refuses ---------------------------------------------------------


func test_it_will_not_overwrite_a_map() -> void:
	# The one refusal that matters. Everything else here is a typo caught early;
	# writing over a painted map destroys work with no other copy.
	_create()
	var again: VltNewMap.Result = _create()

	assert_bool(again.worked()).is_false()
	assert_str(again.problems[0]).contains("already exists")


func test_a_map_id_is_an_identifier_and_not_a_title() -> void:
	# It is held in a save (decision 0040), so the rule is the identifier rule.
	for bad: String in ["Meadow", "the meadow", "meadow-2", "2meadow", "", "meadow!"]:
		var result: VltNewMap.Result = VltNewMap.create(
			bad, Vector2i(2, 2), TILES, "", FOLDER
		)
		assert_bool(result.worked()).override_failure_message(
			"\"%s\" was accepted as a map id" % bad
		).is_false()


func test_a_reasonable_id_is_accepted() -> void:
	# The other direction, so the pattern is not merely refusing everything.
	for good: String in ["meadow", "starter_field", "cave_2", "a"]:
		assert_bool(
			VltNewMap.create(good, Vector2i(2, 2), TILES, "", FOLDER).worked()
		).override_failure_message("\"%s\" was refused" % good).is_true()


func test_a_map_with_no_cells_is_refused() -> void:
	for size: Vector2i in [Vector2i(0, 4), Vector2i(4, 0), Vector2i(-3, 4)]:
		assert_bool(
			VltNewMap.create("meadow", size, TILES, "", FOLDER).worked()
		).override_failure_message("a %s map was accepted" % size).is_false()


func test_a_tile_library_that_is_not_there_is_refused() -> void:
	var result: VltNewMap.Result = VltNewMap.create(
		"meadow", Vector2i(2, 2), "res://game/maps/nothing.meshlib", "", FOLDER
	)

	assert_bool(result.worked()).is_false()
	assert_str(result.problems[0]).contains("no tile library")


func test_an_unknown_ground_tile_is_refused_rather_than_guessed() -> void:
	var result: VltNewMap.Result = VltNewMap.create(
		"meadow", Vector2i(2, 2), TILES, "not_a_tile", FOLDER
	)

	assert_bool(result.worked()).is_false()
	assert_str(result.problems[0]).contains("no item named")


func test_a_named_ground_tile_is_the_one_used() -> void:
	var result: VltNewMap.Result = VltNewMap.create(
		"meadow", Vector2i(2, 2), TILES, "wall", FOLDER
	)

	assert_bool(result.worked()).is_true()
	assert_str(result.ground).is_equal("wall")
