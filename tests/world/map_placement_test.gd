extends GdUnitTestSuite

## Cells and transforms, kept in agreement (the map editor plugin).
##
## The plugin itself cannot be tested headless — it needs the editor. This is the
## half that can, and it is the half worth it: a marker drawn half a cell off is
## an error small enough to look like art, and nobody would find it by eye.


func _map() -> VltWorldMap:
	return auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(6, 6))))


# --- the two languages agree -------------------------------------------------


func test_a_cell_converts_to_a_point_and_back() -> void:
	# The round trip is the whole contract. Everything else the plugin does is
	# built on it holding.
	var map: VltWorldMap = _map()

	for cell: Vector2i in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(5, 5)]:
		var point: Vector3 = VltMapPlacement.centre_of(map, cell)
		assert_vector(VltMapPlacement.cell_at(map, point)).override_failure_message(
			"cell %s came back as %s" % [cell, VltMapPlacement.cell_at(map, point)]
		).is_equal(cell)


func test_a_point_anywhere_inside_a_cell_reads_as_that_cell() -> void:
	# What a drag produces: never the exact centre. If only the centre converted
	# correctly, dropping a door would move it to a neighbour half the time.
	var map: VltWorldMap = _map()
	var centre: Vector3 = VltMapPlacement.centre_of(map, Vector2i(2, 3))
	var size: float = VltMapPlacement.cell_size(map)
	var nearly: float = size * 0.45

	for nudge: Vector3 in [
		Vector3(nearly, 0, 0),
		Vector3(-nearly, 0, 0),
		Vector3(0, 0, nearly),
		Vector3(0, 0, -nearly),
		Vector3(nearly, 0, nearly),
	]:
		assert_vector(VltMapPlacement.cell_at(map, centre + nudge)).override_failure_message(
			"a drop %s from the centre landed on a different cell" % nudge
		).is_equal(Vector2i(2, 3))


func test_neighbouring_cells_are_one_cell_apart() -> void:
	# Catches the offset that is uniform, which the round trip alone would not:
	# a placement wrong by a constant converts back perfectly.
	var map: VltWorldMap = _map()
	var size: float = VltMapPlacement.cell_size(map)

	var here: Vector3 = VltMapPlacement.centre_of(map, Vector2i(1, 1))
	var east: Vector3 = VltMapPlacement.centre_of(map, Vector2i(2, 1))
	var south: Vector3 = VltMapPlacement.centre_of(map, Vector2i(1, 2))

	assert_float(east.x - here.x).is_equal_approx(size, 0.001)
	assert_float(south.z - here.z).is_equal_approx(size, 0.001)


func test_the_cell_size_comes_from_the_grid() -> void:
	# Declared nowhere in the plugin. A constant would be a second place to
	# change, and markers would drift further out the further you looked.
	var map: VltWorldMap = _map()
	map.terrain.cell_size = Vector3(3, 3, 3)

	assert_float(VltMapPlacement.cell_size(map)).is_equal_approx(3.0, 0.001)
	assert_vector(
		VltMapPlacement.cell_at(map, VltMapPlacement.centre_of(map, Vector2i(4, 2)))
	).is_equal(Vector2i(4, 2))


func test_a_map_with_no_terrain_still_answers() -> void:
	# A map somebody is midway through building. Falling back beats dividing by
	# a layer that is not there.
	var bare: VltWorldMap = auto_free(VltWorldMap.new())

	assert_float(VltMapPlacement.cell_size(bare)).is_equal_approx(
		VltMapPlacement.DEFAULT_CELL_SIZE, 0.001
	)
	assert_vector(
		VltMapPlacement.cell_at(bare, VltMapPlacement.centre_of(bare, Vector2i(2, 1)))
	).is_equal(Vector2i(2, 1))


# --- which nodes are placed, and where ---------------------------------------


func test_every_kind_of_placed_node_reports_its_cell() -> void:
	# The list the plugin walks. A node type missing from it is invisible in the
	# viewport, which is the whole problem the plugin exists for.
	var warp: VltWarp = auto_free(VltFixtureMap.warp(
		Vector2i(7, 3), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH
	))
	var event: VltEvent = auto_free(VltEvent.new())
	event.cell = Vector2i(4, 4)
	var rest: VltRestPoint = auto_free(VltFixtureMap.rest(Vector2i(2, 6)))
	var zone: VltEncounterZone = auto_free(
		VltFixtureMap.zone("meadow", Vector2i(1, 2), Vector2i(3, 2))
	)

	assert_vector(VltMapPlacement.anchor_of(warp)).is_equal(Vector2i(7, 3))
	assert_vector(VltMapPlacement.anchor_of(event)).is_equal(Vector2i(4, 4))
	assert_vector(VltMapPlacement.anchor_of(rest)).is_equal(Vector2i(2, 6))
	assert_vector(VltMapPlacement.anchor_of(zone)).override_failure_message(
		"a zone is placed by its corner, which is the only cell it has one of"
	).is_equal(Vector2i(1, 2))

	for node: Node3D in [warp, event, rest, zone]:
		assert_bool(VltMapPlacement.is_placed(node)).override_failure_message(
			"%s is drawn but not recognised as placed" % node.get_class()
		).is_true()


func test_something_that_is_not_placed_says_so() -> void:
	var plain: Node3D = auto_free(Node3D.new())

	assert_bool(VltMapPlacement.is_placed(plain)).is_false()
	assert_vector(VltMapPlacement.anchor_of(plain)).is_equal(VltMapPlacement.INVALID)
	assert_array(VltMapPlacement.cells_of(plain)).is_empty()


func test_a_zone_claims_its_whole_rectangle() -> void:
	var zone: VltEncounterZone = auto_free(
		VltFixtureMap.zone("meadow", Vector2i(1, 2), Vector2i(3, 2))
	)

	var claimed: Array[Vector2i] = VltMapPlacement.cells_of(zone)
	assert_int(claimed.size()).is_equal(6)
	assert_bool(claimed.has(Vector2i(3, 3))).is_true()
	assert_bool(claimed.has(Vector2i(4, 2))).override_failure_message(
		"the rectangle ran one cell past its width"
	).is_false()


func test_a_zone_covering_nothing_claims_nothing() -> void:
	# A size of zero is a zone somebody has started and not finished, and the
	# loop that draws it must not run backwards.
	var empty: VltEncounterZone = auto_free(
		VltFixtureMap.zone("meadow", Vector2i(0, 0), Vector2i(0, -4))
	)

	assert_array(VltMapPlacement.cells_of(empty)).is_empty()


func test_moving_a_node_moves_the_cell_it_names() -> void:
	var warp: VltWarp = auto_free(VltFixtureMap.warp(
		Vector2i(7, 3), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH
	))

	VltMapPlacement.set_anchor(warp, Vector2i(2, 5))
	assert_vector(warp.cell).is_equal(Vector2i(2, 5))


func test_the_map_is_found_through_a_grouping_node() -> void:
	# Doors grouped under a "Warps" node is a reasonable thing to want, and
	# assuming the direct parent would place every one of them at the origin.
	var map: VltWorldMap = _map()
	var group: Node3D = Node3D.new()
	map.add_child(group)

	var warp: VltWarp = VltFixtureMap.warp(
		Vector2i(1, 1), "cave", Vector2i(0, 0), VltFacing.Direction.NORTH
	)
	group.add_child(warp)

	assert_object(VltMapPlacement.map_of(warp)).is_same(map)


func test_a_node_outside_any_map_has_none() -> void:
	var loose: VltWarp = auto_free(VltFixtureMap.warp(
		Vector2i(0, 0), "cave", Vector2i(0, 0), VltFacing.Direction.NORTH
	))

	assert_object(VltMapPlacement.map_of(loose)).is_null()


# --- the plugin still parses -------------------------------------------------


func test_the_editor_plugin_loads() -> void:
	# The rest of this suite covers the arithmetic; nothing covers the files that
	# use it, because they need an editor to do anything. This is the one thing
	# that can be asserted about them from here — and it is the failure that
	# actually happens, since the strict warnings are errors and a plugin is only
	# compiled when somebody opens the editor.
	for path: String in [
		"res://addons/voltari_maps/plugin.gd",
		"res://addons/voltari_maps/map_gizmos.gd",
		"res://addons/voltari_maps/map_dock.gd",
		"res://addons/voltari_maps/tile_library.gd",
		"res://addons/voltari_maps/new_map.gd",
	]:
		assert_object(load(path)).override_failure_message(
			"%s does not compile — the map editor is broken" % path
		).is_not_null()
