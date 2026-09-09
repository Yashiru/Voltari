extends GdUnitTestSuite

## The generation decision interface, and the rule that keeps it separate.


@warning_ignore_start("unsafe_cast")
func _script_methods(instance: Object) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var script: Script = instance.get_script() as Script
	for entry: Dictionary in script.get_script_method_list():
		var name: String = entry["name"]
		# Constructors and Godot's own hooks are not vocabulary.
		if not name.begins_with("_"):
			names.append(name)
	names.sort()
	return names
@warning_ignore_restore("unsafe_cast")


func test_the_two_vocabularies_are_disjoint() -> void:
	# Decision 0029: one pattern applied to two jobs, not two ways of doing one.
	# The rule that keeps that true is that no question is asked in both places,
	# and this is what would notice the day they started to converge.
	var battle: PackedStringArray = _script_methods(VltDecider.new())
	var generation: PackedStringArray = _script_methods(VltGenerationDecider.new())

	assert_int(battle.size()).is_greater(0)
	assert_int(generation.size()).is_greater(0)

	for question: String in generation:
		assert_bool(battle.has(question)).override_failure_message(
			"\"%s\" is asked by both deciders; one pattern, disjoint vocabularies" % question
		).is_false()


func test_a_scripted_decider_answers_what_it_was_told() -> void:
	var decider: VltScriptedGenerationDecider = VltScriptedGenerationDecider.new(19)
	decider.nature_index = 7

	for stat: int in range(VltStats.STAT_COUNT):
		assert_int(decider.individual_value(stat)).is_equal(19)
	assert_int(decider.nature_choice(25)).is_equal(7)


func test_a_nature_choice_stays_inside_the_table() -> void:
	# An index past the table would read off the end of it, far from here.
	var decider: VltScriptedGenerationDecider = VltScriptedGenerationDecider.new()
	decider.nature_index = 999
	assert_int(decider.nature_choice(25)).is_equal(24)

	decider.nature_index = -4
	assert_int(decider.nature_choice(25)).is_equal(0)


func test_individual_values_can_differ_per_stat() -> void:
	var decider: VltScriptedGenerationDecider = VltScriptedGenerationDecider.new()
	decider.individual_values[VltStats.Stat.SPE] = 0

	assert_int(decider.individual_value(VltStats.Stat.SPE)).is_equal(0)
	assert_int(decider.individual_value(VltStats.Stat.HP)).is_equal(
		VltGenerationDecider.MAX_INDIVIDUAL_VALUE
	)
