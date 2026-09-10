extends GdUnitTestSuite

## What one step does (spec 14, section 10).
##
## The overworld is engine-native, so these are example-based tests on a fixture
## map — the project's weakest pillar, and the honest one for code whose failures
## are loud rather than quiet (decision 0038). What they pin is behaviour a
## refactor drops silently.

const SEED: int = 909
const GRASS: String = "meadow"


func _map() -> VltWorldMap:
	# A 5x5 field with a wall at (2, 2).
	var built: VltWorldMap = VltFixtureMap.map(
		"field", VltFixtureMap.filled(Vector2i(5, 5)), [Vector2i(2, 2)] as Array[Vector2i]
	)
	built.add_child(
		VltFixtureMap.warp(Vector2i(4, 4), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH)
	)
	built.add_child(VltFixtureMap.zone(GRASS, Vector2i(0, 3), Vector2i(2, 2)))
	return auto_free(built)


func _walker(map: VltWorldMap, at: Vector2i) -> VltGridWalker:
	var walker: VltGridWalker = auto_free(VltGridWalker.new())
	walker.map = map
	walker.place(at, VltFacing.Direction.SOUTH)
	return walker


func _walking(map: VltWorldMap, at: Vector2i, rate: int) -> VltGridWalker:
	var walker: VltGridWalker = _walker(map, at)
	walker.tables = {GRASS: VltFixtureMap.table(GRASS, rate)}
	walker.encounter_decider = VltSeededEncounterDecider.new(SEED)
	return walker


# --- moving and not moving ---------------------------------------------------


func test_a_step_moves_one_cell() -> void:
	var walker: VltGridWalker = _walker(_map(), Vector2i(1, 1))
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.EAST)

	assert_bool(step.moved).is_true()
	assert_vector(step.cell).is_equal(Vector2i(2, 1))
	assert_vector(walker.cell).is_equal(Vector2i(2, 1))


func test_a_step_into_a_wall_does_not_move_but_still_turns() -> void:
	# The behaviour most easily lost in a refactor: from outside, a blocked step
	# and a step that did nothing look identical.
	var walker: VltGridWalker = _walker(_map(), Vector2i(2, 1))
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.SOUTH)

	assert_bool(step.moved).is_false()
	assert_vector(walker.cell).is_equal(Vector2i(2, 1))
	assert_int(walker.facing).override_failure_message(
		"a blocked step left the walker facing the way it came"
	).is_equal(VltFacing.Direction.SOUTH)


func test_a_step_off_the_edge_is_blocked_like_a_wall() -> void:
	# Off the map is a cell with no terrain, so it blocks without a fence being
	# painted around every map.
	var walker: VltGridWalker = _walker(_map(), Vector2i(0, 0))
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.WEST)

	assert_bool(step.moved).is_false()
	assert_vector(walker.cell).is_equal(Vector2i(0, 0))


func test_every_direction_leads_where_it_says() -> void:
	# A transposed axis or an inverted sign passes any single-direction test.
	# North is -Z, which is Godot's own forward; getting that backwards would
	# make every map play mirrored.
	var walker: VltGridWalker = _walker(_map(), Vector2i(1, 1))

	walker.step(VltFacing.Direction.NORTH)
	assert_vector(walker.cell).is_equal(Vector2i(1, 0))
	walker.step(VltFacing.Direction.SOUTH)
	assert_vector(walker.cell).is_equal(Vector2i(1, 1))
	walker.step(VltFacing.Direction.EAST)
	assert_vector(walker.cell).is_equal(Vector2i(2, 1))
	walker.step(VltFacing.Direction.WEST)
	assert_vector(walker.cell).is_equal(Vector2i(1, 1))


func test_a_walker_with_no_map_goes_nowhere() -> void:
	var walker: VltGridWalker = auto_free(VltGridWalker.new())
	walker.place(Vector2i(3, 3), VltFacing.Direction.NORTH)
	assert_bool(walker.step(VltFacing.Direction.EAST).moved).is_false()


# --- warps -------------------------------------------------------------------


func test_stepping_onto_a_warp_reports_where_it_leads() -> void:
	var map: VltWorldMap = _map()
	var walker: VltGridWalker = _walker(map, Vector2i(3, 4))
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.EAST)

	assert_object(step.warp).is_not_null()
	assert_str(step.warp.to_map).is_equal("cave")
	assert_vector(step.warp.to_cell).is_equal(Vector2i(1, 1))
	assert_int(step.warp.to_facing).is_equal(VltFacing.Direction.NORTH)


func test_an_ordinary_cell_carries_no_warp() -> void:
	var walker: VltGridWalker = _walker(_map(), Vector2i(1, 1))
	assert_object(walker.step(VltFacing.Direction.EAST).warp).is_null()


func test_a_warp_does_not_also_start_a_battle() -> void:
	# An encounter on the way out would open a battle on a map the player has
	# already left. The warp cell sits inside no zone here, so the guard is what
	# is being tested rather than the geometry — the rate is certain.
	var map: VltWorldMap = _map()
	map.add_child(VltFixtureMap.zone(GRASS, Vector2i(4, 4), Vector2i(1, 1)))

	var walker: VltGridWalker = _walking(map, Vector2i(3, 4), VltEncounterDecider.RATE_DENOMINATOR)
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.EAST)

	assert_object(step.warp).is_not_null()
	assert_object(step.encounter).override_failure_message(
		"a step onto a warp also drew an encounter"
	).is_null()


# --- events ------------------------------------------------------------------


func _talking(line: String) -> Array[VltEventStep]:
	var steps: Array[VltEventStep] = [VltFixtureEvent.say(line)]
	return steps


func test_stepping_onto_a_cell_reports_its_event() -> void:
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_talking("a_trap"), VltEvent.Trigger.ENTER_CELL, Vector2i(2, 1)
		)
	)

	var walker: VltGridWalker = _walker(map, Vector2i(1, 1))
	assert_object(walker.step(VltFacing.Direction.EAST).event).is_not_null()


func test_an_interact_event_does_not_fire_by_being_walked_on() -> void:
	# The moments are distinct (decision 0043). An event meant to be asked for
	# must not go off underfoot.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(_talking("a_sign"), VltEvent.Trigger.INTERACT, Vector2i(2, 1))
	)

	var walker: VltGridWalker = _walker(map, Vector2i(1, 1))
	assert_object(walker.step(VltFacing.Direction.EAST).event).override_failure_message(
		"an interact event fired by being stepped on"
	).is_null()


func test_interacting_reads_the_cell_the_walker_faces() -> void:
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(_talking("a_sign"), VltEvent.Trigger.INTERACT, Vector2i(2, 1))
	)

	var walker: VltGridWalker = _walker(map, Vector2i(1, 1))
	walker.place(Vector2i(1, 1), VltFacing.Direction.EAST)
	assert_object(walker.interact()).is_not_null()

	walker.place(Vector2i(1, 1), VltFacing.Direction.WEST)
	assert_object(walker.interact()).override_failure_message(
		"interacting reached a cell the walker was not facing"
	).is_null()


func test_interacting_works_against_a_cell_that_cannot_be_entered() -> void:
	# Talking to somebody means facing them, and a person is something you cannot
	# walk into. An interaction that required a walkable cell would make every
	# NPC unreachable.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(_talking("an_elder"), VltEvent.Trigger.INTERACT, Vector2i(2, 2))
	)

	var walker: VltGridWalker = _walker(map, Vector2i(2, 1))
	walker.place(Vector2i(2, 1), VltFacing.Direction.SOUTH)

	assert_bool(map.is_walkable(Vector2i(2, 2))).is_false()
	assert_object(walker.interact()).is_not_null()


func test_an_event_beats_an_encounter_on_the_same_cell() -> void:
	# Both firing would open a dialogue and a battle at once. The deliberate
	# trigger is not the one to drop.
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_talking("a_trap"), VltEvent.Trigger.ENTER_CELL, Vector2i(0, 3)
		)
	)

	var walker: VltGridWalker = _walking(map, Vector2i(0, 2), VltEncounterDecider.RATE_DENOMINATOR)
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.SOUTH)

	assert_object(step.event).is_not_null()
	assert_object(step.encounter).override_failure_message(
		"a scripted event and an ambient encounter fired on the same step"
	).is_null()


func test_a_warp_beats_an_event() -> void:
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_talking("never_seen"), VltEvent.Trigger.ENTER_CELL, Vector2i(4, 4)
		)
	)

	var walker: VltGridWalker = _walker(map, Vector2i(3, 4))
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.EAST)

	assert_object(step.warp).is_not_null()
	assert_object(step.event).override_failure_message(
		"an event fired on a cell the player was leaving through"
	).is_null()


func test_a_blocked_step_triggers_no_event() -> void:
	var map: VltWorldMap = _map()
	map.add_child(
		VltFixtureEvent.event(
			_talking("behind_the_wall"), VltEvent.Trigger.ENTER_CELL, Vector2i(2, 2)
		)
	)

	var walker: VltGridWalker = _walker(map, Vector2i(2, 1))
	assert_object(walker.step(VltFacing.Direction.SOUTH).event).is_null()


func test_interacting_with_no_map_finds_nothing() -> void:
	var walker: VltGridWalker = auto_free(VltGridWalker.new())
	assert_object(walker.interact()).is_null()


# --- zones and encounters ----------------------------------------------------


func test_a_step_inside_a_zone_can_start_a_battle() -> void:
	var walker: VltGridWalker = _walking(_map(), Vector2i(0, 2), VltEncounterDecider.RATE_DENOMINATOR)
	var step: VltGridWalker.Step = walker.step(VltFacing.Direction.SOUTH)

	assert_bool(step.started_a_battle()).is_true()
	assert_str(step.encounter.species_id).is_equal("placeholder_base")
	assert_int(step.encounter.level).is_between(3, 5)


func test_a_step_outside_every_zone_draws_nothing() -> void:
	var walker: VltGridWalker = _walking(_map(), Vector2i(3, 0), VltEncounterDecider.RATE_DENOMINATOR)
	assert_object(walker.step(VltFacing.Direction.EAST).encounter).override_failure_message(
		"an encounter was drawn outside any zone"
	).is_null()


func test_a_blocked_step_inside_a_zone_draws_nothing() -> void:
	# Standing still in tall grass draws nothing, which is the whole reason the
	# check is per step rather than per moment.
	var map: VltWorldMap = VltFixtureMap.map(
		"pen", VltFixtureMap.filled(Vector2i(1, 1))
	)
	map.add_child(VltFixtureMap.zone(GRASS, Vector2i(0, 0), Vector2i(1, 1)))
	auto_free(map)

	var walker: VltGridWalker = _walking(map, Vector2i(0, 0), VltEncounterDecider.RATE_DENOMINATOR)
	for attempt: int in range(20):
		var step: VltGridWalker.Step = walker.step(VltFacing.Direction.EAST)
		assert_bool(step.moved).is_false()
		assert_object(step.encounter).override_failure_message(
			"walking into a wall inside a zone drew an encounter"
		).is_null()


func test_a_zone_naming_no_loaded_table_is_quiet() -> void:
	# A content error the meta-test catches. At runtime it must not crash: this
	# would otherwise fail in front of a player, which is the worst place to be
	# right about a typo.
	var map: VltWorldMap = _map()
	var walker: VltGridWalker = _walking(map, Vector2i(0, 2), VltEncounterDecider.RATE_DENOMINATOR)
	walker.tables = {}

	assert_object(walker.step(VltFacing.Direction.SOUTH).encounter).is_null()


func test_encounters_are_off_without_a_decider() -> void:
	var walker: VltGridWalker = _walker(_map(), Vector2i(0, 2))
	walker.tables = {GRASS: VltFixtureMap.table(GRASS, VltEncounterDecider.RATE_DENOMINATOR)}

	assert_object(walker.step(VltFacing.Direction.SOUTH).encounter).override_failure_message(
		"an encounter was drawn with no decider to draw it"
	).is_null()


func test_a_quiet_zone_never_fires() -> void:
	var walker: VltGridWalker = _walking(_map(), Vector2i(0, 3), 0)

	for attempt: int in range(50):
		walker.place(Vector2i(0, 3), VltFacing.Direction.SOUTH)
		assert_object(walker.step(VltFacing.Direction.SOUTH).encounter).is_null()
