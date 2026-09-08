class_name VltLogEffectiveness
extends VltLogEvent

## How well the move landed, as the type exponent.
##
## Purely informational: applying it changes nothing. It exists because the UI
## needs the beat — the effectiveness message lands before the health bar
## drains — and pacing is part of what the log has to carry (spec 07).

const KIND: String = "effectiveness"

var target: VltSlotRef = null
var exponent: int = 0


static func create(slot: VltSlotRef, type_exponent: int) -> VltLogEffectiveness:
	var event: VltLogEffectiveness = VltLogEffectiveness.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.exponent = type_exponent
	return event


func kind() -> String:
	return KIND


func _payload() -> Dictionary:
	return {"target": target.to_array(), "exponent": exponent}


static func from_dict(data: Dictionary) -> VltLogEffectiveness:
	var event: VltLogEffectiveness = VltLogEffectiveness.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.exponent = data["exponent"]
	return event
