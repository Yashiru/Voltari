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


## The field both shaders read, and where it covers.
func _field(patch: TurfPatch) -> Image:
	var placing: ShaderMaterial = patch.process_material as ShaderMaterial
	assert_object(placing).is_not_null()
	# Through a typed variable rather than a cast: the strict warnings refuse a cast
	# off a Variant, and an assignment carries the same check.
	var carried: Variant = placing.get_shader_parameter("room_field")
	var found: ImageTexture = carried
	assert_object(found).is_not_null()
	return found.get_image()


## How far inside the grass a point on the ground is, in metres, read the way the
## shaders read it: the two unsigned channels subtracted.
func _inside(patch: TurfPatch, at: Vector2) -> float:
	var image: Image = _field(patch)
	var placing: ShaderMaterial = patch.process_material as ShaderMaterial
	var held: Variant = placing.get_shader_parameter("field_reach")
	var reach: float = held
	var origin: Variant = placing.get_shader_parameter("field_origin")
	var corner: Vector2 = origin
	var sized: Variant = placing.get_shader_parameter("field_size")
	var span: Vector2 = sized

	var x: int = clampi(floori(
		(at.x - corner.x) / span.x * float(image.get_width())
	), 0, image.get_width() - 1)
	var y: int = clampi(floori(
		(at.y - corner.y) / span.y * float(image.get_height())
	), 0, image.get_height() - 1)
	var texel: Color = image.get_pixel(x, y)
	return (texel.g - texel.b) * reach


## How wide the mat takes to fade out, in metres.
func _mat_width(patch: TurfPatch) -> float:
	var mat: MeshInstance3D = patch.get_node_or_null("Mat") as MeshInstance3D
	var paint: ShaderMaterial = mat.material_override as ShaderMaterial
	var carried: Variant = paint.get_shader_parameter("edge_width")
	var found: float = carried
	return found


# --- the two shaders are handed the same boundary -----------------------------


func test_the_mat_carries_what_the_field_says() -> void:
	# The invariant the whole feature rests on. The blades read the boundary out of
	# the field at their own feet; the mat is handed it per vertex. A boundary the
	# two disagree about is a dark halo around the grass, so the mat's number is
	# read out of the same field rather than worked out a second way.
	var cells: Array[Vector3i] = _block(4)
	var patch: TurfPatch = _patch(cells, cells)

	var mat: PackedVector2Array = _mat_edges(patch)
	var points: PackedVector3Array = _mat_points(patch)
	assert_int(mat.size()).is_equal(cells.size() * 4)

	for index: int in range(points.size()):
		assert_float(mat[index].x).is_equal_approx(
			_inside(patch, Vector2(points[index].x, points[index].z)), 0.0001
		)


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
	# there — to within half a texel of the field it is measured on.
	#
	# **Half a diagonal texel at a corner**, which is where a chamfer is at its
	# worst: it measures from texel centre to texel centre, and the nearest grassy
	# centre to an outside corner lies across the diagonal. A straight edge comes
	# back exact. It is under a tenth of a metre either way, the wander moves the
	# boundary by more than that on purpose, and once the mask is painted rather
	# than made of cells the texel grid is the truth and there is no squarer answer
	# to be closer to.
	for carried: Vector2 in _mat_edges(patch):
		assert_float(carried.x).is_between(-0.13, 0.13)


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
	assert_float(edges[0].x).is_between(-0.13, 0.13)


func test_the_fade_is_set_in_cells_and_applied_in_metres() -> void:
	# `edge_fade` is authored in cells and the shaders work in metres, so a grid
	# with two-metre spacing has to come out with twice the fade. Asserted on the
	# uniform rather than on the field, which saturates at its own reach and
	# therefore cannot show a difference this far inside the grass.
	var cells: Array[Vector3i] = _block(3)
	var narrow: TurfPatch = _patch(cells, cells)
	var wide: TurfPatch = _patch(cells, cells)
	var grid: GridMap = wide.get_node(wide.layer) as GridMap
	grid.cell_size = Vector3(2.0, 2.0, 2.0)
	wide.cells = cells

	assert_float(_mat_width(wide)).is_equal_approx(_mat_width(narrow) * 2.0, 0.0001)


# --- it notices the map changing under it -------------------------------------


func test_the_signature_holds_still_when_the_map_does() -> void:
	# The other half of the contract, and the one that matters for the editor: a
	# signature that changed on its own would regrow every patch four times a
	# second for as long as the scene was open.
	var cells: Array[Vector3i] = _block(3)
	var patch: TurfPatch = _patch(cells, cells)

	var once: int = patch.map_signature()
	for again: int in range(4):
		assert_int(patch.map_signature()).is_equal(once)


func test_painting_a_cell_changes_the_signature() -> void:
	var cells: Array[Vector3i] = _block(3)
	var patch: TurfPatch = _patch(cells, cells)
	var grid: GridMap = patch.get_node(patch.layer) as GridMap

	var before: int = patch.map_signature()
	grid.set_cell_item(Vector3i(1, 1, 1), 0, 0)
	assert_int(patch.map_signature()).override_failure_message(
		"something was painted in the middle of the lawn and the patch did not notice"
	).is_not_equal(before)


func test_turning_a_cell_in_place_changes_the_signature() -> void:
	# The case a list of cells cannot see. A fence rotated where it stands adds no
	# cell and removes none, and its footprint turns with it — so a signature built
	# from `get_used_cells` alone would let the grass keep the shape of the fence
	# that used to be there.
	var cells: Array[Vector3i] = _block(3)
	var patch: TurfPatch = _patch(cells, cells)
	var grid: GridMap = patch.get_node(patch.layer) as GridMap
	grid.set_cell_item(Vector3i(1, 1, 1), 0, 0)

	var before: int = patch.map_signature()
	# 16 is a quarter turn about Y in Godot's orthogonal table.
	grid.set_cell_item(Vector3i(1, 1, 1), 0, 16)
	assert_int(patch.map_signature()).override_failure_message(
		"a cell was turned in place and the patch did not notice"
	).is_not_equal(before)


func test_resowing_grows_the_patch_from_the_map_as_it_is() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	var patch: TurfPatch = _patch(cells, [Vector3i(0, 0, 0)])
	assert_int(_mat_edges(patch).size()).is_equal(4)

	# The second cell is filled after the patch was sown, so only a resow can see
	# it. This is what the editor plugin calls when the map settles.
	var grid: GridMap = patch.get_node(patch.layer) as GridMap
	grid.set_cell_item(Vector3i(1, 0, 0), 0, 0)
	patch.resow()
	assert_int(_mat_edges(patch).size()).is_equal(8)


# --- a patch with nothing to sow ----------------------------------------------


func test_a_patch_over_empty_cells_lays_no_mat() -> void:
	var patch: TurfPatch = _patch([Vector3i(4, 0, 4)], [])
	var mat: MeshInstance3D = patch.get_node_or_null("Mat") as MeshInstance3D
	if mat != null:
		assert_bool(mat.visible).is_false()
	# Not the blade count: a particle node cannot hold none, so a patch with
	# nothing to sow is held at one and switched off rather than emptied.
	assert_bool(patch.emitting).is_false()
