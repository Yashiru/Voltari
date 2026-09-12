extends GdUnitTestSuite

## The character who walks the map (decision 0057).
##
## The model is committed, so unlike a creature this one is really there and the
## tests can say so. What they pin is the behaviour a reviewer would look for
## first: that the legs follow the ground continuously rather than switching, that
## chained steps do not flicker, that a turn is a turn and not a snap, and that a
## missing model still leaves a player.

const FRAME: float = 1.0 / 60.0

## The speeds the two gaits were authored for. Read rather than restated, so a
## re-measurement moves the tests with it.
var _walking: float = WalkerGait.LOOKS_RIGHT_AT[HumanoidClips.WALK]
var _running: float = WalkerGait.LOOKS_RIGHT_AT[HumanoidClips.RUN]


func _body() -> WalkerBody:
	var body: WalkerBody = auto_free(WalkerBody.new())
	add_child(body)
	return body


## Long enough for the blend to have caught up with the ground.
func _hold(body: WalkerBody, speed: float, heading: Vector2 = Vector2(0, 1)) -> void:
	for frame: int in range(60):
		body.advance(FRAME, speed, heading)


# --- the model itself ---------------------------------------------------------


func test_the_character_is_there() -> void:
	var body: WalkerBody = _body()

	assert_bool(body.has_model()).override_failure_message(
		"the character model did not load"
	).is_true()


func test_it_stands_at_human_height_and_is_not_resized() -> void:
	# The model is 1.7 m with its feet at its origin, which is a person on a
	# two-metre grid. Resizing it would be inventing a scale the artist chose.
	var body: WalkerBody = _body()

	assert_float(body.height()).is_between(1.5, 2.0)
	var model: Node3D = body.get_child(0) as Node3D
	assert_object(model).is_not_null()
	assert_vector(model.scale).override_failure_message(
		"the character was scaled"
	).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.001)


func test_it_is_idling_before_anything_asks_it_to() -> void:
	assert_str(_body().playing()).is_equal(HumanoidClips.IDLE)


# --- standing, walking, running -----------------------------------------------


func test_moving_runs_and_stopping_settles_to_the_idle() -> void:
	var body: WalkerBody = _body()

	_hold(body, _running)
	assert_str(body.playing()).is_equal(HumanoidClips.RUN)

	# Past the grace, which is what a real stop is.
	_hold(body, 0.0)
	assert_str(body.playing()).is_equal(HumanoidClips.IDLE)


func test_a_walking_pace_walks() -> void:
	# Reachable without anything being written for it: the axis is in metres a
	# second and the walk stands on it at the speed it was authored for.
	var body: WalkerBody = _body()

	_hold(body, _walking)
	assert_str(body.playing()).is_equal(HumanoidClips.WALK)


func test_the_legs_follow_the_ground_continuously() -> void:
	# The blend position is a speed, not a choice between two clips. Every speed
	# between the two gaits has to land somewhere between them, or there is a
	# threshold in here that nobody declared.
	var body: WalkerBody = _body()

	var last: float = -1.0
	for speed: float in [0.0, 0.5, _walking, 2.3, _running]:
		_hold(body, speed)
		assert_float(body.shown_speed()).override_failure_message(
			"the legs did not reach %f m/s" % speed
		).is_equal_approx(speed, 0.01)
		assert_float(body.shown_speed()).override_failure_message(
			"the legs went backwards between speeds"
		).is_greater(last)
		last = body.shown_speed()


func test_the_legs_do_not_change_gait_inside_one_frame() -> void:
	# A stick released goes from full to nothing in one frame. Legs that answered
	# that exactly would be a cut wearing a blend's clothes.
	var body: WalkerBody = _body()
	_hold(body, _running)

	body.advance(FRAME, 0.0, Vector2(0, 1))
	assert_float(body.shown_speed()).override_failure_message(
		"the legs stopped inside one frame"
	).is_greater(_running * 0.5)


func test_chained_steps_never_drop_to_the_idle() -> void:
	# Two steps in a row are separated by a single frame at zero speed. Without a
	# grace the legs flicker between running and standing on every cell boundary,
	# which is the artefact this is here to prevent.
	var body: WalkerBody = _body()

	for step: int in range(6):
		for frame: int in range(9):
			body.advance(FRAME, _running, Vector2(1, 0))
		# The seam between two steps.
		body.advance(FRAME, 0.0, Vector2(1, 0))
		# Not "is running": the legs are still coming up to speed, and which gait
		# a blend is nearest to on the way is not the point. What must never
		# happen at a seam is standing still.
		assert_str(body.playing()).override_failure_message(
			"the legs stopped between step %d and the next" % step
		).is_not_equal(HumanoidClips.IDLE)


func test_the_grace_is_shorter_than_a_pause() -> void:
	# It must not turn a genuine stop into a skid.
	var body: WalkerBody = _body()
	_hold(body, _running)

	var elapsed: float = 0.0
	while body.playing() != HumanoidClips.IDLE and elapsed < 2.0:
		body.advance(FRAME, 0.0, Vector2(0, 1))
		elapsed += FRAME

	assert_float(elapsed).override_failure_message(
		"it took %.2f s to stop" % elapsed
	).is_less(0.6)


func test_every_slot_the_arithmetic_can_ask_for_is_in_the_library() -> void:
	# The vocabulary and the assets, checked against each other rather than by
	# reading both lists. A clip named in the arithmetic and missing from the
	# folder is a character that freezes at one speed and no other.
	var clips: AnimationLibrary = HumanoidClips.library()

	for slot: String in WalkerGait.LOOKS_RIGHT_AT:
		assert_bool(clips.has_animation(slot)).override_failure_message(
			"no clip for the gait %s" % slot
		).is_true()
	for slot: String in HumanoidClips.TURNS:
		assert_bool(clips.has_animation(slot)).override_failure_message(
			"no clip for the turn %s" % slot
		).is_true()
	assert_bool(clips.has_animation(HumanoidClips.IDLE)).is_true()


# --- turning ------------------------------------------------------------------


func test_it_turns_rather_than_snapping() -> void:
	# A world that snapped would flick the model through ninety degrees inside
	# one frame, which is the cheapest thing to get wrong here.
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))
	var from: float = body.rotation.y

	body.advance(FRAME, 0.0, Vector2(1, 0))
	var moved: float = absf(angle_difference(from, body.rotation.y))

	assert_float(moved).override_failure_message("it did not turn at all").is_greater(0.0)
	assert_float(moved).override_failure_message(
		"it snapped a quarter turn in one frame"
	).is_less(PI * 0.5 * 0.9)


func test_a_small_turn_is_not_worth_a_clip() -> void:
	# A character who plays a turn because the stick moved a few degrees is a
	# character who never does what they were told.
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))
	var barely: Vector2 = Vector2(sin(WalkerGait.TURN_FLOOR * 0.5), cos(WalkerGait.TURN_FLOOR * 0.5))

	body.advance(FRAME, 0.0, barely)

	assert_bool(body.is_turning()).override_failure_message(
		"a small turn started a clip"
	).is_false()


func test_a_turn_from_a_standstill_is_carried_by_a_clip() -> void:
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))

	body.advance(FRAME, 0.0, Vector2(1, 0))

	assert_bool(body.is_turning()).override_failure_message(
		"a quarter turn on the spot did not use a clip"
	).is_true()


func test_a_turn_lands_on_the_angle_it_was_asked_for() -> void:
	# The clips deliver 90, -103, 176 and -175 degrees. Landing on what was asked
	# for rather than on what a clip happens to carry is the whole point of
	# warping them.
	for degrees: float in [90.0, -90.0, 180.0, -140.0, 70.0]:
		var body: WalkerBody = _body()
		body.face_at_once(Vector2(0, 1))
		var wanted: float = deg_to_rad(degrees)
		var heading: Vector2 = Vector2(sin(wanted), cos(wanted))

		for frame: int in range(240):
			body.advance(FRAME, 0.0, heading)

		assert_float(
			absf(angle_difference(body.rotation.y, wanted))
		).override_failure_message(
			"asked for %.0f degrees and landed on %.1f" % [degrees, rad_to_deg(body.rotation.y)]
		).is_less(0.01)


func test_a_step_gives_up_on_a_turn() -> void:
	# The legs are about to carry the turn anyway. A body finishing a swivel it no
	# longer needs is the one thing here that reads as ignoring the player.
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))
	body.advance(FRAME, 0.0, Vector2(0, -1))
	assert_bool(body.is_turning()).is_true()

	body.advance(FRAME, _running, Vector2(0, -1))

	assert_bool(body.is_turning()).override_failure_message(
		"it kept turning on the spot while walking away"
	).is_false()


func test_a_turn_finishes() -> void:
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))

	for frame: int in range(240):
		body.advance(FRAME, 0.0, Vector2(-1, 0))

	assert_float(
		absf(angle_difference(body.rotation.y, WalkerGait.yaw_towards(Vector2(-1, 0))))
	).is_less(0.001)


func test_arriving_somewhere_faces_at_once() -> void:
	# A warp, a load and a defeat all put the player somewhere else. Turning
	# through the change would spin them on arrival.
	var body: WalkerBody = _body()
	_hold(body, _running)
	body.face_at_once(Vector2(0, -1))

	assert_float(body.rotation.y).is_equal_approx(
		WalkerGait.yaw_towards(Vector2(0, -1)), 0.001
	)
	assert_str(body.playing()).override_failure_message(
		"it arrived mid-stride"
	).is_equal(HumanoidClips.IDLE)


# --- performing ---------------------------------------------------------------


func test_nothing_is_being_performed_to_begin_with() -> void:
	var body: WalkerBody = _body()

	assert_bool(body.is_performing()).is_false()
	assert_str(body.performing()).is_empty()


func test_a_performance_runs_for_as_long_as_its_clip() -> void:
	var body: WalkerBody = _body()

	var length: float = body.perform(HumanoidClips.THROW)

	assert_float(length).override_failure_message("the throw did not play").is_greater(1.0)
	assert_bool(body.is_performing()).is_true()
	assert_str(body.performing()).is_equal(HumanoidClips.THROW)


func test_a_performance_ends_on_its_own_and_says_so() -> void:
	var body: WalkerBody = _body()
	var ended: Array[String] = []
	body.performed.connect(func(slot: String) -> void: ended.append(slot))

	var length: float = body.perform(HumanoidClips.THROW)
	for frame: int in range(int(length / FRAME) + 4):
		body.advance(FRAME, 0.0, Vector2(0, 1))

	assert_bool(body.is_performing()).override_failure_message(
		"the throw never finished"
	).is_false()
	assert_array(ended).contains([HumanoidClips.THROW])


func test_the_ball_leaves_the_hand_part_way_through() -> void:
	# A caller that waited for the clip would show the ball appearing two and a
	# half seconds after the arm came down.
	var body: WalkerBody = _body()
	# Counted rather than timed inside the handler: a lambda captures by value, so
	# a clock read in there is the clock as it was when the lambda was made.
	var throws: Array[bool] = []
	body.released.connect(func() -> void: throws.append(true))

	var length: float = body.perform(HumanoidClips.THROW)
	var elapsed: float = 0.0
	var thrown_at: float = -1.0
	for frame: int in range(int(length / FRAME) + 4):
		body.advance(FRAME, 0.0, Vector2(0, 1))
		elapsed += FRAME
		if thrown_at < 0.0 and not throws.is_empty():
			thrown_at = elapsed

	assert_int(throws.size()).override_failure_message(
		"the ball was released %d times" % throws.size()
	).is_equal(1)
	assert_float(thrown_at).is_equal_approx(length * WalkerGait.THROW_RELEASE, 0.05)


func test_a_held_pose_runs_until_it_is_let_go() -> void:
	# The fishing stance loops: it is a pose to stand in, not a thing that
	# happens, so nothing ends it but the caller.
	var body: WalkerBody = _body()

	var length: float = body.perform(HumanoidClips.FISHING_IDLE)
	for frame: int in range(int(length / FRAME) * 2):
		body.advance(FRAME, 0.0, Vector2(0, 1))
	assert_bool(body.is_performing()).override_failure_message(
		"a looping pose ended by itself"
	).is_true()

	body.stop_performing()
	assert_bool(body.is_performing()).is_false()


func test_a_clip_nobody_has_performs_nothing() -> void:
	assert_float(_body().perform("cartwheel")).is_equal(0.0)
