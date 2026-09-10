extends GdUnitTestSuite

## Battle state: structure, scope discipline, and the two copy mechanisms.

const PARTY_SIZE: int = 6
const MOVES_PER_CREATURE: int = 4


func _creature(species: String, level: int) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 110, 90, 95, 85, 105])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([84, 84, 84, 0, 0, 0])
	input.level = level
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["water", "flying"])
	)
	for i: int in range(MOVES_PER_CREATURE):
		creature.moves.append(VltMoveSlot.create("move_%d" % i, 15))
	return creature


func _battle(slots_per_side: int = 2) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(slots_per_side)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for index: int in range(PARTY_SIZE):
			state.sides[side].party.append(_creature("species_%d_%d" % [side, index], 50))
		for slot: int in range(slots_per_side):
			state.sides[side].slots[slot].occupy(slot)
	state.turn = 3
	state.weather = "rain"
	state.weather_turns = 4
	return state


func _fingerprint(state: VltBattleState) -> String:
	return JSON.stringify(state.to_dict())


func test_the_field_is_two_sides_of_n_slots() -> void:
	var state: VltBattleState = _battle(2)
	assert_int(state.sides.size()).is_equal(2)
	assert_int(state.slots_per_side()).is_equal(2)
	assert_int(state.all_refs().size()).is_equal(4)


func test_a_reference_designates_a_position_not_a_creature() -> void:
	var state: VltBattleState = _battle(1)
	var reference: VltSlotRef = VltSlotRef.at(0, 0)

	var before: VltBattleCreature = state.creature_at(reference)
	state.slot_at(reference).occupy(3)
	var after: VltBattleCreature = state.creature_at(reference)

	assert_object(after).is_not_same(before)
	assert_str(after.species_id).is_equal("species_0_3")


func test_out_of_range_references_are_rejected() -> void:
	var state: VltBattleState = _battle(1)
	assert_bool(state.is_valid_ref(VltSlotRef.at(0, 0))).is_true()
	assert_bool(state.is_valid_ref(VltSlotRef.at(2, 0))).is_false()
	assert_bool(state.is_valid_ref(VltSlotRef.at(0, 1))).is_false()
	assert_bool(state.is_valid_ref(VltSlotRef.at(-1, 0))).is_false()
	assert_bool(state.is_valid_ref(null)).is_false()


func test_leaving_a_slot_clears_slot_scoped_state_but_not_creature_scoped() -> void:
	# The scope split earns its keep here: stat stages reset on switching
	# because they live on the slot, while status follows the creature out.
	var state: VltBattleState = _battle(1)
	var reference: VltSlotRef = VltSlotRef.at(0, 0)
	var slot: VltSlot = state.slot_at(reference)
	var creature: VltBattleCreature = state.creature_at(reference)
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())

	slot.set_stage(VltStats.Stat.ATK, 4)
	VltEffectDispatch.apply(state, registry, VltBurn.ID, reference, reference)

	slot.occupy(1)

	# The stages belong to the position and are cleared; the burn is
	# creature-scoped and leaves with the creature it is on.
	assert_int(slot.stat_stages[VltStats.Stat.ATK]).is_equal(0)
	assert_int(state.sides[0].party[0].effects.size()).is_equal(1)


func test_stat_stages_are_bounded() -> void:
	var slot: VltSlot = VltSlot.new()
	slot.set_stage(VltStats.Stat.ATK, 99)
	assert_int(slot.stat_stages[VltStats.Stat.ATK]).is_equal(VltSlot.STAGE_LIMIT)
	slot.set_stage(VltStats.Stat.ATK, -99)
	assert_int(slot.stat_stages[VltStats.Stat.ATK]).is_equal(-VltSlot.STAGE_LIMIT)


func test_cloning_is_deep() -> void:
	var state: VltBattleState = _battle()
	var copy: VltBattleState = state.clone()
	assert_str(_fingerprint(copy)).is_equal(_fingerprint(state))

	copy.sides[0].party[0].current_hp = 1
	copy.sides[0].slots[0].set_stage(VltStats.Stat.SPE, -2)
	copy.sides[1].party[2].moves[0].pp = 0
	copy.turn = 99

	assert_int(state.sides[0].party[0].current_hp).is_not_equal(1)
	assert_int(state.sides[0].slots[0].stat_stages[VltStats.Stat.SPE]).is_equal(0)
	assert_int(state.sides[1].party[2].moves[0].pp).is_equal(15)
	assert_int(state.turn).is_equal(3)


func test_serialisation_round_trips() -> void:
	# Invariant 9 of spec 05.
	var state: VltBattleState = _battle()
	var restored: VltBattleState = VltBattleState.from_dict(state.to_dict())
	assert_str(_fingerprint(restored)).is_equal(_fingerprint(state))


func test_the_two_copy_mechanisms_agree() -> void:
	# Decision 0011 left open whether clone() should be derived from a
	# serialise round trip. They must at least produce the same thing.
	var state: VltBattleState = _battle()
	var cloned: VltBattleState = state.clone()
	var round_tripped: VltBattleState = VltBattleState.from_dict(state.to_dict())
	assert_str(_fingerprint(cloned)).is_equal(_fingerprint(round_tripped))


func test_a_side_knows_whether_it_can_switch() -> void:
	var state: VltBattleState = _battle(1)
	var side: VltSide = state.sides[0]
	assert_bool(side.has_available_switch()).is_true()

	for index: int in range(1, PARTY_SIZE):
		side.party[index].current_hp = 0
	assert_bool(side.has_available_switch()).is_false()
