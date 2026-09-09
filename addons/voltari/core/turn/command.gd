class_name VltCommand
extends RefCounted

## What one side submits for one slot, for one turn.
##
## A serialisable structure, never a method call (decision 0001). PvP is
## deferred, but the constraint is not: commands cross a network eventually, and
## retrofitting that would be a rewrite.

enum Kind {
	MOVE,
	SWITCH,
	CATCH,
}

var kind: Kind = Kind.MOVE
var actor: VltSlotRef = null

## MOVE: which of the actor's move slots, and the slot it targets.
var move_index: int = 0
var target: VltSlotRef = null

## SWITCH: which party member comes in.
var party_index: int = 0

## CATCH: the shake threshold the rules layer computed, and the target it was
## computed for. The core never learns what a ball is — it receives a number
## (spec 11, section 1).
var capture_threshold: int = 0


static func use_move(from: VltSlotRef, index: int, at: VltSlotRef) -> VltCommand:
	var command: VltCommand = VltCommand.new()
	command.kind = Kind.MOVE
	command.actor = from
	command.move_index = index
	command.target = at
	return command


static func switch_to(from: VltSlotRef, index: int) -> VltCommand:
	var command: VltCommand = VltCommand.new()
	command.kind = Kind.SWITCH
	command.actor = from
	command.party_index = index
	return command


static func throw_ball(from: VltSlotRef, at: VltSlotRef, threshold: int) -> VltCommand:
	var command: VltCommand = VltCommand.new()
	command.kind = Kind.CATCH
	command.actor = from
	command.target = at
	command.capture_threshold = threshold
	return command


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"actor": actor.to_array(),
		"move_index": move_index,
		"target": target.to_array() if target != null else PackedInt32Array(),
		"party_index": party_index,
		"capture_threshold": capture_threshold,
	}


static func from_dict(data: Dictionary) -> VltCommand:
	var command: VltCommand = VltCommand.new()
	command.kind = data["kind"]
	command.actor = VltSlotRef.from_array(PackedInt32Array(data["actor"]))
	command.move_index = data["move_index"]
	command.party_index = data["party_index"]
	command.capture_threshold = data["capture_threshold"]

	var target_data: PackedInt32Array = PackedInt32Array(data["target"])
	command.target = VltSlotRef.from_array(target_data) if target_data.size() == 2 else null
	return command
