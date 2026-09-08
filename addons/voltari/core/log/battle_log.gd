class_name VltBattleLog
extends RefCounted

## The ordered event stream a battle produces.
##
## Events are appended in resolution order and never reordered. In Gen 4 that is
## already presentation order — the game resolves and presents in lockstep — so
## the core needs no knowledge of the UI (decision 0016).

## Every event kind the log can carry. Deserialisation dispatches on it, and a
## meta-test asserts every entry round-trips, so a kind added without its
## deserialiser fails a test rather than losing data silently.
const KINDS: Array[String] = [
	VltLogTurnStart.KIND,
	VltLogSwitchIn.KIND,
	VltLogSwitchOut.KIND,
	VltLogDamage.KIND,
	VltLogHeal.KIND,
	VltLogFaint.KIND,
	VltLogStatChange.KIND,
	VltLogEffectiveness.KIND,
	VltLogMoveUsed.KIND,
	VltLogMoveFailed.KIND,
	VltLogPendingInput.KIND,
	VltLogEffectChanged.KIND,
]

var events: Array[VltLogEvent] = []


func append(event: VltLogEvent) -> void:
	events.append(event)


func size() -> int:
	return events.size()


func is_empty() -> bool:
	return events.is_empty()


## Replays the whole stream onto a state. Invariant 8 of spec 05: applied to the
## state the battle started from, this must reproduce the state it ended in.
func replay_onto(state: VltBattleState) -> void:
	for event: VltLogEvent in events:
		event.apply(state)


## What one side is entitled to see: hidden events dropped, transformed events
## reduced. Replaying a filtered log reproduces the state observable by that
## viewer, which is what makes the filtering testable rather than hand-checked.
func for_viewer(side: int) -> VltBattleLog:
	var filtered: VltBattleLog = VltBattleLog.new()
	for event: VltLogEvent in events:
		var visible: VltLogEvent = event.for_viewer(side)
		if visible != null:
			filtered.append(visible)
	return filtered


func to_array() -> Array:
	var data: Array = []
	for event: VltLogEvent in events:
		data.append(event.to_dict())
	return data


static func from_array(data: Array) -> VltBattleLog:
	var log: VltBattleLog = VltBattleLog.new()
	for entry: Variant in data:
		log.append(event_from_dict(entry))
	return log


static func event_from_dict(data: Dictionary) -> VltLogEvent:
	match String(data["kind"]):
		VltLogTurnStart.KIND:
			return VltLogTurnStart.from_dict(data)
		VltLogSwitchIn.KIND:
			return VltLogSwitchIn.from_dict(data)
		VltLogSwitchOut.KIND:
			return VltLogSwitchOut.from_dict(data)
		VltLogDamage.KIND:
			return VltLogDamage.from_dict(data)
		VltLogHeal.KIND:
			return VltLogHeal.from_dict(data)
		VltLogFaint.KIND:
			return VltLogFaint.from_dict(data)
		VltLogStatChange.KIND:
			return VltLogStatChange.from_dict(data)
		VltLogEffectiveness.KIND:
			return VltLogEffectiveness.from_dict(data)
		VltLogMoveUsed.KIND:
			return VltLogMoveUsed.from_dict(data)
		VltLogMoveFailed.KIND:
			return VltLogMoveFailed.from_dict(data)
		VltLogPendingInput.KIND:
			return VltLogPendingInput.from_dict(data)
		VltLogEffectChanged.KIND:
			return VltLogEffectChanged.from_dict(data)

	assert(false, "no deserialiser for log event kind \"%s\"" % data["kind"])
	return null
