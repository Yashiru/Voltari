class_name VltFixtureEvent
extends RefCounted

## Events built in code, for the event tests (spec 15, section 9).
##
## Built rather than painted, for the reason the fixture maps are: a `.tscn`
## fixture has to be opened to be understood, and a test whose setup is invisible
## is a test nobody can check. These are the production node types, assembled the
## way the inspector would assemble them.


static func say(line_id: String) -> VltSayStep:
	var step: VltSayStep = VltSayStep.new()
	step.line_id = line_id
	return step


static func set_flag(flag: String, value: bool = true) -> VltSetFlagStep:
	var step: VltSetFlagStep = VltSetFlagStep.new()
	step.flag = flag
	step.value = value
	return step


static func set_counter(flag: String, value: int) -> VltSetCounterStep:
	var step: VltSetCounterStep = VltSetCounterStep.new()
	step.flag = flag
	step.value = value
	return step


static func sequence(of: Array[VltEventStep]) -> VltSequenceStep:
	var step: VltSequenceStep = VltSequenceStep.new()
	for child: VltEventStep in of:
		step.add_child(child)
	return step


## Arms are assigned, never positional — the same way the inspector does it.
static func branch(
	flag: String, when_set: VltEventStep = null, otherwise: VltEventStep = null
) -> VltBranchStep:
	var step: VltBranchStep = VltBranchStep.new()
	step.flag = flag
	step.when_set = when_set
	step.otherwise = otherwise

	# Arms are children too, so freeing the branch frees them. An arm assigned
	# but never parented would leak whenever the other arm was taken.
	if when_set != null:
		step.add_child(when_set)
	if otherwise != null:
		step.add_child(otherwise)
	return step


static func event(
	steps: Array[VltEventStep],
	trigger: VltEvent.Trigger = VltEvent.Trigger.INTERACT,
	cell: Vector2i = Vector2i.ZERO
) -> VltEvent:
	var built: VltEvent = VltEvent.new()
	built.trigger = trigger
	built.cell = cell
	for step: VltEventStep in steps:
		built.add_child(step)
	return built
