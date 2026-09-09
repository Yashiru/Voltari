extends GdUnitTestSuite

## Which way a walker is turned (spec 14, section 2).
##
## Small, and worth its own suite for one reason: these values are held in a
## save, so the guard at the boundary is what stands between a hand-edited file
## and an index past the end of the deltas.


func test_north_is_negative_z() -> void:
	# Godot's own forward. Getting it backwards would make every map play
	# mirrored, and every single-direction test would still pass.
	assert_vector(VltFacing.delta(VltFacing.Direction.NORTH)).is_equal(Vector2i(0, -1))
	assert_vector(VltFacing.delta(VltFacing.Direction.SOUTH)).is_equal(Vector2i(0, 1))
	assert_vector(VltFacing.delta(VltFacing.Direction.EAST)).is_equal(Vector2i(1, 0))
	assert_vector(VltFacing.delta(VltFacing.Direction.WEST)).is_equal(Vector2i(-1, 0))


func test_opposite_directions_cancel() -> void:
	# A property rather than four constants: it holds whatever the axes are, and
	# it fails on the transposition the literals above would not notice.
	for direction: int in VltFacing.Direction.values():
		var back: int = (direction + 2) % VltFacing.DELTAS.size()
		assert_vector(
			VltFacing.delta(direction as VltFacing.Direction)
			+ VltFacing.delta(back as VltFacing.Direction)
		).override_failure_message(
			"facing %d and its opposite do not cancel" % direction
		).is_equal(Vector2i.ZERO)


func test_every_direction_is_known() -> void:
	for direction: int in VltFacing.Direction.values():
		assert_bool(VltFacing.is_known(direction)).is_true()


func test_a_value_naming_no_direction_is_refused() -> void:
	for nonsense: int in [-1, VltFacing.DELTAS.size(), 9999]:
		assert_bool(VltFacing.is_known(nonsense)).override_failure_message(
			"%d was accepted as a direction" % nonsense
		).is_false()


func test_an_unknown_value_takes_the_fallback() -> void:
	assert_int(VltFacing.known_or(99, VltFacing.Direction.WEST)).is_equal(
		VltFacing.Direction.WEST
	)
	assert_int(
		VltFacing.known_or(VltFacing.Direction.EAST, VltFacing.Direction.WEST)
	).override_failure_message("a valid direction was replaced by the fallback").is_equal(
		VltFacing.Direction.EAST
	)
