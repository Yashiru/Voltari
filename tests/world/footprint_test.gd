extends GdUnitTestSuite

## The shape a model occupies on the ground (spec 14, section 2).
##
## A cell is a metre and a model is not, so blocking is a polygon and what stops
## you is the distance from it. Two questions run through all of this: is the
## error always on the side of *more* solid than the model, and does anything you
## can plainly walk under stay walkable.

const REACH: float = VltFootprint.REACH


## A closed box: all six faces.
##
## Closed, and that matters more than it looks. A floor and a ceiling with no
## walls between them are two pieces that share no corner, so a fixture built
## that way would test the piece-finding against geometry no model ever has.
func _box(mesh: ArrayMesh, at: AABB) -> ArrayMesh:
	return _sides(mesh, at.position.x, at.end.x, at.position.z, at.end.z,
		at.position.x, at.end.x, at.position.z, at.end.z, at.position.y, at.end.y)


## A box that changes width with height, so that clipping it at the band and
## keeping or dropping it whole give three different answers.
func _flare(mesh: ArrayMesh, half: float, top: float, height: float) -> ArrayMesh:
	return _sides(mesh, -half, half, -half, half, -top, top, -top, top, 0.0, height)


func _sides(
	mesh: ArrayMesh, x0: float, x1: float, z0: float, z1: float,
	tx0: float, tx1: float, tz0: float, tz1: float, low: float, high: float
) -> ArrayMesh:
	var floor_ring: Array[Vector3] = [
		Vector3(x0, low, z0), Vector3(x1, low, z0), Vector3(x1, low, z1), Vector3(x0, low, z1)
	]
	var roof_ring: Array[Vector3] = [
		Vector3(tx0, high, tz0), Vector3(tx1, high, tz0),
		Vector3(tx1, high, tz1), Vector3(tx0, high, tz1)
	]

	var points: PackedVector3Array = PackedVector3Array()
	for ring: Array in [floor_ring, roof_ring]:
		@warning_ignore("unsafe_cast")
		var corners: Array[Vector3] = ring as Array[Vector3]
		points.append_array(PackedVector3Array([
			corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]
		]))
	for index: int in range(4):
		var next: int = (index + 1) % 4
		points.append_array(PackedVector3Array([
			floor_ring[index], floor_ring[next], roof_ring[next],
			floor_ring[index], roof_ring[next], roof_ring[index],
		]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _one(at: AABB) -> ArrayMesh:
	return _box(ArrayMesh.new(), at)


func _widest(shapes: Array[PackedVector2Array]) -> Rect2:
	var box: Rect2 = Rect2(shapes[0][0], Vector2.ZERO)
	for point: Vector2 in shapes[0]:
		box = box.expand(point)
	return box


# --- only what is low enough is in the way ------------------------------------


func test_a_model_entirely_overhead_takes_no_ground() -> void:
	# An arch, a balcony, a branch. Maps are made of these, and the whole reason
	# there is a height band at all.
	var above: ArrayMesh = _one(AABB(Vector3(-3.0, 3.0, -3.0), Vector3(6.0, 1.0, 6.0)))

	assert_array(VltFootprint.pieces_of(above, REACH)).is_empty()


func test_something_that_flares_above_the_band_is_cut_at_it() -> void:
	# The case that decides between clipping and choosing, and the only fixture
	# where the three possible answers differ. A trunk half a metre across at the
	# foot, eight metres across at five metres up: cut at two it is 3.8 across,
	# kept whole it is 8, and dropped for reaching too high it is nothing.
	var flared: ArrayMesh = _flare(ArrayMesh.new(), 0.5, 4.0, 5.0)

	var box: Rect2 = _widest(VltFootprint.pieces_of(flared, REACH))

	assert_float(box.size.x).override_failure_message(
		"expected the width at two metres, got a footprint measuring %s" % box
	).is_equal_approx(3.8, 0.01)


func test_a_wall_taller_than_the_band_still_has_a_footprint() -> void:
	# The other way the same choice can go wrong. Dropping any triangle that
	# reaches above the band would leave a hole where the wall is.
	var wall: ArrayMesh = _one(AABB(Vector3(-2.0, 0.0, -0.1), Vector3(4.0, 6.0, 0.2)))

	var box: Rect2 = _widest(VltFootprint.pieces_of(wall, REACH))

	assert_float(box.size.x).is_equal_approx(4.0, 0.001)
	assert_float(box.size.y).is_equal_approx(0.2, 0.001)


# --- one shape per piece, not one per model -----------------------------------


func test_two_separate_pieces_are_two_shapes() -> void:
	var pair: ArrayMesh = _one(AABB(Vector3(-3.0, 0.0, -0.5), Vector3(1.0, 1.0, 1.0)))
	_box(pair, AABB(Vector3(2.0, 0.0, -0.5), Vector3(1.0, 1.0, 1.0)))

	assert_int(VltFootprint.pieces_of(pair, REACH).size()).override_failure_message(
		"one hull around both would fill in the six metres between them"
	).is_equal(2)


func test_pieces_that_touch_are_one_shape() -> void:
	# Welded by position, not by index: importers split vertices by material, by
	# normal and by UV seam, so two triangles sharing an edge on screen routinely
	# share no index at all.
	var joined: ArrayMesh = _one(AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0)))
	_box(joined, AABB(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0)))

	assert_int(VltFootprint.pieces_of(joined, REACH).size()).is_equal(1)


func test_a_gazebo_is_its_posts_and_not_its_floor_plan() -> void:
	# Four posts holding a roof. The roof is what connects them, and it is above
	# the band — so it must not be what decides they are one piece. Getting this
	# wrong fills the gazebo in and stops anybody walking under it, which is the
	# entire purpose of a gazebo.
	# The roof shares its corners with the posts, so they are welded into one run
	# of geometry. A roof merely hovering over them would join nothing and this
	# would pass without testing anything.
	var gazebo: ArrayMesh = ArrayMesh.new()
	for x: float in [-2.0, 2.0]:
		for z: float in [-2.0, 2.0]:
			_box(gazebo, AABB(Vector3(x - 0.1, 0.0, z - 0.1), Vector3(0.2, 2.6, 0.2)))
	_box(gazebo, AABB(Vector3(-2.1, 2.6, -2.1), Vector3(4.2, 0.4, 4.2)))

	var shapes: Array[PackedVector2Array] = VltFootprint.pieces_of(gazebo, REACH)

	assert_int(shapes.size()).override_failure_message(
		"expected four posts, got %d shape(s) — the roof joined them" % shapes.size()
	).is_equal(4)


func test_a_sliver_is_not_something_to_walk_into() -> void:
	# A decal, a shadow plane, a stray triangle.
	var speck: ArrayMesh = _one(AABB(Vector3.ZERO, Vector3(0.005, 0.5, 0.005)))

	assert_array(VltFootprint.pieces_of(speck, REACH)).is_empty()


# --- where the shape ends up --------------------------------------------------


func _layer(item_mesh: Mesh, cell: Vector3i, turn: int = 0) -> GridMap:
	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "post")
	library.set_item_mesh(0, item_mesh)

	var grid: GridMap = auto_free(GridMap.new())
	grid.mesh_library = library
	grid.cell_size = Vector3.ONE
	grid.cell_scale = 0.5
	grid.set_cell_item(cell, 0, turn)
	return grid


func test_a_shape_lands_where_the_grid_draws_the_model() -> void:
	# Two units wide drawn at half scale is one metre, centred on the cell the
	# author painted — not on the origin, and not at the model's own size.
	var grid: GridMap = _layer(
		_one(AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))), Vector3i(4, 0, -3)
	)

	var shapes: Array[VltFootprint] = VltFootprint.on(grid)
	assert_int(shapes.size()).is_equal(1)

	var middle: Vector3 = grid.map_to_local(Vector3i(4, 0, -3))
	assert_bool(shapes[0].blocks(Vector2(middle.x, middle.z), 0.0)).override_failure_message(
		"the shape is not over the cell it was painted on"
	).is_true()
	assert_bool(shapes[0].blocks(Vector2(middle.x + 0.9, middle.z), 0.0)).override_failure_message(
		"the shape kept the model's own size instead of the drawn one"
	).is_false()


func test_a_shape_turns_with_the_cell() -> void:
	# A GridMap cell carries one of 24 orientations, and a plank across a cell is
	# a different obstacle turned a quarter.
	var plank: AABB = AABB(Vector3(-2.0, 0.0, -0.2), Vector3(4.0, 2.0, 0.4))
	var square: GridMap = _layer(_one(plank), Vector3i.ZERO, 0)
	var across: GridMap = _layer(_one(plank), Vector3i.ZERO, 16)

	# A cell's own middle, not the origin: a GridMap centres its cells, so cell
	# zero sits half a cell along every axis.
	var here: Vector3 = square.map_to_local(Vector3i.ZERO)
	var along: Vector2 = Vector2(here.x + 0.8, here.z)
	var sideways: Vector2 = Vector2(here.x, here.z + 0.8)

	assert_bool(VltFootprint.on(square)[0].blocks(along, 0.0)).is_true()
	assert_bool(VltFootprint.on(across)[0].blocks(along, 0.0)).override_failure_message(
		"the shape ignored the cell's orientation"
	).is_false()
	assert_bool(VltFootprint.on(across)[0].blocks(sideways, 0.0)).is_true()


# --- what it takes to touch it ------------------------------------------------


func _square() -> VltFootprint:
	return VltFootprint.new(PackedVector2Array([
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)
	]))


func test_a_point_inside_is_blocked() -> void:
	assert_bool(_square().blocks(Vector2(0.5, 0.0), 0.0)).is_true()


func test_a_body_touching_the_edge_is_blocked() -> void:
	# The disc and not four sample corners: against a five centimetre post, four
	# points sixty centimetres apart pass either side of it.
	assert_bool(_square().blocks(Vector2(1.2, 0.0), 0.3)).is_true()


func test_a_body_clear_of_the_edge_is_not() -> void:
	assert_bool(_square().blocks(Vector2(1.4, 0.0), 0.3)).is_false()


func test_the_normal_points_away_from_the_shape() -> void:
	# What the slide is built on. Worked out from the point rather than from the
	# winding, so it cannot be wrong about which side is outside.
	assert_vector(_square().normal_at(Vector2(2.0, 0.0))).is_equal_approx(
		Vector2.RIGHT, Vector2.ONE * 0.001
	)
	assert_vector(_square().normal_at(Vector2(0.0, -2.0))).is_equal_approx(
		Vector2.UP, Vector2.ONE * 0.001
	)
