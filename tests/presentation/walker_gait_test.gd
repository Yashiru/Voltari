extends GdUnitTestSuite

## How fast a character's legs move, and which way it is turned.
##
## The numbers underneath are measured by `tools/characters/measure_gaits.gd`, so
## what is asserted here is the *rules* that use them: the gait that fits a
## speed, a playback rate that never leaves the band where a cadence still reads
## as human, and a turn that arrives without spinning.

const FRAME: float = 1.0 / 60.0


# --- which gait, how fast -----------------------------------------------------


func test_standing_still_has_no_gait() -> void:
	assert_bool(WalkerGait.moving_at(0.0).is_moving()).is_false()
	assert_str(WalkerGait.moving_at(0.0).clip).is_empty()


func test_a_speed_below_the_threshold_is_standing_still() -> void:
	# Floating point never lands on zero. A body drifting by a millimetre a
	# second must not be running.
	assert_bool(WalkerGait.moving_at(0.001).is_moving()).is_false()


func test_a_walking_pace_walks_and_a_running_pace_runs() -> void:
	assert_str(WalkerGait.moving_at(1.4).clip).is_equal("Walking")
	assert_str(WalkerGait.moving_at(3.6).clip).is_equal("Running")


func test_the_nearest_authored_speed_wins() -> void:
	# Nearest rather than a threshold: a threshold is a number somebody has to
	# pick again every time a clip is added.
	for speed: float in [1.0, 1.5, 2.0]:
		assert_str(WalkerGait.moving_at(speed).clip).override_failure_message(
			"%f should walk" % speed
		).is_equal("Walking")
	for speed: float in [3.0, 4.0, 9.0]:
		assert_str(WalkerGait.moving_at(speed).clip).override_failure_message(
			"%f should run" % speed
		).is_equal("Running")


func test_a_gait_at_its_authored_speed_plays_untouched() -> void:
	# The whole reason the world moves at 3.6 m/s: at that speed the run plays at
	# exactly the cadence the animator made, and the rate is one.
	assert_float(WalkerGait.moving_at(3.6).rate).is_equal_approx(1.0, 0.01)
	assert_float(WalkerGait.moving_at(1.47).rate).is_equal_approx(1.0, 0.01)


func test_the_rate_follows_the_speed() -> void:
	assert_float(WalkerGait.rate_for("Running", 3.6 * 1.1)).is_greater(1.0)
	assert_float(WalkerGait.rate_for("Running", 3.6 * 0.9)).is_less(1.0)


func test_the_rate_never_leaves_the_human_band() -> void:
	# Outside it a cadence stops reading as a gait: a run at twice the rate is
	# 340 steps a minute, which no amount of correct footfall rescues.
	for speed: float in [0.0, 0.5, 3.6, 20.0, 500.0]:
		var rate: float = WalkerGait.rate_for("Running", speed)
		assert_float(rate).override_failure_message(
			"%f m/s gave a rate of %f" % [speed, rate]
		).is_between(WalkerGait.SLOWEST_RATE, WalkerGait.FASTEST_RATE)


func test_a_clip_nobody_measured_plays_at_one() -> void:
	# A gait added to the model and not to the measurements plays untouched
	# rather than at some number invented from nothing.
	assert_float(WalkerGait.rate_for("Cartwheel", 8.0)).is_equal(1.0)


# --- which way it faces -------------------------------------------------------


func test_each_facing_turns_the_body_the_right_way() -> void:
	# The model looks along +Z — measured from the rig, where the toes reach
	# further along +Z than the ankles. So a body at yaw θ faces (sin θ, 0, cos θ).
	for direction: VltFacing.Direction in [
		VltFacing.Direction.NORTH,
		VltFacing.Direction.EAST,
		VltFacing.Direction.SOUTH,
		VltFacing.Direction.WEST,
	]:
		var yaw: float = WalkerGait.yaw_of(direction)
		var looking: Vector2 = Vector2(sin(yaw), cos(yaw))
		var wanted: Vector2 = Vector2(VltFacing.DELTAS[direction])

		assert_float(looking.dot(wanted.normalized())).override_failure_message(
			"facing %d looks %s instead of %s" % [direction, looking, wanted]
		).is_greater(0.999)


func test_the_four_facings_are_a_quarter_turn_apart() -> void:
	var south: float = WalkerGait.yaw_of(VltFacing.Direction.SOUTH)
	var east: float = WalkerGait.yaw_of(VltFacing.Direction.EAST)

	assert_float(absf(angle_difference(south, east))).is_equal_approx(PI * 0.5, 0.001)


# --- turning ------------------------------------------------------------------


func test_a_turn_arrives() -> void:
	var yaw: float = WalkerGait.yaw_of(VltFacing.Direction.SOUTH)
	var wanted: float = WalkerGait.yaw_of(VltFacing.Direction.NORTH)

	for frame: int in range(60):
		yaw = WalkerGait.turned(yaw, wanted, FRAME)

	assert_float(absf(angle_difference(yaw, wanted))).override_failure_message(
		"the turn never finished"
	).is_less(0.001)


func test_a_turn_takes_less_than_a_step() -> void:
	# A quarter turn has to be over before the walk that follows it starts, or
	# the character is walking sideways.
	var yaw: float = WalkerGait.yaw_of(VltFacing.Direction.SOUTH)
	var wanted: float = WalkerGait.yaw_of(VltFacing.Direction.EAST)

	var elapsed: float = 0.0
	while absf(angle_difference(yaw, wanted)) > 0.01 and elapsed < 2.0:
		yaw = WalkerGait.turned(yaw, wanted, FRAME)
		elapsed += FRAME

	assert_float(elapsed).override_failure_message(
		"a quarter turn took %.3f s" % elapsed
	).is_less(0.2)


func test_a_turn_never_overshoots() -> void:
	# A frame longer than the turn is ordinary. Passing the target and coming
	# back is a wobble nobody can explain.
	var wanted: float = WalkerGait.yaw_of(VltFacing.Direction.NORTH)
	var yaw: float = WalkerGait.turned(
		WalkerGait.yaw_of(VltFacing.Direction.SOUTH), wanted, 10.0
	)

	assert_float(absf(angle_difference(yaw, wanted))).is_less(0.001)


func test_a_turn_takes_the_short_way_round() -> void:
	# North to west is a quarter turn one way and three quarters the other.
	var from: float = WalkerGait.yaw_of(VltFacing.Direction.NORTH)
	var wanted: float = WalkerGait.yaw_of(VltFacing.Direction.WEST)
	var moved: float = angle_difference(from, WalkerGait.turned(from, wanted, FRAME))

	assert_float(absf(moved)).is_less(PI)
	assert_bool(signf(moved) == signf(angle_difference(from, wanted))).override_failure_message(
		"the turn went the long way round"
	).is_true()


func test_a_frame_of_no_time_turns_nothing() -> void:
	var from: float = WalkerGait.yaw_of(VltFacing.Direction.SOUTH)
	assert_float(WalkerGait.turned(from, 3.0, 0.0)).is_equal(from)
	assert_float(WalkerGait.turned(from, 3.0, -1.0)).is_equal(from)
