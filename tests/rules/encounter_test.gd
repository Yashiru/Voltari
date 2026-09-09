extends GdUnitTestSuite

## Whether something appears, and what (spec 14, section 5).
##
## This is the half of the overworld that can be wrong quietly, so it is the
## half that gets real tests. A slot drawn 1.4 times too often is
## indistinguishable from luck in any single draw, which is why the weighting is
## checked exhaustively rather than sampled.

const SEED: int = 4242
const STEPS: int = 4000


func _table(rate: int = 32) -> VltEncounterTable:
	return (
		VltEncounterTable
		. create("meadow", rate)
		. holds("placeholder_base", 2, 4, 60)
		. holds("placeholder_evolved", 5, 5, 30)
	)


# --- the weighting -----------------------------------------------------------


func test_each_slot_owns_exactly_its_weight() -> void:
	# Exhaustive, not statistical: every point in the weight space is walked, so
	# this is the whole distribution rather than a sample of it. A sampled test
	# would need thousands of draws to notice a boundary off by one, and would
	# still only make it unlikely.
	var table: VltEncounterTable = _table()
	var owned: Dictionary[String, int] = {}

	for point: int in range(table.total_weight()):
		var slot: VltEncounterTable.Slot = VltEncounter.slot_at(table, point)
		owned[slot.species_id] = owned.get(slot.species_id, 0) + 1

	for slot: VltEncounterTable.Slot in table.slots:
		assert_int(owned.get(slot.species_id, 0)).override_failure_message(
			"\"%s\" owns %d points of the weight space, not its weight of %d"
			% [slot.species_id, owned.get(slot.species_id, 0), slot.weight]
		).is_equal(slot.weight)


func test_a_slot_with_no_weight_is_never_drawn() -> void:
	# The half-open interval is what makes this true without a special case: a
	# weight of zero owns [running, running), which contains nothing.
	var table: VltEncounterTable = (
		VltEncounterTable
		. create("meadow", 32)
		. holds("never_here", 2, 4, 0)
		. holds("placeholder_base", 2, 4, 10)
	)

	for point: int in range(table.total_weight()):
		assert_str(VltEncounter.slot_at(table, point).species_id).override_failure_message(
			"a slot with no weight was drawn"
		).is_equal("placeholder_base")


func test_the_boundary_between_two_slots_falls_where_the_weights_say() -> void:
	# Where an off-by-one would live, named rather than left to the exhaustive
	# test to catch anonymously.
	var table: VltEncounterTable = _table()

	assert_str(VltEncounter.slot_at(table, 59).species_id).is_equal("placeholder_base")
	assert_str(VltEncounter.slot_at(table, 60).species_id).override_failure_message(
		"the second slot does not begin where the first one ends"
	).is_equal("placeholder_evolved")


func test_a_seeded_draw_follows_the_weights() -> void:
	# The mapping is proven exactly above; this proves the draw feeding it is not
	# badly skewed. Two to one, so the tolerance can be wide and still mean
	# something.
	var table: VltEncounterTable = _table()
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
	var base: int = 0

	for step: int in range(STEPS):
		if VltEncounter.draw(table, decider).species_id == "placeholder_base":
			base += 1

	var share: float = float(base) / float(STEPS)
	assert_float(share).override_failure_message(
		"a slot weighted 60 of 90 was drawn %.1f%% of the time" % (share * 100.0)
	).is_between(0.60, 0.73)


# --- levels ------------------------------------------------------------------


func test_a_level_lands_inside_its_slot_range() -> void:
	var table: VltEncounterTable = _table()
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)

	for step: int in range(STEPS):
		var outcome: VltEncounter.Outcome = VltEncounter.draw(table, decider)
		if outcome.species_id == "placeholder_base":
			assert_int(outcome.level).is_between(2, 4)
		else:
			assert_int(outcome.level).is_equal(5)


func test_a_slot_spanning_one_level_gives_that_level() -> void:
	# The degenerate range, where an implementation that assumes a span greater
	# than one divides by zero or reads past the end.
	var table: VltEncounterTable = VltEncounterTable.create("cave", 32).holds(
		"placeholder_base", 7, 7, 1
	)
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)

	for step: int in range(50):
		assert_int(VltEncounter.draw(table, decider).level).is_equal(7)


func test_the_whole_range_is_reachable() -> void:
	# Both ends inclusive. An implementation that never produces the maximum
	# passes every other test in this file.
	var table: VltEncounterTable = VltEncounterTable.create("cave", 32).holds(
		"placeholder_base", 3, 6, 1
	)
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
	var seen: Dictionary[int, bool] = {}

	for step: int in range(STEPS):
		seen[VltEncounter.draw(table, decider).level] = true

	for level: int in range(3, 7):
		assert_bool(seen.has(level)).override_failure_message(
			"level %d was never drawn from a range of 3 to 6" % level
		).is_true()


# --- the rate ----------------------------------------------------------------


func test_a_higher_rate_never_gives_fewer_encounters() -> void:
	# Exact rather than statistical: the same seed gives the same draws, and a
	# rate only moves the threshold those draws are compared against. So the
	# counts are monotone step for step, not merely on average.
	#
	# Rates of 0 and 256 are excluded on purpose — they answer without drawing,
	# so they do not share the sequence. They are tested below instead.
	var rates: Array[int] = [1, 8, 64, 128, 255]
	var previous: int = -1

	for rate: int in rates:
		var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
		var table: VltEncounterTable = _table(rate)
		var hits: int = 0

		for step: int in range(STEPS):
			if VltEncounter.occurs(table, decider):
				hits += 1

		assert_int(hits).override_failure_message(
			"rate %d produced %d encounters, fewer than the rate below it" % [rate, hits]
		).is_greater_equal(previous)
		previous = hits


func test_a_rate_of_nothing_never_fires_and_a_full_rate_always_does() -> void:
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
	var quiet: VltEncounterTable = _table(0)
	var certain: VltEncounterTable = _table(VltEncounterDecider.RATE_DENOMINATOR)

	for step: int in range(200):
		assert_bool(VltEncounter.occurs(quiet, decider)).is_false()
		assert_bool(VltEncounter.occurs(certain, decider)).is_true()


func test_a_rate_produces_roughly_its_share() -> void:
	# 64 of 256 is a quarter. Wide bounds: this catches a denominator confused
	# with 100, not a bias of a few percent.
	var decider: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
	var table: VltEncounterTable = _table(64)
	var hits: int = 0

	for step: int in range(STEPS):
		if VltEncounter.occurs(table, decider):
			hits += 1

	assert_float(float(hits) / float(STEPS)).override_failure_message(
		"a rate of 64 in 256 fired %d times in %d steps" % [hits, STEPS]
	).is_between(0.21, 0.29)


# --- determinism -------------------------------------------------------------


func test_the_same_seed_gives_the_same_encounters() -> void:
	var table: VltEncounterTable = _table()
	var first: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)
	var second: VltSeededEncounterDecider = VltSeededEncounterDecider.new(SEED)

	for step: int in range(100):
		var one: VltEncounter.Outcome = VltEncounter.draw(table, first)
		var two: VltEncounter.Outcome = VltEncounter.draw(table, second)
		assert_str(one.species_id).is_equal(two.species_id)
		assert_int(one.level).is_equal(two.level)


func test_different_seeds_diverge() -> void:
	# Without this, a generator stuck on its seed would pass everything above.
	var table: VltEncounterTable = _table()
	var first: VltSeededEncounterDecider = VltSeededEncounterDecider.new(1)
	var second: VltSeededEncounterDecider = VltSeededEncounterDecider.new(2)
	var differed: bool = false

	for step: int in range(100):
		var one: VltEncounter.Outcome = VltEncounter.draw(table, first)
		var two: VltEncounter.Outcome = VltEncounter.draw(table, second)
		if one.species_id != two.species_id or one.level != two.level:
			differed = true

	assert_bool(differed).override_failure_message(
		"two seeds produced the same hundred encounters"
	).is_true()


# --- the scripted decider ----------------------------------------------------


func test_a_scripted_decider_answers_what_it_was_told() -> void:
	var decider: VltScriptedEncounterDecider = VltScriptedEncounterDecider.new(true, 70)
	decider.level_offset = 1

	var outcome: VltEncounter.Outcome = VltEncounter.draw(_table(), decider)
	assert_str(outcome.species_id).is_equal("placeholder_evolved")
	assert_int(outcome.level).is_equal(5)


func test_a_scripted_draw_stays_inside_the_weight_space() -> void:
	# A draw past the total would read off the end of the table, far from here —
	# the same guard the nature table and the policy options already have.
	var decider: VltScriptedEncounterDecider = VltScriptedEncounterDecider.new(true, 999)
	assert_str(VltEncounter.draw(_table(), decider).species_id).is_equal("placeholder_evolved")

	decider.slot_draw = -7
	assert_str(VltEncounter.draw(_table(), decider).species_id).is_equal("placeholder_base")


func test_a_level_offset_past_the_range_is_clamped() -> void:
	var decider: VltScriptedEncounterDecider = VltScriptedEncounterDecider.new(true, 0)
	decider.level_offset = 99
	assert_int(VltEncounter.draw(_table(), decider).level).is_equal(4)
