extends GdUnitTestSuite

## Turning a stick into a step (spec 18, section 6; decision 0051).
##
## The quantiser is the only part of input with anything to be wrong about, and
## it is a pure function, so it is tested as one. The load-bearing test is the
## tremor: a property a test can hold and a hand cannot, because trying it once
## feels fine and it is the hundredth step that reveals it.

const FRAME: float = 1.0 / 60.0


func _held() -> VltStepIntent.Held:
	return VltStepIntent.Held.new()


## Pushes a stick for long enough that a flick has become a walk.
func _walking(stick: Vector2, held: VltStepIntent.Held) -> VltStepIntent.Step:
	var step: VltStepIntent.Step = VltStepIntent.of(stick, held, 0.0)
	for frame: int in range(20):
		step = VltStepIntent.of(stick, held, FRAME)
	return step


# --- the dead zone -----------------------------------------------------------


func test_a_resting_thumb_is_not_a_direction() -> void:
	var step: VltStepIntent.Step = VltStepIntent.of(Vector2(0.1, 0.1), _held(), FRAME)
	assert_bool(step.wanted).is_false()
	assert_bool(step.walk).is_false()


func test_a_tap_in_the_way_you_already_face_walks_at_once() -> void:
	# A flick is how you turn to face something beside you, so it has nothing to
	# say about a direction you are already facing. Applying it there made every
	# tap a turn to where the walker already looked — which is a tap that does
	# nothing at all, however many times it is repeated.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(0, -1), held)

	VltStepIntent.of(Vector2.ZERO, held, FRAME)
	var again: VltStepIntent.Step = VltStepIntent.of(Vector2(0, -1), held, FRAME)

	assert_bool(again.walk).override_failure_message(
		"a tap in the direction already faced did not walk"
	).is_true()


func test_a_tap_in_a_new_direction_still_only_turns() -> void:
	# The other half, and the reason the flick exists at all.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(0, -1), held)

	VltStepIntent.of(Vector2.ZERO, held, FRAME)
	var sideways: VltStepIntent.Step = VltStepIntent.of(Vector2(1, 0), held, FRAME)

	assert_int(sideways.direction).is_equal(VltFacing.Direction.EAST)
	assert_bool(sideways.walk).override_failure_message(
		"a flick into a new direction walked instead of turning"
	).is_false()


func test_repeated_taps_in_one_direction_all_walk() -> void:
	# What a player actually does, and the shape of the bug: every tap after the
	# first was a turn to a direction already held, so tapping never moved
	# anybody however long they kept at it.
	var held: VltStepIntent.Held = _held()
	held.face(VltFacing.Direction.EAST)

	for tap: int in range(5):
		var pushed: VltStepIntent.Step = VltStepIntent.of(Vector2(1, 0), held, FRAME)
		assert_bool(pushed.walk).override_failure_message(
			"tap %d did not walk" % tap
		).is_true()
		VltStepIntent.of(Vector2.ZERO, held, FRAME)


func test_being_turned_by_something_else_is_remembered() -> void:
	# A door sets the walker's facing, and the quantiser has to hear about it or
	# the two records drift: the walker faces east, this still believes north,
	# and the first tap east turns instead of walking.
	var held: VltStepIntent.Held = _held()
	held.face(VltFacing.Direction.WEST)

	assert_bool(VltStepIntent.of(Vector2(-1, 0), held, FRAME).walk).override_failure_message(
		"the walker was turned west and a push west still had to turn first"
	).is_true()
	assert_bool(VltStepIntent.of(Vector2(1, 0), _turned_west(), FRAME).walk).override_failure_message(
		"a push opposite the facing walked without turning"
	).is_false()


func _turned_west() -> VltStepIntent.Held:
	var held: VltStepIntent.Held = _held()
	held.face(VltFacing.Direction.WEST)
	return held


# --- the dominant axis -------------------------------------------------------


func test_each_quarter_of_the_stick_gives_its_direction() -> void:
	var sticks: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]
	var expected: Array[VltFacing.Direction] = [
		VltFacing.Direction.NORTH,
		VltFacing.Direction.SOUTH,
		VltFacing.Direction.EAST,
		VltFacing.Direction.WEST,
	]

	for index: int in range(sticks.size()):
		var step: VltStepIntent.Step = VltStepIntent.of(sticks[index], _held(), FRAME)
		assert_int(step.direction).override_failure_message(
			"%s did not point %d" % [sticks[index], expected[index]]
		).is_equal(expected[index])


func test_there_are_no_diagonals_because_there_are_no_diagonal_steps() -> void:
	var step: VltStepIntent.Step = VltStepIntent.of(Vector2(0.8, -0.6), _held(), FRAME)
	assert_bool(
		step.direction == VltFacing.Direction.EAST
		or step.direction == VltFacing.Direction.NORTH
	).is_true()


# --- the tremor --------------------------------------------------------------


func test_a_tremor_across_the_diagonal_does_not_zigzag() -> void:
	# The property the bias exists for. Without a margin, the dominant axis
	# flips every frame here and a player walking north-east crosses the map in
	# a staircase.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(0.9, -0.6), held)

	var seen: Dictionary[int, bool] = {}
	var wobble: Array[Vector2] = [
		Vector2(0.71, -0.70), Vector2(0.69, -0.72), Vector2(0.70, -0.71),
		Vector2(0.72, -0.69), Vector2(0.68, -0.73),
	]
	for stick: Vector2 in wobble:
		seen[VltStepIntent.of(stick, held, FRAME).direction] = true

	assert_int(seen.size()).override_failure_message(
		"a tremor at 45 degrees produced %d directions" % seen.size()
	).is_equal(1)


func test_a_deliberate_turn_still_gets_through() -> void:
	# The bias must not be a lock: pushing clearly the other way has to work, or
	# the fix for the zigzag becomes a control that ignores the player.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(1, 0), held)

	var turned: VltStepIntent.Step = VltStepIntent.of(Vector2(0.1, -1.0), held, FRAME)
	assert_int(turned.direction).is_equal(VltFacing.Direction.NORTH)


func test_the_margin_is_needed_in_both_axes() -> void:
	# Held horizontally, a vertical push must beat it; held vertically, the
	# reverse. An asymmetric margin would make one turn easier than the other.
	var horizontal: VltStepIntent.Held = _held()
	_walking(Vector2(1, 0), horizontal)
	assert_int(VltStepIntent.of(Vector2(0.7, -0.72), horizontal, FRAME).direction).is_equal(
		VltFacing.Direction.EAST
	)

	var vertical: VltStepIntent.Held = _held()
	_walking(Vector2(0, -1), vertical)
	assert_int(VltStepIntent.of(Vector2(0.72, -0.7), vertical, FRAME).direction).is_equal(
		VltFacing.Direction.NORTH
	)


# --- a flick turns, a hold walks ---------------------------------------------


func test_a_flick_turns_without_walking() -> void:
	var held: VltStepIntent.Held = _held()
	var step: VltStepIntent.Step = VltStepIntent.of(Vector2(1, 0), held, FRAME)

	assert_bool(step.wanted).is_true()
	assert_int(step.direction).is_equal(VltFacing.Direction.EAST)
	assert_bool(step.walk).override_failure_message(
		"the first frame of a push already walked"
	).is_false()


func test_a_hold_becomes_a_walk() -> void:
	var held: VltStepIntent.Held = _held()
	assert_bool(_walking(Vector2(1, 0), held).walk).is_true()


func test_changing_direction_restarts_the_flick() -> void:
	# A flick is short *in this direction*, not short since the stick moved. A
	# player already walking east who pushes north should face north before
	# stepping into whatever is there.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(1, 0), held)

	var turning: VltStepIntent.Step = VltStepIntent.of(Vector2(0, -1), held, FRAME)
	assert_int(turning.direction).is_equal(VltFacing.Direction.NORTH)
	assert_bool(turning.walk).override_failure_message(
		"turning to a new direction walked into it immediately"
	).is_false()


# --- one layer, several sources ----------------------------------------------


func test_a_keyboard_is_a_stick_pinned_to_an_axis() -> void:
	# Section 1 as a test rather than a hope: the same function serves both, so
	# a phone and a keyboard cannot drift apart.
	var keys: Vector2 = VltStepIntent.from_keys(true, false, false, false)
	var stick: Vector2 = Vector2(0, -1)

	assert_int(VltStepIntent.of(keys, _held(), FRAME).direction).is_equal(
		VltStepIntent.of(stick, _held(), FRAME).direction
	)


func test_opposite_keys_cancel_rather_than_picking_one() -> void:
	var both: Vector2 = VltStepIntent.from_keys(true, true, false, false)
	assert_bool(VltStepIntent.of(both, _held(), FRAME).wanted).is_false()


func test_two_walkers_do_not_interfere() -> void:
	# The state is held by the caller, which is why this is true without any
	# arrangement — and why a test needs no setup.
	var one: VltStepIntent.Held = _held()
	var two: VltStepIntent.Held = _held()

	_walking(Vector2(1, 0), one)
	var fresh: VltStepIntent.Step = VltStepIntent.of(Vector2(1, 0), two, FRAME)

	assert_bool(fresh.walk).is_false()
