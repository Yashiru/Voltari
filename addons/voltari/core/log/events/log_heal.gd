class_name VltLogHeal
extends VltLogEvent

## HP restored to a slot. Same reduction rule as damage.

const KIND: String = "heal"
const REDUCED_SCALE: int = 100

var target: VltSlotRef = null
var amount: int = 0
var current_hp: int = 0
var max_hp: int = 1


static func create(slot: VltSlotRef, restored: int, hp_after: int, hp_max: int) -> VltLogHeal:
	var event: VltLogHeal = VltLogHeal.new()
	event.visibility = Visibility.TRANSFORMED
	event.owner_side = slot.side
	event.target = slot
	event.amount = restored
	event.current_hp = hp_after
	event.max_hp = hp_max
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	var creature: VltBattleCreature = state.creature_at(target)
	if creature != null:
		creature.current_hp = current_hp


func reduced() -> VltLogEvent:
	var event: VltLogHeal = VltLogHeal.new()
	event.visibility = visibility
	event.owner_side = owner_side
	event.target = target
	event.max_hp = REDUCED_SCALE
	event.current_hp = _scaled(current_hp)
	event.amount = _scaled(amount)
	return event


func _scaled(value: int) -> int:
	if value <= 0:
		return 0
	return maxi(1, value * REDUCED_SCALE / max_hp)


func _payload() -> Dictionary:
	return {
		"target": target.to_array(),
		"amount": amount,
		"current_hp": current_hp,
		"max_hp": max_hp,
	}


static func from_dict(data: Dictionary) -> VltLogHeal:
	var event: VltLogHeal = VltLogHeal.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.amount = data["amount"]
	event.current_hp = data["current_hp"]
	event.max_hp = data["max_hp"]
	return event
