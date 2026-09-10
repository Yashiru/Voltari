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


func test_letting_go_forgets_the_push() -> void:
	# Otherwise a player who walked north, let go, and flicked north again would
	# walk immediately instead of turning.
	var held: VltStepIntent.Held = _held()
	_walking(Vector2(0, -1), held)

	VltStepIntent.of(Vector2.ZERO, held, FRAME)
	var again: VltStepIntent.Step = VltStepIntent.of(Vector2(0, -1), held, FRAME)

	assert_bool(again.walk).override_failure_message(
		"a fresh push walked without turning first"
	).is_false()


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
