class_name VltLogPendingInput
extends VltLogEvent

## The set of slots awaiting input is now this.
##
## Carries the resulting set rather than a request or an answer, like every
## other event: replay assigns it instead of tracking a protocol. An empty set
## means nothing is pending.
##
## It exists because the fuzzer found its absence. Suspending a turn writes
## `awaiting_replacement` into the state (decision 0012), and nothing recorded
## that, so replaying the log produced a state that had forgotten it was waiting
## — a divergence no hand-written test had reached.

const KIND: String = "pending_input"

var slots: Array[VltSlotRef] = []


static func create(pending: Array[VltSlotRef]) -> VltLogPendingInput:
	var event: VltLogPendingInput = VltLogPendingInput.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = NO_SIDE
	for reference: VltSlotRef in pending:
		event.slots.append(VltSlotRef.at(reference.side, reference.slot))
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.awaiting_replacement = []
	for reference: VltSlotRef in slots:
		state.awaiting_replacement.append(VltSlotRef.at(reference.side, reference.slot))


func _payload() -> Dictionary:
	var serialised: Array = []
	for reference: VltSlotRef in slots:
		serialised.append(reference.to_array())
	return {"slots": serialised}


static func from_dict(data: Dictionary) -> VltLogPendingInput:
	var event: VltLogPendingInput = VltLogPendingInput.new()
	event._read_common(data)
	for entry: Variant in data["slots"]:
		event.slots.append(VltSlotRef.from_array(PackedInt32Array(entry)))
	return event
