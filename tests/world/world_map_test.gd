extends GdUnitTestSuite

## What a map knows about itself (spec 14, section 3).
##
## Three painted layers, of which two are rules: terrain says which cells exist,
## blocking says which of them stop you, and decoration says nothing. Keeping
## them apart is what makes replacing a rock with a bush a change of art rather
## than a change of rule, so it is what these tests pin.

const GRASS: String = "meadow"


func _map() -> VltWorldMap:
	# A 5x5 field with a wall at (2, 2).
	var built: VltWorldMap = VltFixtureMap.map(
		"field", VltFixtureMap.filled(Vector2i(5, 5)), [Vector2i(2, 2)] as Array[Vector2i]
	)
	built.add_child(
		VltFixtureMap.warp(Vector2i(4, 4), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH)
	)
	built.add_child(VltFixtureMap.zone(GRASS, Vector2i(0, 3), Vector2i(2, 2)))
	return auto_free(built)


# --- walkability -------------------------------------------------------------


func test_a_blocked_cell_is_not_walkable_even_though_it_exists() -> void:
	var map: VltWorldMap = _map()

	assert_bool(map.is_walkable(Vector2i(2, 1))).is_true()
	assert_bool(map.is_walkable(Vector2i(2, 2))).override_failure_message(
		"a cell on the blocking layer was walkable"
	).is_false()


func test_a_cell_off_the_map_is_not_walkable() -> void:
	# Off the map is a cell with no terrain, which is why no map needs a fence
	# painted around its edge.
	var map: VltWorldMap = _map()

	assert_bool(map.is_walkable(Vector2i(5, 0))).is_false()
	assert_bool(map.is_walkable(Vector2i(-1, 0))).is_false()
	assert_bool(map.is_walkable(Vector2i(0, -1))).is_false()


func test_a_map_with_no_terrain_is_walkable_nowhere() -> void:
	var empty: VltWorldMap = auto_free(VltWorldMap.new())
	assert_bool(empty.is_walkable(Vector2i.ZERO)).is_false()


func test_a_map_with_nothing_blocking_is_walkable_everywhere_it_exists() -> void:
	# The blocking layer being empty must not make the whole map impassable,
	# which is what an inverted test would produce.
	var open: VltWorldMap = auto_free(
		VltFixtureMap.map("open", VltFixtureMap.filled(Vector2i(2, 2)))
	)

	for cell: Vector2i in VltFixtureMap.filled(Vector2i(2, 2)):
		assert_bool(open.is_walkable(cell)).is_true()


# --- what is placed on it ----------------------------------------------------


func test_a_warp_is_found_on_its_own_cell_and_nowhere_else() -> void:
	var map: VltWorldMap = _map()

	assert_object(map.warp_at(Vector2i(4, 4))).is_not_null()
	assert_object(map.warp_at(Vector2i(4, 3))).is_null()
	assert_int(map.warps().size()).is_equal(1)


func test_a_cell_inside_a_zone_reports_its_table() -> void:
	var map: VltWorldMap = _map()

	assert_str(map.zone_at(Vector2i(0, 3)).table_id).is_equal(GRASS)
	assert_str(map.zone_at(Vector2i(1, 4)).table_id).is_equal(GRASS)
	assert_int(map.zones().size()).is_equal(1)


func test_the_zone_boundary_falls_where_the_rectangle_says() -> void:
	# Where an off-by-one lives. The zone covers (0, 3) to (1, 4) inclusive.
	var map: VltWorldMap = _map()

	assert_object(map.zone_at(Vector2i(1, 3))).override_failure_message(
		"the last cell of the zone was outside it"
	).is_not_null()
	assert_object(map.zone_at(Vector2i(2, 3))).override_failure_message(
		"the cell past the zone was inside it"
	).is_null()
	assert_object(map.zone_at(Vector2i(0, 2))).override_failure_message(
		"the cell before the zone was inside it"
	).is_null()


func test_a_zone_covering_nothing_contains_nothing() -> void:
	var zone: VltEncounterZone = VltFixtureMap.zone(GRASS, Vector2i.ZERO, Vector2i(0, 0))
	assert_bool(zone.contains(Vector2i.ZERO)).is_false()
	assert_bool(zone.is_complete()).is_false()
	zone.free()


func test_a_zone_with_no_table_is_incomplete() -> void:
	var zone: VltEncounterZone = VltFixtureMap.zone("", Vector2i.ZERO, Vector2i.ONE)
	assert_bool(zone.is_complete()).is_false()
	zone.free()


func test_a_warp_with_no_destination_is_incomplete() -> void:
	var warp: VltWarp = VltFixtureMap.warp(
		Vector2i.ZERO, "", Vector2i.ZERO, VltFacing.Direction.NORTH
	)
	assert_bool(warp.is_complete()).is_false()
	warp.free()


# --- decoration --------------------------------------------------------------


func test_decoration_neither_creates_a_cell_nor_blocks_one() -> void:
	# The whole content of decision 0054, and the only thing there is to assert
	# about a layer nothing reads.
	var decorated: VltWorldMap = auto_free(
		VltFixtureMap.map(
			"garden",
			VltFixtureMap.filled(Vector2i(3, 3)),
			[] as Array[Vector2i],
			[Vector2i(1, 1), Vector2i(9, 9)] as Array[Vector2i]
		)
	)

	assert_bool(decorated.is_walkable(Vector2i(1, 1))).override_failure_message(
		"a flower stopped somebody"
	).is_true()
	assert_bool(decorated.is_walkable(Vector2i(9, 9))).override_failure_message(
		"decoration painted off the map made a cell exist"
	).is_false()


func test_a_map_offers_no_way_to_ask_about_decoration() -> void:
	# The guard on the decision rather than on the behaviour. An accessor is how
	# "merely there" becomes something a rule reads, and it cannot appear by
	# accident if its absence is asserted.
	var map: VltWorldMap = _map()

	for method: String in ["decor_at", "has_decoration", "decorations", "decor_cells"]:
		assert_bool(map.has_method(method)).override_failure_message(
			"VltWorldMap grew %s(), which lets a rule read decoration" % method
		).is_false()


# --- grouped, and therefore tidy ----------------------------------------------
#
# A map past three props gets tidied into nodes — `HomeTown/maison bas gauche` is
# what a real one looks like. These used to read direct children only, so the
# editor drew every marker where it sat and the game ignored all of them: content
# authored correctly behaved exactly like content authored wrong, with nothing
# anywhere saying which.


func test_a_grouped_warp_is_found() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	var group: Node3D = Node3D.new()
	map.add_child(group)
	group.add_child(VltFixtureMap.warp(Vector2i(2, 2), "cave", Vector2i(0, 0), VltFacing.Direction.NORTH))

	assert_int(map.warps().size()).is_equal(1)
	assert_object(map.warp_at(Vector2i(2, 2))).is_not_null()


func test_a_warp_grouped_two_deep_is_found() -> void:
	# One level would have been an easy thing to special-case and still be wrong.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	var town: Node3D = Node3D.new()
	map.add_child(town)
	var house: Node3D = Node3D.new()
	town.add_child(house)
	house.add_child(VltFixtureMap.warp(Vector2i(1, 3), "cave", Vector2i(0, 0), VltFacing.Direction.SOUTH))

	assert_object(map.warp_at(Vector2i(1, 3))).is_not_null()


func test_a_grouped_zone_is_found() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(6, 6))))
	var group: Node3D = Node3D.new()
	map.add_child(group)
	group.add_child(VltFixtureMap.zone("meadow", Vector2i(1, 1), Vector2i(3, 3)))

	assert_int(map.zones().size()).is_equal(1)
	assert_object(map.zone_at(Vector2i(2, 2))).is_not_null()
	assert_object(map.zone_at(Vector2i(5, 5))).is_null()


func test_a_grouped_event_is_found() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	var group: Node3D = Node3D.new()
	map.add_child(group)
	var steps: Array[VltEventStep] = [VltFixtureEvent.set_flag("read_it")]
	group.add_child(VltFixtureEvent.event(steps, VltEvent.Trigger.INTERACT, Vector2i(2, 1)))

	assert_int(map.events().size()).is_equal(1)
	assert_object(map.event_at(Vector2i(2, 1), VltEvent.Trigger.INTERACT)).is_not_null()


func test_a_grouped_rest_point_is_found() -> void:
	# The one that reported a content problem that did not exist: a map with a
	# camp tidied into a node was told a defeat there could not recover.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	var group: Node3D = Node3D.new()
	map.add_child(group)
	group.add_child(VltFixtureMap.rest(Vector2i(1, 1)))

	assert_int(VltRestPoint.points_on(map).size()).is_equal(1)


func test_a_loose_marker_is_still_found() -> void:
	# The old arrangement has to keep working: every committed map puts its
	# markers directly under the root.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	map.add_child(VltFixtureMap.warp(Vector2i(2, 2), "cave", Vector2i(0, 0), VltFacing.Direction.NORTH))
	map.add_child(VltFixtureMap.rest(Vector2i(0, 0)))

	assert_object(map.warp_at(Vector2i(2, 2))).is_not_null()
	assert_int(VltRestPoint.points_on(map).size()).is_equal(1)


func test_a_map_with_nothing_grouped_finds_nothing() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	map.add_child(Node3D.new())

	assert_array(map.warps()).is_empty()
	assert_array(map.zones()).is_empty()
	assert_array(map.events()).is_empty()
	assert_array(VltRestPoint.points_on(map)).is_empty()
