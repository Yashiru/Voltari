extends GdUnitTestSuite

## What a map knows about itself (spec 14, section 3).
##
## Two painted layers: terrain says which cells exist, blocking says which of
## them stop you. Keeping them apart is what makes replacing a rock with a bush
## a change of art rather than a change of rule, so it is what these tests pin.

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
