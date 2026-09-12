class_name VltRestPoint
extends Node3D

## Somewhere to be sent back to.
##
## A node on the map, like a warp or a zone. Losing a battle teleports the player
## to the nearest one and heals the party — which makes this the only thing
## standing between a defeat and a game that cannot continue.
##
## **"Nearest" needs a metric, and between two maps there is no obvious one.**
## The one used here is stated rather than assumed:
##
## 1. On the current map, the fewest steps away — Manhattan, because movement is
##    four-directional and a diagonal is two steps.
## 2. Otherwise the fewest map transitions, walking the warp graph outward. The
##    first map reached that has one wins, and within it the same rule applies
##    from the cell the warp arrives at.
##
## It is not "the last one visited", which is what the reference games do. That
## needs a memory and would make two players in the same place wake up somewhere
## different — defensible, and a different decision from the one that was made.

## Which cell to stand on.
@export var cell: Vector2i = Vector2i.ZERO

## Which way to face on arrival. A player who wakes up facing a wall has to work
## out where they are before they can move.
@export var facing: VltFacing.Direction = VltFacing.Direction.SOUTH


## A rest point and the map it is on. Both, because arriving needs the map and
## the map is not something a node can be asked for once it is out of its tree.
class Found:
	extends RefCounted

	var map_id: String = ""
	var cell: Vector2i = Vector2i.ZERO
	var facing: VltFacing.Direction = VltFacing.Direction.SOUTH

	func _init(on: String, at: Vector2i, turned: VltFacing.Direction) -> void:
		map_id = on
		cell = at
		facing = turned


## The nearest rest point to a position, or null when nothing can be reached.
##
## Null is a real answer and the caller has to handle it: a map with no rest
## point anywhere in front of it is content that cannot recover from a defeat,
## and the validator says so at build time rather than leaving it to be met.
static func nearest(
	maps: Dictionary[String, VltWorldMap], from_map: String, from_cell: Vector2i
) -> Found:
	if not maps.has(from_map):
		return null

	var seen: Dictionary[String, bool] = {from_map: true}
	var pending: Array[Array] = [[from_map, from_cell]]

	while not pending.is_empty():
		var step: Array = pending.pop_front()
		@warning_ignore("unsafe_cast")
		var map_id: String = step[0] as String
		@warning_ignore("unsafe_cast")
		var arrived: Vector2i = step[1] as Vector2i

		var here: Found = _closest_on(maps[map_id], arrived)
		if here != null:
			return here

		for warp: VltWarp in maps[map_id].warps():
			if warp.is_complete() and maps.has(warp.to_map) and not seen.has(warp.to_map):
				seen[warp.to_map] = true
				pending.append([warp.to_map, warp.to_cell])

	return null


## The fewest steps away on one map, or null. Manhattan, because a diagonal is
## two steps and a straight-line distance would call a wall a shortcut.
static func _closest_on(map: VltWorldMap, from_cell: Vector2i) -> Found:
	var best: VltRestPoint = null
	var best_steps: int = -1

	for point: VltRestPoint in points_on(map):
		var steps: int = (
			absi(point.cell.x - from_cell.x) + absi(point.cell.y - from_cell.y)
		)
		if best == null or steps < best_steps:
			best = point
			best_steps = steps

	if best == null:
		return null
	return Found.new(map.map_id, best.cell, best.facing)


## Every rest point on a map, at any depth.
##
## Grouped or loose, for the reason `VltWorldMap` gives about warps and zones:
## the editor draws one wherever it sits, so a camp tidied into a node has to
## count. Direct children only meant a map could have a camp drawn in the
## viewport and still report that a defeat there cannot recover.
static func points_on(map: VltWorldMap) -> Array[VltRestPoint]:
	var found: Array[VltRestPoint] = []
	if map == null:
		return found

	for node: Node in map.find_children("*", "", true, false):
		var point: VltRestPoint = node as VltRestPoint
		if point != null:
			found.append(point)
	return found
