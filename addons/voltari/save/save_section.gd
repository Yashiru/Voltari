class_name VltSaveSection
extends RefCounted

## One system's part of a save file (spec 13, section 2).
##
## A system that wants to persist something declares it: a key, a version, and
## the pair of functions that write and read it. Nothing enters a save by
## accident, and what a save contains is readable in one place.
##
## **The hazard this carries is silent loss.** A system that forgets to declare
## its part runs perfectly and loses the player's data. The generic round-trip
## property in the test suite is what answers it — every registered section is
## written, read back and compared, so declaring a section is what earns the
## test rather than remembering to write one.
##
## Pure: this assembles data. Files are L5's business and no section touches one.
##
## Abstract. Every method asserts, so a section that forgets one fails at the
## call rather than persisting something plausible.

## Stable, `snake_case`, never reused for a different meaning — the same rule
## the content identifiers follow, and for the same reason: a save holds it.
func key() -> String:
	assert(false, "VltSaveSection is abstract")
	return ""


## Raised when the section's shape changes in a way a default cannot cover: a
## renamed field, or one whose meaning moved. Adding a field does not need it.
func version() -> int:
	assert(false, "VltSaveSection is abstract")
	return 0


func write() -> Dictionary:
	assert(false, "VltSaveSection is abstract")
	return {}


## `stored_version` is the version that wrote `stored`, never this one.
##
## Read tolerantly: a field that is absent gets a default, because an older save
## simply does not have it (decision 0037). Branch on the version only for what
## a default cannot express.
func read(_stored: Dictionary, _stored_version: int) -> void:
	assert(false, "VltSaveSection is abstract")


# --- reading a stored field -------------------------------------------------
#
# Typed, and here rather than in each section, because every section faces the
# same thing: a stored value is a Variant, and a save that has been edited by
# hand or written by another build may hold anything at all. A section that
# reached into the dictionary itself would repeat these casts, and the day one
# of them was skipped would be the day a save could crash the game.


@warning_ignore_start("unsafe_cast")
static func read_int(stored: Dictionary, key: String, fallback: int = 0) -> int:
	var value: Variant = stored.get(key, fallback)
	if value is float:
		return int(value as float)
	if value is int:
		return value as int
	return fallback


static func read_string(stored: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = stored.get(key, fallback)
	return value as String if value is String else fallback


static func read_bool(stored: Dictionary, key: String, fallback: bool = false) -> bool:
	var value: Variant = stored.get(key, fallback)
	return value as bool if value is bool else fallback
@warning_ignore_restore("unsafe_cast")
