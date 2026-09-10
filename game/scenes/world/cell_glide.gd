class_name CellGlide
extends RefCounted

## The half-step between two cells (spec 14, section 2).
##
## The world moves one cell at a time and always has: `VltGridWalker` is already
## on the new cell before this knows a step happened. **This changes nothing
## about where the player is** — it only says where to draw them while they catch
## up, which is the whole of what spec 14 means by "rendering interpolates
## between cells and the logic is discrete".
##
## Pure, and no node. It holds two points and a clock, so it can be driven a
## frame at a time by a scene or a whole step at a time by a test.
##
## **Linear, deliberately.** Easing in and out of every cell looks better for one
## step and worse for every step after it: holding a direction produces
## back-to-back glides, and a curve at each boundary turns walking into a series
## of lurches. The smoothness that matters is between steps, not within one.

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _seconds: float = 0.0
var _elapsed: float = 0.0


## Begins a glide. A duration of nothing arrives immediately, which is what makes
## a caller with no opinion about pace correct rather than broken.
func to(from: Vector3, destination: Vector3, seconds: float) -> void:
	if not _usable(from) or not _usable(destination):
		return

	_to = destination
	if seconds <= 0.0:
		_from = destination
		_seconds = 0.0
		_elapsed = 0.0
		return

	_from = from
	_seconds = seconds
	_elapsed = 0.0


## Arrives at once, wherever the glide had got to.
##
## What a warp, a load and a defeat all need: those move the player somewhere
## else entirely, and sliding across the gap would draw them walking through
## whatever is between.
func snap(at: Vector3) -> void:
	if not _usable(at):
		return
	_from = at
	_to = at
	_seconds = 0.0
	_elapsed = 0.0


## Advances by a frame and returns where to draw. Safe to call when nothing is
## moving, which is most frames.
func advance(delta: float) -> Vector3:
	if not is_moving():
		return _to
	if delta > 0.0:
		_elapsed += delta
	return position()


func is_moving() -> bool:
	return _seconds > 0.0 and _elapsed < _seconds


## Where to draw, without advancing anything.
func position() -> Vector3:
	if _seconds <= 0.0:
		return _to
	return _from.lerp(_to, clampf(_elapsed / _seconds, 0.0, 1.0))


## How far through the step, from nothing to one.
func progress() -> float:
	if _seconds <= 0.0:
		return 1.0
	return clampf(_elapsed / _seconds, 0.0, 1.0)


## A point that can be drawn at. Guarded rather than asserted: a NaN reaching a
## transform is a node that vanishes with no error anywhere, and the world is not
## the layer that should be crashing over one.
static func _usable(point: Vector3) -> bool:
	return point.is_finite()
