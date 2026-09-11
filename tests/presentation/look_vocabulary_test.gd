extends GdUnitTestSuite

## The look's vocabulary says the same thing in four places (decision 0069).
##
## The shared look is declared once in `comic_look.gdshaderinc`, classified once in
## `Look`, spelled once per preset in `style_presets.json`, and offered once by the
## editor panel. Nothing in the language keeps those four in step — a uniform can
## be renamed in the shader and the three readers go on pushing a name that no
## longer exists, silently, because `set_shader_parameter` accepts anything.
##
## That is not hypothetical. It is what happened to `key_follows_camera` and to the
## six `stucco_*` values: they were dropped from the shader during the lit rework
## and two scripts went on setting them for four commits, one of them a feature the
## maintainer was actively refining. It is also what made the old panel push
## thirteen dead names on five looks out of six.
##
## So the invariant is checked rather than hoped for, and it is checked against the
## shader file itself, which is the only authority there is.

const INCLUDE: String = "res://game/presentation/creature/comic_look.gdshaderinc"

## `uniform <type> <name>`, before any hint, default or semicolon.
const DECLARATION: String = "(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)"


## Every uniform the shared look declares.
func _declared() -> PackedStringArray:
	var finder: RegEx = RegEx.new()
	@warning_ignore("return_value_discarded")
	finder.compile(DECLARATION)
	var names: PackedStringArray = PackedStringArray()
	for hit: RegExMatch in finder.search_all(FileAccess.get_file_as_string(INCLUDE)):
		@warning_ignore("return_value_discarded")
		names.append(hit.get_string(1))
	return names


func test_the_include_declares_uniforms_at_all() -> void:
	# The regex is the whole test's footing. If it stops matching — a reformat, a
	# rename of the file — every assertion below would pass against nothing.
	assert_int(_declared().size()).is_greater(40)


func test_every_uniform_is_classified_as_surface_or_vocabulary() -> void:
	var classified: Dictionary[String, bool] = {}
	for name: String in Look.SURFACE:
		classified[name] = true
	for name: String in Look.vocabulary():
		classified[name] = true

	var stray: PackedStringArray = PackedStringArray()
	for name: String in _declared():
		if not classified.has(name):
			@warning_ignore("return_value_discarded")
			stray.append(name)
	# A uniform added to the include has to be said to be either a description of
	# this surface or a value a look owns. Forgetting means `Look.wear` leaves it
	# behind when the look changes, which is how a saturation from one look ends up
	# on the next one.
	assert_array(stray).override_failure_message(
		"uniforms in the include that `Look` classifies as neither surface nor "
		+ "vocabulary: %s" % str(stray)).is_empty()


func test_nothing_is_classified_that_the_shader_does_not_declare() -> void:
	var declared: PackedStringArray = _declared()
	var ghosts: PackedStringArray = PackedStringArray()
	for name: String in Look.SURFACE:
		if not declared.has(name):
			@warning_ignore("return_value_discarded")
			ghosts.append(name)
	for name: String in Look.vocabulary():
		if not declared.has(name):
			@warning_ignore("return_value_discarded")
			ghosts.append(name)
	assert_array(ghosts).override_failure_message(
		"`Look` names uniforms the include no longer declares: %s" % str(ghosts)
		).is_empty()


func test_a_name_is_never_both_a_surface_and_a_look_value() -> void:
	var both: PackedStringArray = PackedStringArray()
	for name: String in Look.vocabulary():
		if Look.SURFACE.has(name):
			@warning_ignore("return_value_discarded")
			both.append(name)
	assert_array(both).is_empty()


func test_every_preset_names_only_real_values() -> void:
	# A preset is the one place a look's numbers are written by hand, so a typo
	# here is the likeliest way a value goes nowhere. It used to be inert; now it
	# fails the suite.
	var stray: PackedStringArray = PackedStringArray()
	for key: Variant in CreatureView.presets():
		var name: String = str(key)
		if name.begins_with("_"):
			continue
		for value: String in CreatureView.preset_values(name):
			if not Look.vocabulary().has(value):
				@warning_ignore("return_value_discarded")
				stray.append("%s.%s" % [name, value])
	assert_array(stray).override_failure_message(
		"presets naming something that is not a look value: %s" % str(stray)
		).is_empty()


func test_every_preset_resolves_to_a_quantiser_the_shader_has() -> void:
	for key: Variant in CreatureView.presets():
		var name: String = str(key)
		if name.begins_with("_"):
			continue
		# `mode_of` clamps an unknown name to the first quantiser, so asking it
		# would answer 0 either way. The declared `shader` field is what is checked.
		@warning_ignore("unsafe_cast")
		var entry: Dictionary = CreatureView.presets()[key] as Dictionary
		var quantiser: String = str(entry.get("shader"))
		assert_bool(CreatureView.MODES.has(quantiser)).override_failure_message(
			"%s names a quantiser the shader does not have: %s"
			% [name, quantiser]).is_true()


func test_every_look_is_a_preset_so_every_look_can_be_saved() -> void:
	# The five that used to be shaders of their own could not be written to, which
	# meant the looks you could not keep were exactly the ones being tuned.
	for name: String in ["toon", "bd", "vinyl", "ramp", "typelit"]:
		assert_bool(CreatureView.presets().has(name)).override_failure_message(
			"%s is not a preset, so Keep cannot write to it" % name).is_true()


func test_a_control_with_a_slider_declares_both_ends() -> void:
	for entry: Dictionary in Look.CONTROLS:
		if not entry.has("low"):
			continue
		assert_bool(entry.has("high")).override_failure_message(
			"%s has a low but no high" % str(entry["name"])).is_true()
		var span: Vector2 = Look.control_range(entry)
		assert_float(span.y).override_failure_message(
			"%s has an empty range" % str(entry["name"])).is_greater(span.x)


func test_a_control_local_to_one_quantiser_names_a_real_one() -> void:
	for entry: Dictionary in Look.CONTROLS:
		if not entry.has("looks"):
			continue
		@warning_ignore("unsafe_cast")
		for named: Variant in entry["looks"] as Array:
			var quantiser: String = str(named)
			assert_bool(CreatureView.MODES.has(quantiser)).override_failure_message(
				"%s is local to a quantiser that does not exist: %s"
				% [str(entry["name"]), quantiser]).is_true()


func test_the_panel_offers_every_shared_control_to_every_quantiser() -> void:
	# The complaint this whole rework answers ran the other way — the panel offered
	# `comic`'s settings to looks that could not read them. The fix was to make one
	# pipeline rather than to hide rows, so what has to hold now is that a control
	# with no `looks` really does reach all five.
	var shared: int = 0
	for entry: Dictionary in Look.CONTROLS:
		if not entry.has("looks"):
			shared += 1
	for quantiser: String in CreatureView.MODES:
		var offered: int = 0
		for entry: Dictionary in Look.controls_for(quantiser):
			if not entry.has("looks"):
				offered += 1
		assert_int(offered).override_failure_message(
			"%s is offered %d of the %d shared controls" % [quantiser, offered, shared]
			).is_equal(shared)


func test_a_quantiser_is_offered_its_own_controls_and_no_others() -> void:
	for quantiser: String in CreatureView.MODES:
		var offered: PackedStringArray = PackedStringArray()
		for entry: Dictionary in Look.controls_for(quantiser):
			@warning_ignore("return_value_discarded")
			offered.append(str(entry["name"]))
		for entry: Dictionary in Look.CONTROLS:
			if not entry.has("looks"):
				continue
			var name: String = str(entry["name"])
			@warning_ignore("unsafe_cast")
			var mine: bool = (entry["looks"] as Array).has(quantiser)
			assert_bool(offered.has(name)).override_failure_message(
				"%s %s %s" % [quantiser,
					"should be offered" if mine else "should not be offered", name]
				).is_equal(mine)
