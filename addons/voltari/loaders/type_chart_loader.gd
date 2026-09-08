class_name VltTypeChartLoader
extends RefCounted

## Turns the built content payload into a typed VltTypeChart.
##
## Deliberately outside core/: the core performs no I/O and accepts only
## already-typed data (spec 03). This is the boundary where untyped external
## data becomes typed, and the unsafe-cast suppressions are scoped to it.

const OUTCOME_NAMES: Dictionary[String, int] = {
	"super_effective": VltTypeChart.Outcome.SUPER_EFFECTIVE,
	"resisted": VltTypeChart.Outcome.RESISTED,
	"immune": VltTypeChart.Outcome.IMMUNE,
}


## `payload` is the parsed content build output: {version, types, table}.
@warning_ignore_start("unsafe_cast")
static func from_payload(payload: Dictionary) -> VltTypeChart:
	var types: PackedStringArray = PackedStringArray()
	for entry: Variant in payload["types"] as Array:
		types.append(entry as String)

	var outcomes: Dictionary[String, int] = {}
	var table: Dictionary = payload["table"] as Dictionary

	for attacking: Variant in table.keys():
		var row: Dictionary = table[attacking] as Dictionary
		for defending: Variant in row.keys():
			var name: String = row[defending] as String
			assert(OUTCOME_NAMES.has(name), "unknown outcome \"%s\" in the type chart payload" % name)
			outcomes[VltTypeChart.key_for(attacking as String, defending as String)] = (
				OUTCOME_NAMES[name]
			)

	return VltTypeChart.new(types, outcomes)
@warning_ignore_restore("unsafe_cast")
