extends GdUnitTestSuite

## How fast a character's legs move, and which way it is turned.
##
## The numbers underneath are measured by `tools/characters/measure_clips.gd`, so
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
	assert_str(WalkerGait.moving_at(1.33).clip).is_equal(HumanoidClips.WALK)
	assert_str(WalkerGait.moving_at(3.33).clip).is_equal(HumanoidClips.RUN)


func test_the_nearest_authored_speed_wins() -> void:
	# Nearest rather than a threshold: a threshold is a number somebody has to
	# pick again every time a clip is added.
	for speed: float in [1.0, 1.5, 2.0]:
		assert_str(WalkerGait.moving_at(speed).clip).override_failure_message(
			"%f should walk" % speed
		).is_equal(HumanoidClips.WALK)
	for speed: float in [3.0, 4.0, 9.0]:
		assert_str(WalkerGait.moving_at(speed).clip).override_failure_message(
			"%f should run" % speed
		).is_equal(HumanoidClips.RUN)


func test_a_gait_at_its_authored_speed_plays_untouched() -> void:
	# The whole reason the world moves at 3.33 m/s: at that speed the run plays at
	# exactly the cadence the animator made, and the rate is one.
	for slot: String in WalkerGait.LOOKS_RIGHT_AT:
		assert_float(
			WalkerGait.moving_at(WalkerGait.LOOKS_RIGHT_AT[slot]).rate
		).override_failure_message("%s is not played untouched at its own speed" % slot).is_equal_approx(
			1.0, 0.01
		)


func test_the_rate_follows_the_speed() -> void:
	var authored: float = WalkerGait.LOOKS_RIGHT_AT[HumanoidClips.RUN]
	assert_float(WalkerGait.rate_for(HumanoidClips.RUN, authored * 1.1)).is_greater(1.0)
	assert_float(WalkerGait.rate_for(HumanoidClips.RUN, authored * 0.9)).is_less(1.0)


func test_the_rate_never_leaves_the_human_band() -> void:
	# Outside it a cadence stops reading as a gait: a run at twice the rate is
	# 340 steps a minute, which no amount of correct footfall rescues.
	for speed: float in [0.0, 0.5, 3.33, 20.0, 500.0]:
		var rate: float = WalkerGait.rate_for(HumanoidClips.RUN, speed)
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


# --- turning on the spot ------------------------------------------------------

## What the four clips actually deliver, near enough. The runtime reads these off
## the clips themselves; a test that did the same would be asserting that a
## measurement equals itself, so the shape is restated here and the body's own
## tests hold it against the assets.
const DELIVERS: Dictionary[String, float] = {
	HumanoidClips.TURN_LEFT_90: 1.5708,
	HumanoidClips.TURN_RIGHT_90: -1.7914,
	HumanoidClips.TURN_LEFT_180: 3.0743,
	HumanoidClips.TURN_RIGHT_180: -3.0556,
}


func test_a_small_angle_is_not_worth_a_clip() -> void:
	assert_bool(
		WalkerGait.pivot_by(WalkerGait.TURN_FLOOR * 0.9, DELIVERS).is_turning()
	).is_false()
	assert_bool(
		WalkerGait.pivot_by(-WalkerGait.TURN_FLOOR * 0.9, DELIVERS).is_turning()
	).is_false()


func test_a_turn_is_never_served_by_a_clip_that_goes_the_other_way() -> void:
	# The feet cross the other way, and everybody can see it.
	for degrees: float in [65.0, 90.0, 140.0, 180.0]:
		var wanted: float = deg_to_rad(degrees)
		assert_float(
			signf(WalkerGait.pivot_by(wanted, DELIVERS).authored)
		).override_failure_message("%.0f degrees picked a clip going the other way" % degrees).is_equal(1.0)
		assert_float(
			signf(WalkerGait.pivot_by(-wanted, DELIVERS).authored)
		).override_failure_message("-%.0f degrees picked a clip going the other way" % degrees).is_equal(-1.0)


func test_the_nearest_authored_angle_wins() -> void:
	assert_str(WalkerGait.pivot_by(deg_to_rad(85.0), DELIVERS).clip).is_equal(
		HumanoidClips.TURN_LEFT_90
	)
	assert_str(WalkerGait.pivot_by(deg_to_rad(170.0), DELIVERS).clip).is_equal(
		HumanoidClips.TURN_LEFT_180
	)


func test_a_turn_delivers_the_angle_it_was_asked_for() -> void:
	# Warped onto the exact angle rather than played at face value. The clips are
	# 90, -103, 176 and -175 degrees, and none of those is what a player asked
	# for.
	for degrees: float in [70.0, 90.0, 120.0, 176.0, -90.0, -140.0, -175.0]:
		var wanted: float = deg_to_rad(degrees)
		var pivot: WalkerGait.Pivot = WalkerGait.pivot_by(wanted, DELIVERS)
		assert_float(pivot.delivers).override_failure_message(
			"%.0f degrees would have turned %.1f" % [degrees, rad_to_deg(pivot.delivers)]
		).is_equal_approx(wanted, 0.001)


func test_a_clip_is_never_warped_past_the_band() -> void:
	# Outside it the feet pivot across ground the body is not turning through.
	for degrees: float in [61.0, 90.0, 180.0, 270.0, -61.0, -180.0, -270.0]:
		var pivot: WalkerGait.Pivot = WalkerGait.pivot_by(deg_to_rad(degrees), DELIVERS)
		if not pivot.is_turning():
			continue
		assert_float(pivot.warp()).override_failure_message(
			"%.0f degrees warped its clip by %.2f" % [degrees, pivot.warp()]
		).is_between(WalkerGait.NARROWEST_WARP, WalkerGait.WIDEST_WARP)


func test_nothing_is_delivered_when_no_clip_is() -> void:
	var pivot: WalkerGait.Pivot = WalkerGait.pivot_by(0.1, DELIVERS)
	assert_bool(pivot.is_turning()).is_false()
	assert_float(pivot.delivers).is_equal(0.0)
	assert_float(pivot.warp()).is_equal(1.0)
