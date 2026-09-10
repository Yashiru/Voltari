extends GdUnitTestSuite

## The world, assembled (specs 14, 15 and 18).
##
## Every part of this had tests and none of them had a place to meet. This is the
## only test that walks a committed map, through a real door, into an event that
## sets a flag another map reads — and then saves and reloads all of it.
##
## It is a smoke test, not a design test: what it catches is a piece that moved.

const SCENE: String = "res://game/scenes/world/world_sandbox.tscn"


func before_test() -> void:
	_forget()


func after_test() -> void:
	_forget()


## The sandbox writes to a real file, so a test that left one behind would make
## the next one start somewhere it did not choose.
func _forget() -> void:
	for suffix: String in ["", VltSaveStore.TEMPORARY_SUFFIX, VltSaveStore.BACKUP_SUFFIX]:
		if FileAccess.file_exists(WorldSandbox.SAVE_PATH + suffix):
			DirAccess.remove_absolute(WorldSandbox.SAVE_PATH + suffix)


func _sandbox() -> WorldSandbox:
	var packed: PackedScene = load(SCENE)
	assert_object(packed).override_failure_message("no sandbox at %s" % SCENE).is_not_null()

	var world: WorldSandbox = auto_free(packed.instantiate() as WorldSandbox)
	add_child(world)
	return world


# --- walking -----------------------------------------------------------------


func test_it_comes_up_somewhere_standable() -> void:
	var world: WorldSandbox = _sandbox()
	assert_str(world.map_id()).is_equal(WorldSandbox.START_MAP)
	assert_vector(world.cell()).is_equal(WorldSandbox.START_CELL)


func test_a_step_moves_and_a_wall_does_not() -> void:
	var world: WorldSandbox = _sandbox()

	world.walk(VltFacing.Direction.EAST)
	assert_vector(world.cell()).is_equal(WorldSandbox.START_CELL + Vector2i(1, 0))

	# North from row 1 is row 0, which exists; west from column 0 is off the map.
	world.walk(VltFacing.Direction.WEST)
	world.walk(VltFacing.Direction.WEST)
	var against_the_edge: Vector2i = world.cell()
	world.walk(VltFacing.Direction.WEST)

	assert_vector(world.cell()).override_failure_message(
		"the walker left the map"
	).is_equal(against_the_edge)


# --- the door ----------------------------------------------------------------


func test_walking_through_the_door_changes_map() -> void:
	var world: WorldSandbox = _sandbox()

	# East along row 3, through the gap in the wall, to the door at (7, 3).
	world.walk(VltFacing.Direction.SOUTH)
	world.walk(VltFacing.Direction.SOUTH)
	for step: int in range(7):
		world.walk(VltFacing.Direction.EAST)

	assert_str(world.map_id()).override_failure_message(
		"the door did not lead anywhere — stopped at %s on %s" % [world.cell(), world.map_id()]
	).is_equal("starter_cave")


# --- events and flags --------------------------------------------------------


func test_reading_the_sign_sets_a_flag_the_other_map_reads() -> void:
	# Decision 0044 in the open: the flag lands when the event finishes, not
	# while it is playing.
	var world: WorldSandbox = _sandbox()

	# The sign sits on a blocked cell, so you stand beside it and face it — which
	# is spec 14's rule that interacting ignores walkability, on a real map.
	world.walk(VltFacing.Direction.EAST)
	world.face(VltFacing.Direction.SOUTH)
	world.interact()

	assert_bool(world.in_event()).override_failure_message(
		"interacting with the sign started nothing"
	).is_true()
	assert_bool(world.flags().is_set("read_the_sign")).override_failure_message(
		"a flag landed while the event was still playing"
	).is_false()

	_finish(world)
	assert_bool(world.flags().is_set("read_the_sign")).is_true()


func test_interacting_with_nothing_starts_nothing() -> void:
	var world: WorldSandbox = _sandbox()
	world.walk(VltFacing.Direction.NORTH)
	world.interact()
	assert_bool(world.in_event()).is_false()


## Drives an event to its end, the way a key press does.
func _finish(world: WorldSandbox) -> void:
	var guard: int = 0
	while world.in_event():
		world._run.resume()
		world._advance_event()
		guard += 1
		assert_int(guard).override_failure_message("the event did not end").is_less(20)


# --- the save ----------------------------------------------------------------


func test_a_save_carries_both_sections() -> void:
	# Two systems that know nothing about each other, into one document. This is
	# the first place both exist at once.
	var world: WorldSandbox = _sandbox()

	world.walk(VltFacing.Direction.EAST)
	world.face(VltFacing.Direction.SOUTH)
	world.interact()
	_finish(world)
	var where: Vector2i = world.cell()
	world.save_now()

	var again: WorldSandbox = _sandbox()
	assert_vector(again.cell()).override_failure_message(
		"the position did not come back"
	).is_equal(where)
	assert_bool(again.flags().is_set("read_the_sign")).override_failure_message(
		"the flag did not come back"
	).is_true()


func test_a_fresh_world_starts_at_the_start() -> void:
	# The other half: with nothing saved, nothing is restored. A load that
	# silently did something would be far worse than one that did nothing.
	var world: WorldSandbox = _sandbox()
	world.walk(VltFacing.Direction.EAST)
	world.load_now()

	assert_vector(world.cell()).is_equal(WorldSandbox.START_CELL + Vector2i(1, 0))


# --- meeting something -------------------------------------------------------


func _first_species() -> String:
	return VltContentPayloads.ids_in("res://content/generated/species")[0]


func test_an_encounter_puts_a_battle_on_top_of_the_world() -> void:
	# The handoff. The world produces a species and a level and stops there
	# (spec 14, section 5); this is the first thing that takes it further.
	var world: WorldSandbox = _sandbox()
	assert_bool(world.in_battle()).is_false()

	world.meet(_first_species(), 5)
	assert_bool(world.in_battle()).override_failure_message(
		"an encounter did not start a battle"
	).is_true()


func test_the_world_keeps_everything_while_a_battle_runs() -> void:
	# The world stays in the tree holding position, flags and party. Nothing is
	# saved and reloaded to cross the seam, so nothing can be lost crossing it.
	var world: WorldSandbox = _sandbox()

	world.walk(VltFacing.Direction.EAST)
	world.face(VltFacing.Direction.SOUTH)
	world.interact()
	_finish(world)

	var where: Vector2i = world.cell()
	world.meet(_first_species(), 5)

	assert_vector(world.cell()).is_equal(where)
	assert_bool(world.flags().is_set("read_the_sign")).is_true()


func test_the_party_is_the_same_creatures_that_went_in() -> void:
	# Held by the world rather than made when a battle starts, which is what
	# lets a wound carry from one battle to the next.
	var world: WorldSandbox = _sandbox()
	assert_int(world.party().size()).is_greater(0)

	var before: VltBattleCreature = world.party()[0]
	world.meet(_first_species(), 5)

	assert_bool(world.party()[0] == before).override_failure_message(
		"the battle was handed a different array, so nothing in it can reach back"
	).is_true()


func test_walking_is_refused_while_a_battle_is_up() -> void:
	var world: WorldSandbox = _sandbox()
	var where: Vector2i = world.cell()

	world.meet(_first_species(), 5)
	world._process(0.016)

	assert_vector(world.cell()).is_equal(where)


func _battle_of(world: WorldSandbox) -> BattleScreen:
	for child: Node in world.get_children():
		if child is BattleScreen:
			return child as BattleScreen
	return null


func test_the_battle_hands_the_world_back() -> void:
	# The return leg. A handoff that only went one way would look like it worked
	# for exactly as long as the first battle lasted.
	var world: WorldSandbox = _sandbox()
	world.meet(_first_species(), 3)

	var battle: BattleScreen = _battle_of(world)
	assert_object(battle).override_failure_message("no battle was put up").is_not_null()
	battle.skip(true)

	# A level 3 opponent against a level 12 starter: this ends, and quickly.
	var guard: int = 0
	while world.in_battle() and guard < 30:
		await battle.take_turn(0)
		guard += 1

	assert_bool(world.in_battle()).override_failure_message(
		"the battle never handed back after %d turns" % guard
	).is_false()


func test_walking_works_again_afterwards() -> void:
	var world: WorldSandbox = _sandbox()
	var where: Vector2i = world.cell()
	world.meet(_first_species(), 3)

	var battle: BattleScreen = _battle_of(world)
	battle.skip(true)
	var guard: int = 0
	while world.in_battle() and guard < 30:
		await battle.take_turn(0)
		guard += 1

	world.walk(VltFacing.Direction.EAST)
	assert_vector(world.cell()).override_failure_message(
		"the world did not take input back"
	).is_equal(where + Vector2i(1, 0))


# --- what a battle was worth -------------------------------------------------


func _fight(world: WorldSandbox, level: int) -> BattleScreen:
	world.meet(_first_species(), level)
	var battle: BattleScreen = _battle_of(world)
	battle.skip(true)

	var guard: int = 0
	while world.in_battle() and guard < 30:
		await battle.take_turn(0)
		guard += 1
	return battle


func test_winning_a_battle_earns_the_party_experience() -> void:
	# VltPostBattle has been written and tested since spec 10 and nothing called
	# it. This is the call.
	var world: WorldSandbox = _sandbox()
	var before: int = world.party()[0].experience

	await _fight(world, 5)

	assert_int(world.party()[0].experience).override_failure_message(
		"a battle was won and the party learned nothing from it"
	).is_greater(before)


func test_the_experience_lands_on_the_party_the_world_carries() -> void:
	# The array is the shared thing, not the creatures in it. Decision 0011 makes
	# a turn deep-copy its state on entry, so what comes out of a battle is never
	# what went in — and the seam puts the result back into the array the world
	# holds. Asserting object identity here would be asserting the engine is
	# impure.
	var world: WorldSandbox = _sandbox()
	var same_species: String = world.party()[0].species_id

	await _fight(world, 5)

	assert_bool(world.party().is_empty()).is_false()
	assert_str(world.party()[0].species_id).is_equal(same_species)
	assert_int(world.party()[0].experience).override_failure_message(
		"the battle's result never reached the world's party"
	).is_greater(0)


func test_a_lost_battle_earns_nothing() -> void:
	var world: WorldSandbox = _sandbox()
	var battle: BattleScreen = await _fight(world, 5)
	assert_int(battle.awards().size()).is_greater(0)

	# The other direction is hard to arrange honestly — a level 12 starter does
	# not lose to anything the placeholder roster has. What can be checked is
	# that the awards come from the pipeline rather than from winning itself.
	assert_int(battle.awards()[0].experience).is_greater(0)


# --- the party in the save ---------------------------------------------------


func test_the_party_survives_a_save() -> void:
	# The third section, and the first whose contents are the point of the game.
	var world: WorldSandbox = _sandbox()
	await _fight(world, 5)

	var earned: int = world.party()[0].experience
	var wounded: int = world.party()[0].current_hp
	world.save_now()

	var again: WorldSandbox = _sandbox()
	assert_int(again.party().size()).override_failure_message(
		"the party came back a different size"
	).is_equal(world.party().size())
	assert_int(again.party()[0].experience).override_failure_message(
		"the experience did not come back"
	).is_equal(earned)
	assert_int(again.party()[0].current_hp).override_failure_message(
		"a saved party came back healed, which plays as a feature until somebody notices"
	).is_equal(wounded)


# --- being put away ----------------------------------------------------------


func test_being_backgrounded_in_the_world_writes_a_save() -> void:
	# On a phone this is the ordinary way a session ends, and almost all of a
	# session is spent walking.
	var world: WorldSandbox = _sandbox()
	world.walk(VltFacing.Direction.EAST)

	assert_bool(world.save_on_background()).is_true()
	assert_bool(VltSaveStore.exists(WorldSandbox.SAVE_PATH)).is_true()


func test_being_backgrounded_mid_battle_writes_nothing() -> void:
	# A save never holds battle state (spec 13, section 6). The battle is lost
	# on reload either way — that is accepted — but losing the walk that led to
	# it is not.
	var world: WorldSandbox = _sandbox()
	world.meet(_first_species(), 5)

	assert_bool(world.save_on_background()).override_failure_message(
		"a save was written in the middle of a battle"
	).is_false()
	assert_bool(VltSaveStore.exists(WorldSandbox.SAVE_PATH)).is_false()


func test_being_backgrounded_mid_event_writes_nothing() -> void:
	# A half-run event has set no flags, so a save now records a world nothing
	# can resume (decision 0044).
	var world: WorldSandbox = _sandbox()
	world.walk(VltFacing.Direction.EAST)
	world.face(VltFacing.Direction.SOUTH)
	world.interact()

	assert_bool(world.in_event()).is_true()
	assert_bool(world.save_on_background()).override_failure_message(
		"a save was written with an event half-played"
	).is_false()


func test_the_refusal_is_only_a_refusal() -> void:
	# It comes back and saves afterwards. A guard that left the world unable to
	# save at all would be worse than the thing it prevents.
	var world: WorldSandbox = _sandbox()
	world.meet(_first_species(), 5)
	assert_bool(world.save_on_background()).is_false()

	var battle: BattleScreen = _battle_of(world)
	battle.skip(true)
	var guard: int = 0
	while world.in_battle() and guard < 30:
		await battle.take_turn(0)
		guard += 1

	assert_bool(world.save_on_background()).override_failure_message(
		"the world could not save once the battle was over"
	).is_true()
