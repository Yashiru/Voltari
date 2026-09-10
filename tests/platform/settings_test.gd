extends GdUnitTestSuite

## Settings in their own file (spec 18, section 6; decision 0052).
##
## The interesting tests are the refusals: a file that will not parse must start
## the game rather than stop it, and a value somebody edited by hand must not
## reach the game as it was typed.

const PATH: String = "user://voltari_settings_test.json"


func before_test() -> void:
	_remove()


func after_test() -> void:
	_remove()


func _remove() -> void:
	for suffix: String in ["", VltSaveStore.TEMPORARY_SUFFIX, VltSaveStore.BACKUP_SUFFIX]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- the round trip ----------------------------------------------------------


func test_settings_survive_the_disk() -> void:
	var chosen: VltSettings = VltSettings.new()
	chosen.language = "fr"
	chosen.text_speed = 1.5
	chosen.master_volume = 0.3

	assert_bool(chosen.save_to(PATH)).is_true()

	var read_back: VltSettings = VltSettings.load_from(PATH)
	assert_str(read_back.language).is_equal("fr")
	assert_float(read_back.text_speed).is_equal_approx(1.5, 0.001)
	assert_float(read_back.master_volume).is_equal_approx(0.3, 0.001)


func test_a_whole_number_survives_json() -> void:
	# JSON gives 1.0 back as an int, so a speed of exactly one would otherwise
	# read as the wrong type and take its default — which happens to be the same
	# number, and would hide the bug until somebody chose two.
	var chosen: VltSettings = VltSettings.new()
	chosen.text_speed = 2.0
	chosen.save_to(PATH)

	assert_float(VltSettings.load_from(PATH).text_speed).is_equal_approx(2.0, 0.001)


# --- what it does with a file it cannot use ----------------------------------


func test_no_file_at_all_gives_defaults() -> void:
	var settings: VltSettings = VltSettings.load_from(PATH)
	assert_str(settings.language).is_empty()
	assert_float(settings.text_speed).is_equal_approx(1.0, 0.001)


func test_a_file_that_will_not_parse_starts_the_game() -> void:
	# The asymmetry with a save, deliberately: a save that cannot be read is the
	# player's history and is worth interrupting them for. A volume slider is not.
	_write("{ this is not json")

	var settings: VltSettings = VltSettings.load_from(PATH)
	assert_float(settings.master_volume).is_equal_approx(1.0, 0.001)


func test_an_absent_field_takes_its_default() -> void:
	# The common change: a version adds a setting and an older file has none.
	_write('{"version": 1, "language": "fr"}')

	var settings: VltSettings = VltSettings.load_from(PATH)
	assert_str(settings.language).is_equal("fr")
	assert_float(settings.text_speed).is_equal_approx(1.0, 0.001)


func test_a_field_of_the_wrong_kind_takes_its_default() -> void:
	_write('{"language": 7, "master_volume": "loud"}')

	var settings: VltSettings = VltSettings.load_from(PATH)
	assert_str(settings.language).is_empty()
	assert_float(settings.master_volume).is_equal_approx(1.0, 0.001)


func test_an_edited_multiplier_is_clamped_rather_than_trusted() -> void:
	# Not a setting somebody chose; a file somebody edited. A negative volume is
	# a game with no sound and no way to work out why.
	_write('{"master_volume": -3.0, "text_speed": 9999.0}')

	var settings: VltSettings = VltSettings.load_from(PATH)
	assert_float(settings.master_volume).is_equal_approx(0.0, 0.001)
	assert_float(settings.text_speed).is_between(0.0, 4.0)


# --- the same discipline as a save -------------------------------------------


func test_an_interrupted_write_leaves_the_previous_settings_intact() -> void:
	# Two files, one mechanism. The failure to avoid is identical, so the
	# defence is too — and a settings file half-written by a crash is a game
	# that will not start.
	var chosen: VltSettings = VltSettings.new()
	chosen.language = "fr"
	chosen.save_to(PATH)

	var partial: FileAccess = FileAccess.open(PATH + VltSaveStore.TEMPORARY_SUFFIX, FileAccess.WRITE)
	partial.store_string("{ half a file")
	partial.close()

	assert_str(VltSettings.load_from(PATH).language).override_failure_message(
		"an interrupted write damaged the settings that were already there"
	).is_equal("fr")
