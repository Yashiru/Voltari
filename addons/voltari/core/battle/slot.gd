class_name VltSlot
extends RefCounted

## A position on the field, and the state attached to occupying it.
##
## Slot scope (spec 03): everything here clears when the occupant leaves. Stat
## stages live here, not on the creature, which is exactly why switching resets
## them without anyone having to remember to do it.
##
## A slot holds a party index, never a creature: it designates a position, and
## the creature it points at changes.

const EMPTY: int = -1
const STAGE_LIMIT: int = 6

var occupant: int = EMPTY
var stat_stages: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	stat_stages.resize(VltStats.STAT_COUNT)


func is_empty() -> bool:
	return occupant == EMPTY


## Clears slot-scoped state. Called when the occupant leaves, whatever the
## reason — switching, fainting, or being dragged out.
func vacate() -> void:
	occupant = EMPTY
	for stat: int in range(VltStats.STAT_COUNT):
		stat_stages[stat] = 0


func occupy(party_index: int) -> void:
	assert(party_index >= 0, "occupy() needs a party index; use vacate() to empty a slot")
	vacate()
	occupant = party_index


func set_stage(stat: int, value: int) -> void:
	stat_stages[stat] = clampi(value, -STAGE_LIMIT, STAGE_LIMIT)


func clone() -> VltSlot:
	var copy: VltSlot = VltSlot.new()
	copy.occupant = occupant
	copy.stat_stages = stat_stages.duplicate()
	return copy


func to_dict() -> Dictionary:
	return {"occupant": occupant, "stat_stages": stat_stages}


static func from_dict(data: Dictionary) -> VltSlot:
	var slot: VltSlot = VltSlot.new()
	slot.occupant = data["occupant"]
	slot.stat_stages = PackedInt32Array(data["stat_stages"])
	return slot
