extends GdUnitTestSuite

## What the map editor draws over a map (phase 0 of the editor tools).
##
## The overlay's whole value is that it draws what the *rules* read, so these
## tests are about the two mechanisms staying told apart: a cell claimed whole is
## not a shape, a shape is not a cell, and off the map is neither. An overlay that
## confused any pair of those would be worse than no overlay, because it would be
## believed.
##
## Every count below is in points, not segments — the gizmo API takes pairs.

const LIFT: float = VltMapOverlay.LIFT
const BAND: float = VltMapOverlay.BAND

## One side of a boundary drawn with ticks: the side itself and an upright at
## each end.
const TICKED_SIDE: int = 6

## One side of a boundary drawn without them.
const BARE_SIDE: int = 2

## A crossed cell: four sides and two diagonals.
const CROSSED_CELL: int = 12


# --- shapes -------------------------------------------------------------------


func test_a_map_that_speaks_in_cells_draws_no_hitbox() -> void:
	# No `_blocked` in the palette means the old reading, where a painted cell is
	# a blocked cell and nothing measures a mesh. There is no shape to draw.
	var map: VltWorldMap = _plain([Vector2i(1, 1)])
	assert_array(VltMapOverlay.hitboxes(map)).is_empty()


func test_a_post_is_drawn_as_the_prism_it_was_measured_in() -> void:
	var map: VltWorldMap = _posted()
	var lines: PackedVector3Array = VltMapOverlay.hitboxes(map)
	assert_array(lines).is_not_empty()

	var ground: float = VltMapOverlay.ground_of(map)
	var lowest: float = INF
	var highest: float = -INF
	for point: Vector3 in lines:
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)

	# Drawn in the band it was measured in, so what is seen is what was measured.
	assert_float(lowest).is_equal_approx(ground + LIFT, 0.001)
	assert_float(highest).is_equal_approx(ground + BAND, 0.001)


func test_a_shape_is_drawn_where_the_mesh_is_not_where_the_cell_is() -> void:
	# The post is one metre across in a cell that is wider than that. If the
	# overlay drew the cell, the outline would reach the cell's corners.
	var map: VltWorldMap = _posted()
	var middle: Vector2 = VltMapOverlay.flat_of(map, Vector2i(3, 2))
	var half: float = map.cell_width() * 0.5

	var widest: float = 0.0
	for point: Vector3 in VltMapOverlay.hitboxes(map):
		widest = maxf(widest, Vector2(point.x, point.z).distance_to(middle))

	assert_float(widest).is_less(half)


# --- cells claimed whole ------------------------------------------------------


func test_a_cell_claimed_whole_is_crossed() -> void:
	var map: VltWorldMap = _plain([Vector2i(1, 1)])
	assert_int(VltMapOverlay.blocked(map).size()).is_equal(CROSSED_CELL)


func test_a_model_takes_no_cross() -> void:
	# The post's answer is its shape, drawn to the centimetre by `hitboxes`.
	# Crossing its cell as well would claim the whole of a cell it does not fill —
	# which is the reading decision 0072 removed.
	assert_array(VltMapOverlay.blocked(_posted())).is_empty()


func test_a_claim_beyond_the_terrain_is_left_to_the_edge() -> void:
	# Off the map already stops you and `edges` draws it. A cross out there would
	# say two things are happening where only one is.
	var map: VltWorldMap = auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(2, 2)), [Vector2i(5, 5)])
	)
	assert_array(VltMapOverlay.blocked(map)).is_empty()


func test_a_map_with_no_blocking_layer_claims_nothing() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(2, 2))))
	map.remove_child(map.blocking)
	map.blocking.free()
	map.blocking = null
	assert_array(VltMapOverlay.blocked(map)).is_empty()


# --- the edge of the map ------------------------------------------------------


func test_one_cell_has_four_sides() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", [Vector2i(0, 0)]))
	assert_int(VltMapOverlay.edges(map).size()).is_equal(4 * TICKED_SIDE)


func test_a_square_of_cells_is_outlined_once() -> void:
	# Eight sides, not sixteen: the sides two cells share are not boundary.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(2, 2))))
	assert_int(VltMapOverlay.edges(map).size()).is_equal(8 * TICKED_SIDE)


func test_a_hole_is_boundary_too() -> void:
	# A hole in the floor stops you exactly as the outside does, and it is the
	# case a traced outline would miss.
	var cells: Array[Vector2i] = VltFixtureMap.filled(Vector2i(3, 3))
	cells.erase(Vector2i(1, 1))
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", cells))
	assert_int(VltMapOverlay.edges(map).size()).is_equal((12 + 4) * TICKED_SIDE)


func test_a_map_with_no_terrain_has_no_edge() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", []))
	map.remove_child(map.terrain)
	map.terrain.free()
	map.terrain = null
	assert_array(VltMapOverlay.edges(map)).is_empty()


# --- what was sown ------------------------------------------------------------


func test_a_patch_is_outlined_without_ticks() -> void:
	# Flat, unlike the map's edge: a patch is a region on the ground rather than
	# something you can walk off, and uprights everywhere would be a thicket.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(3, 3))))
	_sow(map, map, [Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	assert_int(VltMapOverlay.patches(map).size()).is_equal(6 * BARE_SIDE)


func test_a_grouped_patch_is_still_found() -> void:
	# An author may group patches under a node, and a search that only looked at
	# direct children would quietly stop seeing them — the same defect the turf
	# already has against its own layers.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(3, 3))))
	var group: Node3D = Node3D.new()
	map.add_child(group)
	_sow(map, group, [Vector3i(0, 0, 0)])
	assert_int(VltMapOverlay.patches(map).size()).is_equal(4 * BARE_SIDE)


func test_two_patches_are_outlined_separately() -> void:
	# Side by side, so a merged outline would drop the seam between them — which
	# is the one place two sets of settings meet and the thing worth seeing.
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(3, 3))))
	_sow(map, map, [Vector3i(0, 0, 0)])
	_sow(map, map, [Vector3i(1, 0, 0)])
	assert_int(VltMapOverlay.patches(map).size()).is_equal(8 * BARE_SIDE)


func test_a_map_with_nothing_sown_outlines_nothing() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(2, 2))))
	assert_array(VltMapOverlay.patches(map)).is_empty()


# --- where somebody appears ---------------------------------------------------


func test_a_disc_is_drawn_at_every_arrival() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	map.add_child(VltFixtureMap.warp(Vector2i(1, 1), "cave", Vector2i(0, 0), VltFacing.Direction.NORTH))
	map.add_child(VltFixtureMap.rest(Vector2i(2, 2)))

	var expected: int = 2 * VltMapOverlay.ROUND * 2
	assert_int(VltMapOverlay.arrivals(map, 0.3).size()).is_equal(expected)


func test_a_disc_is_the_size_it_was_asked_for() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	map.add_child(VltFixtureMap.rest(Vector2i(2, 2)))

	var middle: Vector2 = VltMapOverlay.flat_of(map, Vector2i(2, 2))
	for point: Vector3 in VltMapOverlay.arrivals(map, 0.3):
		assert_float(Vector2(point.x, point.z).distance_to(middle)).is_equal_approx(0.3, 0.001)


func test_no_radius_draws_no_disc() -> void:
	var map: VltWorldMap = auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4))))
	map.add_child(VltFixtureMap.rest(Vector2i(2, 2)))
	assert_array(VltMapOverlay.arrivals(map, 0.0)).is_empty()


# --- noticing a brush stroke --------------------------------------------------


func test_an_unchanged_map_reads_the_same_twice() -> void:
	# The whole point: an author who is not painting costs one comparison.
	var map: VltWorldMap = _plain([])
	assert_int(VltMapOverlay.signature_of(map)).is_equal(VltMapOverlay.signature_of(map))


func test_painting_a_cell_is_noticed() -> void:
	var map: VltWorldMap = _plain([])
	var before: int = VltMapOverlay.signature_of(map)
	map.blocking.set_cell_item(Vector3i(1, VltWorldMap.GROUND, 1), VltFixtureMap.MARKER)
	assert_int(VltMapOverlay.signature_of(map)).is_not_equal(before)


func test_erasing_a_cell_is_noticed() -> void:
	var map: VltWorldMap = _plain([Vector2i(1, 1)])
	var before: int = VltMapOverlay.signature_of(map)
	map.blocking.set_cell_item(Vector3i(1, VltWorldMap.GROUND, 1), GridMap.INVALID_CELL_ITEM)
	assert_int(VltMapOverlay.signature_of(map)).is_not_equal(before)


func test_turning_a_cell_is_noticed() -> void:
	# A model painted sideways has a footprint that is long the other way, so the
	# orientation is part of what the overlay draws — watching only presence would
	# leave a rotated fence drawn across its old axis.
	var map: VltWorldMap = _plain([Vector2i(1, 1)])
	var cell: Vector3i = Vector3i(1, VltWorldMap.GROUND, 1)
	var before: int = VltMapOverlay.signature_of(map)
	map.blocking.set_cell_item(cell, VltFixtureMap.MARKER, 10)
	assert_int(VltMapOverlay.signature_of(map)).is_not_equal(before)


func test_losing_a_layer_is_noticed() -> void:
	# An unassigned layer is a change, and silence about it would leave the
	# overlay drawing what used to be there.
	var map: VltWorldMap = _plain([Vector2i(1, 1)])
	var before: int = VltMapOverlay.signature_of(map)
	map.remove_child(map.blocking)
	map.blocking.free()
	map.blocking = null
	assert_int(VltMapOverlay.signature_of(map)).is_not_equal(before)


func test_no_map_has_no_signature() -> void:
	assert_int(VltMapOverlay.signature_of(null)).is_equal(0)


# --- nothing at all -----------------------------------------------------------


func test_no_map_draws_nothing() -> void:
	# Every entry point takes whatever the editor hands it, and the editor hands
	# it null between scenes.
	assert_array(VltMapOverlay.hitboxes(null)).is_empty()
	assert_array(VltMapOverlay.blocked(null)).is_empty()
	assert_array(VltMapOverlay.edges(null)).is_empty()
	assert_array(VltMapOverlay.patches(null)).is_empty()
	assert_array(VltMapOverlay.arrivals(null, 0.3)).is_empty()


func test_a_missing_grid_holds_no_cells() -> void:
	assert_dict(VltMapOverlay.cells_of(null)).is_empty()


# --- fixtures -----------------------------------------------------------------


## A map whose blocking layer speaks in whole cells, as every map painted before
## shapes existed does.
func _plain(blocked: Array[Vector2i]) -> VltWorldMap:
	return auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4)), blocked)
	)


## A map whose blocking layer speaks in shapes, with one post in cell (3, 2).
##
## **Deliberately much narrower than its cell**, which is the case the whole
## mechanism exists for: a fence post owning a square metre it does not fill is
## what decision 0072 was written about. A post as wide as its cell would let an
## overlay that drew cells pass for one that draws shapes.
func _posted() -> VltWorldMap:
	var built: VltWorldMap = auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(6, 6)))
	)
	built.remove_child(built.blocking)
	built.blocking.free()
	built.blocking = VltFixtureMap.shaped([Vector2i(3, 2)], Vector3(0.4, 3.0, 0.4))
	built.add_child(built.blocking)
	built.forget_shapes()
	return built


## Sows turf on some cells, under whichever node the caller names.
##
## Never enters the scene tree, so the patch's own rebuild is skipped — the
## overlay reads the cell list and nothing else.
func _sow(map: VltWorldMap, under: Node, cells: Array[Vector3i]) -> TurfPatch:
	var patch: TurfPatch = auto_free(TurfPatch.new())
	under.add_child(patch)
	patch.layer = patch.get_path_to(map.terrain)
	patch.cells = cells
	return patch
