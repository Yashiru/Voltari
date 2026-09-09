class_name VltBranchStep
extends VltEventStep

## Take one arm or the other, according to a flag (spec 15, section 2).
##
## This is the `if` that spec 09 refused to let into content — and it is allowed
## here because it is **a node, not a syntax**. There is nothing to parse, the
## condition is one named flag rather than an expression, and adding a second
## kind of condition means writing a second kind of node under review.
##
## The arms are assigned rather than inferred from child order. Positional arms
## would make reordering two nodes in the inspector silently invert the event.

## The boolean this reads. It sees what an earlier step in the same run set:
## reads consult the run first and the world second.
@export var flag: String = ""

@export var when_set: VltEventStep

@export var otherwise: VltEventStep


func children_to_run(run: VltEventRun) -> Array[VltEventStep]:
	assert(not flag.is_empty(), "a branch with no flag")

	var taken: VltEventStep = when_set if run.is_set(flag) else otherwise
	var arm: Array[VltEventStep] = []
	if taken != null:
		arm.append(taken)
	return arm


## An arm may legitimately be empty — "do nothing otherwise" is common — so only
## a branch with neither arm is incomplete.
func is_complete() -> bool:
	return not flag.is_empty() and (when_set != null or otherwise != null)
