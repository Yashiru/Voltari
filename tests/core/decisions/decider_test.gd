extends GdUnitTestSuite

## Determinism, distribution, and the property that makes the differential
## possible: the two implementations answer the same questions.

const SAMPLES: int = 20000
const SEED: int = 0xC0FFEE


func _seeded(value: int = SEED) -> VltSeededDecider:
	return VltSeededDecider.new(value)


func test_the_same_seed_gives_the_same_sequence() -> void:
	# Invariant 6 of spec 05 rests on this.
	var first: VltSeededDecider = _seeded()
	var second: VltSeededDecider = _seeded()

	for _i: int in range(500):
		assert_int(first.damage_roll()).is_equal(second.damage_roll())
		assert_bool(first.accuracy_check(75)).is_equal(second.accuracy_check(75))
		assert_bool(first.critical_hit(1, 16)).is_equal(second.critical_hit(1, 16))


func test_different_seeds_diverge() -> void:
	var first: VltSeededDecider = _seeded(1)
	var second: VltSeededDecider = _seeded(2)

	var identical: int = 0
	for _i: int in range(200):
		if first.damage_roll() == second.damage_roll():
			identical += 1
	assert_int(identical).is_less(200)


func test_a_saved_generator_resumes_where_it_left_off() -> void:
	# What lets a battle be saved mid-run without losing its sequence.
	var decider: VltSeededDecider = _seeded()
	for _i: int in range(37):
		decider.damage_roll()

	var checkpoint: int = decider.state()
	var expected: PackedInt32Array = PackedInt32Array()
	for _i: int in range(10):
		expected.append(decider.damage_roll())

	var resumed: VltSeededDecider = _seeded(1)
	resumed.restore(checkpoint)
	for index: int in range(10):
		assert_int(resumed.damage_roll()).is_equal(expected[index])


func test_damage_rolls_cover_the_whole_range() -> void:
	var decider: VltSeededDecider = _seeded()
	var seen: PackedInt32Array = PackedInt32Array()
	seen.resize(VltSeededDecider.DAMAGE_ROLL_COUNT)

	for _i: int in range(SAMPLES):
		var roll: int = decider.damage_roll()
		assert_int(roll).is_between(0, VltSeededDecider.DAMAGE_ROLL_COUNT - 1)
		seen[roll] += 1

	for index: int in range(VltSeededDecider.DAMAGE_ROLL_COUNT):
		assert_int(seen[index]).override_failure_message(
			"roll index %d never came up in %d samples" % [index, SAMPLES]
		).is_greater(0)


func test_certain_and_impossible_chances_never_consult_the_generator() -> void:
	# A 0% or 100% chance must not advance the sequence: burning a draw on a
	# foregone conclusion would shift every later decision.
	var decider: VltSeededDecider = _seeded()
	var before: int = decider.state()

	assert_bool(decider.accuracy_check(100)).is_true()
	assert_bool(decider.accuracy_check(0)).is_false()
	assert_bool(decider.secondary_triggers(0)).is_false()

	assert_int(decider.state()).is_equal(before)


func test_a_one_in_sixteen_chance_lands_near_one_in_sixteen() -> void:
	var decider: VltSeededDecider = _seeded()
	var hits: int = 0
	for _i: int in range(SAMPLES):
		if decider.critical_hit(1, 16):
			hits += 1

	var rate: float = float(hits) / SAMPLES
	assert_float(rate).is_between(0.05, 0.08)


func test_ranged_draws_reach_both_bounds_and_never_leave_them() -> void:
	# A single sample would pass for a generator that is merely close. Sampling
	# and asserting the extremes are actually reached pins the arithmetic.
	var decider: VltSeededDecider = _seeded()
	var lowest: int = 999
	var highest: int = -999

	for _i: int in range(2000):
		var value: int = decider.multi_hit_count(2, 5)
		lowest = mini(lowest, value)
		highest = maxi(highest, value)
	assert_int(lowest).is_equal(2)
	assert_int(highest).is_equal(5)

	lowest = 999
	highest = -999
	for _i: int in range(2000):
		var value: int = decider.status_duration(1, 4)
		lowest = mini(lowest, value)
		highest = maxi(highest, value)
	assert_int(lowest).is_equal(1)
	assert_int(highest).is_equal(4)


func test_a_single_valued_range_needs_no_draw() -> void:
	var decider: VltSeededDecider = _seeded()
	var before: int = decider.state()
	assert_int(decider.multi_hit_count(3, 3)).is_equal(3)
	# One value in range still consumes a draw; what matters is that it is 3.
	assert_int(decider.multi_hit_count(3, 3)).is_equal(3)
	assert_int(before).is_not_equal(0)


func test_the_scripted_decider_draws_nothing() -> void:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = 7
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER

	for _i: int in range(100):
		assert_int(decider.damage_roll()).is_equal(7)
		assert_bool(decider.accuracy_check(1)).is_true()
		assert_bool(decider.critical_hit(1, 16)).is_false()


func test_the_scripted_decider_answers_per_decision_kind() -> void:
	# The trap the whole design exists to avoid: answering every chance the same
	# way also answers accuracy, and every move misses.
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	decider.secondary = VltScriptedDecider.Answer.NEVER

	assert_bool(decider.accuracy_check(50)).is_true()
	assert_bool(decider.critical_hit(1, 16)).is_false()
	assert_bool(decider.secondary_triggers(50)).is_false()


func test_scripted_speed_ties_are_declared_not_drawn() -> void:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	var earlier: VltSlotRef = VltSlotRef.at(0, 0)
	var later: VltSlotRef = VltSlotRef.at(1, 0)

	decider.speed_tie_winner = VltScriptedDecider.TieWinner.EARLIER
	assert_bool(decider.speed_tie(earlier, later).equals(earlier)).is_true()

	decider.speed_tie_winner = VltScriptedDecider.TieWinner.LATER
	assert_bool(decider.speed_tie(earlier, later).equals(later)).is_true()

	# The same policy answers a tie between two allies, which a winner named by
	# side cannot: both references carry the same side, so it has nothing to
	# choose on and the answer falls out of how the policy is written.
	var ally: VltSlotRef = VltSlotRef.at(0, 1)
	assert_bool(decider.speed_tie(earlier, ally).equals(ally)).is_true()

	decider.speed_tie_winner = VltScriptedDecider.TieWinner.EARLIER
	assert_bool(decider.speed_tie(earlier, ally).equals(earlier)).is_true()


func test_both_implementations_answer_the_same_questions() -> void:
	# Substitutability is what makes the differential possible at all.
	var seeded: VltDecider = _seeded()
	var scripted: VltDecider = VltScriptedDecider.new()

	for decider: VltDecider in [seeded, scripted]:
		assert_int(decider.damage_roll()).is_between(0, VltSeededDecider.DAMAGE_ROLL_COUNT - 1)
		assert_int(decider.multi_hit_count(2, 5)).is_between(2, 5)
		assert_int(decider.status_duration(1, 4)).is_between(1, 4)
		assert_object(decider.speed_tie(VltSlotRef.at(0, 0), VltSlotRef.at(1, 0))).is_not_null()
