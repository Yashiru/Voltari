class_name VltWorldMap
extends Node3D

## One map: what exists, what blocks, what leads elsewhere (spec 14, section 3).
##
## Engine-native by decision 0038. The scene is the truth at runtime and nothing
## is exported to a payload — a grid rebuilt from JSON on load would be the same
## information in two places with nothing keeping them equal.
##
## **Two layers, not one.** `terrain` says which cells exist; `blocking` says
## which of them stop you. Walkability is painted rather than inferred from the
## model standing on the cell, so replacing a rock with a bush is a change of art
## and not a change of rule.
##
## A cell with no terrain is off the map, and off the map blocks exactly the way
## a wall does. That falls out rather than being special-cased, which is why the
## edge of a map needs no fence painted around it.

## Stable, `snake_case`, never reused for a different map — a save holds it
## (decision 0040), so renaming one is a migration rather than a rename.
@export var map_id: String = ""

## What exists. A cell absent here is off the map.
@export var terrain: GridMap

## What stops you. A cell present here is blocked.
@export var blocking: GridMap

## Cells are (x, z); the overworld is one storey and y is fixed.
const GROUND: int = 0


func is_walkable(cell: Vector2i) -> bool:
	return _has_cell(terrain, cell) and not _has_cell(blocking, cell)


## The warp on a cell, or null. Null rather than a sentinel warp: "there is no
## warp here" is the answer for almost every cell, and inventing an object for
## it would mean every caller checking a field instead of a reference.
func warp_at(cell: Vector2i) -> VltWarp:
	for child: Node in get_children():
		var warp: VltWarp = child as VltWarp
		if warp != null and warp.cell == cell:
			return warp
	return null


func zone_at(cell: Vector2i) -> VltEncounterZone:
	for child: Node in get_children():
		var zone: VltEncounterZone = child as VltEncounterZone
		if zone != null and zone.contains(cell):
			return zone
	return null


func warps() -> Array[VltWarp]:
	var found: Array[VltWarp] = []
	for child: Node in get_children():
		var warp: VltWarp = child as VltWarp
		if warp != null:
			found.append(warp)
	return found


func zones() -> Array[VltEncounterZone]:
	var found: Array[VltEncounterZone] = []
	for child: Node in get_children():
		var zone: VltEncounterZone = child as VltEncounterZone
		if zone != null:
			found.append(zone)
	return found


static func _has_cell(layer: GridMap, cell: Vector2i) -> bool:
	if layer == null:
		return false
	return layer.get_cell_item(Vector3i(cell.x, GROUND, cell.y)) != GridMap.INVALID_CELL_ITEM
