extends GdUnitTestSuite

## The view advanced by the log (spec 17, section 1; decision 0049).
##
## The load-bearing test is the last one: a view built from the state and a view
## advanced by the log must agree. That is invariant 8 restated about a view, and
## it is what makes "the UI never reads the state" cost nothing in fidelity.

const OURS: int = 0
const THEIRS: int = 1
const MOVE: String = "test_move"


func _registry() -> VltEffectRegistry:
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	registry.register(VltReflect.define())
	return registry


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 90, 80, 70, 60])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["normal"])
	)
	creature.moves.append(VltMoveSlot.create(MOVE, 10))
	return creature


func _battle() -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(_creature("species_%d_a" % side))
		state.sides[side].party.append(_creature("species_%d_b" % side))
		state.sides[side].slots[0].occupy(0)
	return state


func _view(state: VltBattleState) -> VltBattleView:
	return VltBattleView.of(state, _registry(), OURS)


# --- one event at a time -----------------------------------------------------


func test_a_turn_start_moves_the_turn_on() -> void:
	var view: VltBattleView = _view(_battle())
	view.advance(VltLogTurnStart.create(7), _registry())
	assert_int(view.turn).is_equal(7)


func test_damage_to_your_own_side_is_exact() -> void:
	var state: VltBattleState = _battle()
	var view: VltBattleView = _view(state)
	var at: VltSlotRef = VltSlotRef.at(OURS, 0)

	view.advance(VltLogDamage.create(at, 40, 100, 175), _registry())

	assert_int(view.mine[0].current_hp).is_equal(100)
	assert_int(view.mine[0].health).is_equal(57)


func test_damage_to_the_other_side_arrives_already_reduced() -> void:
	# A transformed event is rescaled to hundredths before it reaches an
	# opponent, so the same arithmetic has to serve both forms.
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	var full: VltLogDamage = VltLogDamage.create(at, 40, 100, 175)
	@warning_ignore("unsafe_cast")
	view.advance(full.reduced() as VltLogEvent, _registry())

	assert_int(view.theirs[0].health).is_equal(57)
	assert_bool(view.theirs[0].knows_exact_health()).override_failure_message(
		"a reduced event handed over an exact figure"
	).is_false()


func test_a_faint_shows_as_down_and_empty() -> void:
	var view: VltBattleView = _view(_battle())
	view.advance(VltLogFaint.create(VltSlotRef.at(THEIRS, 0)), _registry())

	assert_bool(view.theirs[0].fainted).is_true()
	assert_int(view.theirs[0].health).is_equal(0)


func test_a_switch_replaces_the_combatant_rather_than_editing_it() -> void:
	# Stages, status and revealed moves belong to whoever just left. Carrying
	# one over would be invisible until the moment it mattered.
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	view.advance(VltLogStatChange.create(at, VltStats.Stat.ATK, 2, 2), _registry())
	assert_int(view.theirs[0].stat_stages[VltStats.Stat.ATK]).is_equal(2)

	view.advance(VltLogSwitchIn.create(at, 1, "species_1_b", 33), _registry())

	assert_str(view.theirs[0].species_id).is_equal("species_1_b")
	assert_int(view.theirs[0].level).is_equal(33)
	assert_int(view.theirs[0].stat_stages[VltStats.Stat.ATK]).override_failure_message(
		"a stat stage survived the creature it belonged to"
	).is_equal(0)


func test_a_switch_takes_its_types_from_the_species() -> void:
	# No event carries types: a switch announces an identifier, and types are a
	# property of the species rather than of the moment.
	var view: VltBattleView = _view(_battle())
	var species: Dictionary[String, VltSpecies] = {
		"species_1_b": VltSpecies.create(
			"species_1_b", PackedStringArray(["water"]), PackedInt32Array([50, 50, 50, 50, 50, 50])
		)
	}

	view.advance(
		VltLogSwitchIn.create(VltSlotRef.at(THEIRS, 0), 1, "species_1_b", 12),
		_registry(),
		species
	)

	assert_array(view.theirs[0].types).is_equal(PackedStringArray(["water"]))


func test_a_major_status_appears_and_clears() -> void:
	var state: VltBattleState = _battle()
	var view: VltBattleView = _view(state)
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	VltEffectDispatch.apply(state, _registry(), VltBurn.ID, at, at)
	var instance: VltEffectInstance = state.creature_at(at).effects[0]

	view.advance(
		VltLogEffectChanged.create(instance, VltEffectDefinition.Scope.CREATURE, at),
		_registry()
	)
	assert_str(view.theirs[0].status_id).is_equal(VltBurn.ID)

	view.advance(
		VltLogEffectChanged.removal(VltBurn.ID, VltEffectDefinition.Scope.CREATURE, at),
		_registry()
	)
	assert_str(view.theirs[0].status_id).is_empty()


func test_an_ordinary_effect_is_not_a_status() -> void:
	var state: VltBattleState = _battle()
	var view: VltBattleView = _view(state)
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	var registry: VltEffectRegistry = _registry()
	VltEffectDispatch.apply(state, registry, VltReflect.ID, at, at)

	# Read through the dispatch rather than a hardcoded container: reflect is
	# side-scoped, and a test that guessed would be testing its own guess.
	var scope: VltEffectDefinition.Scope = registry.definition(VltReflect.ID).scope
	var instance: VltEffectInstance = VltEffectDispatch.container_for(state, scope, at)[0]

	view.advance(VltLogEffectChanged.create(instance, scope, at), registry)

	assert_str(view.theirs[0].status_id).override_failure_message(
		"a screen was reported as a status"
	).is_empty()


func test_an_opponents_move_is_revealed_once() -> void:
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	for repeat: int in range(3):
		view.advance(
			VltLogMoveUsed.create(at, MOVE, 0, 9, VltSlotRef.at(OURS, 0)), _registry()
		)

	assert_array(view.theirs[0].revealed_moves).is_equal(PackedStringArray([MOVE]))


func test_your_own_move_spends_pp_rather_than_being_revealed() -> void:
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(OURS, 0)

	view.advance(VltLogMoveUsed.create(at, MOVE, 0, 9, VltSlotRef.at(THEIRS, 0)), _registry())

	assert_int(view.mine[0].moves[0].pp).is_equal(9)
	assert_array(view.mine[0].revealed_moves).is_empty()


func test_an_event_that_changes_nothing_observable_changes_nothing() -> void:
	# Ignored on purpose rather than by omission.
	var view: VltBattleView = _view(_battle())
	var before: int = view.theirs[0].health

	view.advance(VltLogEffectiveness.create(VltSlotRef.at(THEIRS, 0), 1), _registry())
	view.advance(VltLogPendingInput.create([]), _registry())

	assert_int(view.theirs[0].health).is_equal(before)
	assert_int(view.turn).is_equal(0)


# --- the two constructions must agree ----------------------------------------


## Plays a short battle by hand, mutating the state and logging each change the
## way the engine does. By hand rather than through the turn engine so the
## sequence covers switches, statuses and a faint in one pass — the engine would
## need several turns and a decider to reach the same shapes.
func _play(state: VltBattleState, registry: VltEffectRegistry) -> VltBattleLog:
	var log: VltBattleLog = VltBattleLog.new()
	var ours: VltSlotRef = VltSlotRef.at(OURS, 0)
	var theirs: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	state.turn = 3
	log.append(VltLogTurnStart.create(3))

	state.creature_at(ours).moves[0].pp = 9
	log.append(VltLogMoveUsed.create(ours, MOVE, 0, 9, theirs))

	var victim: VltBattleCreature = state.creature_at(theirs)
	victim.current_hp -= 60
	log.append(VltLogDamage.create(theirs, 60, victim.current_hp, victim.max_hp()))

	state.slot_at(ours).set_stage(VltStats.Stat.ATK, -1)
	log.append(VltLogStatChange.create(ours, VltStats.Stat.ATK, -1, -1))

	VltEffectDispatch.apply(state, registry, VltBurn.ID, ours, theirs, log)

	victim.current_hp = 0
	log.append(VltLogFaint.create(theirs))
	state.slot_at(theirs).vacate()
	log.append(VltLogSwitchOut.create(theirs, 0))
	state.slot_at(theirs).occupy(1)
	log.append(
		VltLogSwitchIn.create(
			theirs,
			1,
			state.creature_at(theirs).species_id,
			state.creature_at(theirs).level,
			state.creature_at(theirs).current_hp,
			state.creature_at(theirs).max_hp()
		)
	)

	return log


func _describe(view: VltBattleView) -> String:
	var rows: Array[String] = []
	for row: Array[VltBattleView.Combatant] in [view.mine, view.theirs]:
		for seat: VltBattleView.Combatant in row:
			rows.append(
				"%s present=%s hp=%d health=%d fainted=%s status=%s stages=%s pp=%s"
				% [
					seat.species_id, seat.present, seat.current_hp, seat.health,
					seat.fainted, seat.status_id, seat.stat_stages,
					("-" if seat.moves.is_empty() else str(seat.moves[0].pp)),
				]
			)
	var benched: Array[String] = []
	for seat: VltBattleView.Combatant in view.bench:
		benched.append("%d:%s hp=%d" % [seat.party_index, seat.species_id, seat.current_hp])

	return "turn %d | %s | bench %s" % [view.turn, " || ".join(rows), " ".join(benched)]


func test_advancing_the_log_agrees_with_reading_the_state() -> void:
	# Invariant 8 restated about a view, and the reason decision 0049 costs
	# nothing in fidelity: the UI never touches the state, and still sees
	# exactly what the state says it may.
	var registry: VltEffectRegistry = _registry()
	var state: VltBattleState = _battle()

	var replayed: VltBattleView = VltBattleView.of(state, registry, OURS)
	var log: VltBattleLog = _play(state, registry)
	for event: VltLogEvent in log.for_viewer(OURS).events:
		replayed.advance(event, registry, {}, state.sides[OURS].party)

	var directly: VltBattleView = VltBattleView.of(state, registry, OURS)

	assert_str(_describe(replayed)).override_failure_message(
		"the log and the state disagree about what this side can see\n  replay: %s\n  direct: %s"
		% [_describe(replayed), _describe(directly)]
	).is_equal(_describe(directly))


func test_the_same_holds_from_the_other_seat() -> void:
	# The asymmetry is the point: one side reads exact figures and the other
	# reads a bar. A replay that agreed only for the owner would prove nothing
	# about the filtering.
	var registry: VltEffectRegistry = _registry()
	var state: VltBattleState = _battle()

	var replayed: VltBattleView = VltBattleView.of(state, registry, THEIRS)
	var log: VltBattleLog = _play(state, registry)

	# Filtered first, because that is what a reader is handed. Replaying the raw
	# log would hand this side exact figures it has no right to, and the test
	# would pass by cheating.
	for event: VltLogEvent in log.for_viewer(THEIRS).events:
		replayed.advance(event, registry, {}, state.sides[THEIRS].party)

	assert_str(_describe(replayed)).is_equal(
		_describe(VltBattleView.of(state, registry, THEIRS))
	)


# --- events the view should not trust ----------------------------------------
#
# A view is advanced by whatever arrives. A filtered log is built by the engine
# and can be trusted; a saved one, a replayed one, or one from a build that
# knew more cannot. Every guard here was a mutation survivor: the code was
# right and nothing said so.


func _advance(event: VltLogEvent) -> VltBattleView:
	var view: VltBattleView = _view(_battle())
	view.advance(event, _registry())
	return view


func test_a_stat_change_for_a_slot_that_does_not_exist_is_ignored() -> void:
	# Doubles events reaching a singles view. Without the null check this reads
	# a combatant off the end of the row.
	var view: VltBattleView = _advance(
		VltLogStatChange.create(VltSlotRef.at(THEIRS, 3), VltStats.Stat.ATK, 2, 2)
	)
	assert_int(view.theirs[0].stat_stages[VltStats.Stat.ATK]).is_equal(0)


func test_a_stat_index_past_the_stats_is_ignored() -> void:
	# One past the end is the index a stat enum grows into, and writing there
	# would corrupt whatever the array is next to.
	var view: VltBattleView = _advance(
		VltLogStatChange.create(VltSlotRef.at(THEIRS, 0), VltStats.STAT_COUNT, 2, 2)
	)
	assert_int(view.theirs[0].stat_stages.size()).is_equal(VltStats.STAT_COUNT)


func test_a_switch_naming_a_party_member_nobody_has_is_ignored() -> void:
	# The event says which party member arrived; a view built beside a shorter
	# party would read past its end.
	var state: VltBattleState = _battle()
	var view: VltBattleView = _view(state)

	# Exactly one past the last, not far past it: `<` and `<=` only disagree at
	# the boundary, so a wild index would pass either way and prove nothing.
	view.advance(
		VltLogSwitchIn.create(
			VltSlotRef.at(OURS, 0), state.sides[OURS].party.size(), "species_0_b", 5, 100, 100
		),
		_registry(),
		{},
		state.sides[OURS].party
	)

	assert_str(view.mine[0].species_id).is_equal("species_0_b")
	assert_bool(view.mine[0].moves.is_empty()).override_failure_message(
		"a party index nobody has produced moves from somewhere"
	).is_true()


func test_a_heal_to_nothing_does_not_bring_anyone_back() -> void:
	# Health of zero is not health. Reviving on a heal that healed nothing is
	# the kind of thing that reads as a flicker and is really a wrong rule.
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	view.advance(VltLogFaint.create(at), _registry())
	view.advance(VltLogHeal.create(at, 0, 0, 175), _registry())

	assert_bool(view.theirs[0].fainted).override_failure_message(
		"a heal of nothing stood a fainted creature back up"
	).is_true()


func test_an_effect_nobody_registered_is_ignored() -> void:
	# A save from a build with a mechanic this one has not got. Asking the
	# registry about it would abort rather than shrug.
	var state: VltBattleState = _battle()
	var view: VltBattleView = _view(state)
	var at: VltSlotRef = VltSlotRef.at(THEIRS, 0)

	view.advance(
		VltLogEffectChanged.removal("a_mechanic_from_later", VltEffectDefinition.Scope.CREATURE, at),
		_registry()
	)

	assert_str(view.theirs[0].status_id).is_empty()


func test_a_move_index_past_the_moveset_is_ignored() -> void:
	# Your own side reports PP by slot. An index nobody has would write past the
	# end of a creature's four.
	var view: VltBattleView = _view(_battle())
	var at: VltSlotRef = VltSlotRef.at(OURS, 0)

	# The first index the creature has not got, for the same reason.
	view.advance(
		VltLogMoveUsed.create(
			at, MOVE, view.mine[0].moves.size(), 3, VltSlotRef.at(THEIRS, 0)
		),
		_registry()
	)

	assert_int(view.mine[0].moves.size()).is_equal(1)
	assert_int(view.mine[0].moves[0].pp).override_failure_message(
		"an index nobody has spent somebody's PP"
	).is_equal(10)


func test_the_unknown_sentinel_is_not_a_value_health_can_take() -> void:
	# Named in spec 05's survivor list and left there. A sentinel of -1 is safe
	# and one of +1 collides with a real health proportion — and no test that
	# compares against the constant can tell the two apart, because it moves too.
	assert_int(VltBattleView.Combatant.UNKNOWN).override_failure_message(
		"the sentinel is inside the range it is supposed to be outside"
	).is_less(0)

	var seat: VltBattleView.Combatant = VltBattleView.Combatant.new()
	seat.current_hp = VltBattleView.Combatant.UNKNOWN
	assert_bool(seat.knows_exact_health()).is_false()

	seat.current_hp = 0
	assert_bool(seat.knows_exact_health()).override_failure_message(
		"a creature on nothing was reported as not knowing its own health"
	).is_true()
