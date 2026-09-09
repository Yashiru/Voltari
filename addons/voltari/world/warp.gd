class_name VltWarp
extends Node3D

## One cell that leads somewhere else (spec 14, section 7).
##
## A node on the map rather than a painted tile, because a warp carries
## something no grid can: where it goes. That destination lives in a *different
## file* from the warp, which is exactly the class of error a scene cannot catch
## by itself — hence the validation meta-test.
##
## **`to_map` is held in a save** only indirectly, but it names a map id, and map
## ids are stable and never reused (decision 0040).

## Which cell of this map triggers it.
@export var cell: Vector2i = Vector2i.ZERO

## The map it leads to, by id.
@export var to_map: String = ""

@export var to_cell: Vector2i = Vector2i.ZERO

## The direction the walker arrives turned. A warp that dropped the player facing
## the door they just came out of would send them straight back through it.
@export var to_facing: VltFacing.Direction = VltFacing.Direction.SOUTH


func is_complete() -> bool:
	return not to_map.is_empty()
