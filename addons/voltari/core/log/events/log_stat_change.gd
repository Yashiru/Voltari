class_name VltLogStatChange
extends VltLogEvent

## A stat stage moved. Carries the resulting stage, not the delta, so replay
## assigns — and so a stage clamped at its limit reads correctly rather than
## drifting past it.

const KIND: String = "stat_change"

var target: VltSlotRef = null
var stat: int = 0
var delta: int = 0
var stage_after: int = 0


static func create(slot: VltSlotRef, which: int, change: int, resulting: int) -> VltLogStatChange:
	var event: VltLogStatChange = VltLogStatChange.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.stat = which
	event.delta = change
	event.stage_after = resulting
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.slot_at(target).set_stage(stat, stage_after)


func _payload() -> Dictionary:
	return {
		"target": target.to_array(),
		"stat": stat,
		"delta": delta,
		"stage_after": stage_after,
	}


static func from_dict(data: Dictionary) -> VltLogStatChange:
	var event: VltLogStatChange = VltLogStatChange.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.stat = data["stat"]
	event.delta = data["delta"]
	event.stage_after = data["stage_after"]
	return event
