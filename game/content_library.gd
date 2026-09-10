class_name ContentLibrary
extends RefCounted

## Where the game reads its content (spec 09, section 1).
##
## The test helper that does the same thing left this deliberately unanswered —
## "a question for the spec that gives it a home; answering it early, from a test
## helper, would settle it by accident". A battle screen is what needed it, so
## here it is, in `game/`: reading files is not the engine's business and the
## loaders take already-parsed data (spec 03).
##
## Loading is all-or-nothing on purpose. A build with half a roster would run,
## and the first thing anybody noticed would be a creature that could not be
## found — which is spec 09's argument for refusing malformed content, applied at
## the other end of the pipeline.

const GENERATED: String = "res://content/generated"

var species: Dictionary[String, VltSpecies] = {}
var moves: Dictionary[String, VltMoveDefinition] = {}
var chart: VltTypeChart = null
var natures: Array[PackedInt32Array] = []
var curves: Dictionary[String, PackedInt32Array] = {}


static func load_all() -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()

	library.species = VltSpeciesLoader.from_entries(_indexed("species"))
	library.moves = VltMoveRegistryLoader.from_entries(_indexed("moves"))
	library.chart = VltTypeChartLoader.from_payload(_json("type-chart.json"))
	library.natures = VltNatureLoader.from_payload(_json("natures.json"))
	library.curves = VltGrowthCurveLoader.from_payload(_json("growth-curves.json"))

	return library


## Every entity of one kind, in index order. Without the index nothing can
## enumerate a roster and a reader is reduced to guessing filenames (spec 09,
## section 9).
static func _indexed(kind: String) -> Array:
	var entries: Array = []
	var index: Dictionary = _json("%s/index.json" % kind)

	@warning_ignore("unsafe_cast")
	for id: Variant in index.get("ids", []) as Array:
		@warning_ignore("unsafe_cast")
		entries.append(_json("%s/%s.json" % [kind, id as String]))

	return entries


static func _json(path: String) -> Dictionary:
	var full: String = "%s/%s" % [GENERATED, path]
	var file: FileAccess = FileAccess.open(full, FileAccess.READ)
	assert(file != null, "missing content payload %s" % full)
	if file == null:
		return {}

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "content payload %s is not an object" % full)

	@warning_ignore("unsafe_cast")
	return parsed as Dictionary if parsed is Dictionary else {}
