extends GdUnitTestSuite

## What a model in the blocking layer stops you walking into.
##
## A `GridMap` cell holds one item and `is_walkable` asks one question of one
## cell, so a house painted on a cell blocked that cell and nothing else. These
## tests are about the cells it should have blocked as well — and, just as much,
## about the ones it must not: a canopy is not in the way, and a wall that
## overhangs its neighbour by a millimetre does not own that neighbour.

const CELL: float = 1.0
const SCALE: float = 0.5


## A layer holding one palette: a post that fits inside a cell, a hall four cells
## across, and a mushroom whose cap is wide and whose stalk is not.
func _layer() -> GridMap:
	var library: MeshLibrary = MeshLibrary.new()
	_add(library, 0, _block(Vector3(0.5, 3.0, 0.5)))
	_add(library, 1, _block(Vector3(6.0, 4.0, 6.0)))
	_add(library, 2, _mushroom())

	var grid: GridMap = auto_free(GridMap.new())
	grid.mesh_library = library
	grid.cell_size = Vector3(CELL, CELL, CELL)
	grid.cell_scale = SCALE
	return grid


func _add(library: MeshLibrary, id: int, mesh: Mesh) -> void:
	library.create_item(id)
	library.set_item_name(id, "item_%d" % id)
	library.set_item_mesh(id, mesh)


## A box standing on its own origin, the way the tile library leaves every model.
func _block(size: Vector3) -> ArrayMesh:
	return _from(AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size))


## A narrow stalk with a wide cap on top of it. The cap is above the reach and is
## the whole point: measuring the bounding box would block everything it shades.
func _mushroom() -> ArrayMesh:
	var mesh: ArrayMesh = _from(AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 6.0, 0.8)))
	_into(mesh, AABB(Vector3(-6.0, 6.0, -6.0), Vector3(12.0, 1.0, 12.0)))
	return mesh


func _from(box: AABB) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	_into(mesh, box)
	return mesh


## One surface spanning a box: its floor and its ceiling, two triangles each.
##
## Every corner of both, and not a cheaper set of points that merely reaches the
## same bounding box. The extent is read per vertex within a height band, so a
## floor missing its far corner measures as having no depth at all — which is a
## fixture lying about the model rather than a tool getting it wrong.
func _into(mesh: ArrayMesh, box: AABB) -> void:
	var points: PackedVector3Array = PackedVector3Array()
	for y: float in [box.position.y, box.end.y]:
		var a: Vector3 = Vector3(box.position.x, y, box.position.z)
		var b: Vector3 = Vector3(box.end.x, y, box.position.z)
		var c: Vector3 = Vector3(box.end.x, y, box.end.z)
		var d: Vector3 = Vector3(box.position.x, y, box.end.z)
		points.append_array(PackedVector3Array([a, b, c, a, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# --- what is low enough to be in the way -------------------------------------


func test_only_what_is_below_the_reach_counts() -> void:
	# The band is roughly the character, because the question is what they would
	# walk into. A cap six metres up is something you walk under.
	var narrow: Rect2 = VltMapBlocking.extent(_mushroom(), 4.0)

	assert_float(narrow.size.x).is_equal_approx(0.8, 0.001)
	assert_float(narrow.size.y).is_equal_approx(0.8, 0.001)


func test_the_whole_model_is_wider_than_the_part_in_the_way() -> void:
	# The other half of the same fact, so a test that measured the bounding box by
	# accident could not pass both.
	var whole: Rect2 = VltMapBlocking.extent(_mushroom(), 100.0)

	assert_float(whole.size.x).is_equal_approx(12.0, 0.001)


func test_a_model_entirely_overhead_stops_nobody() -> void:
	# An arch, a balcony, a branch. Maps are made of these.
	var above: ArrayMesh = _from(AABB(Vector3(-3.0, 5.0, -3.0), Vector3(6.0, 1.0, 6.0)))

	assert_vector(VltMapBlocking.extent(above, 4.0).size).is_equal(Vector2.ZERO)


# --- which cells that covers --------------------------------------------------


func test_a_model_inside_one_cell_takes_only_that_cell() -> void:
	var grid: GridMap = _layer()
	grid.set_cell_item(Vector3i(4, 0, 4), 0)

	assert_array(VltMapBlocking.footprint(grid, Vector3i(4, 0, 4))).is_equal(
		[Vector3i(4, 0, 4)]
	)


func test_a_model_wider_than_a_cell_takes_what_it_covers() -> void:
	# 6 units across, drawn at half scale, on cells one metre wide: three metres
	# exactly, so the cell it stands on and one either side. Exact is the case
	# worth pinning — a model landing on a cell boundary must not take the cell
	# beyond it.
	var grid: GridMap = _layer()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)

	var covered: Array[Vector3i] = VltMapBlocking.footprint(grid, Vector3i(0, 0, 0))

	assert_int(covered.size()).override_failure_message(
		"expected a 3 by 3 block, got %s" % [covered]
	).is_equal(9)
	assert_array(covered).contains([Vector3i(0, 0, 0), Vector3i(-1, 0, -1), Vector3i(1, 0, 1)])


func test_the_footprint_stays_at_the_height_it_was_painted() -> void:
	# A prop on a raised cell blocks around itself up there, not on the ground
	# under it.
	var grid: GridMap = _layer()
	grid.set_cell_item(Vector3i(0, 2, 0), 1)

	for cell: Vector3i in VltMapBlocking.footprint(grid, Vector3i(0, 2, 0)):
		assert_int(cell.y).is_equal(2)


func test_a_sliver_of_overhang_does_not_take_the_next_cell() -> void:
	# A wall drawn a hair wider than its cell would otherwise own its neighbour,
	# and a corridor two cells wide would admit nobody.
	var grid: GridMap = _layer()
	var library: MeshLibrary = grid.mesh_library
	# 2.02 units at half scale is 1.01 m: one cell, plus half a centimetre either
	# side.
	_add(library, 3, _block(Vector3(2.02, 3.0, 2.02)))
	grid.set_cell_item(Vector3i(5, 0, 5), 3)

	assert_array(VltMapBlocking.footprint(grid, Vector3i(5, 0, 5))).is_equal(
		[Vector3i(5, 0, 5)]
	)


# --- filling the cells in and taking them back --------------------------------


func _with_blocker() -> GridMap:
	var grid: GridMap = _layer()
	_add(grid.mesh_library, 9, ArrayMesh.new())
	grid.mesh_library.set_item_name(9, VltMapBlocking.BLOCKER)
	return grid


func test_filling_blocks_the_footprint_and_leaves_the_model_alone() -> void:
	var grid: GridMap = _with_blocker()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)

	assert_int(VltMapBlocking.fill(grid, Vector3i(0, 0, 0))).is_equal(8)
	assert_int(grid.get_cell_item(Vector3i(0, 0, 0))).override_failure_message(
		"the model was overwritten by its own footprint"
	).is_equal(1)
	assert_int(grid.get_cell_item(Vector3i(1, 0, 1))).is_equal(9)


func test_filling_never_overwrites_something_an_author_put_there() -> void:
	# A tile overwritten is work lost. A cell left unblocked is a wall you can walk
	# through, which the next playtest finds — so only an empty cell is written to.
	var grid: GridMap = _with_blocker()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)
	grid.set_cell_item(Vector3i(1, 0, 1), 0)

	VltMapBlocking.fill(grid, Vector3i(0, 0, 0))

	assert_int(grid.get_cell_item(Vector3i(1, 0, 1))).is_equal(0)


func test_clearing_takes_back_only_the_blockers() -> void:
	var grid: GridMap = _with_blocker()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)
	VltMapBlocking.fill(grid, Vector3i(0, 0, 0))

	assert_int(VltMapBlocking.clear(grid, Vector3i(0, 0, 0))).is_equal(8)
	assert_int(grid.get_cell_item(Vector3i(1, 0, 1))).is_equal(GridMap.INVALID_CELL_ITEM)
	assert_int(grid.get_cell_item(Vector3i(0, 0, 0))).override_failure_message(
		"clearing a footprint removed the model that cast it"
	).is_equal(1)


func test_a_cell_two_models_share_survives_one_of_them_leaving() -> void:
	# Two houses along a wall. Taking one away must not open the other.
	var grid: GridMap = _with_blocker()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)
	grid.set_cell_item(Vector3i(2, 0, 0), 1)
	VltMapBlocking.fill(grid, Vector3i(0, 0, 0))
	VltMapBlocking.fill(grid, Vector3i(2, 0, 0))

	VltMapBlocking.clear(grid, Vector3i(0, 0, 0))

	assert_int(grid.get_cell_item(Vector3i(1, 0, 0))).override_failure_message(
		"a cell both models cover was opened when one of them went"
	).is_equal(9)


func test_a_palette_with_no_blocker_changes_nothing() -> void:
	# A library built before this existed. Refusing quietly is right: the author
	# rebuilds the palette and the cells fill in.
	var grid: GridMap = _layer()
	grid.set_cell_item(Vector3i(0, 0, 0), 1)

	assert_int(VltMapBlocking.fill(grid, Vector3i(0, 0, 0))).is_equal(0)
	assert_int(grid.get_used_cells().size()).is_equal(1)
