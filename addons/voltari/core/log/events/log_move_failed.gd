class_name VltLogMoveFailed
extends VltLogEvent

## A move did not connect, and why.
##
## A miss, an immunity and a move with nothing to target are three different
## things to a player, and they read differently on screen. Collapsing them into
## one "nothing happened" would cost the UI information it cannot recover.

const KIND: String = "move_failed"

enum Reason {
	MISSED,
	IMMUNE,
	NO_TARGET,
}

var actor: VltSlotRef = null
var reason: Reason = Reason.MISSED


static func create(from: VltSlotRef, why: Reason) -> VltLogMoveFailed:
	var event: VltLogMoveFailed = VltLogMoveFailed.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = from.side
	event.actor = from
	event.reason = why
	return event


func kind() -> String:
	return KIND


func _payload() -> Dictionary:
	return {"actor": actor.to_array(), "reason": reason}


static func from_dict(data: Dictionary) -> VltLogMoveFailed:
	var event: VltLogMoveFailed = VltLogMoveFailed.new()
	event._read_common(data)
	event.actor = VltSlotRef.from_array(PackedInt32Array(data["actor"]))
	event.reason = data["reason"]
	return event
