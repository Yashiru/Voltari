class_name VltEventStep
extends Node

## One thing an event can do (spec 15, section 2; decision 0041).
##
## A node, so the composition of an event is the scene tree and nothing is ever
## parsed as a language. Behaviour is GDScript, here.
##
## **Each kind does exactly one thing.** A step that would need an `if` among its
## exported properties is a new kind, not a new property — spec 06 section 8,
## applied a second time.
##
## Three hooks, in this order. A step overrides the ones it needs and no more.

## What this step needs before it can act, or null when it needs nothing.
##
## Asked once. A step needing several answers is a sequence of steps, which is
## what keeps this a single suspension point rather than a state machine per
## kind.
func request(_run: VltEventRun) -> VltEventRequest:
	return null


## Do the work. `choice` is what came back, or 0 when nothing was requested.
##
## Flags set here land in the run's pending set, never in the world — the whole
## of decision 0044 rests on nothing here being visible until the run finishes.
func perform(_run: VltEventRun, _choice: int) -> void:
	pass


## The steps to run nested inside this one, innermost first. Empty for a leaf.
##
## This is where branching lives: a branch is a step that answers with one arm
## or the other, rather than a jump anything has to follow.
func children_to_run(_run: VltEventRun) -> Array[VltEventStep]:
	return []


## The `VltEventStep` children of a node, in tree order, skipping anything else.
##
## Shared because every composite kind needs it, and because a sequence that
## silently included a non-step child would be a bug nobody could see in the
## inspector.
static func steps_under(node: Node) -> Array[VltEventStep]:
	var found: Array[VltEventStep] = []
	if node == null:
		return found

	for child: Node in node.get_children():
		var step: VltEventStep = child as VltEventStep
		if step != null:
			found.append(step)
	return found
