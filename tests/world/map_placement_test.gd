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


# --- snapping a free prop -----------------------------------------------------


func test_snapping_a_prop_moves_it_onto_a_cell() -> void:
	# Props are ordinary nodes, not grid cells: a GridMap cell carries an item and
	# one of 24 orientations and no scale at all, so anything whose size you want
	# to choose has to live in the scene and be snapped on request.
	var map: VltWorldMap = _map()
	var centre: Vector3 = VltMapPlacement.centre_of(map, Vector2i(3, 2))
	var size: float = VltMapPlacement.cell_size(map)

	var nudged: Vector3 = centre + Vector3(size * 0.3, 0.0, -size * 0.2)
	assert_vector(VltMapPlacement.snapped_to_grid(map, nudged)).is_equal(centre)


func test_snapping_leaves_the_height_alone() -> void:
	# A prop sunk into the floor or raised onto a ledge is art, and the grid has
	# no opinion about it. Snapping y would undo the one adjustment a free-placed
	# object exists to allow.
	var map: VltWorldMap = _map()
	# Computed rather than written down: a cell centre is not at y zero — the grid
	# centres cells vertically by default, so the floor of this grid is a metre up.
	var floor_level: float = VltMapPlacement.centre_of(map, Vector2i(1, 1)).y
	var raised: Vector3 = VltMapPlacement.centre_of(map, Vector2i(1, 1)) + Vector3(0.1, 2.5, 0.1)

	assert_float(VltMapPlacement.snapped_to_grid(map, raised).y).override_failure_message(
		"the height was snapped away"
	).is_equal_approx(floor_level + 2.5, 0.001)


func test_a_prop_already_on_its_cell_does_not_move() -> void:
	# What lets the caller count what it actually changed, so "nothing to move"
	# can be said rather than reported as work.
	var map: VltWorldMap = _map()
	var centre: Vector3 = VltMapPlacement.centre_of(map, Vector2i(2, 4))

	assert_vector(VltMapPlacement.snapped_to_grid(map, centre)).is_equal(centre)


# --- where a click lands -------------------------------------------------------
#
# The overworld has no physics, so there is nothing to raycast against and a plane
# at the map's own floor is what a click means. These are about that plane being
# the map's rather than the world's: a map somebody has moved or turned is the
# case where an eyeballed answer looks right and is out by however far the map was
# moved.


func test_a_click_from_straight_above_lands_under_the_camera() -> void:
	var map: VltWorldMap = _map_in_tree()
	var camera: Camera3D = _looking_down(Vector3(3.0, 10.0, -4.0))

	var where: Variant = VltMapPlacement.ground_under(map, camera, _middle(camera))
	assert_object(where).is_not_null()

	var landed: Vector3 = where
	assert_float(landed.x).is_equal_approx(3.0, 0.05)
	assert_float(landed.z).is_equal_approx(-4.0, 0.05)


func test_a_click_lands_on_the_floor_not_where_the_ray_started() -> void:
	var map: VltWorldMap = _map_in_tree()
	var camera: Camera3D = _looking_down(Vector3(0.0, 27.0, 0.0))

	var landed: Vector3 = VltMapPlacement.ground_under(map, camera, _middle(camera))
	assert_float(landed.y).is_equal_approx(VltMapPlacement.centre_of(map, Vector2i.ZERO).y, 0.001)


func test_a_click_along_the_floor_lands_nowhere() -> void:
	# What happens while turning the camera, and the reason a miss has to fall
	# through rather than be reported: the viewport would stop responding as soon
	# as somebody looked at the horizon.
	var map: VltWorldMap = _map_in_tree()
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.position = Vector3(0.0, 5.0, 0.0)
	camera.rotation = Vector3.ZERO

	assert_object(VltMapPlacement.ground_under(map, camera, _middle(camera))).is_null()


func test_a_click_on_a_moved_map_lands_in_the_map_s_own_space() -> void:
	# The answer is used to place a child of the map, so it has to be in the map's
	# coordinates. A map nudged twenty metres aside is where an answer in world
	# space looks perfectly reasonable and is twenty metres out.
	var map: VltWorldMap = _map_in_tree()
	map.position = Vector3(20.0, 0.0, -8.0)
	var camera: Camera3D = _looking_down(Vector3(23.0, 10.0, -12.0))

	var landed: Vector3 = VltMapPlacement.ground_under(map, camera, _middle(camera))
	assert_float(landed.x).is_equal_approx(3.0, 0.05)
	assert_float(landed.z).is_equal_approx(-4.0, 0.05)


func test_a_click_on_a_turned_map_lands_in_the_map_s_own_space() -> void:
	var map: VltWorldMap = _map_in_tree()
	map.rotation = Vector3(0.0, PI * 0.5, 0.0)
	# A quarter turn about the vertical sends the map's +x to the world's -z, so a
	# camera over world (0, ·, -5) is over the map's own (5, ·, 0).
	var camera: Camera3D = _looking_down(Vector3(0.0, 10.0, -5.0))

	var landed: Vector3 = VltMapPlacement.ground_under(map, camera, _middle(camera))
	assert_float(landed.x).is_equal_approx(5.0, 0.05)
	assert_float(landed.z).is_equal_approx(0.0, 0.05)


func test_nothing_to_click_on_lands_nowhere() -> void:
	var camera: Camera3D = _looking_down(Vector3.ZERO)
	assert_object(VltMapPlacement.ground_under(null, camera, Vector2.ZERO)).is_null()
	assert_object(VltMapPlacement.ground_under(_map_in_tree(), null, Vector2.ZERO)).is_null()


## In the scene tree, unlike the fixture the tests above use: `global_transform`
## is what a click is resolved against, and it means nothing for a loose node.
func _map_in_tree() -> VltWorldMap:
	var built: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(8, 8))))
	add_child(built)
	return built


## A camera hanging over a spot, pointed straight down.
func _looking_down(from: Vector3) -> Camera3D:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.position = from
	camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	return camera


## The middle of what the camera sees, which is where "straight down" points.
static func _middle(camera: Camera3D) -> Vector2:
	return camera.get_viewport().get_visible_rect().size * 0.5
