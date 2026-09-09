class_name VltWorldSaveSection
extends VltSaveSection

## Where the player is, as a save section (spec 14, section 8; decision 0040).
##
## The world's state is held by the engine and a save deals in dictionaries, so
## something has to convert one into the other. This is that converter, and it
## lives **with the world rather than in `save/`** — a class that reads a node
## cannot sit under the purity lint, and exempting one file from a lint is how a
## lint stops being trusted. `VltSaveSection` is pure and the world depends on
## it, so the dependency runs downward and nothing is inverted.
##
## **One direction only.** This reads the world and produces a dictionary. The
## world never reads a file; L5 still owns the bytes (spec 13, section 1).
##
## What it does not do is load a map. Placing the walker means having the right
## scene in the tree first, and that belongs to whoever owns scenes.

const KEY: String = "world"
const VERSION: int = 1

const MAP_FIELD: String = "map"
const CELL_X_FIELD: String = "cell_x"
const CELL_Z_FIELD: String = "cell_z"
const FACING_FIELD: String = "facing"

## The live world. `write` reads it when it is here.
var walker: VltGridWalker = null

## What the last read produced, and what `write` falls back on. The caller loads
## `map_id`, then places the walker on `cell` facing `facing`.
var map_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var facing: VltFacing.Direction = VltFacing.Direction.SOUTH


func _init(live: VltGridWalker = null) -> void:
	walker = live


func key() -> String:
	return KEY


func version() -> int:
	return VERSION


## Reads the live world when one is attached, and otherwise writes back what was
## last read.
##
## The fallback is not laziness: a section with no walker is one that was never
## given a world, and writing back what it read carries the position through
## untouched rather than inventing a new one. It is the same instinct as
## decision 0036 — what cannot be refreshed is preserved, never guessed at.
func write() -> Dictionary:
	if walker != null:
		if walker.map != null:
			map_id = walker.map.map_id
		cell = walker.cell
		facing = walker.facing

	return {
		MAP_FIELD: map_id,
		CELL_X_FIELD: cell.x,
		CELL_Z_FIELD: cell.y,
		FACING_FIELD: int(facing),
	}


func read(stored: Dictionary, _stored_version: int) -> void:
	map_id = VltSaveSection.read_string(stored, MAP_FIELD)
	cell = Vector2i(
		VltSaveSection.read_int(stored, CELL_X_FIELD),
		VltSaveSection.read_int(stored, CELL_Z_FIELD)
	)
	# A facing naming no direction would index past the deltas the first time the
	# player pressed a key. Guarded here, at the boundary, rather than trusted.
	facing = VltFacing.known_or(
		VltSaveSection.read_int(stored, FACING_FIELD, int(VltFacing.Direction.SOUTH)),
		VltFacing.Direction.SOUTH
	)
