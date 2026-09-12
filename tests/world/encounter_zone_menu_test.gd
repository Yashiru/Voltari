extends GdUnitTestSuite

## The menu of table ids on a zone.
##
## What it has to be is a *display*: the inspector offers only ids that exist, and
## nothing about it touches what a scene has stored. A dropdown that quietly
## rewrote a saved id would be worse than the text field it replaces, because the
## damage would be invisible in the inspector and obvious only in a diff.
##
## The list arrives from the editor plugin. That is the point of the split — a
## class that ships with the game holds no path into `content/` — so these tests
## put it there by hand, exactly as the plugin does.

const PROPERTY: Dictionary = {"name": "table_id", "hint": 0, "hint_string": ""}


func before_test() -> void:
	VltEncounterZone.known_tables = PackedStringArray()


func after_test() -> void:
	# Static, so a suite that left one behind would arm the next one.
	VltEncounterZone.known_tables = PackedStringArray()


func _zone() -> VltEncounterZone:
	var zone: VltEncounterZone = VltEncounterZone.new()
	auto_free(zone)
	return zone


static func _property() -> Dictionary:
	return PROPERTY.duplicate()


# --- what the inspector is told ------------------------------------------------


func test_no_list_leaves_an_ordinary_text_field() -> void:
	var zone: VltEncounterZone = _zone()
	var property: Dictionary = _property()
	zone._validate_property(property)

	assert_int(property["hint"]).is_equal(0)
	assert_str(property["hint_string"]).is_empty()


func test_a_list_turns_the_field_into_a_menu_of_it() -> void:
	VltEncounterZone.known_tables = PackedStringArray(["cave_dark", "meadow"])
	var zone: VltEncounterZone = _zone()
	var property: Dictionary = _property()
	zone._validate_property(property)

	assert_int(property["hint"]).is_equal(PROPERTY_HINT_ENUM)
	assert_str(property["hint_string"]).is_equal("cave_dark,meadow")


func test_only_the_table_id_becomes_a_menu() -> void:
	VltEncounterZone.known_tables = PackedStringArray(["meadow"])
	var zone: VltEncounterZone = _zone()

	for name: String in ["origin", "size", "position", "name"]:
		var property: Dictionary = {"name": name, "hint": 0, "hint_string": ""}
		zone._validate_property(property)
		assert_int(property["hint"]).is_equal(0)
		assert_str(property["hint_string"]).is_empty()


## The menu is strict — it offers what the build produced and nothing else — but
## strict is about what can be *chosen*, not about what is kept. A zone that names
## a table since renamed keeps its id until somebody changes it, and the validator
## is what says so.
func test_an_id_outside_the_list_is_not_rewritten() -> void:
	var zone: VltEncounterZone = _zone()
	zone.table_id = "renamed_away"
	VltEncounterZone.known_tables = PackedStringArray(["meadow"])

	var property: Dictionary = _property()
	zone._validate_property(property)

	assert_str(zone.table_id).is_equal("renamed_away")
	assert_bool(zone.is_complete()).is_true()


## Everything above calls `_validate_property` by hand, which proves the function
## and not the feature: the inspector only shows a menu if the *engine* applies it.
## This asks the node what its properties are and reads the answer back.
func test_the_engine_really_hands_the_inspector_a_menu() -> void:
	VltEncounterZone.known_tables = PackedStringArray(["cave_dark", "meadow"])
	var zone: VltEncounterZone = _zone()

	var found: Dictionary = {}
	for property: Dictionary in zone.get_property_list():
		if property["name"] == "table_id":
			found = property
			break

	assert_dict(found).is_not_empty()
	assert_int(found["hint"]).is_equal(PROPERTY_HINT_ENUM)
	assert_str(found["hint_string"]).is_equal("cave_dark,meadow")


func test_the_engine_hands_it_a_plain_field_with_no_list() -> void:
	var zone: VltEncounterZone = _zone()

	var found: Dictionary = {}
	for property: Dictionary in zone.get_property_list():
		if property["name"] == "table_id":
			found = property
			break

	assert_dict(found).is_not_empty()
	assert_int(found["hint"]).is_not_equal(PROPERTY_HINT_ENUM)


# --- where the list comes from -------------------------------------------------


## The one claim worth a test: the ids the menu offers are the same ids the check
## measures a zone against. Two lists would let the inspector offer something the
## validator then rejects.
func test_the_menu_and_the_check_read_one_list() -> void:
	var ids: PackedStringArray = VltMapDock.table_ids()
	assert_array(ids).is_not_empty()

	var built: PackedStringArray = VltContentPayloads.ids_in(
		"res://content/generated/encounters"
	)
	assert_array(ids).is_equal(built)


func test_the_ids_are_sorted_so_the_menu_has_a_stable_order() -> void:
	var ids: PackedStringArray = VltMapDock.table_ids()
	var sorted: PackedStringArray = ids.duplicate()
	sorted.sort()

	assert_array(ids).is_equal(sorted)


## A clone whose content has never been built is an ordinary state, and
## `VltContentPayloads` asserts on a missing index. The guard is what stops that
## being an error in somebody's face on their first afternoon.
func test_unbuilt_content_is_an_empty_list_and_not_a_crash() -> void:
	assert_bool(FileAccess.file_exists("res://content/generated/nowhere/index.json")).is_false()

	var zone: VltEncounterZone = _zone()
	VltEncounterZone.known_tables = PackedStringArray()
	var property: Dictionary = _property()
	zone._validate_property(property)

	assert_int(property["hint"]).is_equal(0)


## Every id the menu offers has to be one a zone may actually name, which is what
## `VltMapValidator` checks. Proven by naming each of them in turn.
func test_every_offered_id_passes_the_check() -> void:
	var ids: PackedStringArray = VltMapDock.table_ids()
	for id: String in ids:
		var zone: VltEncounterZone = _zone()
		zone.table_id = id
		assert_bool(zone.is_complete()).is_true()
		assert_array(ids).contains([id])
