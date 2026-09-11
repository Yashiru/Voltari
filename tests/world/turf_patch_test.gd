extends GdUnitTestSuite

## Where a patch of turf stops.
##
## The blades and the dark ground under them are drawn by two different shaders
## that never meet: one places particles on the GPU, the other rasterises a quad.
## **They have to stop on the same line**, or the mat shows past the grass as a
## halo — and the only thing making that true is that both are handed the same four
## distances per cell, from the same measurement.
##
## So that is what is asserted here: the numbers, and the fact that the two copies
## of them agree. What the edge *looks* like is the GPU's and is not tested.


func _library() -> MeshLibrary:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(1.0, 0.5, 1.0)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shape.surface_get_arrays(0))

	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "Ground")
	library.set_item_mesh(0, mesh)
	return library


## A grid with `filled` painted, and a patch sown over `cells`, both in the tree.
func _patch(cells: Array[Vector3i], filled: Array[Vector3i]) -> TurfPatch:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)

	var grid: GridMap = GridMap.new()
	grid.cell_size = Vector3.ONE
	grid.mesh_library = _library()
	holder.add_child(grid)
	for cell: Vector3i in filled:
		grid.set_cell_item(cell, 0, 0)

	var patch: TurfPatch = TurfPatch.new()
	holder.add_child(patch)
	patch.cells = cells
	patch.layer = patch.get_path_to(grid)
	return patch


## A square block of cells, row by row, so which cell measures a shared corner
## first is settled by the order and not by chance.
func _block(side: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for z: int in range(side):
		for x: int in range(side):
			cells.append(Vector3i(x, 0, z))
	return cells


## The distance each vertex of the mat carries, in the order the cells were sown:
## four per cell, in the corner order `turf_patch.gd` writes them.
func _mat_edges(patch: TurfPatch) -> PackedVector2Array:
	var mat: MeshInstance3D = patch.get_node_or_null("Mat") as MeshInstance3D
	assert_object(mat).is_not_null()
	@warning_ignore("unsafe_cast")
	var carried: PackedVector2Array = (
		mat.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
	)
	return carried


## Where the mat's vertices are, in the same order.
func _mat_points(patch: TurfPatch) -> PackedVector3Array:
	var mat: MeshInstance3D = patch.get_node_or_null("Mat") as MeshInstance3D
	@warning_ignore("unsafe_cast")
	var points: PackedVector3Array = (
		mat.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	)
	return points


## The four corner distances the blades read, one texel per cell.
func _blade_edges(patch: TurfPatch) -> Array[Color]:
	var placing: ShaderMaterial = patch.process_material as ShaderMaterial
	assert_object(placing).is_not_null()
	# Through a typed variable rather than a cast: the strict warnings refuse a cast
	# off a Variant, and an assignment carries the same check.
	var carried: Variant = placing.get_shader_parameter("cell_spots")
	var spots: ImageTexture = carried
	assert_object(spots).is_not_null()
	var image: Image = spots.get_image()
	var found: Array[Color] = []
	for index: int in range(image.get_width()):
		found.append(image.get_pixel(index, 1))
	return found


# --- the two shaders are handed the same boundary -----------------------------


func test_the_blades_and_the_mat_read_the_same_distances() -> void:
	# The invariant the whole feature rests on. Written twice — into a texture for
	# the particles and into a vertex attribute for the quad — because the two
	# stages have no other way to be told anything, and a boundary they disagree
	# about is a dark halo around the grass.
	var cells: Array[Vector3i] = _block(4)
	var patch: TurfPatch = _patch(cells, cells)

	var mat: PackedVector2Array = _mat_edges(patch)
	var blades: Array[Color] = _blade_edges(patch)
	assert_int(blades.size()).is_equal(cells.size())
	assert_int(mat.size()).is_equal(cells.size() * 4)

	for index: int in range(cells.size()):
		var corners: Color = blades[index]
		assert_float(mat[index * 4].x).is_equal_approx(corners.r, 0.0001)
		assert_float(mat[index * 4 + 1].x).is_equal_approx(corners.g, 0.0001)
		assert_float(mat[index * 4 + 2].x).is_equal_approx(corners.b, 0.0001)
		assert_float(mat[index * 4 + 3].x).is_equal_approx(corners.a, 0.0001)


func test_a_corner_four_cells_share_carries_one_distance() -> void:
	# Four quads meet at an inner corner. Measured per cell rather than per corner,
	# each would get its own answer from its own neighbourhood and the mat would
	# crack along the seam between them.
	var cells: Array[Vector3i] = _block(4)
	var patch: TurfPatch = _patch(cells, cells)

	var points: PackedVector3Array = _mat_points(patch)
	var edges: PackedVector2Array = _mat_edges(patch)
	var seen: Dictionary[Vector2i, float] = {}
	for index: int in range(points.size()):
		# Rounded to a tenth of a millimetre, because two quads reach the same
		# corner by adding half a cell to two different centres.
		var at: Vector2i = Vector2i(
			roundi(points[index].x * 10000.0), roundi(points[index].z * 10000.0)
		)
		if not seen.has(at):
			seen[at] = edges[index].x
			continue
		assert_float(edges[index].x).override_failure_message(
			"two quads disagree about the corner at %s" % [points[index]]
		).is_equal_approx(seen[at], 0.0001)


# --- the distances are distances ----------------------------------------------


func test_the_outside_of_a_lone_cell_is_the_edge_itself() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var patch: TurfPatch = _patch(cells, cells)

	# Every corner of a single sown cell touches bare ground, so the grass ends
	# exactly there and there is nothing for the fade to run over.
	for carried: Vector2 in _mat_edges(patch):
		assert_float(carried.x).is_equal_approx(0.0, 0.0001)


func test_the_middle_of_a_block_is_further_in_than_its_border() -> void:
	var cells: Array[Vector3i] = _block(3)
	var patch: TurfPatch = _patch(cells, cells)

	var edges: PackedVector2Array = _mat_edges(patch)
	var deepest: float = 0.0
	for carried: Vector2 in edges:
		deepest = maxf(deepest, carried.x)
	# The inner corners of a three by three block are a cell and a bit from the
	# nearest bare ground; its outer ones are on it.
	assert_float(deepest).is_greater(0.5)
	assert_float(edges[0].x).is_equal_approx(0.0, 0.0001)


func test_the_distances_grow_with_the_grid() -> void:
	# Cells are measured in metres, not in cells: a grid with two-metre spacing is
	# twice as far across, and a fade set in cells has to come out twice as wide.
	var cells: Array[Vector3i] = _block(3)
	var narrow: TurfPatch = _patch(cells, cells)
	var wide: TurfPatch = _patch(cells, cells)
	var grid: GridMap = wide.get_node(wide.layer) as GridMap
	grid.cell_size = Vector3(2.0, 2.0, 2.0)
	wide.cells = cells

	var one: float = 0.0
	for carried: Vector2 in _mat_edges(narrow):
		one = maxf(one, carried.x)
	var two: float = 0.0
	for carried: Vector2 in _mat_edges(wide):
		two = maxf(two, carried.x)
	assert_float(two).is_equal_approx(one * 2.0, 0.0001)


# --- a patch with nothing to sow ----------------------------------------------


func test_a_patch_over_empty_cells_lays_no_mat() -> void:
	var patch: TurfPatch = _patch([Vector3i(4, 0, 4)], [])
	var mat: MeshInstance3D = patch.get_node_or_null("Mat") as MeshInstance3D
	if mat != null:
		assert_bool(mat.visible).is_false()
	# Not the blade count: a particle node cannot hold none, so a patch with
	# nothing to sow is held at one and switched off rather than emptied.
	assert_bool(patch.emitting).is_false()
