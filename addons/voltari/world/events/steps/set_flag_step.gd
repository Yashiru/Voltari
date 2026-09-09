class_name VltSetFlagStep
extends VltEventStep

## Raise or lower a named boolean (spec 15, section 3).
##
## It writes into the run's pending set, never into the world. Nothing this step
## does is visible until the event finishes, which is the whole of decision 0044
## expressed in one line.

@export var flag: String = ""

## False is set as deliberately as true. A step that treated lowering as "nothing
## to say" would make a flag impossible to clear.
@export var value: bool = true


func perform(run: VltEventRun, _choice: int) -> void:
	assert(not flag.is_empty(), "a set-flag step with no flag")
	if value:
		run.pending.raise(flag)
	else:
		run.pending.lower(flag)
