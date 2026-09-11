extends GdUnitTestSuite

## Leaves on the cells somebody chose.
##
## The patch stores cells and numbers and grows the mesh again on load, which is
## only sound if two things hold. **A cell must keep its own tree**, or editing
## one corner of a map would reshuffle the foliage in another. And **a patch must
## own nothing but its leaves**, so deleting it cannot leave a hole where a model
## used to be.
##
## What it looks like is not asserted here and should not be.

const SEED: int = 77


func _library() -> MeshLibrary:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shape.surface_get_arrays(0))

	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "Box")
	library.set_item_mesh(0, mesh)
	return library


## A grid with `cells` filled, and a patch over them, both in the tree.
##
## `turned` is the orthogonal orientation every filled cell is painted with — 0 is
## the unrotated one a `GridMap` uses unless the author says otherwise.
func _patch(
	cells: Array[Vector3i], filled: Array[Vector3i], turned: int = 0
) -> VltFoliagePatch:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)

	var grid: GridMap = GridMap.new()
	grid.cell_size = Vector3.ONE
	grid.mesh_library = _library()
	holder.add_child(grid)
	for cell: Vector3i in filled:
		grid.set_cell_item(cell, 0, turned)

	var patch: VltFoliagePatch = VltFoliagePatch.new()
	patch.seed = SEED
	patch.density = 4.0
	holder.add_child(patch)
	patch.cells = cells
	patch.layer = patch.get_path_to(grid)
	return patch


## A patch's first surface of leaves, in world space.
func _points(patch: VltFoliagePatch) -> PackedVector3Array:
	@warning_ignore("unsafe_cast")
	var points: PackedVector3Array = (
		patch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	)
	return points


# --- a cell keeps its own tree -----------------------------------------------


func test_the_same_cells_grow_the_same_leaves() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(3, 0, 1)]
	var once: VltFoliagePatch = _patch(cells, cells)
	var again: VltFoliagePatch = _patch(cells, cells)

	assert_int(again.leaf_total()).is_equal(once.leaf_total())
	var first: PackedVector3Array = _points(once)
	var second: PackedVector3Array = _points(again)
	for point: int in range(first.size()):
		assert_vector(second[point]).is_equal(first[point])


func test_two_cells_of_one_item_are_not_the_same_tree() -> void:
	# Both cells hold the same box. If the seed were the item's rather than the
	# cell's, the two would be identical down to the last leaf and a row of trees
	# would read as a wallpaper.
	var near: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var far: Array[Vector3i] = [Vector3i(9, 0, 0)]
	var one: VltFoliagePatch = _patch(near, near)
	var other: VltFoliagePatch = _patch(far, far)

	# Compared where the cell is not: the leaves of the far cell, moved back.
	var first: PackedVector3Array = _points(one)
	var second: PackedVector3Array = _points(other)
	var same: bool = first.size() == second.size()
	if same:
		for point: int in range(first.size()):
			if not first[point].is_equal_approx(second[point] - Vector3(9.0, 0.0, 0.0)):
				same = false
				break
	assert_bool(same).override_failure_message(
		"two cells grew the same tree, so the seed is not the cell's"
	).is_false()


func test_rerolling_the_patch_changes_every_cell() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var patch: VltFoliagePatch = _patch(cells, cells)
	var before: PackedVector3Array = _points(patch)

	patch.seed = SEED + 1
	var after: PackedVector3Array = _points(patch)
	assert_bool(before == after).override_failure_message(
		"the seed was changed and the same leaves came back"
	).is_false()


# --- it owns nothing but its leaves ------------------------------------------


func test_a_patch_over_empty_cells_grows_nothing() -> void:
	var patch: VltFoliagePatch = _patch([Vector3i(4, 0, 4)], [])
	assert_object(patch.mesh).is_null()
	assert_int(patch.leaf_total()).is_equal(0)


func test_a_patch_with_no_cells_grows_nothing() -> void:
	var patch: VltFoliagePatch = _patch([], [Vector3i(0, 0, 0)])
	assert_object(patch.mesh).is_null()


func test_the_leaves_stand_at_the_cell_they_were_sown_on() -> void:
	var cells: Array[Vector3i] = [Vector3i(5, 0, 2)]
	var patch: VltFoliagePatch = _patch(cells, cells)
	var points: PackedVector3Array = _points(patch)

	assert_int(points.size()).is_greater(0)
	# The box is two units across and the grid's cells are one, so everything a
	# cell grows sits within a couple of units of its centre.
	var middle: Vector3 = Vector3(5.0, 0.0, 2.0)
	for point: Vector3 in points:
		assert_float(point.distance_to(middle)).override_failure_message(
			"a leaf grew at %s, which is nowhere near cell (5, 0, 2)" % point
		).is_less(3.0)


# --- the settings belong to the patch ----------------------------------------


func test_turning_the_density_up_grows_more_leaves() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var patch: VltFoliagePatch = _patch(cells, cells)
	var before: int = patch.leaf_total()

	patch.density = patch.density * 3.0
	assert_int(patch.leaf_total()).is_greater(before)


# --- a turned cell grows turned leaves ---------------------------------------


func test_leaves_follow_a_cell_that_was_painted_turned() -> void:
	# The defect this exists for: a cell stores an item *and* one of twenty-four
	# orientations. Sown against an identity basis, the leaves stayed in the
	# model's untouched pose while the GridMap drew the model turned — foliage
	# crossways to the thing it grew on. On an unrotated cell the two agree, which
	# is why every render made here missed it.
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var upright: VltFoliagePatch = _patch(cells, cells)
	# 16 is a quarter turn about Y in Godot's orthogonal table.
	var sideways: VltFoliagePatch = _patch(cells, cells, 16)

	var straight: PackedVector3Array = _points(upright)
	var turned: PackedVector3Array = _points(sideways)
	assert_int(turned.size()).is_equal(straight.size())

	# Asked of the grid rather than written out: which way orientation 16 turns is
	# the engine's convention, and a test that guesses it is testing the guess.
	var grid: GridMap = sideways.get_node(sideways.layer) as GridMap
	var quarter: Basis = grid.get_basis_with_orthogonal_index(16)
	# A cell turns about its own centre, not about the world origin.
	var centre: Vector3 = grid.map_to_local(Vector3i.ZERO)

	var moved: int = 0
	for point: int in range(straight.size()):
		if not straight[point].is_equal_approx(turned[point]):
			moved += 1
	assert_int(moved).override_failure_message(
		"turning the cell moved no leaf, so the cell's orientation is being ignored"
	).is_greater(0)

	# And it is the cell's turn exactly, not some other transform: every leaf of
	# the turned cell is a leaf of the upright one, rotated.
	for point: int in range(straight.size()):
		assert_vector(turned[point]).is_equal_approx(
			centre + quarter * (straight[point] - centre), Vector3.ONE * 0.001
		)
