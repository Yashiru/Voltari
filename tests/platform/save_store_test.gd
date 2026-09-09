extends GdUnitTestSuite

## The only part of saving that touches a file (spec 13, section 7).
##
## The failure a save system has to prevent is not losing the new data. It is
## destroying the old while writing the new, so most of this is about what
## survives an interruption.

const PATH: String = "user://voltari_save_store_test.json"


func before_test() -> void:
	_remove_all()


func after_test() -> void:
	_remove_all()


func _remove_all() -> void:
	for suffix: String in ["", VltSaveStore.TEMPORARY_SUFFIX, VltSaveStore.BACKUP_SUFFIX]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _document(marker: String) -> Dictionary:
	return {"format": 1, "sections": {"counter": {"version": 1, "data": {"name": marker}}}}


## JSON does not keep an integer an integer: everything numeric comes back as a
## float. Comparing serialised forms would fail on that alone, which says
## nothing about the file. So the tests read the value out, the way a section
## does — and it is exactly why VltSaveSection.read_int accepts a float.
@warning_ignore_start("unsafe_cast")
func _marker_in(document: Dictionary) -> String:
	if not document.has("sections"):
		return ""
	var sections: Dictionary = document["sections"] as Dictionary
	if not sections.has("counter"):
		return ""
	var wrapper: Dictionary = sections["counter"] as Dictionary
	return (wrapper["data"] as Dictionary)["name"] as String
@warning_ignore_restore("unsafe_cast")


func test_a_document_survives_the_disk() -> void:
	assert_bool(VltSaveStore.write(PATH, _document("first"))).is_true()
	assert_str(_marker_in(VltSaveStore.read(PATH))).is_equal("first")


func test_reading_what_is_not_there_is_not_an_error() -> void:
	# Whether an absent file means "no save yet" or "something is wrong" belongs
	# to the layer that knows what it asked for.
	assert_bool(VltSaveStore.read(PATH).is_empty()).is_true()
	assert_bool(VltSaveStore.exists(PATH)).is_false()


func test_a_corrupt_file_reads_as_nothing_rather_than_crashing() -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()

	assert_bool(VltSaveStore.read(PATH).is_empty()).is_true()
	assert_bool(VltSaveStore.exists(PATH)).override_failure_message(
		"reading a corrupt file removed it"
	).is_true()


func test_a_write_left_half_done_leaves_the_previous_save_intact() -> void:
	# The interruption that matters. A crash between writing and replacing leaves
	# a temporary file behind; the real save must be untouched.
	VltSaveStore.write(PATH, _document("original"))

	var partial: FileAccess = FileAccess.open(
		PATH + VltSaveStore.TEMPORARY_SUFFIX, FileAccess.WRITE
	)
	partial.store_string("{ half a save")
	partial.close()

	assert_str(_marker_in(VltSaveStore.read(PATH))).override_failure_message(
		"an interrupted write damaged the save that was already there"
	).is_equal("original")


func test_a_stale_temporary_file_can_be_cleared() -> void:
	var partial: FileAccess = FileAccess.open(
		PATH + VltSaveStore.TEMPORARY_SUFFIX, FileAccess.WRITE
	)
	partial.store_string("{ half a save")
	partial.close()

	VltSaveStore.clear_temporary(PATH)
	assert_bool(FileAccess.file_exists(PATH + VltSaveStore.TEMPORARY_SUFFIX)).is_false()


func test_a_write_leaves_no_temporary_behind() -> void:
	VltSaveStore.write(PATH, _document("clean"))
	assert_bool(FileAccess.file_exists(PATH + VltSaveStore.TEMPORARY_SUFFIX)).override_failure_message(
		"a completed write left its temporary file on disk"
	).is_false()


func test_a_backup_is_the_save_as_it_was() -> void:
	# Taken before the first write over a save that read incompletely: the
	# confirmation buys informed consent, this makes it recoverable.
	VltSaveStore.write(PATH, _document("before"))
	assert_bool(VltSaveStore.back_up(PATH)).is_true()

	VltSaveStore.write(PATH, _document("after"))

	assert_str(_marker_in(VltSaveStore.read(PATH))).is_equal("after")
	assert_str(
		_marker_in(VltSaveStore.read(PATH + VltSaveStore.BACKUP_SUFFIX))
	).override_failure_message(
		"the backup did not hold what the save had before it was overwritten"
	).is_equal("before")


func test_backing_up_nothing_reports_rather_than_pretends() -> void:
	assert_bool(VltSaveStore.back_up(PATH)).is_false()
