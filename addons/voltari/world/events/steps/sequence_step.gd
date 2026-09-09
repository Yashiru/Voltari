class_name VltSequenceStep
extends VltEventStep

## Run the steps under this node, in order (spec 15, section 2).
##
## It does nothing itself. It exists so that a branch's arm can hold more than
## one step, and so that a long event can be grouped into parts that read as
## parts.

func children_to_run(_run: VltEventRun) -> Array[VltEventStep]:
	return VltEventStep.steps_under(self)
