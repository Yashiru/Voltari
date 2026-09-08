class_name VltSlotRef
extends RefCounted

## Designates a position on the field: (side, slot).
##
## A position, never a creature. A move targets a slot; a burn belongs to a
## creature and follows it out of the battle (spec 03). Conflating the two
## breaks the moment anything switches, so they are distinct types.

var side: int = 0
var slot: int = 0


static func at(side_index: int, slot_index: int) -> VltSlotRef:
	var reference: VltSlotRef = VltSlotRef.new()
	reference.side = side_index
	reference.slot = slot_index
	return reference


func equals(other: VltSlotRef) -> bool:
	return other != null and side == other.side and slot == other.slot


func to_array() -> PackedInt32Array:
	return PackedInt32Array([side, slot])


static func from_array(data: PackedInt32Array) -> VltSlotRef:
	assert(data.size() == 2, "a slot reference serialises as exactly two indices")
	return VltSlotRef.at(data[0], data[1])


func _to_string() -> String:
	return "slot(%d,%d)" % [side, slot]
