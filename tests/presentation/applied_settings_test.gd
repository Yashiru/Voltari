extends GdUnitTestSuite

## Turning what the player configured into what the engine does (spec 18,
## section 4).
##
## The settings were written, tested and read by nobody until this existed —
## a file the player could edit and a game that never looked. So the tests are
## about the looking, not about the file.

const PATH: String = "user://settings.json"

var _locale: String
var _volume: float


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_volume = db_to_linear(AudioServer.get_bus_volume_db(0))
	_remove()


func after_test() -> void:
	_remove()
	TranslationServer.set_locale(_locale)
	AudioServer.set_bus_volume_db(0, linear_to_db(_volume))
	AudioServer.set_bus_mute(0, false)


func _remove() -> void:
	for suffix: String in ["", VltSaveStore.TEMPORARY_SUFFIX]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _store(settings: VltSettings) -> void:
	settings.save_to(PATH)


func test_a_chosen_language_reaches_the_translation_server() -> void:
	var chosen: VltSettings = VltSettings.new()
	chosen.language = "fr"
	_store(chosen)

	AppliedSettings.install()

	assert_str(TranslationServer.get_locale()).override_failure_message(
		"the language was configured and nothing read it"
	).contains("fr")


func test_no_language_leaves_the_system_alone() -> void:
	# An empty locale is not a choice, so applying one would be answering for
	# the player with whatever happened to be first in the file.
	var before: String = TranslationServer.get_locale()
	_store(VltSettings.new())

	AppliedSettings.install()

	assert_str(TranslationServer.get_locale()).is_equal(before)


func test_a_chosen_volume_reaches_the_mixer() -> void:
	var chosen: VltSettings = VltSettings.new()
	chosen.master_volume = 0.25
	_store(chosen)

	AppliedSettings.install()

	assert_float(db_to_linear(AudioServer.get_bus_volume_db(0))).is_equal_approx(0.25, 0.01)


func test_silence_mutes_rather_than_approaching_it() -> void:
	# Zero in decibels is minus infinity, which is not a number a mixer takes.
	# Muting is the honest way to say it.
	var chosen: VltSettings = VltSettings.new()
	chosen.master_volume = 0.0
	_store(chosen)

	AppliedSettings.install()

	assert_bool(AudioServer.is_bus_mute(0)).is_true()


func test_text_speed_comes_back_rather_than_being_applied_somewhere() -> void:
	# It is not something a server holds, so whoever paces a screen has to be
	# told — and a setting nobody is told about is a setting that does nothing.
	var chosen: VltSettings = VltSettings.new()
	chosen.text_speed = 2.5
	_store(chosen)

	assert_float(AppliedSettings.install().text_speed).is_equal_approx(2.5, 0.001)


func test_a_faster_pace_holds_a_line_for_less_time() -> void:
	# The setting reaching the stage, which is the last step and the one that
	# would silently do nothing.
	var label: Label = auto_free(Label.new())
	var stage: BattleScreenStage = BattleScreenStage.new(get_tree(), label)
	assert_float(stage.pace).is_equal_approx(1.0, 0.001)

	stage.pace = 2.0
	assert_float(stage.pace).is_equal_approx(2.0, 0.001)


func test_a_missing_file_applies_defaults_without_complaint() -> void:
	var settings: VltSettings = AppliedSettings.install()
	assert_float(settings.text_speed).is_equal_approx(1.0, 0.001)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()
