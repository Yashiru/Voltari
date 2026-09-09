class_name VltSaveStore
extends RefCounted

## L5: the only class in the engine that touches a file (spec 13, section 1).
##
## Everything above it deals in dictionaries. That separation is what lets every
## rule about saving be tested without a filesystem, and it is why this class has
## no rules in it at all — it moves bytes.
##
## **A write must survive being interrupted.** The failure a save system has to
## prevent is not losing the new data; it is destroying the old while writing the
## new. So a save goes to a temporary file first and only replaces the real one
## once it is completely on disk.

const TEMPORARY_SUFFIX: String = ".writing"
const BACKUP_SUFFIX: String = ".previous"


## Writes, and only then replaces. Returns whether the save is now on disk.
##
## A crash between the two leaves a stray temporary file and the previous save
## untouched, which is the outcome to aim for: the player loses the last session,
## never the whole game.
static func write(path: String, document: Dictionary) -> bool:
	var temporary: String = path + TEMPORARY_SUFFIX

	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(document, "\t"))
	file.close()

	# Rename over the old one. On every platform this either happens or does
	# not; there is no state where half the file is the new save.
	return DirAccess.rename_absolute(temporary, path) == OK


## The document, or an empty dictionary when there is nothing readable.
##
## An unreadable file is not an error here. Whether it means "no save yet" or
## "something is wrong" is a question for the layer that knows what it asked for.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}

	@warning_ignore("unsafe_cast")
	return parsed as Dictionary


## Copies the current save aside before it is overwritten.
##
## Called before the first write over a save that read incompletely
## (decision 0036): the confirmation buys informed consent, and this is what
## makes that consent recoverable when it was given too quickly.
static func back_up(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.copy_absolute(path, path + BACKUP_SUFFIX) == OK


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


## Removes a temporary file a previous run left behind. A crash mid-write leaves
## one, and it is harmless — but a stale one lying around invites the guess that
## it means something.
static func clear_temporary(path: String) -> void:
	var temporary: String = path + TEMPORARY_SUFFIX
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
