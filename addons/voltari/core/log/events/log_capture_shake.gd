class_name VltLogCaptureShake
extends VltLogEvent

## One shake check passed.
##
## Informational: a shake changes nothing about the battle, so `apply` is a
## no-op — which spec 07 allows for exactly this, an event that is perceived
## without anything moving.
##
## One event per check rather than a count, because a shake is a beat and four
## of them are four beats. A log too coarse cannot be re-paced by the UI, and
## coarseness is not recoverable after the fact.

const KIND: String = "capture_shake"

var target: VltSlotRef = null

## Which shake this is, from one. Carried so a consumer never has to count
## events to know where it is in the sequence.
var ordinal: int = 1


static func create(slot: VltSlotRef, number: int) -> VltLogCaptureShake:
	var event: VltLogCaptureShake = VltLogCaptureShake.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.ordinal = number
	return event


func kind() -> String:
	return KIND


func _payload() -> Dictionary:
	return {"target": target.to_array(), "ordinal": ordinal}


static func from_dict(data: Dictionary) -> VltLogCaptureShake:
	var event: VltLogCaptureShake = VltLogCaptureShake.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.ordinal = data["ordinal"]
	return event
