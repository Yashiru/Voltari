extends GdUnitTestSuite

## The placeholder clip bridge (spec 16, section 4).
##
## Every case here is a shape the library actually contains, and each exists
## because getting it wrong is a real failure rather than a hypothetical one.
## The rule the whole suite defends: **nothing is dropped**.

const FIXTURE: String = "res://tests/fixtures/models/clip_shapes.glb"


func _names(of: Array[String]) -> PackedStringArray:
	return PackedStringArray(of)


func _map(of: Array[String]) -> ClipMap.Mapping:
	return ClipMap.of(_names(of))


# --- the code decides the context --------------------------------------------


func test_a_code_maps_its_slot() -> void:
	var mapping: ClipMap.Mapping = _map(["ba20_buturi01"])
	assert_array(mapping.takes["attack_physical"]).is_equal(["ba20_buturi01"])


func test_the_same_word_under_three_codes_is_three_slots() -> void:
	# `wait` is the battle idle, the field idle and the companion idle. Nothing
	# but the code separates them, which is why the code is read first.
	var mapping: ClipMap.Mapping = _map(["ba10_waitA01", "fi01_wait01", "kw01_wait01"])

	assert_array(mapping.takes["idle"]).is_equal(["ba10_waitA01"])
	assert_array(mapping.takes["field_idle"]).is_equal(["fi01_wait01"])
	assert_array(mapping.takes["companion_idle"]).is_equal(["kw01_wait01"])


func test_a_known_code_with_an_unknown_word_is_an_extra() -> void:
	# `ba10_adjustear` is an ear flourish, not a second idle. Absorbing it into
	# the slot its code names would make a creature twitch at rest.
	var mapping: ClipMap.Mapping = _map(["ba10_waitA01", "ba10_adjustear"])

	assert_array(mapping.takes["idle"]).is_equal(["ba10_waitA01"])
	assert_array(mapping.extras).is_equal(["ba10_adjustear"])


# --- takes -------------------------------------------------------------------


func test_a_slot_keeps_every_take() -> void:
	# Three landings map to three. A slot that held one clip would throw away
	# two thirds of what the library carries.
	var mapping: ClipMap.Mapping = _map(["ba01_landA01", "ba01_landB01", "ba01_landC01"])
	assert_int(mapping.takes["enter"].size()).is_equal(3)


func test_takes_keep_the_order_the_model_gave() -> void:
	var mapping: ClipMap.Mapping = _map(["ba10_waitB01", "ba10_waitA01"])
	assert_array(mapping.takes["idle"]).is_equal(["ba10_waitB01", "ba10_waitA01"])


# --- noise -------------------------------------------------------------------


func test_a_duplicate_suffix_is_the_same_take_twice_not_two_slots() -> void:
	# glTF de-duplicates a repeated name with `_1`. Read literally it looks like
	# a second variant, and a creature would play the same clip twice as often.
	var mapping: ClipMap.Mapping = _map(["ba20_buturi01", "ba20_buturi01_1"])

	assert_int(mapping.takes["attack_physical"].size()).is_equal(2)
	assert_array(mapping.extras).override_failure_message(
		"a de-duplicated name was not recognised as its own clip"
	).is_empty()


func test_conversion_suffixes_are_stripped_before_matching() -> void:
	for noisy: String in [
		"ba21_tokusyu01_FBX_OVERRIDE",
		"ba21_tokusyu01_HAT_OVERRIDE",
		"ba21_tokusyu01_euler",
		"ba21_tokusyu01_RemovedScale",
	]:
		var mapping: ClipMap.Mapping = _map([noisy])
		assert_bool(mapping.takes.has("attack_special")).override_failure_message(
			"\"%s\" was not recognised" % noisy
		).is_true()


func test_two_suffixes_at_once_are_both_stripped() -> void:
	var mapping: ClipMap.Mapping = _map(["ba41_down01_euler_1"])
	assert_bool(mapping.takes.has("faint")).is_true()


# --- what is not an animation ------------------------------------------------


func test_a_stow_clip_never_reaches_a_slot() -> void:
	# It hides a part. Played as an animation it would be a creature freezing.
	var mapping: ClipMap.Mapping = _map(["HideLeftEar", "hide_right_ear", "HideHair"])

	assert_int(mapping.stow.size()).is_equal(3)
	assert_bool(mapping.takes.is_empty()).is_true()
	assert_bool(mapping.extras.is_empty()).is_true()


func test_an_effect_track_sits_beside_its_slot_not_inside_it() -> void:
	# It plays alongside. Inside the slot it would be picked as a take, and the
	# creature would sometimes attack with the effect and no attack.
	var mapping: ClipMap.Mapping = _map(["ba20_buturi01", "ba20_buturi01_FX"])

	assert_array(mapping.takes["attack_physical"]).is_equal(["ba20_buturi01"])
	assert_array(mapping.effects["attack_physical"]).is_equal(["ba20_buturi01_FX"])


func test_an_effect_track_alone_still_finds_its_slot() -> void:
	var mapping: ClipMap.Mapping = _map(["ba41_down01_FX"])
	assert_array(mapping.effects["faint"]).is_equal(["ba41_down01_FX"])
	assert_bool(mapping.takes.has("faint")).is_false()


# --- the older extraction ----------------------------------------------------


func test_a_bare_name_resolves_by_word() -> void:
	# About a fifth of the library carries no code at all — two generations of
	# extraction coexist. An exact-match list matched none of these, silently.
	var mapping: ClipMap.Mapping = _map(
		["waitA01", "buturi01", "tokusyu01", "damageS01", "down01", "land01"]
	)

	for slot: String in ["idle", "attack_physical", "attack_special", "hurt", "faint", "enter"]:
		assert_bool(mapping.takes.has(slot)).override_failure_message(
			"the bare form of \"%s\" was not recognised" % slot
		).is_true()


func test_a_bare_wait_is_the_battle_idle() -> void:
	# The one assumption in the map, and it is stated: the older extraction
	# carries battle clips only.
	assert_bool(_map(["waitB01"]).takes.has("idle")).is_true()


# --- nothing is dropped ------------------------------------------------------


func test_every_clip_is_accounted_for() -> void:
	# The property the whole design rests on. A clip that matched nothing used
	# to disappear without a word.
	var names: Array[String] = [
		"ba10_waitA01", "ba10_waitB01", "ba20_buturi01", "ba20_buturi01_1",
		"ba21_tokusyu01_FBX_OVERRIDE", "damageS01", "ba41_down01_FX",
		"kw32_happyA01", "ba10_adjustear", "HideLeftEar", "ba02_megaappeal01",
	]
	assert_int(_map(names).accounted()).is_equal(names.size())


func test_an_unrecognisable_name_becomes_an_extra_rather_than_nothing() -> void:
	var mapping: ClipMap.Mapping = _map(["something_nobody_planned"])
	assert_array(mapping.extras).is_equal(["something_nobody_planned"])


# --- against a real glTF -----------------------------------------------------


func test_the_map_holds_against_a_file_a_parser_actually_read() -> void:
	# Everything above is strings. This one goes through Godot's own glTF
	# importer, so the names are ones a real parser agreed were there.
	var packed: PackedScene = load(FIXTURE)
	var root: Node = auto_free(packed.instantiate())

	var player: AnimationPlayer = null
	for child: Node in root.get_children():
		if child is AnimationPlayer:
			player = child as AnimationPlayer

	assert_object(player).override_failure_message(
		"the fixture model carries no AnimationPlayer"
	).is_not_null()

	var clips: PackedStringArray = player.get_animation_list()
	var mapping: ClipMap.Mapping = ClipMap.of(clips)

	assert_int(mapping.accounted()).override_failure_message(
		"%d clips went in and %d came out" % [clips.size(), mapping.accounted()]
	).is_equal(clips.size())

	assert_array(mapping.takes["idle"]).contains(["ba10_waitA01", "ba10_waitB01"])
	assert_array(mapping.effects["faint"]).is_equal(["ba41_down01_FX"])
	assert_array(mapping.stow).is_equal(["HideLeftEar"])
	assert_array(mapping.extras).is_equal(["ba10_adjustear"])


# --- looping -----------------------------------------------------------------


func test_looping_follows_the_slot_not_a_substring() -> void:
	# The placeholder era decided this by looking for `wait` in the name, because
	# take names could not be trusted. The slot is the answer now.
	assert_bool(ClipMap.loops("idle")).is_true()
	assert_bool(ClipMap.loops("walk")).is_true()
	assert_bool(ClipMap.loops("faint")).is_false()
	assert_bool(ClipMap.loops("attack_physical")).is_false()


func test_every_slot_is_one_of_the_three_sets() -> void:
	# A slot added to a set and forgotten in the vocabulary would be unaskable.
	var every: Array[String] = ClipMap.all_slots()
	assert_int(every.size()).is_equal(
		ClipMap.BATTLE.size() + ClipMap.FIELD.size() + ClipMap.COMPANION.size()
	)
	for slot: String in ClipMap.LOOPING:
		assert_bool(every.has(slot)).override_failure_message(
			"\"%s\" loops but is in no set" % slot
		).is_true()
