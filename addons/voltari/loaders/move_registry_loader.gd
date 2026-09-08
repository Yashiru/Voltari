class_name VltMoveRegistryLoader
extends RefCounted

## Turns the built move payload into the registry the turn engine consumes.
##
## Outside core/ for the same reason as the type chart loader: the core accepts
## only already-typed data and performs no I/O (spec 03). This is where untyped
## content becomes typed, and the unsafe-cast suppressions stop here.

const CATEGORY_NAMES: Dictionary[String, int] = {
	"physical": VltMoveDefinition.Category.PHYSICAL,
	"special": VltMoveDefinition.Category.SPECIAL,
	"status": VltMoveDefinition.Category.STATUS,
}


## `entries` is one built payload per move (decision 0025). Reading them off
## disk belongs to the caller: this is the typing boundary, not a file reader.
@warning_ignore_start("unsafe_cast")
static func from_entries(entries: Array) -> Dictionary[String, VltMoveDefinition]:
	var registry: Dictionary[String, VltMoveDefinition] = {}

	for entry: Variant in entries:
		var data: Dictionary = entry as Dictionary
		var id: String = data["id"] as String
		var category: String = data["category"] as String

		assert(not registry.has(id), "duplicate move id \"%s\" in the payload" % id)
		assert(CATEGORY_NAMES.has(category), "unknown move category \"%s\"" % category)

		registry[id] = VltMoveDefinition.create(
			id,
			data["type"] as String,
			CATEGORY_NAMES[category] as VltMoveDefinition.Category,
			int(data["power"] as float),
			int(data["accuracy"] as float),
			int(data["priority"] as float),
			int(data["pp"] as float),
		)

	return registry
@warning_ignore_restore("unsafe_cast")
