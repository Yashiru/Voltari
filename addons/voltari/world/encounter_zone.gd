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
##
## `@tool` for one reason and no other: so `table_id` can be a menu of the ids
## that exist rather than a field to mistype. Nothing here runs in the editor
## beyond answering what shape that one property has.

## The table ids the content build produced, for the inspector's benefit.
##
## **Put here by the editor plugin; never read from disk by this file.** A zone
## names a table and carries nothing else about it, and knowing where content sits
## on disk is something else — `addons/voltari_maps` already holds that path for
## the map check, and a second copy of it here is exactly the drift decision 0039
## is about. It would also ship file-reading code inside the running game for the
## sake of a dropdown.
##
## Empty outside the editor, and empty inside it until the plugin has looked.
static var known_tables: PackedStringArray = PackedStringArray()

## The table this terrain draws from, by content id.
@export var table_id: String = ""

## Lowest corner, in cells.
@export var origin: Vector2i = Vector2i.ZERO

## Extent in cells, both components positive.
@export var size: Vector2i = Vector2i.ONE


## Makes `table_id` a menu of the ids the build knows about.
##
## **Display only.** What is stored is the same string it always was, and nothing
## here writes to it: a zone naming a table that has since been renamed keeps its
## id in the scene until somebody changes it. `VltMapValidator` is what says an id
## is wrong, and it stays the only thing that says so — this just makes it harder
## to produce one.
##
## **A plain text field when the list is empty**, which is a project whose content
## has never been built. A menu with nothing in it would make a zone unauthorable
## and explain nothing; a text field is what this property has always been.
func _validate_property(property: Dictionary) -> void:
	if property["name"] != "table_id" or known_tables.is_empty():
		return
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = ",".join(known_tables)


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
