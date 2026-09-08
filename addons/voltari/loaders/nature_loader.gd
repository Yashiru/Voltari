class_name VltNatureLoader
extends RefCounted

## Turns the built nature payload into the table generation picks from.
##
## A nature is a pair of stats and nothing else, so the table is pairs: the
## raised stat and the lowered one, or NO_STAT for both when it is neutral. The
## authored identifier does not survive the crossing because nothing downstream
## needs it — a creature stores the pair, not the name (spec 03).



## `payload` is the content build output: {version, stats, natures}.
@warning_ignore_start("unsafe_cast")
static func from_payload(payload: Dictionary) -> Array[PackedInt32Array]:
	var table: Array[PackedInt32Array] = []

	for entry: Variant in payload["natures"] as Array:
		var nature: Dictionary = entry as Dictionary
		table.append(
			PackedInt32Array([_stat_index(nature["plus"]), _stat_index(nature["minus"])])
		)

	return table


## A neutral nature names no stat on either side, and the two must agree — the
## content build already refuses a half-neutral entry.
static func _stat_index(value: Variant) -> int:
	if value == null:
		return VltStats.NO_STAT

	var name: String = value as String
	var index: int = VltStats.STAT_KEYS.find(name)
	assert(index != -1, "nature names unknown stat \"%s\"" % name)
	return index
@warning_ignore_restore("unsafe_cast")
