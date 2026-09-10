extends GdUnitTestSuite

## Where the player is, and what moving does (spec 14, section 2).
##
## Movement stopped being discrete and the rules did not. What these pin is that
## split: the origin decides which cell you are in, the body decides where you
## may be, and everything a step used to trigger now fires on crossing a
## boundary — in the same order, with no new constant anywhere.

const GRASS: String = "meadow"


func _map(size: Vector2i = Vector2i(6, 6), blocked: Array[Vector2i] = []) -> VltWorldMap:
	return auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(size), blocked))


func _walker(on: VltWorldMap) -> VltFreeWalker:
	var walker: VltFreeWalker = auto_free(VltFreeWalker.new())
	walker.map = on
	add_child(walker)
	walker.place(Vector2i(2, 2), VltFacing.Direction.SOUTH)
	return walker


func _width(of: VltWorldMap) -> float:
	return of.cell_width()


# --- free, and still on a grid ------------------------------------------------


func test_it_moves_by_metres_and_lands_between_cells() -> void:
	# The whole request: no snapping. A tenth of a cell is a tenth of a cell.
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)
	var was: Vector2 = walker.spot

	walker.move(Vector2(_width(map) * 0.1, 0.0))

	assert_float(walker.spot.x - was.x).is_equal_approx(_width(map) * 0.1, 0.001)
	assert_vector(walker.cell()).override_failure_message(
		"a tenth of a cell changed which cell it was in"
	).is_equal(Vector2i(2, 2))


func test_the_origin_is_what_says_which_cell() -> void:
	# Stated by the maintainer and pinned here: the body may overlap a
	# neighbour, and the cell is still whichever one the origin is in.
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)

	walker.move(Vector2(_width(map) * 0.49, 0.0))
	assert_vector(walker.cell()).is_equal(Vector2i(2, 2))

	walker.move(Vector2(_width(map) * 0.02, 0.0))
	assert_vector(walker.cell()).override_failure_message(
		"crossing the boundary did not change the cell"
	).is_equal(Vector2i(3, 2))


func test_it_moves_in_any_direction_at_once() -> void:
	# Omnidirectional: a diagonal is one move, not two steps.
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)
	var was: Vector2 = walker.spot

	walker.move(Vector2(0.2, 0.2))

	assert_float(walker.spot.x - was.x).is_equal_approx(0.2, 0.001)
	assert_float(walker.spot.y - was.y).is_equal_approx(0.2, 0.001)


func test_the_facing_follows_the_heading() -> void:
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)

	walker.move(Vector2(0.1, 0.0))
	assert_int(walker.facing()).is_equal(VltFacing.Direction.EAST)

	walker.move(Vector2(0.0, -0.1))
	assert_int(walker.facing()).is_equal(VltFacing.Direction.NORTH)


func test_a_move_of_nothing_keeps_the_heading() -> void:
	# Standing still must not spin the character to some default.
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)
	walker.move(Vector2(0.1, 0.0))

	walker.move(Vector2.ZERO)
	assert_int(walker.facing()).is_equal(VltFacing.Direction.EAST)


# --- what stops you -----------------------------------------------------------


func test_a_wall_stops_you_before_you_are_inside_it() -> void:
	var map: VltWorldMap = _map(Vector2i(6, 6), [Vector2i(3, 2)] as Array[Vector2i])
	var walker: VltFreeWalker = _walker(map)

	var result: VltFreeWalker.Move = walker.move(Vector2(_width(map), 0.0))

	assert_bool(result.blocked).is_true()
	assert_vector(walker.cell()).override_failure_message(
		"walked into a blocked cell"
	).is_equal(Vector2i(2, 2))


func test_a_body_cannot_end_up_overlapping_a_wall() -> void:
	# The origin alone is not enough: a character whose shoulder is inside a wall
	# looks broken however correct its cell is.
	var map: VltWorldMap = _map(Vector2i(6, 6), [Vector2i(3, 2)] as Array[Vector2i])
	var walker: VltFreeWalker = _walker(map)

	for push: int in range(40):
		walker.move(Vector2(0.05, 0.0))

	var edge: float = map.centre_of(Vector2i(3, 2)).x - _width(map) * 0.5
	assert_float(walker.spot.x).override_failure_message(
		"the body is %.3f m past the wall's face" % (walker.spot.x - (edge - VltFreeWalker.RADIUS))
	).is_less_equal(edge - VltFreeWalker.RADIUS + 0.001)


func test_walking_into_a_wall_at_an_angle_slides_along_it() -> void:
	# It falls out of trying each axis on its own rather than being written, and
	# it is the difference between a wall and a trap.
	var map: VltWorldMap = _map(Vector2i(6, 6), [Vector2i(3, 2)] as Array[Vector2i])
	var walker: VltFreeWalker = _walker(map)
	var was: Vector2 = walker.spot

	var result: VltFreeWalker.Move = walker.move(Vector2(0.2, 0.2))

	assert_bool(result.moved).override_failure_message("it stopped dead").is_true()
	assert_float(walker.spot.y - was.y).override_failure_message(
		"it did not slide along the wall"
	).is_equal_approx(0.2, 0.001)


func test_the_edge_of_the_map_stops_you_like_a_wall() -> void:
	var map: VltWorldMap = _map(Vector2i(3, 3))
	var walker: VltFreeWalker = _walker(map)
	walker.place(Vector2i(0, 0), VltFacing.Direction.WEST)

	for push: int in range(40):
		walker.move(Vector2(-0.05, 0.0))

	assert_vector(walker.cell()).override_failure_message(
		"the walker left the map at %s" % walker.spot
	).is_equal(Vector2i(0, 0))


func test_a_corridor_one_cell_wide_admits_the_player() -> void:
	# The radius has to stay under half a cell or the world is impassable, and
	# nothing about that is obvious from the number alone.
	var walls: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 2)]
	var map: VltWorldMap = _map(Vector2i(4, 3), walls)
	var walker: VltFreeWalker = _walker(map)
	walker.place(Vector2i(0, 1), VltFacing.Direction.EAST)

	# Walked until it stops making progress rather than a fixed count: the
	# fixture's cells are not the game's, and a count tuned to one is a test that
	# passes for the wrong reason on the other.
	var was: Vector2 = Vector2.INF
	var guard: int = 0
	while not walker.spot.is_equal_approx(was) and guard < 2000:
		was = walker.spot
		walker.move(Vector2(0.05, 0.0))
		guard += 1

	assert_vector(walker.cell()).override_failure_message(
		"the player could not get down a one-cell corridor, stopped at %s" % walker.spot
	).is_equal(Vector2i(3, 1))


# --- what a boundary triggers -------------------------------------------------


func test_nothing_fires_while_you_stay_in_one_cell() -> void:
	# The replacement for "a step": the cell changing. Moving inside one cell is
	# not an event, however far you walk.
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureMap.zone(GRASS, Vector2i(0, 0), Vector2i(6, 6)))
	var walker: VltFreeWalker = _walker(map)
	walker.tables = {GRASS: VltFixtureMap.table(GRASS, 255)}
	walker.encounter_decider = VltSeededEncounterDecider.new(1)

	for push: int in range(8):
		var result: VltFreeWalker.Move = walker.move(Vector2(0.01, 0.0))
		assert_bool(result.entered).is_false()
		assert_object(result.encounter).override_failure_message(
			"an encounter happened without leaving the cell"
		).is_null()


func test_crossing_into_grass_can_start_a_battle() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureMap.zone(GRASS, Vector2i(0, 0), Vector2i(6, 6)))
	var walker: VltFreeWalker = _walker(map)
	walker.tables = {GRASS: VltFixtureMap.table(GRASS, 255)}
	walker.encounter_decider = VltSeededEncounterDecider.new(1)

	var met: bool = false
	for push: int in range(60):
		if walker.move(Vector2(0.05, 0.0)).started_a_battle():
			met = true
			break

	assert_bool(met).override_failure_message(
		"a table with a rate of 255 never fired while crossing cells"
	).is_true()


func test_a_warp_fires_on_entering_its_cell() -> void:
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureMap.warp(Vector2i(3, 2), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH)
	)
	var walker: VltFreeWalker = _walker(map)

	var warped: VltWarp = null
	for push: int in range(40):
		var result: VltFreeWalker.Move = walker.move(Vector2(0.05, 0.0))
		if result.warp != null:
			warped = result.warp
			break

	assert_object(warped).override_failure_message("the warp never fired").is_not_null()
	assert_str(warped.to_map).is_equal("cave")


func test_a_warp_fires_once_and_not_every_frame() -> void:
	# Standing on a door must not warp you sixty times a second.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureMap.warp(Vector2i(3, 2), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH)
	)
	var walker: VltFreeWalker = _walker(map)

	var fired: int = 0
	for push: int in range(40):
		if walker.move(Vector2(0.05, 0.0)).warp != null:
			fired += 1

	assert_int(fired).override_failure_message(
		"the warp fired %d times while walking over it" % fired
	).is_equal(1)


func test_an_event_fires_on_entering_and_a_warp_wins() -> void:
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureEvent.event([] as Array[VltEventStep], VltEvent.Trigger.ENTER_CELL, Vector2i(3, 2)))
	var walker: VltFreeWalker = _walker(map)

	var fired: bool = false
	for push: int in range(40):
		if walker.move(Vector2(0.05, 0.0)).event != null:
			fired = true
			break
	assert_bool(fired).is_true()


# --- interacting --------------------------------------------------------------


func test_it_reads_what_is_in_front_even_on_a_wall() -> void:
	# A sign is something you face, not something you stand on.
	var map: VltWorldMap = _map(Vector2i(6, 6), [Vector2i(2, 3)] as Array[Vector2i])
	map.add_child(VltFixtureEvent.event([] as Array[VltEventStep], VltEvent.Trigger.INTERACT, Vector2i(2, 3)))
	var walker: VltFreeWalker = _walker(map)
	walker.heading = Vector2(0.0, 1.0)

	assert_object(walker.interact()).override_failure_message(
		"the sign in front could not be read"
	).is_not_null()


func test_it_reads_nothing_when_facing_nothing() -> void:
	var map: VltWorldMap = _map()
	var walker: VltFreeWalker = _walker(map)

	assert_object(walker.interact()).is_null()


# --- what the stick asks for --------------------------------------------------


func test_a_resting_thumb_is_not_a_direction() -> void:
	assert_vector(VltStepIntent.of(Vector2(0.1, 0.1))).is_equal(Vector2.ZERO)


func test_a_half_push_walks_at_half_pace() -> void:
	# Clamped rather than normalised. Normalising would make a stick a switch,
	# and a thumb held halfway is asking for half.
	assert_float(VltStepIntent.of(Vector2(0.6, 0.0)).length()).is_equal_approx(0.6, 0.001)


func test_a_key_is_always_a_full_push() -> void:
	var both: Vector2 = VltStepIntent.from_keys(true, false, true, false)
	assert_float(VltStepIntent.of(both).length()).override_failure_message(
		"two keys walked faster than one"
	).is_equal_approx(1.0, 0.001)


func test_two_keys_are_a_real_diagonal() -> void:
	# What free movement buys, and what the staircase of decision 0056 was
	# standing in for.
	var both: Vector2 = VltStepIntent.of(VltStepIntent.from_keys(true, false, true, false))

	assert_float(absf(both.x)).is_equal_approx(absf(both.y), 0.001)
	assert_float(both.x).is_greater(0.0)
	assert_float(both.y).is_less(0.0)


func test_opposite_keys_cancel() -> void:
	assert_vector(
		VltStepIntent.of(VltStepIntent.from_keys(true, true, false, false))
	).is_equal(Vector2.ZERO)
