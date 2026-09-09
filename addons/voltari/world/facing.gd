class_name VltFacing
extends RefCounted

## Which way a walker is turned (spec 14, section 2).
##
## Facing is part of position, not a rendering detail: a warp declares the
## direction you arrive turned, and spec 15 will have interactions read it.
##
## **The values are held in a save**, so they are stable. Reordering this enum
## would silently turn every stored character around.

enum Direction { NORTH, EAST, SOUTH, WEST }

## Cells are (x, z). North is -Z, which is Godot's own forward.
const DELTAS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]


static func delta(direction: Direction) -> Vector2i:
	assert(is_known(direction), "unknown facing %d" % direction)
	return DELTAS[direction]


## Guards the boundary where a facing arrives as a plain integer — from a save,
## or from a warp somebody typed by hand.
static func is_known(value: int) -> bool:
	return value >= 0 and value < DELTAS.size()


## A facing that arrived as a plain integer, or `fallback` when it names no
## direction. Used where a save, or a value somebody typed, reaches the world.
static func known_or(value: int, fallback: Direction) -> Direction:
	return value as Direction if is_known(value) else fallback
