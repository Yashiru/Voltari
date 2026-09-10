extends GdUnitTestSuite

## Telling the grass where the walker is.
##
## The shader is a pure function of one point, so all of the softness is here:
## the point lags behind the player, and grass just left is still inside the
## reach of a centre that has not caught up. What is asserted is the lag —
## that it converges, that it does not depend on the frame rate, and that the
## two cases which must not lag, do not.

const HERE: Vector3 = Vector3.ZERO
const THERE: Vector3 = Vector3(4, 0, 0)
const FRAME: float = 1.0 / 60.0


func _following() -> GrassField:
	var field: GrassField = GrassField.new()
	field.place(HERE)
	return field


# --- the lag -------------------------------------------------------------------


func test_the_centre_starts_where_it_was_told() -> void:
	assert_vector(_following().centre()).is_equal_approx(HERE, Vector3.ONE * 0.001)


func test_it_lags_behind_rather_than_arriving() -> void:
	# The whole effect. A centre that arrived at once would make grass spring
	# upright the instant a foot left it.
	var field: GrassField = _following()
	field.follow(THERE, FRAME)

	assert_bool(field.centre().distance_to(THERE) > 0.1).override_failure_message(
		"the centre arrived in one frame"
	).is_true()
	assert_bool(field.centre().distance_to(HERE) > 0.0).override_failure_message(
		"the centre did not move at all"
	).is_true()


func test_it_gets_there() -> void:
	var field: GrassField = _following()
	for frame: int in range(120):
		field.follow(THERE, FRAME)

	assert_vector(field.centre()).is_equal_approx(THERE, Vector3.ONE * 0.01)


func test_it_never_overshoots() -> void:
	# A frame far longer than the smoothing constant is ordinary — a hitch, a
	# breakpoint — and a fixed fraction per frame would fly past the player.
	var field: GrassField = _following()
	field.follow(THERE, 10.0)

	assert_float(field.centre().x).is_less_equal(THERE.x + 0.001)


func test_the_frame_rate_does_not_change_the_feel() -> void:
	# A fixed fraction per frame makes grass recover faster on a fast machine,
	# which is the sort of difference nobody attributes to the frame rate.
	var slow: GrassField = _following()
	for frame: int in range(30):
		slow.follow(THERE, 1.0 / 30.0)

	var fast: GrassField = _following()
	for frame: int in range(240):
		fast.follow(THERE, 1.0 / 240.0)

	assert_vector(slow.centre()).override_failure_message(
		"thirty frames landed at %s and two hundred and forty at %s"
		% [slow.centre(), fast.centre()]
	).is_equal_approx(fast.centre(), Vector3.ONE * 0.02)


func test_placing_arrives_at_once() -> void:
	# What a warp and a defeat need: letting the centre travel would draw a
	# parting sweeping across the floor.
	var field: GrassField = _following()
	field.follow(THERE, FRAME)
	field.place(THERE)

	assert_vector(field.centre()).is_equal_approx(THERE, Vector3.ONE * 0.001)


func test_a_frame_of_no_time_changes_nothing() -> void:
	var field: GrassField = _following()
	field.follow(THERE, 0.0)

	assert_vector(field.centre()).is_equal_approx(HERE, Vector3.ONE * 0.001)


func test_somewhere_that_is_not_a_place_is_refused() -> void:
	var field: GrassField = _following()
	field.follow(Vector3(NAN, 0, 0), FRAME)
	field.place(Vector3(0, INF, 0))

	assert_bool(field.centre().is_finite()).is_true()
	assert_vector(field.centre()).is_equal_approx(HERE, Vector3.ONE * 0.001)


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
	var field: GrassField = GrassField.new()
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

	var field: GrassField = GrassField.new()
	field.of_map(map)

	assert_int(field.material_count()).is_equal(1)


func test_a_map_with_no_grass_holds_nothing() -> void:
	var bare: VltWorldMap = auto_free(
		VltFixtureMap.map("bare", VltFixtureMap.filled(Vector2i(2, 2)))
	)
	var field: GrassField = GrassField.new()
	field.of_map(bare)

	assert_int(field.material_count()).is_equal(0)


func test_no_map_at_all_is_harmless() -> void:
	var field: GrassField = GrassField.new()
	field.of_map(null)
	field.follow(THERE, FRAME)

	assert_int(field.material_count()).is_equal(0)


# --- the wake ------------------------------------------------------------------


## Walks the way the world walks: a position that moves every frame.
##
## Handing the same point over and over is a teleport followed by standing still,
## and a field told that correctly reports nobody going anywhere. Getting this
## wrong is what three of these tests did first time round.
func _walk(field: GrassField, direction: Vector3, pace: float, frames: int) -> Vector3:
	var at: Vector3 = field.centre()
	for frame: int in range(frames):
		at += direction.normalized() * pace * FRAME
		field.follow(at, FRAME)
	return at


func test_the_wake_trails_behind_the_centre() -> void:
	# The whole of the trail. Grass the trailing centre still covers but the
	# leading one has left is grass just stepped off — and the shader has no
	# other way to know it.
	var field: GrassField = _following()
	var at: Vector3 = _walk(field, Vector3(1, 0, 0), 2.0, 30)

	assert_float(field.wake().distance_to(at)).override_failure_message(
		"the wake kept up with the walker, so there is nothing behind them"
	).is_greater(field.centre().distance_to(at) + 0.05)


func test_the_wake_catches_up_when_the_walker_stops() -> void:
	# Otherwise the trail never closes and the field stays dented for good.
	var field: GrassField = _following()
	var at: Vector3 = _walk(field, Vector3(1, 0, 0), 2.0, 30)
	for frame: int in range(240):
		field.follow(at, FRAME)

	assert_vector(field.wake()).is_equal_approx(at, Vector3.ONE * 0.02)


func test_placing_collapses_the_wake_onto_the_walker() -> void:
	# A warp leaves no trail: the player was never between the two maps.
	var field: GrassField = _following()
	_walk(field, Vector3(1, 0, 0), 2.0, 20)
	field.place(Vector3(9, 0, 9))

	assert_vector(field.wake()).is_equal_approx(field.centre(), Vector3.ONE * 0.001)


# --- which way, and how fast ---------------------------------------------------


func test_the_heading_points_where_the_walker_is_going() -> void:
	# Grass splays along the path rather than opening in a circle, and a circle
	# is a force field.
	var field: GrassField = _following()
	_walk(field, Vector3(1, 0, 0), 2.0, 40)

	assert_float(field.heading().dot(Vector3(1, 0, 0))).override_failure_message(
		"heading is %s for a walk due east" % field.heading()
	).is_greater(0.9)


func test_the_heading_is_always_a_direction() -> void:
	# A zero heading is not a direction, and handing one to the shader would
	# collapse the splay to whatever the arithmetic happened to produce.
	var field: GrassField = _following()
	assert_float(field.heading().length()).is_equal_approx(1.0, 0.001)

	for frame: int in range(60):
		field.follow(field.centre(), FRAME)
	assert_float(field.heading().length()).override_failure_message(
		"standing still flattened the heading to nothing"
	).is_equal_approx(1.0, 0.001)


func test_the_heading_does_not_snap_round_a_corner() -> void:
	# A heading that turned in one frame would flick the splay through ninety
	# degrees the frame a player turned.
	var field: GrassField = _following()
	var at: Vector3 = _walk(field, Vector3(1, 0, 0), 2.0, 40)

	var before: Vector3 = field.heading()
	field.follow(at + Vector3(0, 0, 0.2), FRAME)

	assert_float(field.heading().angle_to(before)).override_failure_message(
		"the heading turned %f radians in one frame" % field.heading().angle_to(before)
	).is_less(0.5)


func test_speed_rises_with_walking_and_falls_with_standing() -> void:
	var field: GrassField = _following()
	var at: Vector3 = _walk(field, Vector3(1, 0, 0), 3.0, 30)
	var walking: float = field.speed()

	for frame: int in range(60):
		field.follow(at, FRAME)

	assert_float(walking).override_failure_message("walking read as still").is_greater(0.4)
	assert_float(field.speed()).override_failure_message(
		"standing still read as walking"
	).is_less(0.05)


func test_speed_never_leaves_its_range() -> void:
	# It scales the splay, and a splay beyond one would push grass further than
	# the shader was tuned for.
	var field: GrassField = _following()
	_walk(field, Vector3(1, 0, 0), 40.0, 20)

	assert_float(field.speed()).is_between(0.0, 1.0)


func test_a_frame_of_no_time_does_not_erase_the_travel() -> void:
	# A zero-delta frame that moved the mark would make the next frame measure
	# no motion at all, and the walker would read as standing still while
	# walking.
	var field: GrassField = _following()
	var at: Vector3 = _walk(field, Vector3(1, 0, 0), 3.0, 30)
	var walking: float = field.speed()

	at += Vector3(0.05, 0, 0)
	field.follow(at, 0.0)
	field.follow(at, FRAME)

	assert_float(field.speed()).override_failure_message(
		"a frame of no time dropped the speed from %f to %f" % [walking, field.speed()]
	).is_greater(0.2)
