class_name PresentationLoader
extends RefCounted

## Turns built presentation payloads into what the runtime reads.
##
## The typing boundary (spec 01): parsed data in, typed objects out. The build
## has already checked every rule; they are checked again here because this is
## the last point where a payload edited by hand, or written by a different
## version, can be refused rather than played.

const FALLBACK_PREFIX: String = "use "


@warning_ignore_start("unsafe_cast")
static func from_payload(data: Dictionary) -> PresentationEntry:
	var entry: PresentationEntry = PresentationEntry.new()
	entry.id = data.get("id", "") as String
	entry.scene_path = data.get("scene", "") as String
	entry.height = _metres(data.get("height", 1.0))

	var clips: Dictionary = data.get("clips", {}) as Dictionary
	for key: Variant in clips.keys():
		var slot: String = key as String
		var value: Variant = clips[slot]

		if value is String:
			var named: String = value as String
			assert(named.begins_with(FALLBACK_PREFIX), "\"%s\" is not a fallback" % named)
			entry.fallbacks[slot] = named.substr(FALLBACK_PREFIX.length()).strip_edges()
			continue

		var takes: PackedStringArray = PackedStringArray()
		for take: Variant in value as Array:
			takes.append(take as String)
		assert(not takes.is_empty(), "slot \"%s\" lists no takes" % slot)
		entry.takes[slot] = takes

	entry.extras = _names(data.get("extras", []))
	entry.stow = _names(data.get("stow", []))
	return entry


static func all_from_payload(entries: Array) -> Dictionary[String, PresentationEntry]:
	var manifests: Dictionary[String, PresentationEntry] = {}

	for entry: Variant in entries:
		var manifest: PresentationEntry = from_payload(entry as Dictionary)
		assert(not manifests.has(manifest.id), "duplicate manifest \"%s\"" % manifest.id)
		manifests[manifest.id] = manifest

	return manifests


## JSON gives a whole number back as an int, so a height of 2 is not a float.
static func _metres(value: Variant) -> float:
	if value is float:
		return value as float
	if value is int:
		return float(value as int)
	return 1.0


static func _names(value: Variant) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if not value is Array:
		return names
	for name: Variant in value as Array:
		names.append(name as String)
	return names
@warning_ignore_restore("unsafe_cast")
