extends GdUnitTestSuite

## Pins the damage pipeline order against the sequence extracted from the oracle.
## A reorder here is a fidelity defect, so it must fail a test rather than pass
## review unnoticed.


func test_pipeline_order_matches_the_extracted_oracle_sequence() -> void:
	var sequence: Array[int] = [
		VltDamageStage.Stage.BURN,
		VltDamageStage.Stage.MODIFIER_PHASE_1,
		VltDamageStage.Stage.SPREAD,
		VltDamageStage.Stage.WEATHER,
		VltDamageStage.Stage.PLUS_TWO,
		VltDamageStage.Stage.CRITICAL,
		VltDamageStage.Stage.MODIFIER_PHASE_2,
		VltDamageStage.Stage.RANDOM_ROLL,
		VltDamageStage.Stage.STAB,
		VltDamageStage.Stage.TYPE_EFFECTIVENESS,
		VltDamageStage.Stage.FINAL_MODIFIER,
		VltDamageStage.Stage.FLOOR_MINIMUM,
	]

	for i: int in range(sequence.size() - 1):
		assert_int(sequence[i]).is_less(sequence[i + 1])


func test_the_pipeline_has_exactly_the_extracted_stages() -> void:
	assert_int(VltDamageStage.Stage.size()).is_equal(12)


func test_the_constant_addition_sits_after_weather_and_before_critical() -> void:
	# Singled out because it is the stage anyone reconstructing the formula from
	# memory places in the base damage instead. Decision 0018 exists for it.
	assert_int(VltDamageStage.Stage.PLUS_TWO).is_greater(VltDamageStage.Stage.WEATHER)
	assert_int(VltDamageStage.Stage.PLUS_TWO).is_less(VltDamageStage.Stage.CRITICAL)
