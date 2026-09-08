extends GdUnitTestSuite

## Differential test: every stat derivation vector, under all three nature cases.

const VECTORS: String = "res://tests/fixtures/oracle/procedure/stats/derivation.json"

const STAT_BY_NAME: Dictionary[String, int] = {
	"hp": VltStats.Stat.HP,
	"atk": VltStats.Stat.ATK,
	"def": VltStats.Stat.DEF,
	"spa": VltStats.Stat.SPA,
	"spd": VltStats.Stat.SPD,
	"spe": VltStats.Stat.SPE,
}


@warning_ignore_start("unsafe_cast")
func _read_vectors() -> Array:
	var file: FileAccess = FileAccess.open(VECTORS, FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	return (parsed as Dictionary)["vectors"] as Array


func _field(entry: Variant, key: String) -> int:
	return int((entry as Dictionary)[key] as float)


func _stat_of(entry: Variant) -> int:
	return STAT_BY_NAME[(entry as Dictionary)["stat"] as String]
@warning_ignore_restore("unsafe_cast")


func test_every_stat_vector_is_reproduced() -> void:
	var vectors: Array = _read_vectors()
	assert_int(vectors.size()).is_greater(0)

	for entry: Variant in vectors:
		var stat: int = _stat_of(entry)
		var base: int = _field(entry, "base")
		var iv: int = _field(entry, "iv")
		var ev: int = _field(entry, "ev")
		var level: int = _field(entry, "level")
		var label: String = "stat=%d base=%d iv=%d ev=%d level=%d" % [stat, base, iv, ev, level]

		var neutral: int = VltStats.derive(stat, base, iv, ev, level, VltStats.NO_STAT, VltStats.NO_STAT)
		assert_int(neutral).override_failure_message("neutral %s" % label).is_equal(
			_field(entry, "neutral")
		)

		var raised: int = VltStats.derive(stat, base, iv, ev, level, stat, VltStats.NO_STAT)
		assert_int(raised).override_failure_message("raised %s" % label).is_equal(
			_field(entry, "raised")
		)

		var lowered: int = VltStats.derive(stat, base, iv, ev, level, VltStats.NO_STAT, stat)
		assert_int(lowered).override_failure_message("lowered %s" % label).is_equal(
			_field(entry, "lowered")
		)


func test_hp_ignores_natures() -> void:
	# HP takes no nature modifier at all, which is easy to implement by accident
	# and invisible until someone wonders why a nature does nothing.
	var plain: int = VltStats.derive(VltStats.Stat.HP, 100, 31, 252, 100, VltStats.NO_STAT, VltStats.NO_STAT)
	var raised: int = VltStats.derive(VltStats.Stat.HP, 100, 31, 252, 100, VltStats.Stat.HP, VltStats.NO_STAT)
	assert_int(raised).is_equal(plain)


func test_a_nature_raising_and_lowering_the_same_stat_is_neutral() -> void:
	var neutral: int = VltStats.derive(VltStats.Stat.ATK, 100, 31, 0, 50, VltStats.NO_STAT, VltStats.NO_STAT)
	var both: int = VltStats.derive(VltStats.Stat.ATK, 100, 31, 0, 50, VltStats.Stat.ATK, VltStats.Stat.ATK)
	assert_int(both).is_equal(neutral)


func test_the_spread_derives_every_stat() -> void:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 100, 100, 100, 100, 100])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var spread: PackedInt32Array = VltStats.derive_spread(input)
	assert_int(spread.size()).is_equal(VltStats.STAT_COUNT)

	assert_int(spread[VltStats.Stat.ATK]).is_greater(spread[VltStats.Stat.DEF])
	assert_int(spread[VltStats.Stat.SPA]).is_less(spread[VltStats.Stat.DEF])
	assert_int(spread[VltStats.Stat.DEF]).is_equal(spread[VltStats.Stat.SPD])
