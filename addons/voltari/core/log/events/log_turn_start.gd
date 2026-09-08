class_name VltLogTurnStart
extends VltLogEvent

## A new turn began. Field-level, so it belongs to no side.

const KIND: String = "turn_start"

var number: int = 0


static func create(turn: int) -> VltLogTurnStart:
	var event: VltLogTurnStart = VltLogTurnStart.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = NO_SIDE
	event.number = turn
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.turn = number


func _payload() -> Dictionary:
	return {"number": number}


static func from_dict(data: Dictionary) -> VltLogTurnStart:
	var event: VltLogTurnStart = VltLogTurnStart.new()
	event._read_common(data)
	event.number = data["number"]
	return event
