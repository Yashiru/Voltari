extends GdUnitTestSuite

## Every key the reader can ask for exists (spec 17, section 5).
##
## Engine-side rather than in the content build, and for the reason the map
## validation is: the keys live in GDScript, and only GDScript knows which ones
## something can produce. The build reasons about YAML.
##
## This is the other end of "the core emits identifiers, never text". Without it,
## a missing key surfaces as its own name printed on screen, in front of whoever
## is playing.

const TABLE: String = "res://game/localisation/battle.csv"
const SPECIES: String = "res://content/generated/species"


## The keys the table declares. Read as text rather than through `tr()`, because
## a missing key is exactly what `tr()` hides — it returns the key itself.
func _declared() -> PackedStringArray:
	var file: FileAccess = FileAccess.open(TABLE, FileAccess.READ)
	assert_object(file).override_failure_message("no translation table at %s" % TABLE).is_not_null()

	var keys: PackedStringArray = PackedStringArray()
	var header: bool = true
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if header:
			header = false
			continue
		if row.size() > 0 and not row[0].is_empty():
			keys.append(row[0])
	file.close()
	return keys


func test_every_line_the_reader_can_say_is_in_the_table() -> void:
	var declared: PackedStringArray = _declared()
	for key: String in BattleLines.KEYS:
		assert_bool(declared.has(key)).override_failure_message(
			"nothing translates \"%s\", so it would print as its own name" % key
		).is_true()


func test_every_registered_effect_can_announce_itself() -> void:
	# Effect keys carry an identifier, so they cannot be listed up front. Only
	# the registry knows which exist.
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	registry.register(VltReflect.define())

	var declared: PackedStringArray = _declared()
	for id: String in [VltBurn.ID, VltReflect.ID]:
		for removed: bool in [false, true]:
			var key: String = BattleLines.effect_key(id, removed)
			assert_bool(declared.has(key)).override_failure_message(
				"effect \"%s\" has no line for %s" % [id, "ending" if removed else "beginning"]
			).is_true()


func test_every_species_has_something_to_be_called() -> void:
	# The names are the identifiers for now: naming is IP work that has not
	# happened (content/README.md). What matters here is that the join exists,
	# so the day real names land they land in one file.
	var declared: PackedStringArray = _declared()
	for id: String in VltContentPayloads.ids_in(SPECIES):
		assert_bool(declared.has(BattleLines.species_key(id))).override_failure_message(
			"species \"%s\" has no name to show" % id
		).is_true()


func test_the_table_declares_nothing_nobody_asks_for() -> void:
	# The opposite direction, and the one that rots quietly: a key left behind
	# after the event that used it was renamed reads as a translated game.
	var registry_ids: Array[String] = [VltBurn.ID, VltReflect.ID]
	var expected: PackedStringArray = PackedStringArray(BattleLines.KEYS)
	for id: String in registry_ids:
		expected.append(BattleLines.effect_key(id, false))
		expected.append(BattleLines.effect_key(id, true))
	for id: String in VltContentPayloads.ids_in(SPECIES):
		expected.append(BattleLines.species_key(id))

	for key: String in _declared():
		assert_bool(expected.has(key)).override_failure_message(
			"\"%s\" is translated and nothing asks for it" % key
		).is_true()
