extends GdUnitTestSuite

## One playing of an event (spec 15, section 9).
##
## The properties here are the ones decision 0044 exists for. An interrupted
## event leaving a flag behind, or a replay landing somewhere different from a
## first run, would put a save in a state no event knows how to resume — and
## nothing else in the suite would notice.


func _steps(of: Array[VltEventStep]) -> Array[VltEventStep]:
	return of


func _run(event: VltEvent, flags: VltQuestFlags) -> VltEventRun:
	var run: VltEventRun = VltEventRun.of(event, flags)
	run.advance()
	return run


## Drives a run to its end, acknowledging every line it asks for. Returns the
## lines in the order they were said.
func _play(run: VltEventRun) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	var guard: int = 0

	while not run.is_finished():
		var request: VltEventRequest = run.request()
		assert_object(request).override_failure_message(
			"the run stopped without finishing and without asking for anything"
		).is_not_null()
		said.append(request.line_id)
		run.resume()

		guard += 1
		assert_int(guard).override_failure_message("the run did not terminate").is_less(100)

	return said


# --- order and nesting -------------------------------------------------------


func test_steps_run_in_tree_order() -> void:
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.say("first"),
					VltFixtureEvent.say("second"),
					VltFixtureEvent.say("third"),
				]
			)
		)
	)

	var said: PackedStringArray = _play(_run(event, VltQuestFlags.new()))
	assert_array(said).is_equal(["first", "second", "third"])


func test_a_sequence_runs_where_it_sits() -> void:
	# Nesting must not reorder anything: the group's steps happen at the group's
	# position, not before or after the rest.
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.say("before"),
					VltFixtureEvent.sequence(
						_steps([VltFixtureEvent.say("inside_one"), VltFixtureEvent.say("inside_two")])
					),
					VltFixtureEvent.say("after"),
				]
			)
		)
	)

	assert_array(_play(_run(event, VltQuestFlags.new()))).is_equal(
		["before", "inside_one", "inside_two", "after"]
	)


func test_an_event_with_no_steps_is_finished_immediately() -> void:
	var event: VltEvent = auto_free(VltFixtureEvent.event(_steps([])))
	var run: VltEventRun = _run(event, VltQuestFlags.new())

	assert_bool(run.is_finished()).is_true()
	assert_object(run.request()).is_null()


# --- suspension --------------------------------------------------------------


func test_a_line_suspends_the_run_and_names_itself() -> void:
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(_steps([VltFixtureEvent.say("elder_greeting")]))
	)
	var run: VltEventRun = _run(event, VltQuestFlags.new())

	assert_bool(run.is_finished()).is_false()
	assert_int(run.request().kind).is_equal(VltEventRequest.Kind.SAY)
	assert_str(run.request().line_id).is_equal("elder_greeting")

	run.resume()
	assert_bool(run.is_finished()).is_true()


func test_advancing_while_waiting_changes_nothing() -> void:
	# The caller drives the loop, so it will call this again. It must not skip
	# the answer it is waiting for.
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(_steps([VltFixtureEvent.say("one"), VltFixtureEvent.say("two")]))
	)
	var run: VltEventRun = _run(event, VltQuestFlags.new())

	run.advance()
	run.advance()
	assert_str(run.request().line_id).override_failure_message(
		"advancing while waiting walked past the request"
	).is_equal("one")


# --- the atomic commit -------------------------------------------------------


func test_an_interrupted_event_leaves_no_flag_set() -> void:
	# The property the whole of decision 0044 exists for. On mobile the
	# application will be killed here.
	var world: VltQuestFlags = VltQuestFlags.new()
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.set_flag("met_the_elder"),
					VltFixtureEvent.say("a_long_speech"),
					VltFixtureEvent.set_counter("elder_quest", 1),
				]
			)
		)
	)

	var run: VltEventRun = _run(event, world)
	assert_bool(run.is_finished()).is_false()

	assert_bool(world.is_set("met_the_elder")).override_failure_message(
		"a flag set before the interruption reached the world"
	).is_false()
	assert_int(world.count("elder_quest")).is_equal(0)


func test_the_flags_land_together_when_it_finishes() -> void:
	var world: VltQuestFlags = VltQuestFlags.new()
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.set_flag("met_the_elder"),
					VltFixtureEvent.say("a_speech"),
					VltFixtureEvent.set_counter("elder_quest", 1),
				]
			)
		)
	)

	_play(_run(event, world))

	assert_bool(world.is_set("met_the_elder")).is_true()
	assert_int(world.count("elder_quest")).is_equal(1)


func _greeting() -> VltEvent:
	return auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.set_flag("met_the_elder"),
					VltFixtureEvent.say("a_speech"),
					VltFixtureEvent.set_counter("elder_quest", 2),
				]
			)
		)
	)


func _world_after(runs: int) -> String:
	var world: VltQuestFlags = VltQuestFlags.new()
	for repeat: int in range(runs):
		_play(_run(_greeting(), world))
	return JSON.stringify(VltQuestFlagsSection.new(world).write())


func test_replaying_twice_is_indistinguishable_from_running_once() -> void:
	# Decision 0044 requires an interrupted event to replay from its start, which
	# is only safe if replaying changes nothing the first run already did. This is
	# why a counter is set to a value rather than incremented.
	assert_str(_world_after(2)).override_failure_message(
		"running an event twice left a different world than running it once"
	).is_equal(_world_after(1))


# --- branching ---------------------------------------------------------------


func test_a_branch_takes_the_arm_the_flag_selects() -> void:
	var world: VltQuestFlags = VltQuestFlags.new()
	world.raise("has_key")

	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch(
						"has_key", VltFixtureEvent.say("it_opens"), VltFixtureEvent.say("its_locked")
					)
				]
			)
		)
	)

	assert_array(_play(_run(event, world))).is_equal(["it_opens"])


func test_a_branch_on_an_absent_flag_takes_the_other_arm() -> void:
	# The absent flag is the case every quest starts in, so it is the one an
	# implementation reading a missing key as "true" would break.
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch(
						"has_key", VltFixtureEvent.say("it_opens"), VltFixtureEvent.say("its_locked")
					)
				]
			)
		)
	)

	assert_array(_play(_run(event, VltQuestFlags.new()))).is_equal(["its_locked"])


func test_a_branch_sees_a_flag_set_earlier_in_the_same_run() -> void:
	# Flags land in the world only at the end, so a branch reading the world
	# alone would never see what its own event just did.
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.set_flag("just_now"),
					VltFixtureEvent.branch(
						"just_now", VltFixtureEvent.say("saw_it"), VltFixtureEvent.say("missed_it")
					),
				]
			)
		)
	)

	assert_array(_play(_run(event, VltQuestFlags.new()))).override_failure_message(
		"a branch could not see what an earlier step in its own run set"
	).is_equal(["saw_it"])


func test_an_empty_arm_is_allowed() -> void:
	# "Do nothing otherwise" is the common shape, and it must not be a hole.
	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch("has_key", VltFixtureEvent.say("it_opens")),
					VltFixtureEvent.say("afterwards"),
				]
			)
		)
	)

	assert_array(_play(_run(event, VltQuestFlags.new()))).is_equal(["afterwards"])


func test_an_arm_may_hold_several_steps() -> void:
	var world: VltQuestFlags = VltQuestFlags.new()
	world.raise("has_key")

	var event: VltEvent = auto_free(
		VltFixtureEvent.event(
			_steps(
				[
					VltFixtureEvent.branch(
						"has_key",
						VltFixtureEvent.sequence(
							_steps([VltFixtureEvent.say("turn"), VltFixtureEvent.say("push")])
						)
					),
					VltFixtureEvent.say("through"),
				]
			)
		)
	)

	assert_array(_play(_run(event, world))).is_equal(["turn", "push", "through"])


# --- lowering ----------------------------------------------------------------


func test_an_event_can_clear_a_flag() -> void:
	# False is carried as deliberately as true, or a flag could never be undone.
	var world: VltQuestFlags = VltQuestFlags.new()
	world.raise("door_open")

	var event: VltEvent = auto_free(
		VltFixtureEvent.event(_steps([VltFixtureEvent.set_flag("door_open", false)]))
	)
	_play(_run(event, world))

	assert_bool(world.is_set("door_open")).is_false()
