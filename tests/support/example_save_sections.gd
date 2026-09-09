class_name VltExampleSaveSections
extends RefCounted

## Sections that exist only to prove the mechanism (spec 13).
##
## The real ones — party, inventory, position — belong to systems that have no
## spec yet. These stand in for them so the save machinery can be built and
## tested now rather than assumed to work later.


## A plain section: a few fields, one version.
class Counter:
	extends VltSaveSection

	var steps: int = 0
	var name: String = ""

	func key() -> String:
		return "counter"

	func version() -> int:
		return 1

	func write() -> Dictionary:
		return {"steps": steps, "name": name}

	func read(stored: Dictionary, _stored_version: int) -> void:
		# Absent gets a default. An older save simply did not have it, which is
		# the common change and the whole point of reading tolerantly.
		steps = read_int(stored, "steps")
		name = read_string(stored, "name")


## A section that changed the MEANING of a field, which no default can cover.
##
## Version 1 stored a distance in steps; version 2 stores it in metres. Reading a
## version 1 payload as metres would produce a number that is present, valid and
## wrong — the failure the section version exists to prevent (decision 0037).
class Distance:
	extends VltSaveSection

	const STEPS_PER_METRE: int = 2

	var metres: int = 0

	func key() -> String:
		return "distance"

	func version() -> int:
		return 2

	func write() -> Dictionary:
		return {"travelled": metres}

	func read(stored: Dictionary, stored_version: int) -> void:
		var travelled: int = read_int(stored, "travelled")
		metres = travelled if stored_version >= 2 else travelled / STEPS_PER_METRE
