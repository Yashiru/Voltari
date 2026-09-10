extends GdUnitTestSuite

## Somewhere to be sent back to.
##
## The interesting half is the metric. "Nearest" between two maps has no obvious
## meaning, so the one chosen is stated — and these are what say it out loud.


func _map(id: String, size: Vector2i = Vector2i(6, 6)) -> VltWorldMap:
	return auto_free(VltFixtureMap.map(id, VltFixtureMap.filled(size)))


func _rest(map: VltWorldMap, at: Vector2i) -> VltRestPoint:
	var point: VltRestPoint = VltRestPoint.new()
	point.cell = at
	point.facing = VltFacing.Direction.NORTH
	map.add_child(point)
	return point


func _link(from: VltWorldMap, at: Vector2i, to: String, arriving: Vector2i) -> void:
	from.add_child(VltFixtureMap.warp(at, to, arriving, VltFacing.Direction.EAST))


func _world(of: Array[VltWorldMap]) -> Dictionary[String, VltWorldMap]:
	var maps: Dictionary[String, VltWorldMap] = {}
	for map: VltWorldMap in of:
		maps[map.map_id] = map
	return maps


# --- on one map --------------------------------------------------------------


func test_the_fewest_steps_wins() -> void:
	# Manhattan, because movement is four-directional: a diagonal is two steps
	# and a straight-line distance would call a wall a shortcut.
	var field: VltWorldMap = _map("field")
	_rest(field, Vector2i(5, 5))
	_rest(field, Vector2i(2, 0))

	var found: VltRestPoint.Found = VltRestPoint.nearest(
		_world([field]), "field", Vector2i(0, 0)
	)

	assert_vector(found.cell).is_equal(Vector2i(2, 0))
	assert_str(found.map_id).is_equal("field")


func test_it_carries_the_way_to_face() -> void:
	# A player who wakes up facing a wall has to work out where they are before
	# they can move.
	var field: VltWorldMap = _map("field")
	_rest(field, Vector2i(1, 1))

	assert_int(
		VltRestPoint.nearest(_world([field]), "field", Vector2i(0, 0)).facing
	).is_equal(VltFacing.Direction.NORTH)


# --- across maps -------------------------------------------------------------


func test_a_map_with_none_looks_through_its_doors() -> void:
	# The case the metric exists for: the cave has nowhere to rest and reaches
	# the field's camp through a door.
	var field: VltWorldMap = _map("field")
	var cave: VltWorldMap = _map("cave", Vector2i(3, 3))
	_rest(field, Vector2i(4, 4))
	_link(cave, Vector2i(0, 1), "field", Vector2i(1, 1))

	var found: VltRestPoint.Found = VltRestPoint.nearest(
		_world([field, cave]), "cave", Vector2i(2, 2)
	)

	assert_str(found.map_id).is_equal("field")
	assert_vector(found.cell).is_equal(Vector2i(4, 4))


func test_the_fewest_doors_wins_before_the_fewest_steps() -> void:
	# One transition away beats two, whatever the grid distances are. A metric
	# that summed them would need an exchange rate between a step and a door.
	var here: VltWorldMap = _map("here", Vector2i(3, 3))
	var near: VltWorldMap = _map("near", Vector2i(9, 9))
	var far: VltWorldMap = _map("far", Vector2i(3, 3))

	_rest(near, Vector2i(8, 8))
	_rest(far, Vector2i(0, 0))

	_link(here, Vector2i(0, 0), "near", Vector2i(0, 0))
	_link(near, Vector2i(1, 0), "far", Vector2i(0, 0))

	assert_str(
		VltRestPoint.nearest(_world([here, near, far]), "here", Vector2i(0, 0)).map_id
	).override_failure_message(
		"a far corner two doors away beat one a single door away"
	).is_equal("near")


func test_the_map_you_are_on_wins_over_a_door() -> void:
	var here: VltWorldMap = _map("here")
	var over_there: VltWorldMap = _map("over_there")
	_rest(here, Vector2i(5, 5))
	_rest(over_there, Vector2i(0, 0))
	_link(here, Vector2i(0, 1), "over_there", Vector2i(0, 0))

	assert_str(
		VltRestPoint.nearest(_world([here, over_there]), "here", Vector2i(0, 0)).map_id
	).is_equal("here")


func test_nothing_reachable_is_null_rather_than_a_guess() -> void:
	# Null is a real answer and the caller has to handle it. The validator
	# refuses content that can reach none, so this is a world built by hand.
	var alone: VltWorldMap = _map("alone")

	assert_object(
		VltRestPoint.nearest(_world([alone]), "alone", Vector2i(0, 0))
	).is_null()


func test_a_ring_of_doors_terminates() -> void:
	# The warp graph has cycles — a door and the door back are one.
	var one: VltWorldMap = _map("one", Vector2i(3, 3))
	var two: VltWorldMap = _map("two", Vector2i(3, 3))
	_link(one, Vector2i(0, 0), "two", Vector2i(0, 0))
	_link(two, Vector2i(0, 0), "one", Vector2i(0, 0))

	assert_object(
		VltRestPoint.nearest(_world([one, two]), "one", Vector2i(1, 1))
	).is_null()
