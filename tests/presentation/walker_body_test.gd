extends GdUnitTestSuite

## The character who walks the map (decision 0057).
##
## The model is committed, so unlike a creature this one is really there and the
## tests can say so. What they pin is the behaviour a reviewer would look for
## first: the clip a speed produces, that chained steps do not flicker, that a
## turn is a turn and not a snap, and that a missing model still leaves a player.

const FRAME: float = 1.0 / 60.0
const RUNNING: float = 3.6


func _body() -> WalkerBody:
	var body: WalkerBody = auto_free(WalkerBody.new())
	add_child(body)
	return body


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
	assert_str(_body().playing()).is_equal(WalkerGait.IDLE_CLIP)


# --- standing, walking, running -----------------------------------------------


func test_moving_runs_and_stopping_settles_to_the_idle() -> void:
	var body: WalkerBody = _body()

	body.advance(FRAME, RUNNING, Vector2(0, 1))
	assert_str(body.playing()).is_equal("Running")

	# Past the grace, which is what a real stop is.
	for frame: int in range(30):
		body.advance(FRAME, 0.0, Vector2(0, 1))
	assert_str(body.playing()).is_equal(WalkerGait.IDLE_CLIP)


func test_chained_steps_never_drop_to_the_idle() -> void:
	# Two steps in a row are separated by a single frame at zero speed. Without a
	# grace the legs flicker between running and standing on every cell boundary,
	# which is the artefact this is here to prevent.
	var body: WalkerBody = _body()

	for step: int in range(6):
		for frame: int in range(9):
			body.advance(FRAME, RUNNING, Vector2(1, 0))
		# The seam between two steps.
		body.advance(FRAME, 0.0, Vector2(1, 0))
		assert_str(body.playing()).override_failure_message(
			"the legs stopped between step %d and the next" % step
		).is_equal("Running")


func test_the_grace_is_shorter_than_a_pause() -> void:
	# It must not turn a genuine stop into a skid.
	var body: WalkerBody = _body()
	body.advance(FRAME, RUNNING, Vector2(0, 1))

	var elapsed: float = 0.0
	while body.playing() != WalkerGait.IDLE_CLIP and elapsed < 1.0:
		body.advance(FRAME, 0.0, Vector2(0, 1))
		elapsed += FRAME

	assert_float(elapsed).override_failure_message(
		"it took %.2f s to stop" % elapsed
	).is_less(0.25)


func test_the_playback_rate_follows_the_speed() -> void:
	var body: WalkerBody = _body()
	body.advance(FRAME, RUNNING, Vector2(0, 1))

	var player: AnimationPlayer = _player(body)
	assert_float(player.speed_scale).is_equal_approx(1.0, 0.01)

	body.advance(FRAME, RUNNING * 1.2, Vector2(0, 1))
	assert_float(player.speed_scale).is_greater(1.0)


func test_the_idle_plays_at_its_own_rate() -> void:
	# Standing still is not a gait, so nothing scales it.
	var body: WalkerBody = _body()
	for frame: int in range(30):
		body.advance(FRAME, 0.0, Vector2(0, 1))

	assert_float(_player(body).speed_scale).is_equal_approx(1.0, 0.001)


func test_every_gait_it_can_ask_for_is_in_the_model() -> void:
	# The vocabulary and the model, checked against each other rather than by
	# reading both lists. A clip named in the arithmetic and missing from the
	# model is a character that freezes at one speed and no other.
	var player: AnimationPlayer = _player(_body())

	assert_bool(player.has_animation(WalkerGait.IDLE_CLIP)).override_failure_message(
		"the model has no %s" % WalkerGait.IDLE_CLIP
	).is_true()
	for clip: String in WalkerGait.LOOKS_RIGHT_AT:
		assert_bool(player.has_animation(clip)).override_failure_message(
			"the model has no %s" % clip
		).is_true()


func test_every_gait_loops() -> void:
	# Set at import rather than by code mutating a shared resource. A gait that
	# did not loop would stop dead at the end of its cycle.
	var player: AnimationPlayer = _player(_body())

	for clip: String in WalkerGait.LOOKS_RIGHT_AT:
		assert_int(player.get_animation(clip).loop_mode).override_failure_message(
			"%s does not loop" % clip
		).is_not_equal(Animation.LOOP_NONE)
	assert_int(player.get_animation(WalkerGait.IDLE_CLIP).loop_mode).is_not_equal(
		Animation.LOOP_NONE
	)


# --- turning ------------------------------------------------------------------


func test_it_turns_rather_than_snapping() -> void:
	# A four-facing world that snapped would flick the model through ninety
	# degrees inside one frame, which is the cheapest thing to get wrong here.
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))
	var from: float = body.rotation.y

	body.advance(FRAME, 0.0, Vector2(1, 0))
	var moved: float = absf(angle_difference(from, body.rotation.y))

	assert_float(moved).override_failure_message("it did not turn at all").is_greater(0.0)
	assert_float(moved).override_failure_message(
		"it snapped a quarter turn in one frame"
	).is_less(PI * 0.5 * 0.9)


func test_a_turn_finishes() -> void:
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, 1))

	for frame: int in range(60):
		body.advance(FRAME, 0.0, Vector2(-1, 0))

	assert_float(
		absf(angle_difference(body.rotation.y, WalkerGait.yaw_towards(Vector2(-1, 0))))
	).is_less(0.001)


func test_arriving_somewhere_faces_at_once() -> void:
	# A warp, a load and a defeat all put the player somewhere else. Turning
	# through the change would spin them on arrival.
	var body: WalkerBody = _body()
	body.face_at_once(Vector2(0, -1))

	assert_float(body.rotation.y).is_equal_approx(
		WalkerGait.yaw_towards(Vector2(0, -1)), 0.001
	)
	assert_str(body.playing()).override_failure_message(
		"it arrived mid-stride"
	).is_equal(WalkerGait.IDLE_CLIP)


func _player(body: WalkerBody) -> AnimationPlayer:
	for node: Node in _every(body):
		if node is AnimationPlayer:
			return node as AnimationPlayer
	return null


func _every(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_every(child))
	return found
