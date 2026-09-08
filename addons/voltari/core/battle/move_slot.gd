class_name VltMoveSlot
extends RefCounted

## One of a creature's known moves, with its remaining PP.
##
## Creature scope (spec 03): PP survives switching and persists past the battle.

var move_id: String = ""
var pp: int = 0
var max_pp: int = 0


static func create(id: String, maximum: int) -> VltMoveSlot:
	var slot: VltMoveSlot = VltMoveSlot.new()
	slot.move_id = id
	slot.pp = maximum
	slot.max_pp = maximum
	return slot


func clone() -> VltMoveSlot:
	var copy: VltMoveSlot = VltMoveSlot.new()
	copy.move_id = move_id
	copy.pp = pp
	copy.max_pp = max_pp
	return copy


func to_dict() -> Dictionary:
	return {"move_id": move_id, "pp": pp, "max_pp": max_pp}


static func from_dict(data: Dictionary) -> VltMoveSlot:
	var slot: VltMoveSlot = VltMoveSlot.new()
	slot.move_id = data["move_id"]
	slot.pp = data["pp"]
	slot.max_pp = data["max_pp"]
	return slot
