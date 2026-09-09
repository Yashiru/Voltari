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


func test_the_vocabularies_are_disjoint() -> void:
	# Decision 0029: one pattern applied to disjoint jobs, not several ways of
	# doing one. There are three now — battle, generation, policy — and the rule
	# is unchanged: no question appears in two of them.
	#
	# At two this was nearly self-evident. At three it is the thing that would
	# notice the day they started to converge, which is why it checks every pair
	# rather than the one that happened to be added last.
	var vocabularies: Dictionary[String, PackedStringArray] = {
		"battle": _script_methods(VltDecider.new()),
		"generation": _script_methods(VltGenerationDecider.new()),
		"policy": _script_methods(VltPolicyDecider.new()),
	}

	var names: Array[String] = ["battle", "generation", "policy"]
	for vocabulary: String in names:
		assert_int(vocabularies[vocabulary].size()).override_failure_message(
			"the %s decider declares no questions at all" % vocabulary
		).is_greater(0)

	for first: int in range(names.size()):
		for second: int in range(first + 1, names.size()):
			for question: String in vocabularies[names[second]]:
				assert_bool(vocabularies[names[first]].has(question)).override_failure_message(
					"\"%s\" is asked by both the %s and %s deciders"
					% [question, names[first], names[second]]
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
