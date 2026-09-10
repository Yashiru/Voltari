extends GdUnitTestSuite

## Telling the grass which cell was just stepped into.
##
## A jostle is one shot: a cell is either ringing or it is not, nothing
## accumulates, and nothing is recorded about where anybody has been. What is
## asserted is that shape — that a step starts a swing, that a swing ends, and
## that the two cases which must not ring, do not.

const HERE: Vector3 = Vector3.ZERO
const NEXT: Vector3 = Vector3(1, 0, 0)
const FRAME: float = 1.0 / 60.0

## Longer than any swing, so a test that waits it out is waiting out the real
## thing rather than a number of its own.
const LONG_ENOUGH: float = 4.0


func _field() -> GrassField:
	return GrassField.new()


# --- one shot ------------------------------------------------------------------


func test_a_fresh_field_is_not_ringing() -> void:
	# Grass that started life swinging would ring a cell nobody has stepped on.
	assert_bool(_field().settling()).is_false()


func test_stepping_into_a_cell_starts_it_swinging() -> void:
	var field: GrassField = _field()
	field.enter_cell(HERE)

	assert_bool(field.settling()).is_true()
	assert_float(field.newest_age()).is_equal(0.0)
	assert_vector(field.newest_cell()).is_equal_approx(HERE, Vector3.ONE * 0.001)


func test_a_swing_ends() -> void:
	# Otherwise a cell rings for the rest of the session.
	var field: GrassField = _field()
	field.enter_cell(HERE)

	for frame: int in range(int(LONG_ENOUGH / FRAME)):
		field.advance(FRAME)

	assert_bool(field.settling()).override_failure_message(
		"the cell was still ringing after %.0f seconds" % LONG_ENOUGH
	).is_false()


func test_a_swing_ages_by_the_time_that_passed() -> void:
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.advance(0.25)

	assert_float(field.newest_age()).is_equal_approx(0.25, 0.001)


func test_the_frame_rate_does_not_change_how_long_it_rings() -> void:
	# Ages are seconds, not frames. A swing that lasted a fixed number of frames
	# would be twice as long on a machine running twice as fast.
	var slow: GrassField = _field()
	slow.enter_cell(HERE)
	for frame: int in range(30):
		slow.advance(1.0 / 30.0)

	var fast: GrassField = _field()
	fast.enter_cell(HERE)
	for frame: int in range(240):
		fast.advance(1.0 / 240.0)

	assert_float(slow.newest_age()).is_equal_approx(fast.newest_age(), 0.001)


# --- two cells at a time -------------------------------------------------------


func test_the_cell_you_left_keeps_ringing() -> void:
	# A cell is crossed in about half a second and a swing lasts about as long.
	# With one slot, walking on would cut every swing off mid-air.
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.advance(0.2)
	field.enter_cell(NEXT)

	assert_vector(field.newest_cell()).is_equal_approx(NEXT, Vector3.ONE * 0.001)
	assert_float(field.newest_age()).is_equal(0.0)
	assert_float(field.older_age()).override_failure_message(
		"the cell just left was forgotten rather than left to settle"
	).is_equal_approx(0.2, 0.001)


func test_both_cells_age_together() -> void:
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.enter_cell(NEXT)
	field.advance(0.1)

	assert_float(field.newest_age()).is_equal_approx(0.1, 0.001)
	assert_float(field.older_age()).is_equal_approx(0.1, 0.001)


func test_a_third_step_drops_the_oldest() -> void:
	# Two slots, and the one that goes is the one furthest through its swing.
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.advance(0.3)
	field.enter_cell(NEXT)
	field.advance(0.1)
	field.enter_cell(Vector3(2, 0, 0))

	assert_float(field.older_age()).is_equal_approx(0.1, 0.001)


# --- what must not ring --------------------------------------------------------


func test_going_quiet_stops_everything() -> void:
	# What a warp and a defeat need: a swing left over from the map you came from
	# would ring a cell on this one that nobody has stepped on.
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.enter_cell(NEXT)
	field.quiet()

	assert_bool(field.settling()).is_false()


func test_advancing_a_quiet_field_costs_nothing_and_changes_nothing() -> void:
	var field: GrassField = _field()
	field.advance(1.0)

	assert_bool(field.settling()).is_false()


func test_a_frame_of_no_time_ages_nothing() -> void:
	var field: GrassField = _field()
	field.enter_cell(HERE)
	field.advance(0.0)
	field.advance(-1.0)

	assert_float(field.newest_age()).is_equal(0.0)


func test_a_cell_that_is_not_a_place_is_refused() -> void:
	# A NaN reaching a shader is grass that vanishes with no error anywhere.
	var field: GrassField = _field()
	field.enter_cell(Vector3(NAN, 0.0, 0.0))

	assert_bool(field.settling()).is_false()
	assert_bool(field.newest_cell().is_finite()).is_true()


# --- finding the materials -----------------------------------------------------


func _grassy_map() -> VltWorldMap:
	var map: VltWorldMap = auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(3, 3)))
	)

	var shaded: ShaderMaterial = ShaderMaterial.new()
	shaded.shader = load("res://game/presentation/world/grass_parting.gdshader")

	var mesh: ArrayMesh = ArrayMesh.new()
	var box: BoxMesh = BoxMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	mesh.surface_set_material(0, shaded)

	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_mesh(0, mesh)
	map.decor.mesh_library = library
	return map


func test_it_finds_the_grass_a_map_draws_with() -> void:
	var field: GrassField = _field()
	field.of_map(_grassy_map())

	assert_int(field.material_count()).override_failure_message(
		"the grass material was not found on the map"
	).is_equal(1)


func test_a_material_shared_by_two_layers_is_held_once() -> void:
	# The same library usually sits on all three layers. Without this, every
	# uniform would be written three times a frame for no effect.
	var map: VltWorldMap = _grassy_map()
	map.terrain.mesh_library = map.decor.mesh_library
	map.blocking.mesh_library = map.decor.mesh_library

	var field: GrassField = _field()
	field.of_map(map)

	assert_int(field.material_count()).is_equal(1)


func test_a_map_with_no_grass_holds_nothing() -> void:
	var bare: VltWorldMap = auto_free(
		VltFixtureMap.map("bare", VltFixtureMap.filled(Vector2i(2, 2)))
	)
	var field: GrassField = _field()
	field.of_map(bare)

	assert_int(field.material_count()).is_equal(0)


func test_no_map_at_all_is_harmless() -> void:
	var field: GrassField = _field()
	field.of_map(null)
	field.enter_cell(HERE)
	field.advance(FRAME)

	assert_int(field.material_count()).is_equal(0)


# --- how far a jostle reaches --------------------------------------------------


func _reach_of(map: VltWorldMap) -> float:
	var field: GrassField = _field()
	field.of_map(map)
	var mesh: Mesh = map.decor.mesh_library.get_item_mesh(0)
	var material: ShaderMaterial = mesh.surface_get_material(0) as ShaderMaterial
	return material.get_shader_parameter("jostle_reach")


func test_the_reach_comes_from_the_grid() -> void:
	# A number in the shader would ring five cells on a map painted at half the
	# size and none at all on one painted at twice. The grid is the only thing
	# that knows.
	var map: VltWorldMap = _grassy_map()
	map.terrain.cell_size = Vector3.ONE * 2.0

	assert_float(_reach_of(map)).is_equal_approx(
		2.0 * GrassField.REACH_OF_A_CELL, 0.001
	)


func test_the_reach_stays_inside_one_cell() -> void:
	# Over half a cell, so the cell stepped onto rings; under a whole one, so its
	# neighbours do not.
	var map: VltWorldMap = _grassy_map()
	map.terrain.cell_size = Vector3.ONE * 1.0

	assert_float(_reach_of(map)).is_between(0.5, 0.999)
