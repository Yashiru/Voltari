class_name VltLogSwitchOut
extends VltLogEvent

## A slot was vacated. Applying it clears slot-scoped state, which is where
## stat stages go when a creature leaves (spec 03).

const KIND: String = "switch_out"

var target: VltSlotRef = null
var party_index: int = 0


static func create(slot: VltSlotRef, index: int) -> VltLogSwitchOut:
	var event: VltLogSwitchOut = VltLogSwitchOut.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.party_index = index
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.slot_at(target).vacate()


func _payload() -> Dictionary:
	return {"target": target.to_array(), "party_index": party_index}


static func from_dict(data: Dictionary) -> VltLogSwitchOut:
	var event: VltLogSwitchOut = VltLogSwitchOut.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.party_index = data["party_index"]
	return event
