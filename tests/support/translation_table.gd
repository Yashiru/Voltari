class_name VltTranslationTable
extends RefCounted

## The keys the translation table declares, for tests.
##
## Read as text rather than through `tr()`, because a missing key is exactly what
## `tr()` hides — it hands back the key itself, so every check would pass.

const BATTLE: String = "res://game/localisation/battle.csv"
const WORLD: String = "res://game/localisation/world.csv"

## One table per domain, because each has a test that checks it declares nothing
## nobody asks for — and that check only works when the table and the thing that
## asks are the same shape.
const EVERY: Array[String] = [BATTLE, WORLD]


## Every key across every table. What the map validator needs, since an event
## may say a battle line and a battle may not say a sign.
static func all_keys() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for path: String in EVERY:
		found.append_array(keys(path))
	return found


static func keys(path: String = BATTLE) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(file != null, "no translation table at %s" % path)
	if file == null:
		return PackedStringArray()

	var declared: PackedStringArray = PackedStringArray()
	var header: bool = true

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if header:
			header = false
			continue
		if row.size() > 0 and not row[0].is_empty():
			declared.append(row[0])

	file.close()
	return declared
