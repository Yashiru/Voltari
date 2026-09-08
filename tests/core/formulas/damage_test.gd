extends GdUnitTestSuite

## Differential test: replays every oracle vector through the pipeline.
##
## Loading happens here, in the test, never in the core — the core performs no
## I/O and receives already-typed data (spec 03). This suite is that loader.
##
## Untyped JSON is confined to _decode below. Everything downstream of it is
## typed, which is why the unsafe-cast suppressions are scoped to that one
## function rather than to the file.

const FIXTURE: String = "res://tests/fixtures/oracle/procedure/damage/stages.json"
const FIRST_ROLL: int = 85


func _read_vectors() -> Array:
	var file: FileAccess = FileAccess.open(FIXTURE, FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	return _vectors_of(parsed)


@warning_ignore_start("unsafe_cast")
func _vectors_of(parsed: Variant) -> Array:
	return (parsed as Dictionary)["vectors"] as Array


## The typing boundary: Variant in, fully typed VltDamageInput out.
func _decode(entry: Variant, roll: int) -> VltDamageInput:
	var source: Dictionary = (entry as Dictionary)["input"] as Dictionary
	var move: Dictionary = source["move"] as Dictionary
	var attacker: Dictionary = source["attacker"] as Dictionary
	var defender: Dictionary = source["defender"] as Dictionary
	var context: Dictionary = source["context"] as Dictionary
	var weather: Array = context["weather_modifier"] as Array
	var is_physical: bool = String(move["category"] as String) == "physical"

	var input: VltDamageInput = VltDamageInput.new()
	input.level = int(source["level"] as float)
	input.base_power = int(move["power"] as float)
	input.attack = int((attacker["attack"] if is_physical else attacker["special_attack"]) as float)
	input.defense = int((defender["defense"] if is_physical else defender["special_defense"]) as float)
	input.is_critical = context["critical"] as bool
	input.has_stab = context["stab"] as bool

	# The vector describes conditions, and the test contributes the ratios an
	# effect would. Deliberately not routed through the effect system: this suite
	# pins the pipeline on its own, so a defect here cannot be mistaken for one
	# in what feeds it. The effect suite covers the other direction.
	if is_physical and str(attacker["status"]) == "brn":
		input.modifiers.contribute(VltDamageStage.Stage.BURN, 1, 2)
	if not (context["screens"] as Array).is_empty():
		input.modifiers.contribute(VltDamageStage.Stage.MODIFIER_PHASE_1, 1, 2)
	if context["spread"] as bool:
		input.modifiers.contribute(VltDamageStage.Stage.SPREAD, 3, 4)
	input.modifiers.contribute(
		VltDamageStage.Stage.WEATHER, int(weather[0] as float), int(weather[1] as float)
	)
	input.damage_roll = roll
	input.type_effectiveness_exponent = int(context["type_effectiveness_exponent"] as float)
	return input


## Returns a typed array, so nothing downstream has to touch a Variant.
func _expected_rolls(entry: Variant) -> PackedInt32Array:
	var raw: Array = ((entry as Dictionary)["expected"] as Dictionary)["rolls"] as Array
	var rolls: PackedInt32Array = PackedInt32Array()
	for value: Variant in raw:
		rolls.append(int(value as float))
	return rolls


func _id_of(entry: Variant) -> String:
	return (entry as Dictionary)["id"] as String
@warning_ignore_restore("unsafe_cast")


func test_every_oracle_vector_is_reproduced() -> void:
	var vectors: Array = _read_vectors()
	assert_int(vectors.size()).is_greater(0)

	for entry: Variant in vectors:
		var expected: PackedInt32Array = _expected_rolls(entry)
		var id: String = _id_of(entry)

		for index: int in range(expected.size()):
			var roll: int = FIRST_ROLL + index
			var want: int = expected[index]
			var got: int = VltDamage.compute(_decode(entry, roll))
			assert_int(got).override_failure_message(
				"%s at roll %d: expected %d, got %d" % [id, roll, want, got]
			).is_equal(want)


func test_damage_never_falls_below_one() -> void:
	var input: VltDamageInput = VltDamageInput.new()
	input.level = 1
	input.base_power = 1
	input.attack = 1
	input.defense = 999
	input.damage_roll = FIRST_ROLL
	input.type_effectiveness_exponent = -6

	assert_int(VltDamage.compute(input)).is_equal(1)


func test_the_modifier_rounds_at_4096() -> void:
	# Pins the oracle's modifier arithmetic itself, independently of any vector.
	assert_int(VltDamage.modify(100, 1, 2)).is_equal(50)
	assert_int(VltDamage.modify(100, 3, 2)).is_equal(150)
	assert_int(VltDamage.modify(100, 3, 4)).is_equal(75)


func test_the_modifier_rounds_halves_down() -> void:
	# The distinguishing case: 1.5 becomes 1, not 2. That is what the `+ 2048 - 1`
	# term buys — round to nearest, halves downward. Getting it backwards shifts
	# damage by one point on a large share of hits, which no coarse test notices.
	assert_int(VltDamage.modify(3, 1, 2)).is_equal(1)
	assert_int(VltDamage.modify(5, 1, 2)).is_equal(2)
	assert_int(VltDamage.modify(7, 1, 2)).is_equal(3)
