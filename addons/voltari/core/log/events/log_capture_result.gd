class_name VltLogCaptureResult
extends VltLogEvent

## How the throw ended.
##
## Carries `party_index` because the state does not: a captured creature leaves
## the field and nothing marks it. **The log is how the rules layer learns which
## creature it caught** — chosen over adding a marker to the battle state, which
## would be one more thing to serialise, clone and replay for a fact the log
## already records (spec 11).
##
## On success the slot empties, which is a state change and so travels here as a
## resulting value like any other.

const KIND: String = "capture_result"

var target: VltSlotRef = null
var captured: bool = false

## Which party member was in the slot. Meaningful whether or not it was caught,
## so a consumer can name the creature that escaped as well as the one that did
## not.
var party_index: int = 0


static func create(slot: VltSlotRef, index: int, succeeded: bool) -> VltLogCaptureResult:
	var event: VltLogCaptureResult = VltLogCaptureResult.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.party_index = index
	event.captured = succeeded
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	if captured:
		state.slot_at(target).vacate()


func _payload() -> Dictionary:
	return {
		"target": target.to_array(),
		"party_index": party_index,
		"captured": captured,
	}


static func from_dict(data: Dictionary) -> VltLogCaptureResult:
	var event: VltLogCaptureResult = VltLogCaptureResult.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.party_index = data["party_index"]
	event.captured = data["captured"]
	return event
