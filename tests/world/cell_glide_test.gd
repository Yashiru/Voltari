extends GdUnitTestSuite

## The half-step between two cells (spec 14, section 2).
##
## Nothing here moves the player. What is asserted is that the drawing catches up
## exactly, arrives, and never overshoots — and that the two cases which must not
## slide, do not.

const HERE: Vector3 = Vector3(0, 0.8, 0)
const NEXT: Vector3 = Vector3(2, 0.8, 0)
const STEP: float = 0.16


func _walking() -> CellGlide:
	var glide: CellGlide = CellGlide.new()
	glide.snap(HERE)
	glide.to(HERE, NEXT, STEP)
	return glide


# --- catching up ---------------------------------------------------------------


func test_it_starts_where_it_was_and_not_where_it_is_going() -> void:
	# The whole point. A step that jumped to the destination and then eased would
	# be the teleport with extra frames.
	assert_vector(_walking().position()).is_equal_approx(HERE, Vector3.ONE * 0.001)


func test_it_arrives_exactly() -> void:
	var glide: CellGlide = _walking()
	glide.advance(STEP)

	assert_vector(glide.position()).is_equal_approx(NEXT, Vector3.ONE * 0.001)
	assert_bool(glide.is_moving()).is_false()


func test_it_never_overshoots() -> void:
	# A frame longer than the step is ordinary — a hitch, a breakpoint, a slow
	# first frame — and it must not throw the body past the cell it is walking to.
	var glide: CellGlide = _walking()
	glide.advance(STEP * 10.0)

	assert_vector(glide.position()).is_equal_approx(NEXT, Vector3.ONE * 0.001)


func test_it_is_halfway_at_halfway() -> void:
	# Linear, deliberately: easing each cell boundary turns holding a direction
	# into a series of lurches.
	var glide: CellGlide = _walking()
	glide.advance(STEP * 0.5)

	assert_vector(glide.position()).is_equal_approx(
		HERE.lerp(NEXT, 0.5), Vector3.ONE * 0.001
	)
	assert_float(glide.progress()).is_equal_approx(0.5, 0.001)


func test_the_pace_is_even_across_the_step() -> void:
	# Same distance per equal slice, which is what makes two steps in a row read
	# as one walk.
	var glide: CellGlide = _walking()
	var last: Vector3 = glide.position()
	var first_move: float = 0.0

	for slice: int in range(4):
		glide.advance(STEP * 0.25)
		var moved: float = last.distance_to(glide.position())
		if slice == 0:
			first_move = moved
		else:
			assert_float(moved).override_failure_message(
				"slice %d moved %f against %f" % [slice, moved, first_move]
			).is_equal_approx(first_move, 0.001)
		last = glide.position()


func test_many_small_frames_arrive_where_one_big_one_does() -> void:
	# The frame rate must not change where anybody ends up.
	var stepped: CellGlide = _walking()
	for frame: int in range(64):
		stepped.advance(STEP / 64.0)

	assert_vector(stepped.position()).is_equal_approx(NEXT, Vector3.ONE * 0.001)


# --- what must not slide -------------------------------------------------------


func test_snapping_arrives_at_once() -> void:
	# A warp, a load and a defeat all move the player somewhere else entirely.
	# Sliding across the gap would draw them walking through whatever is between.
	var glide: CellGlide = _walking()
	glide.advance(STEP * 0.4)
	glide.snap(Vector3(40, 0.8, 40))

	assert_vector(glide.position()).is_equal_approx(Vector3(40, 0.8, 40), Vector3.ONE * 0.001)
	assert_bool(glide.is_moving()).is_false()


func test_a_step_of_no_time_arrives_at_once() -> void:
	# A caller with no opinion about pace is correct rather than broken.
	var glide: CellGlide = CellGlide.new()
	glide.snap(HERE)
	glide.to(HERE, NEXT, 0.0)

	assert_vector(glide.position()).is_equal_approx(NEXT, Vector3.ONE * 0.001)
	assert_bool(glide.is_moving()).is_false()


func test_a_new_step_starts_from_where_the_last_one_got_to() -> void:
	# Interrupting mid-step is ordinary: a step is 0.16 s and a player can turn a
	# corner inside one. Starting the new glide from the cell rather than from the
	# body is the jump this exists to remove.
	var glide: CellGlide = _walking()
	glide.advance(STEP * 0.5)

	var midway: Vector3 = glide.position()
	glide.to(midway, Vector3(2, 0.8, 2), STEP)

	assert_vector(glide.position()).is_equal_approx(midway, Vector3.ONE * 0.001)


# --- refusing nonsense ---------------------------------------------------------


func test_a_frame_of_no_time_changes_nothing() -> void:
	var glide: CellGlide = _walking()
	glide.advance(0.0)
	glide.advance(-1.0)

	assert_vector(glide.position()).is_equal_approx(HERE, Vector3.ONE * 0.001)
	assert_bool(glide.is_moving()).is_true()


func test_advancing_something_that_is_not_moving_is_harmless() -> void:
	var glide: CellGlide = CellGlide.new()
	glide.snap(HERE)

	assert_vector(glide.advance(1.0)).is_equal_approx(HERE, Vector3.ONE * 0.001)


func test_a_destination_that_is_not_a_place_is_refused() -> void:
	# A NaN reaching a transform is a node that vanishes with no error anywhere,
	# and the world is not the layer that should crash over one.
	var glide: CellGlide = CellGlide.new()
	glide.snap(HERE)
	glide.to(HERE, Vector3(NAN, 0, 0), STEP)

	assert_bool(glide.position().is_finite()).is_true()
	assert_vector(glide.position()).is_equal_approx(HERE, Vector3.ONE * 0.001)
