class_name VltSetCounterStep
extends VltEventStep

## Move a named integer to a value (spec 15, section 3).
##
## A quest stage advances with this rather than by raising one more boolean —
## which is the difference between a stage that cannot contradict itself and five
## flags that can.
##
## Absolute, not relative. `+= 1` would make an event's effect depend on how many
## times it has run, and decision 0044 requires replaying an event from its start
## to be indistinguishable from running it once.

@export var flag: String = ""
@export var value: int = 0


func perform(run: VltEventRun, _choice: int) -> void:
	assert(not flag.is_empty(), "a set-counter step with no flag")
	run.pending.set_count(flag, value)
