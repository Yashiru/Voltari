class_name VltLogMoveUsed
extends VltLogEvent

## A slot used a move.
##
## Carries the resulting PP, because using a move spends it and invariant 8
## admits no state change without an event. That is not bookkeeping: the first
## version of this class omitted PP and the replay test caught it immediately.
##
## TRANSFORMED, since an opponent does not learn your exact PP. Their filtered
## replay simply does not track it, which is correct — they cannot observe it.

const KIND: String = "move_used"

## PP the viewer is not entitled to know.
const UNKNOWN_PP: int = -1

var actor: VltSlotRef = null
var move_id: String = ""
var move_index: int = 0
var pp_after: int = UNKNOWN_PP
var target: VltSlotRef = null


static func create(
	from: VltSlotRef, move: String, index: int, pp_remaining: int, at: VltSlotRef
) -> VltLogMoveUsed:
	var event: VltLogMoveUsed = VltLogMoveUsed.new()
	event.visibility = Visibility.TRANSFORMED
	event.owner_side = from.side
	event.actor = from
	event.move_id = move
	event.move_index = index
	event.pp_after = pp_remaining
	event.target = at
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	if pp_after == UNKNOWN_PP:
		return
	var creature: VltBattleCreature = state.creature_at(actor)
	if creature != null and move_index < creature.moves.size():
		creature.moves[move_index].pp = pp_after


func reduced() -> VltLogEvent:
	var event: VltLogMoveUsed = VltLogMoveUsed.new()
	event.visibility = visibility
	event.owner_side = owner_side
	event.actor = actor
	event.move_id = move_id
	event.move_index = move_index
	event.pp_after = UNKNOWN_PP
	event.target = target
	return event


func _payload() -> Dictionary:
	return {
		"actor": actor.to_array(),
		"move_id": move_id,
		"move_index": move_index,
		"pp_after": pp_after,
		"target": target.to_array() if target != null else PackedInt32Array(),
	}


static func from_dict(data: Dictionary) -> VltLogMoveUsed:
	var event: VltLogMoveUsed = VltLogMoveUsed.new()
	event._read_common(data)
	event.actor = VltSlotRef.from_array(PackedInt32Array(data["actor"]))
	event.move_id = data["move_id"]
	event.move_index = data["move_index"]
	event.pp_after = data["pp_after"]
	var target_data: PackedInt32Array = PackedInt32Array(data["target"])
	event.target = VltSlotRef.from_array(target_data) if target_data.size() == 2 else null
	return event
