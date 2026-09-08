class_name VltContentPayloads
extends RefCounted

## Reads built content payloads from disk, for tests.
##
## Here rather than in `loaders/` because the loaders take already-parsed data
## and perform no I/O — the same rule the core follows (spec 03). Where the game
## itself reads content from is a question for the spec that gives it a home;
## answering it early, from a test helper, would settle it by accident.
##
## Content is deliberately NOT a fixture for core tests (spec 09, section 10):
## a core test that reads this is coupling the engine's correctness to the
## roster's balance. It is for the tests that exist to check the content.

@warning_ignore_start("unsafe_cast")
static func read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing payload %s" % path)
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary


## Every entity of one kind, in index order.
##
## The index is what makes one-file-per-entity output usable: without it there
## is nothing to enumerate and a reader is reduced to guessing filenames
## (decision 0025).
static func read_indexed(directory: String) -> Array:
	var entries: Array = []
	for id: String in ids_in(directory):
		entries.append(read_json("%s/%s.json" % [directory, id]))
	return entries


## The ids the index declares, sorted.
static func ids_in(directory: String) -> PackedStringArray:
	var index: Dictionary = read_json("%s/index.json" % directory)
	var ids: PackedStringArray = PackedStringArray()

	for entry: Variant in index["ids"] as Array:
		ids.append(entry as String)

	ids.sort()
	return ids
@warning_ignore_restore("unsafe_cast")
