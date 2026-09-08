extends GdUnitTestSuite

## Differential test: every single and dual matchup against the oracle.
##
## Exhaustive rather than sampled, because the chart is data and a single wrong
## cell is invisible to inspection but decides battles.

const PAYLOAD: String = "res://content/generated/type-chart.json"
const VECTORS: String = "res://tests/fixtures/oracle/procedure/type-chart/pairs.json"

var _chart: VltTypeChart


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(_read_json(PAYLOAD))


@warning_ignore_start("unsafe_cast")
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file).override_failure_message("missing %s — run `npm run content:build`" % path).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	return parsed as Dictionary


func _rows(source: Dictionary, key: String) -> Array:
	return source[key] as Array


func _cell(row: Variant, index: int) -> Variant:
	return (row as Array)[index]


## JSON numbers arrive as floats; this is the one place that narrows them.
func _int_of(value: Variant) -> int:
	return int(value as float)
@warning_ignore_restore("unsafe_cast")


func _types(values: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		result.append(str(value))
	return result


func test_every_single_type_matchup_matches_the_oracle() -> void:
	var vectors: Dictionary = _read_json(VECTORS)
	var rows: Array = _rows(vectors, "single")
	assert_int(rows.size()).is_equal(289)

	for row: Variant in rows:
		var attacking: String = str(_cell(row, 0))
		var defending: PackedStringArray = _types([_cell(row, 1)])
		var expected: Variant = _cell(row, 2)

		if expected == null:
			assert_bool(_chart.is_immune(attacking, defending)).override_failure_message(
				"%s vs %s should be immune" % [attacking, defending[0]]
			).is_true()
			continue

		assert_bool(_chart.is_immune(attacking, defending)).override_failure_message(
			"%s vs %s should not be immune" % [attacking, defending[0]]
		).is_false()
		assert_int(_chart.exponent(attacking, defending)).override_failure_message(
			"%s vs %s" % [attacking, defending[0]]
		).is_equal(_int_of(expected))


func test_every_dual_type_matchup_matches_the_oracle() -> void:
	var vectors: Dictionary = _read_json(VECTORS)
	var rows: Array = _rows(vectors, "dual")
	assert_int(rows.size()).is_equal(2312)

	for row: Variant in rows:
		var attacking: String = str(_cell(row, 0))
		var defending: PackedStringArray = _types([_cell(row, 1), _cell(row, 2)])
		var expected: Variant = _cell(row, 3)
		var label: String = "%s vs %s/%s" % [attacking, defending[0], defending[1]]

		if expected == null:
			assert_bool(_chart.is_immune(attacking, defending)).override_failure_message(
				"%s should be immune" % label
			).is_true()
			continue

		assert_bool(_chart.is_immune(attacking, defending)).override_failure_message(
			"%s should not be immune" % label
		).is_false()
		assert_int(_chart.exponent(attacking, defending)).override_failure_message(
			label
		).is_equal(_int_of(expected))


func test_the_chart_holds_exactly_the_gen_four_types() -> void:
	# Fairy re-entering would silently contradict decision 0003.
	assert_int(_chart.known_types().size()).is_equal(17)
	assert_bool(_chart.known_types().has("fairy")).is_false()


func test_immunity_wins_over_any_weakness() -> void:
	# Ground is doubly relevant here: Electric cannot touch it at all, so no
	# amount of weakness on the partner type can bring the damage back.
	assert_bool(_chart.is_immune("electric", _types(["ground", "water"]))).is_true()
	assert_bool(_chart.is_immune("electric", _types(["water"]))).is_false()
	assert_int(_chart.exponent("electric", _types(["water"]))).is_equal(1)
