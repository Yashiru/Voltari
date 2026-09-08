class_name VltLogDamage
extends VltLogEvent

## Damage dealt to a slot.
##
## Carries the resulting HP, not just the amount, so replay assigns rather than
## subtracts. TRANSFORMED: an opponent sees a percentage, never exact HP —
## which in a PvP context is not cosmetic but a cheating vector.

const KIND: String = "damage"
const REDUCED_SCALE: int = 100

var target: VltSlotRef = null
var amount: int = 0
var current_hp: int = 0
var max_hp: int = 1


static func create(slot: VltSlotRef, dealt: int, hp_after: int, hp_max: int) -> VltLogDamage:
	var event: VltLogDamage = VltLogDamage.new()
	event.visibility = Visibility.TRANSFORMED
	event.owner_side = slot.side
	event.target = slot
	event.amount = dealt
	event.current_hp = hp_after
	event.max_hp = hp_max
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	var creature: VltBattleCreature = state.creature_at(target)
	if creature != null:
		creature.current_hp = current_hp


## Rescaled to hundredths, the way the games show an opponent's health bar.
## Rounded up so a survivor never reads as zero.
func reduced() -> VltLogEvent:
	var event: VltLogDamage = VltLogDamage.new()
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


static func from_dict(data: Dictionary) -> VltLogDamage:
	var event: VltLogDamage = VltLogDamage.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.amount = data["amount"]
	event.current_hp = data["current_hp"]
	event.max_hp = data["max_hp"]
	return event
