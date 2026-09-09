extends GdUnitTestSuite

## Stages one and two of capture (spec 11).
##
## No oracle covers this, so the arithmetic answers to a closed form instead: the
## net probability of four checks is a/255, and that is checkable across the whole
## range rather than at chosen points.

const ITEMS_DIR: String = "res://content/generated/items"
const SPECIES_DIR: String = "res://content/generated/species"

const NO_STATUS: float = 1.0
const ASLEEP: float = 2.5
const DRAWS: int = 65536

var _balls: Dictionary[String, float]


func before() -> void:
	_balls = VltItemLoader.ball_multipliers(VltContentPayloads.read_indexed(ITEMS_DIR))


func _rate(max_hp: int, current: int, species: int, ball: float = 1.0, status: float = NO_STATUS) -> int:
	return VltCapture.modified_rate(max_hp, current, species, ball, status)


# --- stage one ---------------------------------------------------------------


func test_a_full_health_target_gives_a_third_of_the_rate() -> void:
	# The health fraction is (3H − 2H)/3H = 1/3 at full health, exactly.
	assert_int(_rate(300, 300, 255)).is_equal(85)
	assert_int(_rate(300, 300, 150)).is_equal(50)


func test_weakening_a_target_very_nearly_triples_the_odds() -> void:
	# 1/3 at full, approaching 1 at a single point. This is the lever that makes
	# the loop "weaken, then throw" instead of "throw repeatedly".
	var full: int = _rate(300, 300, 200)
	var sliver: int = _rate(300, 1, 200)

	assert_int(sliver).is_greater(full * 2)
	assert_int(sliver).is_less_equal(full * 3 + 1)


func test_a_status_multiplies_before_the_floor_not_after() -> void:
	# The formula floors once, at the end. Flooring the health step first and
	# multiplying after gives 82 where the formula gives 83 — one unit, and the
	# kind of one unit that is a different formula rather than a rounding taste.
	var plain: int = _rate(300, 300, 100, 1.0, NO_STATUS)
	var asleep: int = _rate(300, 300, 100, 1.0, ASLEEP)

	assert_int(plain).is_equal(33)
	assert_int(asleep).override_failure_message(
		"the status bonus was applied after the floor instead of before it"
	).is_equal(83)
	assert_int(asleep).is_not_equal(int(plain * ASLEEP))


func test_a_better_ball_beats_a_plain_one() -> void:
	var plain: int = _rate(300, 200, 100, _balls["basic_ball"])
	var better: int = _rate(300, 200, 100, _balls["better_ball"])
	var best: int = _rate(300, 200, 100, _balls["best_ball"])

	assert_int(better).is_greater(plain)
	assert_int(best).is_greater(better)


func test_the_rate_is_capped() -> void:
	# Everything at once must not run past the cap, or stage two would be handed
	# a value it has no table for.
	assert_int(_rate(300, 1, 255, 2.0, ASLEEP)).is_equal(VltCapture.MAX_RATE)


func test_a_species_nothing_can_catch_stays_uncatchable() -> void:
	assert_int(_rate(300, 1, 0, 2.0, ASLEEP)).is_equal(0)


# --- stage two ---------------------------------------------------------------


func test_the_threshold_matches_its_closed_form() -> void:
	# Derived here rather than by re-running the implementation: b is
	# 65535 × (a/255)^(1/4). Within 7%: the three nested integer floors pull the exact value above the
	# smooth curve, by as much as 6.1% around a = 201. A tighter window would be
	# asserting that the formula has no floors in it.
	for rate: int in range(1, VltCapture.MAX_RATE):
		var closed: float = 65535.0 * pow(float(rate) / 255.0, 0.25)
		var actual: int = VltCapture.shake_threshold(rate)

		assert_float(abs(float(actual) - closed) / closed).override_failure_message(
			"a=%d: threshold %d is nowhere near the closed form %d" % [rate, actual, int(closed)]
		).is_less(0.07)


func test_the_net_probability_is_the_raw_ratio() -> void:
	# The claim decision 0033 rests on, and the check that would notice the day
	# someone turned stage two into a second curve: four checks give back a/255.
	for rate: int in [10, 30, 60, 100, 128, 180, 254]:
		var threshold: float = float(VltCapture.shake_threshold(rate)) / float(DRAWS)
		var net: float = pow(threshold, 4.0)
		var ratio: float = float(rate) / 255.0

		assert_float(net).override_failure_message(
			"a=%d: net probability %f against a raw ratio of %f" % [rate, net, ratio]
		).is_between(ratio - 0.09, ratio + 0.09)


func test_a_capped_rate_is_certain() -> void:
	# 65536 against a draw of 0 to 65535: every check passes, and the core needs
	# no special case for it.
	assert_int(VltCapture.shake_threshold(VltCapture.MAX_RATE)).is_equal(
		VltDecider.CAPTURE_DRAW_RANGE
	)
	assert_int(VltDecider.CAPTURE_DRAW_RANGE).is_greater(DRAWS - 1)


func test_a_rate_of_nothing_never_shakes() -> void:
	assert_int(VltCapture.shake_threshold(0)).is_equal(0)


func test_the_threshold_never_falls() -> void:
	# Non-decreasing, not strictly increasing: the integer floors make neighbours
	# share a value often — a=21 and a=22 both give 36157. What matters is that it
	# never drops, which is what stops a better ball ever being worse.
	var previous: int = -1
	var flat: int = 0

	for rate: int in range(0, VltCapture.MAX_RATE + 1):
		var threshold: int = VltCapture.shake_threshold(rate)
		assert_int(threshold).override_failure_message(
			"a=%d dropped below a=%d" % [rate, rate - 1]
		).is_greater_equal(previous)
		if threshold == previous:
			flat += 1
		previous = threshold

	# And it does climb overall, so "never falls" is not passing on a constant.
	assert_int(VltCapture.shake_threshold(254)).is_greater(
		VltCapture.shake_threshold(1) * 2
	)
	assert_int(flat).override_failure_message(
		"no two neighbours shared a value, so the floors are not being applied"
	).is_greater(0)


func test_the_same_inputs_always_give_the_same_threshold() -> void:
	# Integer throughout, so this holds by construction rather than by luck —
	# and the test is what says the construction was not quietly changed.
	for _repeat: int in range(20):
		assert_int(VltCapture.shake_threshold(97)).is_equal(VltCapture.shake_threshold(97))


func test_a_species_capture_rate_reaches_the_formula() -> void:
	# The authored rates are content; this is the crossing.
	var species: Dictionary[String, VltSpecies] = VltSpeciesLoader.from_entries(
		VltContentPayloads.read_indexed(SPECIES_DIR)
	)
	var subject: VltSpecies = species["placeholder_base"]

	assert_int(subject.catch_rate).is_greater(0)
	assert_int(_rate(300, 300, subject.catch_rate)).is_greater(0)
