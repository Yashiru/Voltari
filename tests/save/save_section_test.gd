extends GdUnitTestSuite

## Reading a stored field (spec 13, section 2).
##
## This is the boundary where a save edited by hand, or written by another
## build, meets typed code. Every section goes through these helpers precisely so
## that the day one of them was skipped is not the day a save could crash the
## game — which makes them worth testing directly rather than through a section
## that happens to use them.


func test_an_integer_survives_being_a_float() -> void:
	# JSON has no integers. Every counter, level and cell coordinate comes back
	# as a float, so this is the single most-exercised line in the save layer.
	assert_int(VltSaveSection.read_int({"steps": 42.0}, "steps")).is_equal(42)
	assert_int(VltSaveSection.read_int({"steps": 42}, "steps")).is_equal(42)


func test_a_float_is_truncated_rather_than_rounded() -> void:
	# Stated because both are defensible and the choice must not drift: 2.9 is
	# not a legitimate stored integer, so the question is only which wrong answer
	# is predictable.
	assert_int(VltSaveSection.read_int({"steps": 2.9}, "steps")).is_equal(2)


func test_an_absent_field_takes_its_fallback() -> void:
	assert_int(VltSaveSection.read_int({}, "steps")).is_equal(0)
	assert_int(VltSaveSection.read_int({}, "steps", 7)).is_equal(7)
	assert_str(VltSaveSection.read_string({}, "name")).is_equal("")
	assert_str(VltSaveSection.read_string({}, "name", "voltari")).is_equal("voltari")


func test_an_absent_boolean_is_false_unless_told_otherwise() -> void:
	# Found by mutation: nothing pinned the default. A helper quietly defaulting
	# to true would turn every unset flag in an older save into a set one.
	assert_bool(VltSaveSection.read_bool({}, "seen")).override_failure_message(
		"an absent boolean did not read as false"
	).is_false()
	assert_bool(VltSaveSection.read_bool({}, "seen", true)).is_true()


func test_a_boolean_reads_as_itself() -> void:
	assert_bool(VltSaveSection.read_bool({"seen": true}, "seen")).is_true()
	assert_bool(VltSaveSection.read_bool({"seen": false}, "seen", true)).override_failure_message(
		"a stored false was overridden by the fallback"
	).is_false()


func test_a_field_of_the_wrong_kind_takes_the_fallback() -> void:
	# A save somebody edited by hand. Reading it as the wrong type is what these
	# helpers exist to prevent, and it must not crash either.
	assert_int(VltSaveSection.read_int({"steps": "many"}, "steps", 3)).is_equal(3)
	assert_str(VltSaveSection.read_string({"name": 7}, "name", "fallback")).is_equal("fallback")
	assert_bool(VltSaveSection.read_bool({"seen": "yes"}, "seen")).is_false()


func test_a_nested_group_reads_as_a_dictionary_or_as_nothing() -> void:
	var group: Dictionary = VltSaveSection.read_dictionary({"flags": {"a": true}}, "flags")
	assert_bool(group.has("a")).is_true()

	assert_bool(VltSaveSection.read_dictionary({}, "flags").is_empty()).is_true()
	assert_bool(
		VltSaveSection.read_dictionary({"flags": "not a group"}, "flags").is_empty()
	).override_failure_message("a malformed group did not read as nothing").is_true()


func test_the_abstract_section_refuses_to_pretend() -> void:
	# Not the assert itself — that aborts — but the shape around it: a section
	# that forgot a method must not be constructible into something plausible.
	var section: VltSaveSection = VltSaveSection.new()
	assert_object(section).is_not_null()
