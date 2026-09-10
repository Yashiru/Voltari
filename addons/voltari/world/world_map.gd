class_name VltWorldMap
extends Node3D

## One map: what exists, what blocks, what leads elsewhere (spec 14, section 3).
##
## Engine-native by decision 0038. The scene is the truth at runtime and nothing
## is exported to a payload — a grid rebuilt from JSON on load would be the same
## information in two places with nothing keeping them equal.
##
## **Three layers, and only two of them are rules.** `terrain` says which cells
## exist; `blocking` says which of them stop you. Walkability is painted rather
## than inferred from the model standing on the cell, so replacing a rock with a
## bush is a change of art and not a change of rule.
##
## `decor` says nothing at all. Nothing reads it (decision 0054) — it is there so
## that a flower can be painted without claiming a cell exists and without
## stopping anybody.
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

## What is merely there. Read by nobody: this class offers no accessor for it on
## purpose, so that a rule cannot come to depend on decoration by accident.
@export var decor: GridMap

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


## The event a cell triggers, or null. Events fire only at named moments
## (decision 0043), so the moment is part of the question.
func event_at(cell: Vector2i, trigger: VltEvent.Trigger) -> VltEvent:
	for child: Node in get_children():
		var event: VltEvent = child as VltEvent
		if event != null and event.fires_at(cell, trigger):
			return event
	return null


func events() -> Array[VltEvent]:
	var found: Array[VltEvent] = []
	for child: Node in get_children():
		var event: VltEvent = child as VltEvent
		if event != null:
			found.append(event)
	return found


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


## Which cell a point in this map's space falls in.
##
## Asked of the grid rather than computed, because the grid has opinions this
## would otherwise have to reproduce: how wide a cell is, and whether cell zero
## straddles the origin or starts at it. Getting the second wrong offsets
## everything by half a cell, which is small enough to look like art.
func cell_at(local: Vector3) -> Vector2i:
	if terrain == null:
		return Vector2i(int(roundf(local.x)), int(roundf(local.z)))
	var grid: Vector3i = terrain.local_to_map(local)
	return Vector2i(grid.x, grid.z)


## The middle of a cell, in this map's space.
func centre_of(cell: Vector2i) -> Vector3:
	if terrain == null:
		return Vector3(cell.x, 0.0, cell.y)
	return terrain.map_to_local(Vector3i(cell.x, GROUND, cell.y))


## How wide a cell is, in metres.
func cell_width() -> float:
	if terrain == null:
		return 1.0
	return maxf(terrain.cell_size.x, 0.001)


static func _has_cell(layer: GridMap, cell: Vector2i) -> bool:
	if layer == null:
		return false
	return layer.get_cell_item(Vector3i(cell.x, GROUND, cell.y)) != GridMap.INVALID_CELL_ITEM
