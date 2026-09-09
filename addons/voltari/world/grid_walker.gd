class_name VltGridWalker
extends Node3D

## Where the player is, and what one step does (spec 14, section 2).
##
## Movement is locked to the grid. Rendering interpolates between cells and the
## rigged characters animate through the step (decision 0020), so it looks
## continuous — the logic is discrete, and that is what gives **a step** a
## beginning and an end for an encounter check to happen per.
##
## This is the join between the engine-native half of the overworld and the pure
## half: the map answers what is walkable, `VltEncounter` answers what appears,
## and neither knows about the other.

## Everything one step produced. A step always produces one of these, including
## the step that went nowhere.
class Step:
	extends RefCounted

	## False when a wall or the edge of the map refused it. The walker still
	## turned — see `VltGridWalker.step`.
	var moved: bool = false

	var cell: Vector2i = Vector2i.ZERO
	var facing: VltFacing.Direction = VltFacing.Direction.SOUTH

	## The warp the step landed on, or null.
	var warp: VltWarp = null

	## The event the step landed on, or null. Never set on a step that did not
	## move, and never on a step that landed on a warp.
	var event: VltEvent = null

	## What appeared, or null. Never set on a step that did not move, on a step
	## that landed on a warp, or on a step that triggered an event.
	var encounter: VltEncounter.Outcome = null

	func started_a_battle() -> bool:
		return encounter != null


@export var cell: Vector2i = Vector2i.ZERO
@export var facing: VltFacing.Direction = VltFacing.Direction.SOUTH

var map: VltWorldMap = null

## Tables by content id, as loaded. Absent ids are a content error the
## validation meta-test catches; here they simply produce no encounter, because
## refusing at runtime would be refusing in front of a player.
var tables: Dictionary[String, VltEncounterTable] = {}

## Absent means encounters are off — cutscenes, menus, and the movement tests
## that have no business drawing anything.
var encounter_decider: VltEncounterDecider = null


## One step in a direction.
##
## **Turning happens even when the step is refused.** That is the behaviour most
## easily lost in a refactor, because from outside a blocked step and a step that
## did nothing look identical.
func step(direction: VltFacing.Direction) -> Step:
	var result: Step = Step.new()
	facing = direction
	result.facing = direction

	var target: Vector2i = cell + VltFacing.delta(direction)
	if map == null or not map.is_walkable(target):
		result.cell = cell
		return result

	cell = target
	result.cell = target
	result.moved = true

	# A warp is leaving, so nothing else happens on the way out. An encounter or
	# an event fired on the same step would land on a map the player has left.
	result.warp = map.warp_at(target)
	if result.warp != null:
		return result

	# A scripted trigger beats an ambient one. Both firing would open a dialogue
	# and a battle at once, and something has to lose — the deliberate thing is
	# not the one to drop.
	result.event = map.event_at(target, VltEvent.Trigger.ENTER_CELL)
	if result.event != null:
		return result

	result.encounter = _encounter_at(target)
	return result


## The event on the cell the walker faces, or null.
##
## Interacting is its own moment (decision 0043), separate from stepping: the
## player asks, rather than the world noticing.
func interact() -> VltEvent:
	if map == null:
		return null
	return map.event_at(cell + VltFacing.delta(facing), VltEvent.Trigger.INTERACT)


## Only inside a zone, and only on a step that actually moved. Standing still in
## tall grass draws nothing, which is the whole reason the check is per step.
func _encounter_at(where: Vector2i) -> VltEncounter.Outcome:
	if encounter_decider == null or map == null:
		return null

	var zone: VltEncounterZone = map.zone_at(where)
	if zone == null or not tables.has(zone.table_id):
		return null

	var table: VltEncounterTable = tables[zone.table_id]
	if not VltEncounter.occurs(table, encounter_decider):
		return null
	return VltEncounter.draw(table, encounter_decider)


## Puts the walker somewhere without walking there: a warp's far end, a loaded
## save, the start of a new game.
func place(at: Vector2i, turned: VltFacing.Direction) -> void:
	cell = at
	facing = turned
