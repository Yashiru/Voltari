class_name VltSpeciesLoader
extends RefCounted

## Turns built species payloads into the typed form the engine accepts.
##
## Outside core/ for the same reason as the other loaders: the core takes
## already-typed data and performs no I/O (spec 03). The unsafe-cast
## suppressions stop here.

const GENDERLESS_KEY: String = "genderless"


## `entries` is one built payload per species (decision 0025). Reading them off
## disk belongs to the caller.
static func from_entries(entries: Array) -> Dictionary[String, VltSpecies]:
	var registry: Dictionary[String, VltSpecies] = {}

	for entry: Variant in entries:
		var species: VltSpecies = from_payload(_dict(entry))
		assert(not registry.has(species.id), "duplicate species id \"%s\"" % species.id)
		registry[species.id] = species

	return registry


static func from_payload(data: Dictionary) -> VltSpecies:
	var species: VltSpecies = VltSpecies.create(
		_text(data["id"]),
		_strings(_array(data["types"])),
		_spread(_dict(data["base_stats"]))
	)

	for entry: Variant in _learnset_of(data):
		var learned: Dictionary = _dict(entry)
		species.learns(_num(learned["level"]), _text(learned["move"]))

	# Absent rather than empty when there is nothing to say (spec 09).
	if data.has("evolutions"):
		for entry: Variant in _array(data["evolutions"]):
			var evolution: Dictionary = _dict(entry)
			species.evolves(
				_text(evolution["into"]),
				_text(evolution["trigger"]),
				_num(evolution["level"]) if evolution.has("level") else 0
			)

	species.growth_rate = _text(data["growth_rate"])
	species.base_experience = _num(data["base_experience"])
	species.ev_yield = _spread(_dict(data["ev_yield"]))
	species.catch_rate = _num(data["catch_rate"])
	species.gender_ratio = _gender_ratio(data["gender_ratio"])

	return species


@warning_ignore_start("unsafe_cast")
static func _learnset_of(data: Dictionary) -> Array:
	if not data.has("learnset"):
		return []
	var learnset: Dictionary = _dict(data["learnset"])
	return _array(learnset["level_up"]) if learnset.has("level_up") else []


## Stat maps are read through the engine's own stat order, so content and code
## never have to agree on a second ordering convention.
static func _spread(source: Dictionary) -> PackedInt32Array:
	var spread: PackedInt32Array = PackedInt32Array()
	spread.resize(VltStats.STAT_COUNT)
	for stat: int in range(VltStats.STAT_COUNT):
		spread[stat] = _num(source[VltStats.STAT_KEYS[stat]])
	return spread


static func _gender_ratio(value: Variant) -> int:
	if value is String:
		assert(value as String == GENDERLESS_KEY, "unknown gender ratio \"%s\"" % value)
		return VltSpecies.GENDERLESS
	return _num(value)


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary


static func _array(value: Variant) -> Array:
	return value as Array


static func _num(value: Variant) -> int:
	return int(value as float)


static func _text(value: Variant) -> String:
	return value as String


static func _strings(values: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		result.append(_text(value))
	return result
@warning_ignore_restore("unsafe_cast")
