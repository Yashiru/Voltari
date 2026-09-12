class_name VltFreeWalker
extends Node3D

## Where the player is, and what moving does (spec 14, section 2).
##
## **The position is continuous and the rules are not.** The player goes where
## they like, in metres; the cell their **origin** falls in is what every rule
## reads. That split is the whole design: nothing below has to know that movement
## stopped being discrete, because a cell is still a cell.
##
## ## What replaced "a step"
##
## Spec 14 used to lock movement to the grid, and argued that free movement would
## turn an encounter check into "a distance threshold — a constant with no
## defensible value". It does not, and the reason is that there was never a need
## for a distance at all: the trigger is **the occupied cell changing**. Warps,
## events and encounters keep the rule and the order they always had, fired by
## crossing a boundary instead of by a discrete step. No new constant exists.
##
## ## What stops you
##
## A radius, and the cells under it. Each axis is tried separately, so a player
## walking into a wall at an angle slides along it rather than stopping dead —
## which falls out of the order rather than being written. **No physics body and
## no collision shapes** (spec 14, section 1): what stops you is still the
## painted blocking layer, read as a lookup.
##
## The body is a disc and the cells it touches must all be walkable. The origin
## decides *which cell you are in*; the radius decides *where you may be*. Those
## are different questions and giving them one answer is what makes a character
## either clip through corners or refuse to enter a corridor.

## Everything one move produced. A move always produces one of these, including
## the move that went nowhere.
class Move:
	extends RefCounted

	## Whether the position changed at all.
	var moved: bool = false

	## Whether either axis was refused. A slide along a wall is both `moved` and
	## `blocked`, which is exactly what it is.
	var blocked: bool = false

	## The cell the origin is now in.
	var cell: Vector2i = Vector2i.ZERO

	## Whether that cell is not the one it was. Everything below only ever
	## happens on a move where this is true.
	var entered: bool = false

	## The warp under the new cell, or null.
	var warp: VltWarp = null

	## The event the new cell triggers, or null. Never set on a move that landed
	## on a warp.
	var event: VltEvent = null

	## What appeared, or null. Never set on a move that landed on a warp or
	## triggered an event.
	var encounter: VltEncounter.Outcome = null

	func started_a_battle() -> bool:
		return encounter != null


## How much room the player takes, in metres.
##
## Half a person, near enough: the character is 0.9 m across the shoulders and
## 0.64 m front to back. It has to stay under half a cell or a one-cell corridor
## would refuse to admit anybody.
const RADIUS: float = 0.3

## Where the player is, in the map's own space. Metres, not cells.
@export var spot: Vector2 = Vector2.ZERO

## The way they are pointed, as a unit vector. Continuous, because movement is:
## the four-way `facing` is derived from it and never stored.
@export var heading: Vector2 = Vector2(0.0, 1.0)

var map: VltWorldMap = null

## Tables by content id, as loaded. Absent ids are a content error the
## validation meta-test catches; here they simply produce no encounter, because
## refusing at runtime would be refusing in front of a player.
var tables: Dictionary[String, VltEncounterTable] = {}

## Absent means encounters are off — cutscenes, menus, and the movement tests
## that have no business drawing anything.
var encounter_decider: VltEncounterDecider = null


## The cell the origin falls in. **What every rule reads.**
func cell() -> Vector2i:
	if map == null:
		return Vector2i(int(floor(spot.x)), int(floor(spot.y)))
	return map.cell_at(Vector3(spot.x, 0.0, spot.y))


## The heading, reduced to the four the world stores.
##
## Warps, rest points and interaction all speak in four directions, and the
## dominant axis is what a heading means in that vocabulary. Derived rather than
## kept, so the two can never disagree.
func facing() -> VltFacing.Direction:
	if absf(heading.x) > absf(heading.y):
		return VltFacing.Direction.EAST if heading.x > 0.0 else VltFacing.Direction.WEST
	return VltFacing.Direction.SOUTH if heading.y > 0.0 else VltFacing.Direction.NORTH


## Moves by a displacement in metres, and reports what that ran into.
##
## Each axis is tried on its own. Walking into a wall at an angle therefore
## slides along it: the axis that is refused stays put and the other one goes
## through. Trying the whole vector at once would stop the player dead against
## every wall they were not exactly square to.
func move(by: Vector2) -> Move:
	var result: Move = Move.new()
	var was: Vector2i = cell()

	if by.length_squared() > 0.0:
		heading = by.normalized()

	var wanted: Vector2 = spot + by
	if not _fits(wanted):
		result.blocked = true
		wanted = _slid(by)

	result.moved = not wanted.is_equal_approx(spot)
	spot = wanted

	result.cell = cell()
	result.entered = result.cell != was
	if not result.entered:
		return result

	# The order a step always had. A cell that both warps and holds an event is
	# a warp: you are gone before the event could run.
	result.warp = map.warp_at(result.cell) if map != null else null
	if result.warp != null and result.warp.is_complete():
		return result
	result.warp = null

	result.event = map.event_at(result.cell, VltEvent.Trigger.ENTER_CELL) if map != null else null
	if result.event != null:
		return result

	result.encounter = _encounter_at(result.cell)
	return result


## Puts the player on a cell, facing a direction, without moving them there.
##
## What arriving needs: a warp, a load, a defeat. The centre of the cell, because
## a cell is the only thing those three know how to say.
func place(at: Vector2i, turned: VltFacing.Direction) -> void:
	var centre: Vector3 = map.centre_of(at) if map != null else Vector3(at.x, 0.0, at.y)
	spot = Vector2(centre.x, centre.z)
	heading = Vector2(VltFacing.DELTAS[turned])


## The event in front of the player, or null.
##
## **Walkability is ignored on purpose.** A sign is something you face, not
## something you stand on, and requiring the faced cell to be standable would
## make every sign and every NPC unreachable.
func interact() -> VltEvent:
	if map == null:
		return null
	var ahead: Vector2i = cell() + VltFacing.DELTAS[facing()]
	return map.event_at(ahead, VltEvent.Trigger.INTERACT)


## Whether the player's body fits at a point.
##
## The four corners of the box around the disc, because a disc that overlapped a
## blocked cell only diagonally would still be inside it. Checking the origin
## alone is what lets a character stand halfway inside a wall.
## Where a refused move gets to by following whatever refused it.
##
## **The surface first.** The part of the move that runs into the shape is taken
## out and the rest goes through, so a wall met at any angle is walked along
## rather than into. Square to it there is nothing left to keep, and that is the
## one case that stops you dead — which is the rule, not a consequence of it.
##
## **Then the axes**, for the things that have no surface: the edge of the map,
## and a cell blocked whole. Those are square to the grid by construction, so
## dropping the refused axis is the same answer reached without a normal.
func _slid(by: Vector2) -> Vector2:
	if map != null:
		var normal: Vector2 = map.surface_at(spot + by, RADIUS)
		if not normal.is_zero_approx():
			var along: Vector2 = by - normal * by.dot(normal)
			if along.length_squared() > 0.0 and _fits(spot + along):
				return spot + along

	var wanted: Vector2 = spot
	for axis: Vector2 in [Vector2(by.x, 0.0), Vector2(0.0, by.y)]:
		if axis.length_squared() > 0.0 and _fits(wanted + axis):
			wanted += axis
	return wanted


func _fits(at: Vector2) -> bool:
	if map == null:
		return true

	# The grid part: off the map, or a cell something claims whole. Four corners is
	# enough for a question whose answer is the same everywhere in a cell.
	for corner: Vector2 in [
		Vector2(-RADIUS, -RADIUS),
		Vector2(RADIUS, -RADIUS),
		Vector2(RADIUS, RADIUS),
		Vector2(-RADIUS, RADIUS),
	]:
		var point: Vector2 = at + corner
		if not map.is_open(map.cell_at(Vector3(point.x, 0.0, point.y))):
			return false

	# The shapes: the whole disc against them, not four points on it. Corners were
	# enough while nothing was thinner than a cell; a five centimetre post fits
	# between two of them and would be walked straight through.
	return not map.blocked_at(at, RADIUS)


func _encounter_at(where: Vector2i) -> VltEncounter.Outcome:
	if map == null or encounter_decider == null:
		return null

	var zone: VltEncounterZone = map.zone_at(where)
	if zone == null or not tables.has(zone.table_id):
		return null

	var table: VltEncounterTable = tables[zone.table_id]
	if not VltEncounter.occurs(table, encounter_decider):
		return null
	return VltEncounter.draw(table, encounter_decider)
