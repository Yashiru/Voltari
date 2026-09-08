extends GdUnitTestSuite

## Pillar 2 of spec 05: the invariants, under generated battles.
##
## The seeds below are fixed so the suite is reproducible and its runtime
## bounded. A failure reports the seed, and the seed alone reproduces the whole
## battle — which is what makes a fuzz failure actionable instead of a curiosity.

const CASES: int = 120
const TURNS: int = 25
const FIRST_SEED: int = 1

const MOVES_DIR: String = "res://content/generated/moves"
const CHART_PAYLOAD: String = "res://content/generated/type-chart.json"

var _moves: Dictionary[String, VltMoveDefinition]
var _chart: VltTypeChart
var _effects: VltEffectRegistry


func before() -> void:
	_moves = VltMoveRegistryLoader.from_entries(VltContentPayloads.read_indexed(MOVES_DIR))
	_chart = VltTypeChartLoader.from_payload(_read_json(CHART_PAYLOAD))
	_effects = VltEffectRegistry.new()
	_effects.register(VltBurn.define())
	_effects.register(VltReflect.define())


@warning_ignore_start("unsafe_cast")
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary
@warning_ignore_restore("unsafe_cast")


func test_the_invariants_hold_across_generated_battles() -> void:
	var played: int = 0

	for offset: int in range(CASES):
		var seed_value: int = FIRST_SEED + offset
		var report: VltFuzzHarness.Report = VltFuzzHarness.run_case(
			seed_value, TURNS, _moves, _chart, _effects
		)
		played += report.turns_played

		if report.failed():
			# Shrink before reporting: a minimal case is the difference between
			# a bug you can fix and a battle you have to read.
			var minimal: int = VltFuzzHarness.shrink(
				seed_value, TURNS, _moves, _chart, _effects
			)
			fail(
				"seed %d: %d turn(s) attempted, %d resolved; reproduces in %d turn(s)\n  %s"
				% [seed_value, report.turns_attempted, report.turns_played, minimal, report.failure]
			)
			return

	# A fuzzer that never reaches a turn proves nothing, so the run itself is
	# checked for having done work.
	assert_int(played).override_failure_message(
		"the generator produced no playable turns"
	).is_greater(CASES)


func test_a_fixed_seed_replays_identically() -> void:
	# Invariant 6, at battle scale rather than per turn.
	var first: VltFuzzHarness.Report = VltFuzzHarness.run_case(4242, TURNS, _moves, _chart, _effects)
	var second: VltFuzzHarness.Report = VltFuzzHarness.run_case(4242, TURNS, _moves, _chart, _effects)

	assert_str(first.failure).is_equal(second.failure)
	assert_int(first.turns_played).is_equal(second.turns_played)


func test_the_shrinker_finds_a_smaller_case_than_it_was_given() -> void:
	# The shrinker is checked against a deliberately broken invariant, so its
	# usefulness is demonstrated rather than assumed. Without this, a shrinker
	# that always returned its input would look like it worked.
	var broken: int = VltFuzzHarness.shrink_probe(TURNS)
	assert_int(broken).is_less(TURNS)
	assert_int(broken).is_greater(0)
