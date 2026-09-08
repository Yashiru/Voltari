class_name VltLogFaint
extends VltLogEvent

## A slot's occupant fell. Public: nothing about it is hidden.

const KIND: String = "faint"

var target: VltSlotRef = null


static func create(slot: VltSlotRef) -> VltLogFaint:
	var event: VltLogFaint = VltLogFaint.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	var creature: VltBattleCreature = state.creature_at(target)
	if creature != null:
		creature.current_hp = 0


func _payload() -> Dictionary:
	return {"target": target.to_array()}


static func from_dict(data: Dictionary) -> VltLogFaint:
	var event: VltLogFaint = VltLogFaint.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	return event
