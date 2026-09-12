extends GdUnitTestSuite

## Tidying a row of props that are nearly where they should be.
##
## Positions in, positions out, so the awkward cases can be asked directly rather
## than discovered by clicking: one prop, none, several on one spot, a selection
## in an order nobody chose.


# --- which way the row runs ---------------------------------------------------


func test_a_row_along_x_is_read_as_a_row_along_x() -> void:
	assert_bool(
		VltPropLayout.line_of(_points([[0.0, 0.1], [3.0, -0.1], [6.0, 0.05]]))
			.is_equal_approx(Vector3.RIGHT)
	).is_true()


func test_a_row_along_z_is_read_as_a_row_along_z() -> void:
	assert_bool(
		VltPropLayout.line_of(_points([[0.1, 0.0], [-0.1, 3.0], [0.05, 6.0]]))
			.is_equal_approx(Vector3.BACK)
	).is_true()


func test_a_square_always_answers_the_same_way() -> void:
	# Four corners have no row in them, so any answer is arbitrary. What matters is
	# that the arbitrary one does not move between two runs on one selection.
	var square: Array[Vector3] = _points([[0.0, 0.0], [4.0, 0.0], [0.0, 4.0], [4.0, 4.0]])
	assert_bool(VltPropLayout.line_of(square).is_equal_approx(Vector3.RIGHT)).is_true()


func test_one_prop_has_no_row_and_does_not_crash() -> void:
	assert_bool(VltPropLayout.line_of(_points([[1.0, 1.0]])).is_equal_approx(Vector3.RIGHT)).is_true()


# --- aligning -----------------------------------------------------------------


func test_a_nearly_straight_row_becomes_straight() -> void:
	var moved: Array[Vector3] = VltPropLayout.aligned(
		_points([[0.0, 0.2], [3.0, -0.1], [6.0, 0.5]])
	)
	for point: Vector3 in moved:
		assert_float(point.z).is_equal_approx(0.2, 0.0001)


func test_aligning_moves_everything_as_little_as_possible() -> void:
	# The average, not the first of them: the first depends on selection order,
	# which is not something an author chose or can see.
	# Spread ten along the row and three across it, so the row is unambiguously
	# along x and the average across it is a third of three.
	var moved: Array[Vector3] = VltPropLayout.aligned(_points([[0.0, 0.0], [5.0, 0.0], [10.0, 3.0]]))
	for point: Vector3 in moved:
		assert_float(point.z).is_equal_approx(1.0, 0.0001)


func test_aligning_keeps_the_position_along_the_row() -> void:
	var moved: Array[Vector3] = VltPropLayout.aligned(
		_points([[0.0, 0.2], [3.0, -0.1], [6.0, 0.5]])
	)
	assert_float(moved[0].x).is_equal_approx(0.0, 0.0001)
	assert_float(moved[1].x).is_equal_approx(3.0, 0.0001)
	assert_float(moved[2].x).is_equal_approx(6.0, 0.0001)


func test_aligning_leaves_heights_alone() -> void:
	# A row of posts on a slope is a row of posts on a slope. Levelling one would
	# be a second gesture nobody asked for.
	var slope: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0), Vector3(3.0, 1.0, 0.1), Vector3(6.0, 2.0, -0.1)
	]
	var moved: Array[Vector3] = VltPropLayout.aligned(slope)
	for index: int in range(slope.size()):
		assert_float(moved[index].y).is_equal_approx(slope[index].y, 0.0001)


func test_aligning_a_row_that_is_already_straight_changes_nothing() -> void:
	var straight: Array[Vector3] = _points([[0.0, 2.0], [3.0, 2.0], [6.0, 2.0]])
	var moved: Array[Vector3] = VltPropLayout.aligned(straight)
	for index: int in range(straight.size()):
		assert_bool(moved[index].is_equal_approx(straight[index])).is_true()


func test_aligning_one_prop_or_none_does_nothing() -> void:
	assert_array(VltPropLayout.aligned([] as Array[Vector3])).is_empty()
	assert_int(VltPropLayout.aligned(_points([[1.0, 1.0]])).size()).is_equal(1)


# --- spreading ----------------------------------------------------------------


func test_spreading_evens_out_the_gaps() -> void:
	var moved: Array[Vector3] = VltPropLayout.spread(
		_points([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [9.0, 0.0]])
	)
	for index: int in range(1, moved.size()):
		assert_float(moved[index].x - moved[index - 1].x).is_equal_approx(3.0, 0.0001)


func test_spreading_keeps_both_ends_where_they_were() -> void:
	# What makes it repeatable, and what keeps an author's choice of where the row
	# starts and stops.
	var row: Array[Vector3] = _points([[2.0, 0.0], [3.0, 0.0], [11.0, 0.0]])
	var moved: Array[Vector3] = VltPropLayout.spread(row)

	assert_float(moved[0].x).is_equal_approx(2.0, 0.0001)
	assert_float(moved[moved.size() - 1].x).is_equal_approx(11.0, 0.0001)


func test_spreading_twice_changes_nothing_the_second_time() -> void:
	var once: Array[Vector3] = VltPropLayout.spread(
		_points([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [9.0, 0.0]])
	)
	var twice: Array[Vector3] = VltPropLayout.spread(once)
	for index: int in range(once.size()):
		assert_bool(twice[index].is_equal_approx(once[index])).is_true()


func test_spreading_ignores_the_order_it_was_given() -> void:
	# Selection order is not something an author arranged, so a row handed over
	# backwards or shuffled has to come out the same way round.
	var forwards: Array[Vector3] = VltPropLayout.spread(
		_points([[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [9.0, 0.0]])
	)
	var shuffled: Array[Vector3] = VltPropLayout.spread(
		_points([[2.0, 0.0], [9.0, 0.0], [0.0, 0.0], [1.0, 0.0]])
	)
	for index: int in range(forwards.size()):
		assert_bool(shuffled[index].is_equal_approx(forwards[index])).is_true()


func test_spreading_along_z_works_the_same_way() -> void:
	var moved: Array[Vector3] = VltPropLayout.spread(
		_points([[0.0, 0.0], [0.0, 1.0], [0.0, 2.0], [0.0, 9.0]])
	)
	for index: int in range(1, moved.size()):
		assert_float(moved[index].z - moved[index - 1].z).is_equal_approx(3.0, 0.0001)


func test_spreading_leaves_heights_alone() -> void:
	var slope: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 5.0, 0.0), Vector3(9.0, 2.0, 0.0)
	]
	var moved: Array[Vector3] = VltPropLayout.spread(slope)
	for index: int in range(slope.size()):
		assert_float(moved[index].y).is_equal_approx(slope[index].y, 0.0001)


func test_spreading_fewer_than_three_does_nothing() -> void:
	# Two points are already evenly spaced, and so is one.
	var pair: Array[Vector3] = _points([[0.0, 0.0], [4.0, 0.0]])
	var moved: Array[Vector3] = VltPropLayout.spread(pair)
	for index: int in range(pair.size()):
		assert_bool(moved[index].is_equal_approx(pair[index])).is_true()
	assert_array(VltPropLayout.spread([] as Array[Vector3])).is_empty()


func test_spreading_props_all_on_one_spot_does_not_divide_by_nothing() -> void:
	# Three props dropped on the same place is a plausible accident, and it is the
	# input a spacing calculation is most likely to fall over on.
	var heap: Array[Vector3] = _points([[4.0, 4.0], [4.0, 4.0], [4.0, 4.0]])
	for point: Vector3 in VltPropLayout.spread(heap):
		assert_bool(point.is_equal_approx(Vector3(4.0, 0.0, 4.0))).is_true()


# --- fixtures -----------------------------------------------------------------


## Points on the ground, written as (x, z) pairs because the height is never what
## these are about.
func _points(pairs: Array) -> Array[Vector3]:
	var made: Array[Vector3] = []
	for pair: Variant in pairs:
		@warning_ignore("unsafe_cast")
		var xz: Array = pair as Array
		var across: float = xz[0]
		var along: float = xz[1]
		made.append(Vector3(across, 0.0, along))
	return made


# --- fitting to the grid -------------------------------------------------------
#
# A pack's models arrive at whatever size the pack was authored at, so a crate can
# be a tenth of a cell or ten of them. Fitting is per axis on purpose: what comes
# out is a cube of the grid's own units, which is what "one by one by one" says.


func test_a_box_becomes_exactly_one_cell() -> void:
	var wanted: Vector3 = VltPropLayout.fitted(AABB(Vector3.ZERO, Vector3(2.0, 2.0, 2.0)), 1.0, 1)
	assert_bool(wanted.is_equal_approx(Vector3(0.5, 0.5, 0.5))).is_true()


func test_a_box_becomes_exactly_the_cells_asked_for() -> void:
	var wanted: Vector3 = VltPropLayout.fitted(AABB(Vector3.ZERO, Vector3(2.0, 2.0, 2.0)), 1.0, 3)
	assert_bool(wanted.is_equal_approx(Vector3(1.5, 1.5, 1.5))).is_true()


func test_a_lamp_post_is_squashed_into_a_cube() -> void:
	# The consequence of fitting per axis, stated rather than discovered: a model
	# with proportions loses them. It is what was asked for, and a crate — the
	# case this exists for — has none to lose.
	var lamp: AABB = AABB(Vector3.ZERO, Vector3(0.3, 3.0, 0.3))
	var wanted: Vector3 = VltPropLayout.fitted(lamp, 1.0, 1)

	assert_float(lamp.size.x * wanted.x).is_equal_approx(1.0, 0.0001)
	assert_float(lamp.size.y * wanted.y).is_equal_approx(1.0, 0.0001)
	assert_float(lamp.size.z * wanted.z).is_equal_approx(1.0, 0.0001)


func test_fitting_follows_the_grid_s_own_cell() -> void:
	# Two metres a cell is a real setting, and a fit that assumed one would put
	# every prop at half the size on such a map.
	var wanted: Vector3 = VltPropLayout.fitted(AABB(Vector3.ZERO, Vector3(4.0, 4.0, 4.0)), 2.0, 1)
	assert_bool(wanted.is_equal_approx(Vector3(0.5, 0.5, 0.5))).is_true()


func test_an_axis_with_no_thickness_is_left_alone() -> void:
	# A flat sign has no height, and no factor turns nothing into a metre.
	# Stretching by infinity would make a prop that is everywhere and nowhere.
	var flat: Vector3 = VltPropLayout.fitted(AABB(Vector3.ZERO, Vector3(2.0, 0.0, 2.0)), 1.0, 1)
	assert_float(flat.y).is_equal_approx(1.0, 0.0001)
	assert_float(flat.x).is_equal_approx(0.5, 0.0001)


func test_asking_for_no_cells_still_fits_one() -> void:
	var wanted: Vector3 = VltPropLayout.fitted(AABB(Vector3.ZERO, Vector3(2.0, 2.0, 2.0)), 1.0, 0)
	assert_bool(wanted.is_equal_approx(Vector3(0.5, 0.5, 0.5))).is_true()


func test_a_box_reaching_backwards_still_fits() -> void:
	# A model authored around its origin has a box starting at a negative corner,
	# and a size read without its sign would come out negative and mirror it.
	var around: AABB = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))
	assert_bool(VltPropLayout.fitted(around, 1.0, 1).is_equal_approx(Vector3(0.5, 0.5, 0.5))).is_true()


# --- measuring what a prop fills -----------------------------------------------


func test_a_prop_is_measured_in_its_own_space() -> void:
	# Not through the scale it already carries, or fitting twice would give two
	# answers — each measured through the last attempt.
	var prop: VltProp = _prop(Vector3(2.0, 2.0, 2.0))
	prop.scale = Vector3(7.0, 7.0, 7.0)
	assert_bool(VltPropLayout.bounds_of(prop).size.is_equal_approx(Vector3(2.0, 2.0, 2.0))).is_true()


func test_fitting_a_prop_twice_lands_on_the_same_size() -> void:
	var prop: VltProp = _prop(Vector3(2.0, 2.0, 2.0))
	prop.scale = VltPropLayout.fitted(VltPropLayout.bounds_of(prop), 1.0, 1)
	var once: Vector3 = prop.scale

	prop.scale = VltPropLayout.fitted(VltPropLayout.bounds_of(prop), 1.0, 1)
	assert_bool(prop.scale.is_equal_approx(once)).is_true()


func test_a_prop_of_several_models_is_measured_across_all_of_them() -> void:
	var prop: VltProp = _prop(Vector3(1.0, 1.0, 1.0))
	var second: MeshInstance3D = MeshInstance3D.new()
	second.mesh = VltFixtureMap.block(Vector3(1.0, 1.0, 1.0))
	prop.add_child(second)
	second.position = Vector3(4.0, 0.0, 0.0)

	assert_float(VltPropLayout.bounds_of(prop).size.x).is_equal_approx(5.0, 0.0001)


func test_a_prop_with_no_model_fills_nothing() -> void:
	var prop: VltProp = auto_free(VltProp.new())
	assert_bool(VltPropLayout.bounds_of(prop).size.is_zero_approx()).is_true()


## A prop holding one box, centred on its origin in x and z and standing up from
## it — the way the tile library leaves every model.
func _prop(size: Vector3) -> VltProp:
	var prop: VltProp = auto_free(VltProp.new())
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = VltFixtureMap.block(size)
	prop.add_child(part)
	return prop
