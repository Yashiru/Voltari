class_name VltTurnOutcome
extends RefCounted

## What resolving a turn produced.
##
## Either the turn finished, or it stopped to ask for input it could not have
## been given up front — a replacement depends on what just happened in the turn
## (decision 0012). Or the commands were rejected, in which case nothing ran and
## the state is untouched.

enum Status {
	COMPLETE,
	NEEDS_INPUT,
	REJECTED,
}

enum RequestKind {
	NONE,
	## Slots whose occupant fainted and must be replaced before the turn ends.
	REPLACEMENT,
}

var status: Status = Status.COMPLETE
var state: VltBattleState = null
var log: VltBattleLog = null

var request_kind: RequestKind = RequestKind.NONE
var request_slots: Array[VltSlotRef] = []

## Why the commands were refused. Empty unless REJECTED.
var rejection: String = ""


static func complete(final_state: VltBattleState, produced: VltBattleLog) -> VltTurnOutcome:
	var outcome: VltTurnOutcome = VltTurnOutcome.new()
	outcome.status = Status.COMPLETE
	outcome.state = final_state
	outcome.log = produced
	return outcome


static func needs_input(
	current: VltBattleState, produced: VltBattleLog, slots: Array[VltSlotRef]
) -> VltTurnOutcome:
	assert(not slots.is_empty(), "a request that names no slot cannot be answered")
	var outcome: VltTurnOutcome = VltTurnOutcome.new()
	outcome.status = Status.NEEDS_INPUT
	outcome.state = current
	outcome.log = produced
	outcome.request_kind = RequestKind.REPLACEMENT
	outcome.request_slots = slots
	return outcome


## The caller's state is never touched on rejection: an illegal command produces
## an error, never a corrupted battle (decision 0013).
static func rejected(reason: String) -> VltTurnOutcome:
	var outcome: VltTurnOutcome = VltTurnOutcome.new()
	outcome.status = Status.REJECTED
	outcome.rejection = reason
	outcome.log = VltBattleLog.new()
	return outcome


func is_complete() -> bool:
	return status == Status.COMPLETE
