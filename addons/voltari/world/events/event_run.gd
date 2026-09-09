class_name VltEventRun
extends RefCounted

## One playing of an event (spec 15, section 5; decision 0044).
##
## Suspendable rather than coroutine-driven, the same shape the turn engine
## already uses (decision 0012): it advances until it needs something, says what,
## and is resumed with the answer. Synchronous, so it is testable without a scene
## and without a frame.
##
## **Flags land only when it finishes.** Everything a step sets goes into
## `pending`, which is merged into the world in one call at the end. A run that
## is abandoned — the application killed mid-cutscene, which on mobile it will
## be — leaves nothing behind.
##
## Unlike a turn, **a run's position is not serialisable and does not need to
## be**: nothing may save while an event is running, so there is no state to
## carry across a session. That is the simplification decision 0044 bought.

## Where a run is, one frame per nesting level.
class Frame:
	extends RefCounted

	var steps: Array[VltEventStep] = []
	var index: int = 0

	func _init(of: Array[VltEventStep]) -> void:
		steps = of

	func done() -> bool:
		return index >= steps.size()

	func current() -> VltEventStep:
		return steps[index]


## Changes this run has made, visible to its own branches and to nothing else
## until it finishes.
var pending: VltQuestFlags = VltQuestFlags.new()

var _world: VltQuestFlags
var _frames: Array[Frame] = []
var _waiting: VltEventStep = null
var _request: VltEventRequest = null
var _finished: bool = false


func _init(body: Array[VltEventStep], world_flags: VltQuestFlags) -> void:
	_world = world_flags if world_flags != null else VltQuestFlags.new()
	if not body.is_empty():
		_frames.append(Frame.new(body))
	_finished = _frames.is_empty()


static func of(event: VltEvent, world_flags: VltQuestFlags) -> VltEventRun:
	return VltEventRun.new(event.body(), world_flags)


# --- reading flags -----------------------------------------------------------
#
# A branch must see what an earlier step in the same run set, or an event could
# not set a flag and then act on it. So reads consult this run first and the
# world second — and the world never sees the run's changes until the end.


func is_set(flag: String) -> bool:
	if pending.switch_names().has(flag):
		return pending.is_set(flag)
	return _world.is_set(flag)


func count(flag: String) -> int:
	if pending.counter_names().has(flag):
		return pending.count(flag)
	return _world.count(flag)


# --- driving -----------------------------------------------------------------


func is_finished() -> bool:
	return _finished


## What the run is waiting for, or null when it is not waiting.
func request() -> VltEventRequest:
	return _request


## Runs until something is needed or the event ends. Safe to call again while
## waiting: it does nothing until the request is answered.
func advance() -> void:
	while not _finished and _request == null:
		_advance_one()


## Answers the outstanding request and carries on.
func resume(choice: int = 0) -> void:
	assert(_request != null, "nothing was asked for")
	var step: VltEventStep = _waiting
	_request = null
	_waiting = null

	step.perform(self, choice)
	_enter(step)
	advance()


func _advance_one() -> void:
	var frame: Frame = _frames[_frames.size() - 1]
	if frame.done():
		_frames.pop_back()
		if _frames.is_empty():
			_finish()
		return

	var step: VltEventStep = frame.current()
	frame.index += 1

	var asked: VltEventRequest = step.request(self)
	if asked != null:
		_waiting = step
		_request = asked
		return

	step.perform(self, 0)
	_enter(step)


## Pushes whatever a step nests inside itself. A branch's chosen arm arrives
## here exactly like a sequence's children do, which is why branching needs no
## jump and no label.
func _enter(step: VltEventStep) -> void:
	var nested: Array[VltEventStep] = step.children_to_run(self)
	if not nested.is_empty():
		_frames.append(Frame.new(nested))


## The atomic landing. Called only from here, so a caller cannot forget it and
## lose a player's progress silently.
func _finish() -> void:
	_finished = true
	_world.merge(pending)
