class_name VltSaveCodec
extends RefCounted

## Turns declared sections into a save document and back (spec 13).
##
## Pure: dictionaries in, dictionaries out. It never sees a path — writing bytes
## is L5's, and keeping the two apart is what lets every rule here be tested
## without a filesystem.
##
## Two properties carry the design:
##
## **A section that cannot be read is kept, not dropped** (decision 0036). It
## comes back in the report and goes back into the next write untouched. Without
## that, a partly-understood save is rewritten complete and everything unread is
## gone — the player noticing weeks later, by looking for what is missing.
##
## **Sections are read independently.** One that fails cannot take another down
## with it, which is a constraint on the format and not only on the reader.

const FORMAT_KEY: String = "format"
const SECTIONS_KEY: String = "sections"
const VERSION_KEY: String = "version"
const DATA_KEY: String = "data"

## The envelope's own version, apart from any section's.
const FORMAT_VERSION: int = 1


## What a read produced, and what it could not.
class Report:
	extends RefCounted

	## Keys that could not be read: unknown to this build, written by a newer
	## version, or malformed. Every one of them is also in `preserved`.
	var unread: PackedStringArray = PackedStringArray()

	## Raw payloads to carry into the next write, by key.
	var preserved: Dictionary[String, Variant] = {}

	## True when the envelope itself came from a build ahead of this one.
	var newer_format: bool = false

	func complete() -> bool:
		return unread.is_empty() and not newer_format


## `preserved` is what a previous read could not understand. Passing it back is
## what makes an unread section survive a round trip.
static func write(
	sections: Array[VltSaveSection], preserved: Dictionary[String, Variant] = {}
) -> Dictionary:
	var stored: Dictionary = {}

	for key: String in preserved.keys():
		stored[key] = preserved[key]

	for section: VltSaveSection in sections:
		var key: String = section.key()
		assert(not _declared_twice(stored, preserved, key), "two sections claim \"%s\"" % key)
		stored[key] = {VERSION_KEY: section.version(), DATA_KEY: section.write()}

	return {FORMAT_KEY: FORMAT_VERSION, SECTIONS_KEY: stored}


@warning_ignore_start("unsafe_cast")
static func read(document: Dictionary, sections: Array[VltSaveSection]) -> Report:
	var report: Report = Report.new()

	if not document.has(SECTIONS_KEY) or not document[SECTIONS_KEY] is Dictionary:
		# Nothing recognisable at all. Reported rather than crashed on, and
		# nothing is preserved because nothing could be identified.
		report.unread.append(SECTIONS_KEY)
		return report

	# A newer envelope is still walked: its sections may be readable, and the
	# ones that are not are preserved like any other.
	report.newer_format = _number(document.get(FORMAT_KEY, 0)) > FORMAT_VERSION

	var by_key: Dictionary[String, VltSaveSection] = {}
	for section: VltSaveSection in sections:
		by_key[section.key()] = section

	var stored: Dictionary = document[SECTIONS_KEY] as Dictionary
	for entry: Variant in stored.keys():
		var key: String = entry as String
		_read_one(key, stored[key], by_key, report)

	return report


static func _read_one(
	key: String,
	payload: Variant,
	by_key: Dictionary[String, VltSaveSection],
	report: Report
) -> void:
	# Unknown to this build: not a failure of the save, but not something this
	# build can act on either. Kept, and reported.
	if not by_key.has(key):
		_keep(key, payload, report)
		return

	if not payload is Dictionary:
		_keep(key, payload, report)
		return

	var wrapper: Dictionary = payload as Dictionary
	var stored_version: int = _number(wrapper.get(VERSION_KEY, 0))
	var section: VltSaveSection = by_key[key]

	# Written by a build ahead of this one. Reading it would be guessing at a
	# shape nobody here has seen.
	if stored_version > section.version():
		_keep(key, payload, report)
		return

	if not wrapper.get(DATA_KEY, null) is Dictionary:
		_keep(key, payload, report)
		return

	section.read(wrapper[DATA_KEY] as Dictionary, stored_version)


static func _keep(key: String, payload: Variant, report: Report) -> void:
	report.unread.append(key)
	report.preserved[key] = payload


static func _declared_twice(
	stored: Dictionary, preserved: Dictionary[String, Variant], key: String
) -> bool:
	# A key already in `stored` and not carried over from `preserved` means two
	# sections claimed it, which would make one of them silently overwrite the
	# other every save.
	return stored.has(key) and not preserved.has(key)


static func _number(value: Variant) -> int:
	if value is float:
		return int(value as float)
	if value is int:
		return value as int
	return 0
@warning_ignore_restore("unsafe_cast")
