extends GdUnitTestSuite

## The overworld's only mechanical guard (spec 14, section 7).
##
## Every case here is a map built to be broken. A validator with no failing
## fixture is a validator nobody has ever seen reject anything — and this one
## stands in for the test pillars the overworld gives up (decision 0038), so it
## had better fire.

## A PackedStringArray literal is not a constant expression in GDScript, so the
## known tables are built rather than declared.
func _tables() -> PackedStringArray:
	return PackedStringArray(["meadow"])


## A map that is fine, which since section 9 includes having somewhere to send a
## defeated player. The tests that are about the absence of one build a bare map
## instead.
func _field(id: String) -> VltWorldMap:
	var built: VltWorldMap = _bare(id)
	built.add_child(VltFixtureMap.rest(Vector2i(0, 0)))
	return built


func _bare(id: String) -> VltWorldMap:
	return auto_free(VltFixtureMap.map(id, VltFixtureMap.filled(Vector2i(4, 4))))


func _maps(of: Array[VltWorldMap]) -> Array[VltWorldMap]:
	return of


func _problems(maps: Array[VltWorldMap], entry: String = "") -> PackedStringArray:
	return VltMapValidator.check(maps, _tables(), entry)


func _complains_about(problems: PackedStringArray, fragment: String) -> bool:
	for problem: String in problems:
		if problem.contains(fragment):
			return true
	return false


# --- the filename is the id --------------------------------------------------


func test_a_map_whose_file_is_named_something_else_is_caught() -> void:
	# The overworld lists the folder and takes each filename as an id, without
	# opening anything. So a disagreement here is not untidiness: the map does not
	# exist as far as the game is concerned, and a save holding its id (decision
	# 0040) loads into nothing.
	var map: VltWorldMap = _field("starter_field")
	map.scene_file_path = "res://game/maps/an_older_name.tscn"

	assert_bool(
		_complains_about(_problems(_maps([map])), "an_older_name")
	).override_failure_message(
		"a map the game can never find was not reported"
	).is_true()


func test_a_map_named_after_its_id_passes() -> void:
	var map: VltWorldMap = _field("starter_field")
	map.scene_file_path = "res://game/maps/starter_field.tscn"

	assert_array(_problems(_maps([map]))).is_empty()


func test_a_map_with_no_file_is_not_asked() -> void:
	# Every other fixture in this suite is built in code and has no file at all.
	# The rule is about files, so it has to leave those alone — otherwise it would
	# fire on every case here and say nothing about any of them.
	var map: VltWorldMap = _field("built_in_code")

	assert_array(_problems(_maps([map]))).is_empty()


# --- a map that is fine ------------------------------------------------------


func test_a_sound_pair_of_maps_reports_nothing() -> void:
	# Without this, every test below would pass on a validator that complains
	# about everything.
	var field: VltWorldMap = _field("field")
	var cave: VltWorldMap = _field("cave")
	field.add_child(
		VltFixtureMap.warp(Vector2i(3, 3), "cave", Vector2i(1, 1), VltFacing.Direction.NORTH)
	)
	cave.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "field", Vector2i(3, 3), VltFacing.Direction.SOUTH)
	)
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(0, 0), Vector2i(2, 2)))

	assert_array(_problems(_maps([field, cave]), "field")).is_empty()


# --- warps -------------------------------------------------------------------


func test_a_warp_to_an_unknown_map_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "nowhere", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	assert_bool(_complains_about(_problems(_maps([field])), "unknown map")).is_true()


func test_a_warp_arriving_where_nobody_can_stand_is_reported() -> void:
	# The check no single map can make on its own: the destination lives in a
	# different file from the warp.
	var field: VltWorldMap = _field("field")
	var cave: VltWorldMap = _field("cave")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "cave", Vector2i(40, 40), VltFacing.Direction.NORTH)
	)

	assert_bool(
		_complains_about(_problems(_maps([field, cave])), "cannot be stood on")
	).is_true()


func test_a_warp_leading_nowhere_at_all_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "", Vector2i.ZERO, VltFacing.Direction.NORTH)
	)

	assert_bool(_complains_about(_problems(_maps([field])), "leads nowhere")).is_true()


func test_a_warp_on_a_cell_nobody_can_reach_is_reported() -> void:
	# It can never fire, which looks exactly like a warp that is merely hidden.
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(9, 9), "field", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	assert_bool(
		_complains_about(_problems(_maps([field])), "sits on a cell that cannot be stood on")
	).is_true()


func test_two_warps_on_one_cell_are_reported() -> void:
	var field: VltWorldMap = _field("field")
	for repeat: int in range(2):
		field.add_child(
			VltFixtureMap.warp(Vector2i(1, 1), "field", Vector2i(0, 0), VltFacing.Direction.NORTH)
		)

	assert_bool(_complains_about(_problems(_maps([field])), "two warps on one cell")).is_true()


# --- zones -------------------------------------------------------------------


func test_a_zone_naming_an_unknown_table_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	field.add_child(VltFixtureMap.zone("swamp", Vector2i(0, 0), Vector2i(2, 2)))

	assert_bool(_complains_about(_problems(_maps([field])), "unknown table")).is_true()


func test_a_zone_with_no_table_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	field.add_child(VltFixtureMap.zone("", Vector2i(0, 0), Vector2i(2, 2)))

	assert_bool(_complains_about(_problems(_maps([field])), "names no encounter table")).is_true()


func test_a_zone_covering_nothing_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(0, 0), Vector2i(0, 3)))

	assert_bool(_complains_about(_problems(_maps([field])), "covers no cells")).is_true()


func test_overlapping_zones_are_reported() -> void:
	# Two tables claiming one cell has no right answer, and picking one silently
	# would be a bias nobody could see.
	var field: VltWorldMap = _field("field")
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(0, 0), Vector2i(3, 3)))
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(2, 2), Vector2i(2, 2)))

	assert_bool(_complains_about(_problems(_maps([field])), "overlaps")).is_true()


func test_zones_that_merely_touch_do_not_overlap() -> void:
	# The boundary case the rectangle comparison gets wrong in one direction.
	var field: VltWorldMap = _field("field")
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(0, 0), Vector2i(2, 2)))
	field.add_child(VltFixtureMap.zone("meadow", Vector2i(2, 0), Vector2i(2, 2)))

	assert_bool(_complains_about(_problems(_maps([field])), "overlaps")).is_false()


# --- identity and reachability ----------------------------------------------


func test_two_maps_with_one_id_are_reported() -> void:
	# A save holds a map id, so a duplicate means a loaded save can land on
	# either one of them.
	assert_bool(
		_complains_about(_problems(_maps([_field("field"), _field("field")])), "two maps claim")
	).is_true()


func test_a_map_with_no_id_is_reported() -> void:
	assert_bool(_complains_about(_problems(_maps([_field("")])), "no id")).is_true()


func test_a_map_no_warp_leads_to_is_reported() -> void:
	var field: VltWorldMap = _field("field")
	var island: VltWorldMap = _field("island")

	assert_bool(
		_complains_about(_problems(_maps([field, island]), "field"), "cannot be reached")
	).is_true()


func test_reachability_is_skipped_without_somewhere_to_start() -> void:
	# The check has no meaning without an entry point, so it is absent rather
	# than guessing at one.
	assert_array(_problems(_maps([_field("field"), _field("island")]))).is_empty()


func test_an_entry_map_that_does_not_exist_is_reported() -> void:
	assert_bool(
		_complains_about(_problems(_maps([_field("field")]), "missing"), "entry map")
	).is_true()


# --- somewhere to send a defeated player -------------------------------------


func test_a_world_with_no_rest_point_anywhere_is_refused() -> void:
	# Said once rather than once per map. A pass that printed the same sentence
	# for every room would bury everything else in this list.
	var problems: PackedStringArray = _problems(_maps([_bare("field"), _bare("cave")]))

	assert_bool(_complains_about(problems, "nowhere to send anybody")).is_true()
	assert_int(problems.size()).is_equal(1)


func test_a_map_that_can_reach_none_is_refused() -> void:
	# Content a defeat cannot recover from, and invisible until somebody loses
	# there.
	var field: VltWorldMap = _field("field")
	var island: VltWorldMap = _bare("island")

	assert_bool(
		_complains_about(_problems(_maps([field, island])), "island")
	).override_failure_message(
		"an island a defeat cannot recover from was accepted"
	).is_true()


func test_reaching_one_through_a_door_is_enough() -> void:
	var field: VltWorldMap = _field("field")
	var cave: VltWorldMap = _bare("cave")
	cave.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "field", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	assert_bool(
		_complains_about(_problems(_maps([field, cave])), "cannot recover")
	).is_false()


# --- everything at once ------------------------------------------------------


func test_all_problems_are_reported_rather_than_the_first() -> void:
	# A map pass fixes ten broken warps in one go or ten times over.
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "nowhere", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)
	field.add_child(VltFixtureMap.zone("swamp", Vector2i(0, 0), Vector2i(2, 2)))

	assert_int(_problems(_maps([field])).size()).is_greater(1)


# --- where each problem is ----------------------------------------------------
#
# The sentences are what a person reads and they have not changed. What is new is
# that each problem also says where it is, so a report can be walked to rather
# than only read. These are about that second reading staying honest: a place
# that is wrong is worse than no place, because it sends somebody somewhere.


func test_both_readings_come_from_one_run() -> void:
	# `check` is `lines` of `problems`, so the two cannot disagree. Pinned anyway:
	# the day somebody reimplements one of them, this is what says no.
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "nowhere", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	var maps: Array[VltWorldMap] = _maps([field])
	var carried: Array[VltMapProblem] = VltMapValidator.problems(maps, _tables())
	assert_array(VltMapValidator.lines(carried)).is_equal(VltMapValidator.check(maps, _tables()))


func test_a_broken_warp_carries_its_own_cell_and_file() -> void:
	var field: VltWorldMap = auto_free(
		VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(4, 4)), [Vector2i(2, 2)])
	)
	field.scene_file_path = "res://game/maps/field.tscn"
	field.add_child(VltFixtureMap.rest(Vector2i(0, 0)))
	field.add_child(
		VltFixtureMap.warp(Vector2i(2, 2), "field", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	var found: VltMapProblem = _carrying(
		VltMapValidator.problems(_maps([field]), _tables()), "cannot be stood on"
	)
	assert_object(found).is_not_null()
	assert_bool(found.located).is_true()
	assert_vector(found.cell).is_equal(Vector2i(2, 2))
	assert_str(found.scene_path).is_equal("res://game/maps/field.tscn")


func test_a_zone_problem_carries_the_corner_it_is_named_by() -> void:
	var field: VltWorldMap = _field("field")
	field.scene_file_path = "res://game/maps/field.tscn"
	field.add_child(VltFixtureMap.zone("", Vector2i(1, 2), Vector2i(2, 2)))

	var found: VltMapProblem = _carrying(
		VltMapValidator.problems(_maps([field]), _tables()), "names no encounter table"
	)
	assert_object(found).is_not_null()
	assert_vector(found.cell).is_equal(Vector2i(1, 2))


func test_a_flag_nothing_sets_carries_the_event_that_reads_it() -> void:
	# The two halves of a flag typo are found in one walk and reported after it,
	# so the place each was seen has to survive the walk.
	var field: VltWorldMap = _field("field")
	field.scene_file_path = "res://game/maps/field.tscn"
	var steps: Array[VltEventStep] = [VltFixtureEvent.branch("met_the_elder")]
	field.add_child(VltFixtureEvent.event(steps, VltEvent.Trigger.INTERACT, Vector2i(3, 1)))

	var found: VltMapProblem = _carrying(
		VltMapValidator.problems(_maps([field]), _tables()), "which nothing ever sets"
	)
	assert_object(found).is_not_null()
	assert_vector(found.cell).is_equal(Vector2i(3, 1))
	assert_str(found.scene_path).is_equal("res://game/maps/field.tscn")


func test_a_problem_about_the_world_has_nowhere_to_send_anybody() -> void:
	# "no map has a rest point" is about every map at once. A link on it would
	# have to pick one, and picking one would be a guess dressed as an answer.
	var found: VltMapProblem = _carrying(
		VltMapValidator.problems(_maps([_bare("field")]), _tables()), "no map has a rest point"
	)
	assert_object(found).is_not_null()
	assert_bool(found.navigable()).is_false()
	assert_bool(found.located).is_false()


func test_a_map_built_in_code_has_no_file_to_point_at() -> void:
	# Every fixture in this suite is one, and a report that offered to open them
	# would offer to open nothing.
	var field: VltWorldMap = _field("field")
	field.add_child(
		VltFixtureMap.warp(Vector2i(1, 1), "nowhere", Vector2i(0, 0), VltFacing.Direction.NORTH)
	)

	var found: VltMapProblem = _carrying(
		VltMapValidator.problems(_maps([field]), _tables()), "leads to unknown map"
	)
	assert_object(found).is_not_null()
	assert_bool(found.navigable()).is_false()


func test_nothing_wrong_says_nothing() -> void:
	var nothing: Array[VltMapProblem] = []
	assert_array(VltMapValidator.lines(nothing)).is_empty()


## The first problem whose sentence contains a fragment, or null.
func _carrying(found: Array[VltMapProblem], fragment: String) -> VltMapProblem:
	for problem: VltMapProblem in found:
		if problem.message.contains(fragment):
			return problem
	return null
