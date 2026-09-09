extends GdUnitTestSuite

## The experience award (spec 10, section 4).
##
## This formula is ours, so there is no oracle and no published table to check
## against. What can be checked is its shape: the design claims it makes, and the
## arithmetic promises it has to keep.

const YIELD: int = 200


func _award(
	defeated: int, earner: int, sharers: int = 1, trainer: bool = false, base: int = YIELD
) -> int:
	return VltExperience.award(base, defeated, earner, sharers, trainer)


# --- the design claims -------------------------------------------------------


func test_beating_something_stronger_pays_more() -> void:
	# The whole point of the ratio. Defeat the same creature at the same level
	# with earners of different levels: the weaker earner is rewarded more.
	var underdog: int = _award(50, 20)
	var equal: int = _award(50, 50)
	var overlevelled: int = _award(50, 80)

	assert_int(underdog).is_greater(equal)
	assert_int(equal).is_greater(overlevelled)


func test_grinding_on_the_weak_collapses() -> void:
	# A level 80 creature farming level 5 targets should earn nearly nothing
	# relative to fighting its own level — the discouragement is the design.
	var fair: int = _award(80, 80)
	var farming: int = _award(5, 80)

	assert_int(farming * 20).override_failure_message(
		"farming far below your level is not discouraged enough to matter"
	).is_less(fair)


func test_a_trainer_is_worth_half_again() -> void:
	var wild: int = _award(50, 50, 1, false)
	var owned: int = _award(50, 50, 1, true)

	# Half again, give or take the single truncation at the end.
	assert_int(owned).is_between(int(wild * 1.5) - 1, int(wild * 1.5) + 1)


func test_sharing_divides_the_award() -> void:
	var alone: int = _award(50, 50, 1)
	var shared: int = _award(50, 50, 2)

	assert_int(shared).is_between(alone / 2 - 1, alone / 2 + 1)


func test_a_richer_species_pays_more() -> void:
	assert_int(_award(50, 50, 1, false, 250)).is_greater(_award(50, 50, 1, false, 60))


# --- the numbers themselves --------------------------------------------------


func test_the_award_matches_a_hand_derived_vector() -> void:
	# Every other test here is comparative, and an exponent that was wrong would
	# preserve every ordering while paying the wrong amount. These four were
	# computed from the formula outside this implementation, which is what spec
	# 10 section 9 asks for in the absence of an oracle.
	#
	#   b=200, L=50, Lp=50, s=1, wild  ->  share 2000, ratio 1        -> 2001
	#   b=200, L=25, Lp=25, s=1, wild  ->  share 1000, ratio 1        -> 1001
	#   b=200, L=100, Lp=10, s=1, wild ->  share 4000, ratio 4.0513   -> 16206
	#   b=200, L=5,  Lp=80, s=1, wild  ->  share  200, ratio 0.02034  ->     5
	assert_int(VltExperience.award(200, 50, 50, 1, false)).is_equal(2001)
	assert_int(VltExperience.award(200, 25, 25, 1, false)).is_equal(1001)
	assert_int(VltExperience.award(200, 100, 10, 1, false)).is_equal(16206)
	assert_int(VltExperience.award(200, 5, 80, 1, false)).is_equal(5)


func test_the_ratio_is_one_when_the_levels_match() -> void:
	# The clearest case to reason about: equal levels make numerator and
	# denominator identical, so the award is the share plus one and nothing else.
	# It pins the exponent without needing to evaluate it.
	for level: int in [1, 10, 50, 100]:
		var share: int = (200 * level) / 5
		assert_int(VltExperience.award(200, level, level, 1, false)).override_failure_message(
			"at equal levels the ratio must be exactly one"
		).is_equal(share + 1)


# --- the arithmetic promises -------------------------------------------------


func test_an_award_is_never_nothing() -> void:
	# The +1 lands before the truncation, so the worst case still pays. A zero
	# award would be a creature that fought and gained nothing at all.
	assert_int(_award(1, 100, 6, false, VltExperience.MIN_BASE_YIELD)).is_greater(0)
	assert_int(_award(1, 100, 1, false, VltExperience.MIN_BASE_YIELD)).is_greater(0)


func test_modifiers_compose_before_the_result_is_made_whole() -> void:
	# Two halves must give back the whole. Applied one after another to an
	# integer they would round twice and drift, which is the reasoning
	# VltDamageModifiers already follows for damage.
	var plain: int = VltExperience.award(YIELD, 50, 50, 1, false)
	var halved_twice: int = VltExperience.award(YIELD, 50, 50, 1, false, [0.5, 2.0])

	assert_int(halved_twice).is_equal(plain)


func test_a_modifier_scales_the_award() -> void:
	var plain: int = VltExperience.award(YIELD, 50, 50, 1, false)
	var boosted: int = VltExperience.award(YIELD, 50, 50, 1, false, [1.5])

	assert_int(boosted).is_between(int(plain * 1.5) - 1, int(plain * 1.5) + 1)


func test_the_same_inputs_always_give_the_same_award() -> void:
	# Determinism, which is why the exponent is written as x squared times its
	# root: IEEE-754 pins sqrt down and leaves pow free to differ.
	for _repeat: int in range(50):
		assert_int(_award(37, 23, 3, true)).is_equal(_award(37, 23, 3, true))


func test_the_award_climbs_with_the_defeated_level() -> void:
	# Monotone in L, which is the property that stops a level range paying less
	# than the one below it.
	var previous: int = 0
	for level: int in range(1, 101):
		var earned: int = _award(level, 50)
		assert_int(earned).override_failure_message(
			"level %d paid less than level %d" % [level, level - 1]
		).is_greater_equal(previous)
		previous = earned


func test_awards_stay_in_a_sane_range_across_the_whole_table() -> void:
	# The bounds exist so a stray digit is caught. This walks the extremes and
	# asserts nothing overflows or collapses on the way.
	for level: int in range(1, 101):
		for base: int in [VltExperience.MIN_BASE_YIELD, YIELD, VltExperience.MAX_BASE_YIELD]:
			var earned: int = VltExperience.award(base, level, 1, 1, true)
			assert_int(earned).is_greater(0)
			assert_int(earned).override_failure_message(
				"level %d at base %d paid %d, which is out of any sane range" % [level, base, earned]
			).is_less(10_000_000)
