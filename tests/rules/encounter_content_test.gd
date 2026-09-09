extends GdUnitTestSuite

## Every authored encounter table loads, and every id in one resolves
## (spec 09, section 10).
##
## The build already checks all of this. This checks it again in the engine's
## own terms, which is the point: the build reasons about YAML and this reasons
## about the objects the world will actually be handed.

const ENCOUNTERS: String = "res://content/generated/encounters"
const SPECIES: String = "res://content/generated/species"


func _tables() -> Dictionary[String, VltEncounterTable]:
	return VltEncounterTableLoader.all_from_payload(
		VltContentPayloads.read_indexed(ENCOUNTERS)
	)


func test_every_authored_table_loads() -> void:
	var tables: Dictionary[String, VltEncounterTable] = _tables()

	assert_int(tables.size()).override_failure_message(
		"no encounter table was loaded at all"
	).is_greater(0)

	for id: String in VltContentPayloads.ids_in(ENCOUNTERS):
		assert_bool(tables.has(id)).override_failure_message(
			"table \"%s\" is in the index but did not load" % id
		).is_true()


func test_every_slot_names_a_species_that_exists() -> void:
	# The cross-reference that survives review: a table naming a species that was
	# renamed reads perfectly and produces an encounter with nothing in it.
	var known: PackedStringArray = VltContentPayloads.ids_in(SPECIES)

	for table: VltEncounterTable in _tables().values():
		for slot: VltEncounterTable.Slot in table.slots:
			assert_bool(known.has(slot.species_id)).override_failure_message(
				"table \"%s\" names unknown species \"%s\"" % [table.id, slot.species_id]
			).is_true()


func test_every_table_can_actually_be_drawn_from() -> void:
	# A table with no weight fires and then has nothing to show. Checked here
	# because it is the one failure a player would meet standing in the grass.
	for table: VltEncounterTable in _tables().values():
		assert_int(table.total_weight()).override_failure_message(
			"table \"%s\" carries no weight" % table.id
		).is_greater(0)

		var decider: VltScriptedEncounterDecider = VltScriptedEncounterDecider.new()
		for point: int in range(table.total_weight()):
			decider.slot_draw = point
			var outcome: VltEncounter.Outcome = VltEncounter.draw(table, decider)
			assert_str(outcome.species_id).is_not_empty()


func test_every_rate_is_one_a_step_can_express() -> void:
	for table: VltEncounterTable in _tables().values():
		assert_int(table.rate).override_failure_message(
			"table \"%s\" has a rate of %d, outside what 256ths can express"
			% [table.id, table.rate]
		).is_between(1, VltEncounterDecider.RATE_DENOMINATOR - 1)
