class_name VltEvent
extends Node3D

## Something that happens at a place (spec 15, sections 1 and 4).
##
## A node on the map, with its steps as children. The composition is the event
## (decision 0041), so what an event does is read by opening it rather than by
## finding the file it was written in.
##
## **It fires at one of three discrete moments and never otherwise**
## (decision 0043). Nothing polls, and nothing watches a flag waiting for it to
## become true — which is what guarantees an event cannot start in the middle of
## another one, and therefore what makes the atomic commit mean anything.

enum Trigger {
	## The player faces this cell and asks.
	INTERACT,
	## The player steps onto this cell.
	ENTER_CELL,
	## The player arrives on this map, whatever cell they land on.
	ENTER_MAP,
}

@export var trigger: Trigger = Trigger.INTERACT

## Which cell. Ignored by ENTER_MAP, which has no place on the map.
@export var cell: Vector2i = Vector2i.ZERO


## The steps, in tree order.
func body() -> Array[VltEventStep]:
	return VltEventStep.steps_under(self)


func fires_at(at: Vector2i, on: Trigger) -> bool:
	if trigger != on:
		return false
	if on == Trigger.ENTER_MAP:
		return true
	return cell == at


func is_complete() -> bool:
	return not body().is_empty()
