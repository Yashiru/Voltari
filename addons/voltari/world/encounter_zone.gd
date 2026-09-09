@tool
class_name VltEncounterZone
extends Node3D

## The stretch of a map where something may appear (spec 14, section 4).
##
## It names a table by id and carries nothing else about it. The table is
## content — shared, diffable, balanced in one place — and duplicating any of it
## here would be the second copy that drifts (decision 0039).
##
## **A zone is a rectangle.** Irregular grass is several zones, which is cheap;
## a per-cell list would be unauthorable in the inspector and unreadable in a
## diff. Overlap is refused rather than resolved: two tables claiming one cell
## has no right answer, and picking one silently would be a bias nobody could
## see.

## The table this terrain draws from, by content id.
@export var table_id: String = ""

## Lowest corner, in cells.
@export var origin: Vector2i = Vector2i.ZERO

## Extent in cells, both components positive.
@export var size: Vector2i = Vector2i.ONE


func contains(cell: Vector2i) -> bool:
	if size.x < 1 or size.y < 1:
		return false
	return (
		cell.x >= origin.x
		and cell.y >= origin.y
		and cell.x < origin.x + size.x
		and cell.y < origin.y + size.y
	)


func is_complete() -> bool:
	return not table_id.is_empty() and size.x >= 1 and size.y >= 1
