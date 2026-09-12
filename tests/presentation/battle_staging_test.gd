extends GdUnitTestSuite

## Where the two creatures stand and where the camera watches from (spec 17).
##
## The reason this is arithmetic rather than four numbers in a scene: the numbers
## were tuned against a screenshot, and every one of them was wrong the moment
## another changed. What is asserted here is the *relationships* — both in frame,
## facing each other, one nearer than the other — so retuning the staging cannot
## quietly break the framing.

const HEIGHT: float = 1.0
const FOV: float = 75.0
const PLAYER: int = 0
const FOE: int = 1


func _seats() -> Array[Vector3]:
	return [BattleStaging.seat(PLAYER), BattleStaging.seat(FOE)]


# --- where they stand ---------------------------------------------------------


func test_the_two_seats_are_mirror_images() -> void:
	# So the pair is centred whatever the separation, which is what lets the
	# camera look at the origin and be right.
	var seats: Array[Vector3] = _seats()
	assert_vector(seats[PLAYER] + seats[FOE]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_they_stand_the_separation_apart() -> void:
	var seats: Array[Vector3] = _seats()
	assert_float(seats[PLAYER].distance_to(seats[FOE])).is_equal_approx(
		BattleStaging.SEPARATION, 0.001
	)


func test_yours_is_nearer_the_camera_and_to_the_left() -> void:
	# The whole staging in one assertion. Two creatures the same distance away
	# read as a diagram; the depth is what makes one of them yours.
	var seats: Array[Vector3] = _seats()

	assert_bool(seats[PLAYER].z > seats[FOE].z).override_failure_message(
		"your creature is not the near one: %s against %s" % [seats[PLAYER], seats[FOE]]
	).is_true()
	assert_bool(seats[PLAYER].x < seats[FOE].x).override_failure_message(
		"your creature is not the left one"
	).is_true()


func test_they_are_not_side_by_side_and_not_in_line() -> void:
	# Zero slant is a diagram; ninety puts one exactly behind the other. The
	# staging is only staging in between.
	var seats: Array[Vector3] = _seats()

	assert_bool(absf(seats[PLAYER].z - seats[FOE].z) > 0.2).override_failure_message(
		"the pair is flat across the frame"
	).is_true()
	assert_bool(absf(seats[PLAYER].x - seats[FOE].x) > 0.2).override_failure_message(
		"one creature is hidden behind the other"
	).is_true()


func test_a_wider_separation_moves_both_and_keeps_the_centre() -> void:
	var wide_player: Vector3 = BattleStaging.seat(PLAYER, 6.0)
	var wide_foe: Vector3 = BattleStaging.seat(FOE, 6.0)

	assert_float(wide_player.distance_to(wide_foe)).is_equal_approx(6.0, 0.001)
	assert_vector(wide_player + wide_foe).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_a_separation_of_nothing_puts_both_on_the_spot() -> void:
	# Degenerate rather than negative: a negative separation would swap the two
	# sides silently, which is worse than them overlapping.
	assert_vector(BattleStaging.seat(PLAYER, -4.0)).is_equal_approx(
		Vector3.ZERO, Vector3.ONE * 0.001
	)


# --- which way they face ------------------------------------------------------


func test_each_faces_the_other() -> void:
	# The property that stops the facing drifting when the seats are retuned:
	# neither is turned to a fixed angle, both are turned at each other.
	var seats: Array[Vector3] = _seats()

	for side: int in [PLAYER, FOE]:
		var other: int = FOE if side == PLAYER else PLAYER
		var yaw: float = BattleStaging.yaw_towards(seats[side], seats[other])
		# A model looks along +Z, so a body at yaw θ faces (sin θ, 0, cos θ).
		var looking: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
		var towards: Vector3 = (seats[other] - seats[side]).normalized()

		assert_float(looking.dot(towards)).override_failure_message(
			"side %d faces %s instead of %s" % [side, looking, towards]
		).is_greater(0.999)


func test_they_face_opposite_ways() -> void:
	var seats: Array[Vector3] = _seats()
	var mine: float = BattleStaging.yaw_towards(seats[PLAYER], seats[FOE])
	var theirs: float = BattleStaging.yaw_towards(seats[FOE], seats[PLAYER])

	assert_float(absf(angle_difference(mine, theirs))).override_failure_message(
		"the two are not turned away from each other"
	).is_equal_approx(PI, 0.001)


func test_facing_a_place_you_already_are_is_not_an_error() -> void:
	# Two creatures on the same spot is a degenerate staging, not a crash, and a
	# NaN yaw would put a body somewhere no assertion could describe.
	var yaw: float = BattleStaging.yaw_towards(Vector3.ZERO, Vector3.ZERO)
	assert_bool(is_nan(yaw)).is_false()
	assert_float(yaw).is_equal(0.0)


# --- what the camera sees -----------------------------------------------------


func _in_frame(point: Vector3, eye: Vector3, target: Vector3, fov: float) -> bool:
	var looking: Vector3 = (target - eye).normalized()
	var towards: Vector3 = (point - eye).normalized()
	return rad_to_deg(looking.angle_to(towards)) <= fov * 0.5


func test_both_creatures_are_inside_the_field_of_view() -> void:
	# The assertion that makes the arithmetic worth having: head and feet of both
	# creatures, inside the vertical field of view, computed rather than checked
	# against a screenshot.
	var eye: Vector3 = BattleStaging.eye(HEIGHT, FOV)
	var target: Vector3 = BattleStaging.target(HEIGHT)

	for seat: Vector3 in _seats():
		for point: Vector3 in [seat, seat + Vector3(0, HEIGHT, 0)]:
			assert_bool(_in_frame(point, eye, target, FOV)).override_failure_message(
				"%s is outside the frame from %s" % [point, eye]
			).is_true()


func test_it_stays_in_frame_at_other_fields_of_view() -> void:
	# A camera somebody retunes, or a different aspect. The distance is derived
	# from the field of view, so a narrower one must simply stand further back.
	for fov: float in [40.0, 55.0, 75.0, 100.0]:
		var eye: Vector3 = BattleStaging.eye(HEIGHT, fov)
		var target: Vector3 = BattleStaging.target(HEIGHT)

		for seat: Vector3 in _seats():
			assert_bool(
				_in_frame(seat + Vector3(0, HEIGHT, 0), eye, target, fov)
			).override_failure_message(
				"a head leaves the frame at %d degrees" % fov
			).is_true()


func test_a_narrower_lens_stands_further_back() -> void:
	assert_float(BattleStaging.eye(HEIGHT, 40.0).length()).is_greater(
		BattleStaging.eye(HEIGHT, 90.0).length()
	)


func test_a_bigger_pair_pushes_the_camera_back() -> void:
	assert_float(BattleStaging.distance_for(4.0, FOV)).is_greater(
		BattleStaging.distance_for(1.0, FOV)
	)


func test_the_camera_is_behind_your_creature_along_the_fight() -> void:
	# Behind *yours*, not behind the world. A camera on +Z watches a fight that
	# runs diagonally from the side, and the pair reads as a line-up however
	# carefully they are turned towards each other.
	var seats: Array[Vector3] = _seats()
	var eye: Vector3 = BattleStaging.eye(HEIGHT, FOV)

	var forward: Vector3 = (seats[FOE] - seats[PLAYER]).normalized()
	var along: float = (eye - seats[PLAYER]).dot(forward)

	assert_float(along).override_failure_message(
		"the camera is level with or past your creature rather than behind it"
	).is_less(0.0)


func test_the_camera_is_off_the_axis_rather_than_on_it() -> void:
	# Exactly behind is exactly where your creature hides the other one.
	var seats: Array[Vector3] = _seats()
	var eye: Vector3 = BattleStaging.eye(HEIGHT, FOV)

	var forward: Vector3 = (seats[FOE] - seats[PLAYER]).normalized()
	var sideways: Vector3 = forward.cross(Vector3.UP).normalized()

	assert_float((eye - seats[PLAYER]).dot(sideways)).override_failure_message(
		"the camera sits on the line of the fight"
	).is_greater(0.3)


func test_the_camera_is_above() -> void:
	assert_float(BattleStaging.eye(HEIGHT, FOV).y).override_failure_message(
		"the camera is at ground level, so the far creature is hidden by the near one"
	).is_greater(HEIGHT)


func test_neither_creature_hides_the_other() -> void:
	# The failure a distance check cannot see: both in frame, one in front of the
	# other. Measured as the angle between them from the camera, which is what
	# overlapping actually means.
	var seats: Array[Vector3] = _seats()
	var eye: Vector3 = BattleStaging.eye(HEIGHT, FOV)

	var apart: float = rad_to_deg(
		(seats[PLAYER] - eye).normalized().angle_to((seats[FOE] - eye).normalized())
	)
	assert_float(apart).override_failure_message(
		"only %.1f degrees apart on screen" % apart
	).is_greater(12.0)


func test_the_shoulder_holds_whichever_way_the_fight_leans() -> void:
	# Composed from the axis rather than rotated by a signed yaw, so a negative
	# slant cannot put the camera on the wrong shoulder.
	for slant: float in [-60.0, -38.0, 0.0, 38.0, 60.0]:
		var near: Vector3 = BattleStaging.seat(PLAYER, BattleStaging.SEPARATION, slant)
		var far: Vector3 = BattleStaging.seat(FOE, BattleStaging.SEPARATION, slant)
		var eye: Vector3 = BattleStaging.eye(
			HEIGHT, FOV, BattleStaging.SEPARATION, BattleStaging.PITCH_DEGREES,
			BattleStaging.MARGIN, BattleStaging.SHOULDER_DEGREES, slant
		)

		var forward: Vector3 = (far - near).normalized()
		var sideways: Vector3 = forward.cross(Vector3.UP).normalized()

		assert_float((eye - near).dot(forward)).override_failure_message(
			"at %.0f degrees of slant the camera is not behind your creature" % slant
		).is_less(0.0)
		assert_float((eye - near).dot(sideways)).override_failure_message(
			"at %.0f degrees of slant the camera is on the wrong shoulder" % slant
		).is_greater(0.0)


func test_yours_is_the_nearer_to_the_camera() -> void:
	# Both in frame is not enough: the near one has to be *yours*, or the depth
	# says the wrong thing.
	var eye: Vector3 = BattleStaging.eye(HEIGHT, FOV)
	var seats: Array[Vector3] = _seats()

	assert_float(eye.distance_to(seats[PLAYER])).is_less(eye.distance_to(seats[FOE]))


func test_nothing_here_produces_a_nan() -> void:
	# Every degenerate input at once. A NaN in a transform is a node that
	# disappears with no error anywhere.
	for fov: float in [0.0, -30.0, 180.0, 400.0]:
		var eye: Vector3 = BattleStaging.eye(0.0, fov, 0.0)
		assert_bool(is_nan(eye.x) or is_nan(eye.y) or is_nan(eye.z)).override_failure_message(
			"fov %f produced %s" % [fov, eye]
		).is_false()
		assert_bool(eye.is_finite()).is_true()


# --- the trainer ---------------------------------------------------------------


func test_the_trainer_stands_on_their_own_side() -> void:
	# Behind the line between the two, not between them: a trainer standing in
	# the middle of the fight is in the way of it.
	var near: Vector3 = BattleStaging.seat(BattleStaging.NEAR_SIDE)
	var far: Vector3 = BattleStaging.seat(BattleStaging.NEAR_SIDE + 1)
	var standing: Vector3 = BattleStaging.trainer_seat()

	assert_float(standing.distance_to(far)).override_failure_message(
		"the trainer is nearer the opponent than their own creature is"
	).is_greater(near.distance_to(far))


func test_the_trainer_stands_clear_of_the_camera_shoulder() -> void:
	# The camera watches over the near creature's right. A trainer put on the
	# same side would be under the lens and would hide what the player is
	# watching, so they stand off the other one.
	var forward: Vector3 = BattleStaging.towards_the_foe()
	var to_the_right: Vector3 = forward.cross(Vector3.UP).normalized()
	var aside: Vector3 = BattleStaging.trainer_seat() - BattleStaging.seat(BattleStaging.NEAR_SIDE)

	assert_float(aside.dot(to_the_right)).override_failure_message(
		"the trainer stands on the camera's own shoulder"
	).is_less(0.0)


func test_the_frame_holds_the_trainer() -> void:
	# A radius that ignored them would frame the fight perfectly and cut the
	# player in half.
	var without: float = BattleStaging.framing_radius(1.0)
	var with_them: float = BattleStaging.framing_radius(
		1.0, BattleStaging.SEPARATION, BattleStaging.WIDTH_RATIO, 1.7
	)

	assert_float(with_them).override_failure_message(
		"standing somebody else on the field did not widen the frame"
	).is_greater(without)

	var middle: Vector3 = BattleStaging.centre(1.0, 1.7)
	var standing: Vector3 = BattleStaging.trainer_seat()
	assert_float(
		Vector3(standing.x, 1.7, standing.z).distance_to(middle)
	).override_failure_message("the top of the trainer's head is outside the frame").is_less(
		with_them
	)


func test_the_frame_still_holds_both_creatures() -> void:
	var middle: Vector3 = BattleStaging.centre(1.0, 1.7)
	var radius: float = BattleStaging.framing_radius(
		1.0, BattleStaging.SEPARATION, BattleStaging.WIDTH_RATIO, 1.7
	)

	for side: int in [BattleStaging.NEAR_SIDE, BattleStaging.NEAR_SIDE + 1]:
		var standing: Vector3 = BattleStaging.seat(side)
		assert_float(
			Vector3(standing.x, 1.0, standing.z).distance_to(middle)
		).override_failure_message("creature %d fell out of the frame" % side).is_less(radius)


func test_nobody_standing_there_frames_it_as_it_always_was() -> void:
	# The default is the pair and nothing else, so every caller that knows
	# nothing about a trainer is unchanged.
	assert_vector(BattleStaging.centre(1.0, 0.0)).is_equal_approx(
		BattleStaging.centre(1.0), Vector3.ONE * 0.0001
	)
	assert_float(BattleStaging.framing_radius(1.0, BattleStaging.SEPARATION)).is_equal_approx(
		BattleStaging.framing_radius(
			1.0, BattleStaging.SEPARATION, BattleStaging.WIDTH_RATIO, 0.0
		),
		0.0001
	)
