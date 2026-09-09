class_name VltEncounterTableLoader
extends RefCounted

## Turns built encounter payloads into what the world reads.
##
## The typing boundary (spec 01): parsed data in, typed objects out. Every
## bound the build already checked is checked again here — not out of distrust,
## but because this is the last point where a payload edited by hand, or built
## by a different version, can be refused rather than played.

@warning_ignore_start("unsafe_cast")
static func from_payload(data: Dictionary) -> VltEncounterTable:
	var id: String = data["id"] as String
	var table: VltEncounterTable = VltEncounterTable.create(id, data["rate"] as int)

	for entry: Variant in data["slots"] as Array:
		var slot: Dictionary = entry as Dictionary
		var levels: Dictionary = slot["levels"] as Dictionary
		table.holds(
			slot["species"] as String,
			levels["min"] as int,
			levels["max"] as int,
			slot["weight"] as int
		)

	assert(not table.slots.is_empty(), "encounter table \"%s\" has no slots" % id)
	assert(table.total_weight() > 0, "encounter table \"%s\" has no weight" % id)
	return table


static func all_from_payload(entries: Array) -> Dictionary[String, VltEncounterTable]:
	var tables: Dictionary[String, VltEncounterTable] = {}

	for entry: Variant in entries:
		var table: VltEncounterTable = from_payload(entry as Dictionary)
		assert(not tables.has(table.id), "duplicate encounter table \"%s\"" % table.id)
		tables[table.id] = table

	return tables
@warning_ignore_restore("unsafe_cast")
